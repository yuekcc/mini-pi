// test_curl_multi.c3
//
// 验证 curl multi 事件循环 + 跨线程取消模式（docs/arch-next.md 阶段 2 的起点）。
// 来源：EXP3 实验（2026-08-15），见 docs/arch-next.md §13 验证记录。
//
// 设计要点：
//  - 内置线程 mock HTTP server（hermetic，不依赖外部网络 / python）；
//    /fast 立即响应，/slow 延迟 5 秒响应（取消测试用）。
//  - worker 线程：multi_poll(100ms) + multi_perform 循环，每轮检查 atomic 取消标志；
//    正常完成（running==0）或取消即退出循环，multi_info_read 收集结果。
//  - 线程函数必须 @pool_init 包裹才能使用 tmem（新线程不会隐式创建临时分配器）。
//  - 响应体 DString 用 LIBC_ALLOCATOR（堆）分配：线程退出后主线程仍要读取。

import std::io;
import std::thread;
import std::atomic;
import std::time::clock;
import std::net::tcp;
import std::core::mem::allocators;
import curl;
import app;
import api;

const int MOCK_PORT = 18765;
const int SLOW_MS = 5000;

// ---- 内置 mock HTTP server --------------------------------------------------

Thread g_server;
bool g_server_started;
bool g_server_stop; // 永不置位：仅用于避免「无限循环后 return 不可达」告警

// 每连接一个 handler 线程：/slow 的 sleep 不会阻塞其他连接（如后续 /fast 请求）
struct ConnCtx
{
	TcpSocket client;
}

fn int mock_handler(void* arg)
{
	ConnCtx* c = (ConnCtx*)arg;
	@pool_init(&allocators::LIBC_ALLOCATOR, 1024 * 1024)
	{
		defer (void)c.client.close();

		char[1024] req_buf;
		if (try n = c.client.read(&req_buf))
		{
			String req = (String)((char[])req_buf[:n]);

			if (req.contains(" /slow"))
			{
				// 慢响应：客户端若取消，写入失败静默忽略
				thread::sleep_ms(SLOW_MS);
			}

			String resp;
			if (req.contains(" /err429"))
			{
				resp = "HTTP/1.1 429 Too Many Requests\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno";
			}
			else if (req.contains(" /err500"))
			{
				resp = "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno";
			}
			else if (req.contains(" /sse200"))
			{
				String body =
					"data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}\n\n"
					"data: {\"choices\":[{\"delta\":{\"content\":\"hi there\"},\"finish_reason\":null}]}\n\n"
					"data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
					"data: {\"usage\":{\"prompt_tokens\":11,\"completion_tokens\":3,\"reasoning_tokens\":2},\"choices\":[]}\n\n"
					"data: [DONE]\n\n";
				resp = string::tformat(
					"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
					body.len,
					body
				);
			}
			else
			{
				resp = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok";
			}
			(void)c.client.write(resp);
		}
	};
	alloc::free(&allocators::LIBC_ALLOCATOR, c);
	return 0;
}

fn int mock_server_fn(void* arg)
{
	@pool_init(&allocators::LIBC_ALLOCATOR, 1024 * 1024)
	{
		TcpServerSocket server = tcp::listen("127.0.0.1", MOCK_PORT, 4)!!;
		defer (void)server.close();

		while (!g_server_stop)
		{
			TcpSocket client = tcp::accept(&server)!!;

			ConnCtx* c = alloc::new(&allocators::LIBC_ALLOCATOR, ConnCtx);
			c.client = client;

			Thread h;
			h.create(&mock_handler, c)!!;
			h.detach()!!;
		}
	};
	return 0;
}

fn void ensure_server()
{
	if (g_server_started) return;
	g_server_started = true;
	g_server.create(&mock_server_fn, null)!!;
}

// ---- curl multi worker（EXP3 模式）------------------------------------------

struct MultiCtx
{
	String url;
	Atomic{bool} cancel;
	int status_code;
	DString body;
	bool cancelled;
	long elapsed_ms;
}

fn usz write_cb(char* buffer, usz size, usz nitems, void* userdata)
{
	usz realsize = size * nitems;
	DString* buf = (DString*)userdata;
	buf.append_bytes((char[])buffer[:realsize]);
	return realsize;
}

fn int curl_worker(void* arg)
{
	MultiCtx* ctx = (MultiCtx*)arg;
	@pool_init(&allocators::LIBC_ALLOCATOR, 1024 * 1024)
	{
		Curl* easy = curl::easy_init();
		// 响应体用堆分配器：线程结束后主线程仍要读取（跨线程存活）
		ctx.body = dstring::new(&allocators::LIBC_ALLOCATOR);

		curl::easy_setopt(easy, (curl::CurlOption)10002, ctx.url);  // URL
		curl::easy_setopt(easy, (curl::CurlOption)20011, &write_cb); // WRITEFUNCTION
		curl::easy_setopt(easy, (curl::CurlOption)10001, &ctx.body); // WRITEDATA
		curl::easy_setopt(easy, (curl::CurlOption)80, 1);            // HTTPGET

		CurlM* multi = curl::multi_init();
		(void)curl::multi_add_handle(multi, easy);

		Clock started = clock::now();
		ctx.cancelled = false;

		while (true)
		{
			int running = 0;
			(void)curl::multi_poll(multi, null, 0, 100, &running); // 100ms 取消检查窗口
			(void)curl::multi_perform(multi, &running);

			if (ctx.cancel.load())
			{
				ctx.cancelled = true;
				break;
			}
			if (running == 0) break;
		}

		// 收集结果消息（CURLMSG_DONE）
		int msgs = 0;
		while (CurlMsg* msg = curl::multi_info_read(multi, &msgs))
		{
			if (msg.msg == curl::CurlMsgType.DONE)
			{
				int code = 0;
				curl::easy_getinfo(easy, (curl::CurlInfoType)2097154, &code); // RESPONSE_CODE
				ctx.status_code = code;
			}
		}

		ctx.elapsed_ms = started.to_now().to_ms();

		(void)curl::multi_remove_handle(multi, easy);
		curl::easy_cleanup(easy);
		(void)curl::multi_cleanup(multi);
	};
	return 0;
}

// ---- 测试用例 ---------------------------------------------------------------

fn void test_multi_fast_get() @test
{
	ensure_server();
	(void)curl::global_init(curl::CurlGlobal.ALL);

	MultiCtx ctx = { .url = string::format(tmem, "http://127.0.0.1:%d/fast", MOCK_PORT) };

	Thread t;
	t.create(&curl_worker, &ctx)!!;
	(void)t.join()!!;

	io::printfn("[multi-fast] status=%d elapsed=%dms body=%.8s", ctx.status_code, ctx.elapsed_ms, ctx.body.str_view());
	assert(ctx.status_code == 200, "fast request should return 200");
	assert(!ctx.cancelled, "fast request should not be cancelled");
	assert(ctx.body.str_view() == "ok", "fast request body should be 'ok'");
	ctx.body.free();
}

fn void test_multi_cancel() @test
{
	ensure_server();
	(void)curl::global_init(curl::CurlGlobal.ALL);

	MultiCtx ctx = { .url = string::format(tmem, "http://127.0.0.1:%d/slow", MOCK_PORT) };

	Thread t;
	t.create(&curl_worker, &ctx)!!;

	// 300ms 后请求仍在途（/slow 需 5 秒），置取消标志
	Clock wait = clock::now();
	thread::sleep_ms(300);
	ctx.cancel.store(true);
	(void)t.join()!!;
	long cancel_latency = wait.to_now().to_ms() - 300;

	io::printfn("[multi-cancel] cancelled=%s elapsed=%dms cancel_latency=%dms", ctx.cancelled ? "yes" : "no", ctx.elapsed_ms, cancel_latency);
	assert(ctx.cancelled, "worker should report cancelled");
	assert(ctx.elapsed_ms < 3000, "cancel should take effect within 100ms poll window (elapsed < 3s)");
	ctx.body.free();
}

// ---------------------------------------------------------------------------
// execute_api_request（API worker 的执行函数）三路径：200 SSE / HTTP 错误 / 取消。
// 中断缝测试（arch-next-spec 测试矩阵：API worker 200/错误码/取消）。
// ---------------------------------------------------------------------------

fn ApiRequest* make_req(Allocator heap, String path)
{
	ApiRequest* req = alloc::new(heap, ApiRequest);
	req.request_id = "test_req".copy(heap);
	req.body_json = "{}".copy(heap);
	req.url = string::format(heap, "http://127.0.0.1:%d%s", MOCK_PORT, path);
	req.headers.init(heap);
	req.headers.push("Content-Type: application/json".copy(heap));
	return req;
}

fn void test_execute_api_request_sse_200() @test
{
	ensure_server();
	(void)curl::global_init(curl::CurlGlobal.ALL);

	Allocator heap = &allocators::LIBC_ALLOCATOR;
	ApiRequest* req = make_req(heap, "/sse200");
	ApiResponse resp;
	api::execute_api_request(req, heap, &resp, null);

	assert(resp.error_detail.len == 0, "no error");
	assert(!resp.cancelled, "not cancelled");
	assert(resp.message != null, "message parsed");
	assert(resp.message.content == "hi there", "SSE content accumulated, got '%s'", resp.message.content);
	assert(resp.message.role == "assistant", "role assistant");
	assert(resp.has_usage, "usage captured");
	assert(resp.usage.prompt_tokens == 11 && resp.usage.completion_tokens == 3 && resp.usage.reasoning_tokens == 2, "usage values");
	assert(resp.finish_reason == "stop", "finish_reason stop");
	assert(resp.latency_ms >= 0, "latency measured");
	io::printfn("[exec-sse] content='%s' usage=%d/%d/%d", resp.message.content, resp.usage.prompt_tokens, resp.usage.completion_tokens, resp.usage.reasoning_tokens);

	api::api_response_free(&resp, heap);
	api::api_request_free(req, heap);
}

fn void test_execute_api_request_http_errors() @test
{
	ensure_server();
	(void)curl::global_init(curl::CurlGlobal.ALL);

	Allocator heap = &allocators::LIBC_ALLOCATOR;

	// 429
	ApiRequest* req = make_req(heap, "/err429");
	ApiResponse resp;
	api::execute_api_request(req, heap, &resp, null);
	assert(resp.message == null, "429 no message");
	assert(resp.error_detail.contains("429"), "429 error detail, got '%s'", resp.error_detail);
	api::api_response_free(&resp, heap);
	api::api_request_free(req, heap);

	// 500
	req = make_req(heap, "/err500");
	api::execute_api_request(req, heap, &resp, null);
	assert(resp.message == null, "500 no message");
	assert(resp.error_detail.contains("500"), "500 error detail, got '%s'", resp.error_detail);
	io::printfn("[exec-http-err] 429/500 error details captured");
	api::api_response_free(&resp, heap);
	api::api_request_free(req, heap);
}

// 取消辅助：300ms 后置位取消标志（模拟 Ctrl+C 时序）
struct CancelCtx
{
	Atomic{bool}* flag;
}

fn int cancel_after_300ms(void* arg)
{
	// 新线程必须 @pool_init 包裹才能使用 tmem（本函数未用 tmem，保持规则一致）。
	@pool_init(&allocators::LIBC_ALLOCATOR, 64 * 1024)
	{
		CancelCtx* ctx = (CancelCtx*)arg;
		thread::sleep_ms(300);
		ctx.flag.store(true);
	};
	return 0;
}

fn void test_execute_api_request_cancel() @test
{
	ensure_server();
	(void)curl::global_init(curl::CurlGlobal.ALL);

	Allocator heap = &allocators::LIBC_ALLOCATOR;
	ApiRequest* req = make_req(heap, "/slow");
	ApiResponse resp;

	Atomic{bool} cancel;
	// 用线程并发置位取消标志，模拟 Ctrl+C 时序（执行函数本身在测试主线程同步跑）
	CancelCtx cctx = { .flag = &cancel };
	Thread canceller;
	canceller.create(&cancel_after_300ms, &cctx)!!;

	api::execute_api_request(req, heap, &resp, &cancel);
	(void)canceller.join()!!;

	assert(resp.cancelled, "cancelled by flag");
	assert(resp.message == null, "no message on cancel");
	assert(resp.latency_ms < 3000, "cancel latency under 3s (100ms poll window), got %d", resp.latency_ms);
	io::printfn("[exec-cancel] cancelled elapsed=%dms", resp.latency_ms);

	api::api_response_free(&resp, heap);
	api::api_request_free(req, heap);
}
