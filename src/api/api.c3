module api;

import std::io;
import std::collections::list;
import std::time::datetime;
import std::time::clock;
import std::atomic;

import cjson;
import curl;
import context;
import app;
import util;
import log;
import transcript;

faultdef
	API_ERROR, EMPTY_RESPONSE;

// API 调用元数据：usage 与 finish_reason 在解析层捕获（transcript api_usage 的硬前置）。
// v2：由 API worker 回报给 Agent 线程，Agent 负责记账（TokenLedger）与写 api_usage 事件。
struct ApiMeta
{
	String finish_reason;
	transcript::Usage usage;
	bool has_usage;
}

fn CJsonItem* api_error_detail(String message)
{
	CJsonItem* detail = cjson::new_object(tmem);
	detail.set("message", message);
	detail.set("retry_attempt", 0);
	return detail;
}

fn void capture_usage(CJsonItem* usage_chunk, transcript::Usage* usage, bool* has_usage)
{
	usage.prompt_tokens = (long)(usage_chunk.get_key_int("prompt_tokens") ?? 0);
	usage.completion_tokens = (long)(usage_chunk.get_key_int("completion_tokens") ?? 0);
	usage.reasoning_tokens = (long)(usage_chunk.get_key_int("reasoning_tokens") ?? 0);
	*has_usage = true;
}

fn Message? read_response_to_message(Allocator allocator, String json_doc, ApiMeta* meta)
{
	CJsonItem* res = cjson::parse((ZString)json_doc);
	if (!res) return EMPTY_RESPONSE~;
	defer res.free();

	CJsonItem* choices = res.get_key("choices");
	if (!choices) return EMPTY_RESPONSE~;
	CJsonItem* last_choice = choices.get_at(0);

	// 非流式响应：finish_reason 在 choice 上，usage 在根对象上。
	if (meta)
	{
		meta.finish_reason = (last_choice.get_key_string("finish_reason", allocator) ?? "").copy(allocator);
		if (CJsonItem* usage_chunk = res.get_key("usage"))
		{
			capture_usage(usage_chunk, &meta.usage, &meta.has_usage);
		}
	}

	if (CJsonItem* message = last_choice.get_key("message"))
	{
		String role              = message.get_key_string("role", tmem) ?? "assistant";
		String content           = message.get_key_string("content", tmem) ?? "";
		// 文档标准字段为 "reasoning"（ChatAssistantMessage.reasoning）。
		// "reasoning_content" 是 DeepSeek 私有扩展，作为兼容回退。
		String reasoning = message.get_key_string("reasoning", tmem) ?? "";
		if (reasoning.len == 0)
		{
			reasoning = message.get_key_string("reasoning_content", tmem) ?? "";
		}
		Message result = {
			.id = util::timestamp_id(allocator),
			.role = role.copy(allocator),
			.content = content.copy(allocator),
			.reasoning_content = reasoning.copy(allocator),
			.tool_call_id = "",
			.timestamp = datetime::now().to_local(),
		};
		result.tool_calls.init(allocator);

		if (CJsonItem* tool_calls = message.get_key("tool_calls"))
		{
			usz tc_len = tool_calls.get_len();
			for (usz i = 0; i < tc_len; i++)
			{
				CJsonItem* tc = tool_calls.get_at((sz)i);
				if (tc == null) continue;

				ToolCall parsed;
				parsed.id = tc.get_key_string("id", tmem) ?? "";
				parsed.index = (usz)(tc.get_key_int("index") ?? 0);
				if (CJsonItem* function = tc.get_key("function"))
				{
					parsed.name = function.get_key_string("name", tmem) ?? "";
					parsed.arguments = function.get_key_string("arguments", tmem) ?? "";
				}
				else
				{
					parsed.name = "";
					parsed.arguments = "";
				}

				if (parsed.name.len == 0) continue;

				result.tool_calls.push(
					{
						.id = parsed.id.copy(allocator),
						.index = parsed.index,
						.name = parsed.name.copy(allocator),
						.arguments = parsed.arguments.copy(allocator),
					}
				);
			}

			if (result.tool_calls.len() > 0)
			{
				log::debug("> Detect %d tool calls", result.tool_calls.len());
			}
		}

		return result;
	}

	return EMPTY_RESPONSE~;
}

// 解析 OpenAI 兼容的 SSE 流式响应。
// HttpClient 已经把整个响应体累积进 DString 并作为 response.body 返回，
// 因此这里在请求结束后，一次性处理完整的 SSE 文本，不做打字机效果。
// 
// 流式响应中，tools 调用以增量分片形式下发：每个 delta.tool_calls 是数组，
// 元素通过 "index" 字段区分属于第几个工具调用；id 与 name 通常只在首个分片出现，
// arguments 则跨多个分片拼接。这里按 index 分组累积，从而支持单次回复中的多个 tool_call。
fn Message? read_stream_to_message(Allocator allocator, String sse_body, ApiMeta* meta)
{
	@pool()
	{
		DString content_buf   = dstring::new(tmem);
		DString reasoning_buf = dstring::new(tmem);

		String role = "assistant";

		// 累积多个 tool_call，按 index 分组。
		List{ToolCall} tool_calls_acc;
		tool_calls_acc.init(tmem);
		List{DString} tool_args_bufs;
		tool_args_bufs.init(tmem);
		bool has_tool_call = false;

		usz event_count = 0;
		usz skipped     = 0;

		// SSE 每行以 "data:" 开头，事件之间以空行分隔，结束标记为 "data: [DONE]"。
		String[] lines = sse_body.split(tmem, "\n");
		log::debug("parsing SSE stream response: %d lines", lines.len);
		foreach (String raw_line : lines)
		{
			String line = raw_line.trim();
			if (line.len == 0) continue;
			if (!line.starts_with("data:")) continue;

			String payload = line.strip_prefix("data:").trim();
			if (payload.len == 0) continue;
			if (payload == "[DONE]") break;

			CJsonItem* chunk = cjson::parse(payload.zstr_copy(tmem));
			if (!chunk)
			{
				log::debug("skipping unparseable SSE chunk: %s", payload);
				skipped++;
				continue;
			}
			defer chunk.free();

			// usage 捕获必须在 delta/choices 守卫之外：OpenAI 风格独立 usage chunk
			// 可能带 choices:[] 或空 delta（规格 L141：流式 usage 可能在终止 chunk 中）。
			if (meta && !meta.has_usage)
			{
				if (CJsonItem* usage_chunk = chunk.get_key("usage"))
				{
					capture_usage(usage_chunk, &meta.usage, &meta.has_usage);
				}
			}

			CJsonItem* choices = chunk.get_key("choices");
			if (!choices) continue;
			CJsonItem* choice = choices.get_at(0);
			if (!choice) continue;

			if (meta)
			{
				String fr = choice.get_key_string("finish_reason", allocator) ?? "";
				if (fr.len > 0) meta.finish_reason = fr.copy(allocator);
			}

			CJsonItem* delta = choice.get_key("delta");
			if (!delta) continue;

			event_count++;

			String role_part = delta.get_key_string("role", tmem) ?? "";
			if (role_part.len > 0) role = role_part.copy(tmem);

			String content_part = delta.get_key_string("content", tmem) ?? "";
			if (content_part.len > 0) content_buf.append(content_part);

			// 文档标准字段为 "reasoning"（ChatStreamDelta.reasoning）。
			// "reasoning_content" 是 DeepSeek 私有扩展，作为兼容回退。
			String reasoning_part = delta.get_key_string("reasoning", tmem) ?? "";
			if (reasoning_part.len == 0)
			{
				reasoning_part = delta.get_key_string("reasoning_content", tmem) ?? "";
			}
			if (reasoning_part.len > 0) reasoning_buf.append(reasoning_part);

			log::debug(
				"stream event #%d: content +%d bytes, reasoning +%d bytes",
				event_count,
				content_part.len,
				reasoning_part.len
			);

			if (CJsonItem* tool_calls = delta.get_key("tool_calls"))
			{
				usz tc_len = tool_calls.get_len();
				for (usz i = 0; i < tc_len; i++)
				{
					CJsonItem* tool_call = tool_calls.get_at((sz)i);
					if (tool_call == null) continue;

					has_tool_call = true;

					sz idx = (sz)(tool_call.get_key_int("index") ?? 0);

					// 确保 acc 列表中存在 idx 位置（模型可能乱序到达，需补齐中间空位）。
					while (tool_calls_acc.len() <= idx)
					{
						ToolCall empty;
						empty.id = "";
						empty.index = (usz)tool_calls_acc.len();
						empty.name = "";
						empty.arguments = "";
						tool_calls_acc.push(empty);

						DString args_buf = dstring::new(tmem);
						tool_args_bufs.push(args_buf);
					}

					ToolCall* acc = tool_calls_acc.get_ref(idx);
					DString* buf  = tool_args_bufs.get_ref(idx);

					// id 与 name 通常只在首个分片中出现。
					String id_part = tool_call.get_key_string("id", tmem) ?? "";
					if (id_part.len > 0) acc.id = id_part.copy(tmem);

					if (CJsonItem* function = tool_call.get_key("function"))
					{
						String name_part = function.get_key_string("name", tmem) ?? "";
						if (name_part.len > 0) acc.name = name_part.copy(tmem);

						String args_part = function.get_key_string("arguments", tmem) ?? "";
						if (args_part.len > 0) buf.append(args_part);

						log::debug(
							"stream event #%d: tool_call delta (index=%d id=%s name=%s, +%d args bytes)",
							event_count,
							idx,
							acc.id,
							acc.name,
							args_part.len
						);
					}
				}
			}
		}

		Message result = {
			.id = util::timestamp_id(allocator),
			.role = role.copy(allocator),
			.content = content_buf.copy_str(allocator),
			.reasoning_content = reasoning_buf.copy_str(allocator),
			.tool_call_id = "",
			.timestamp = datetime::now().to_local(),
		};
	result.tool_calls.init(allocator);

	log::debug(
			"stream parse complete: %d events parsed, %d skipped, content=%d chars, reasoning=%d chars, tool_call=%s",
			event_count,
			skipped,
			content_buf.str_view()
			.len, reasoning_buf.str_view().len, has_tool_call ? "yes" : "no");

		if (has_tool_call)
		{
			for (sz i = 0; i < tool_calls_acc.len(); i++)
			{
				ToolCall* acc = tool_calls_acc.get_ref(i);
				DString* buf  = tool_args_bufs.get_ref(i);

				// 跳过未完整接收（没有 name）的占位项，理论上不会发生。
				if (acc.name.len == 0) continue;

				log::debug(
					"> Detect tool call #%d: id = %s, name = %s, arguments = %s",
					i,
					acc.id,
					acc.name,
					buf.str_view()
				);

				result.tool_calls.push(
					{
						.id = acc.id.copy(allocator),
						.index = acc.index,
						.name = acc.name.copy(allocator),
						.arguments = buf.copy_str(allocator),
					}
				);
			}
		}

		return result;
	};
}

// ---- v2 三线程拓扑的请求执行（阶段 1：worker 内 blocking easy_perform，阶段 2 换 multi）----

// Agent 线程：构造请求快照（body_json / url / headers 全部 heap 分配），投递 API worker。
// worker 不读共享 messages 列表（NFR-2）。
fn ApiRequest* build_api_request(AppContext* app, Allocator heap, String request_id)
{
	ApiRequest* req = alloc::new(heap, ApiRequest);
	req.request_id = request_id.copy(heap);

	// build_request_body 已返回 heap 分配产物，直接移交（不再二次拷贝）。
	req.body_json = build_request_body(heap, app);
	if (app.debug())
	{
		file::save(string::tformat("logs/req_%s.json", request_id), req.body_json)!!;
	}

	// TODO 从配置读出 baseUrl/api-key，而不是直接使用 flag
	req.url = string::format(heap, "%s/chat/completions", app.flag.baseUrl);

	List{String} headers;
	headers.init(heap);
	headers.push(string::format(heap, "Authorization: Bearer %s", app.flag.apiKey));
	headers.push("Content-Type: application/json".copy(heap));
	req.headers = headers;

	return req;
}

// 释放 build_api_request 的负载（worker 处理完请求后调用；结构体本身为通道值，不在此释放）。
// len 守卫与 api_response_free 一致：build_api_request 保证非空，防御性防未来路径注入空串。
fn void api_request_free(ApiRequest* req, Allocator heap)
{
	if (req.request_id.len > 0) req.request_id.free(heap);
	if (req.body_json.len > 0) req.body_json.free(heap);
	if (req.url.len > 0) req.url.free(heap);
	foreach (h : req.headers) h.free(heap);
	req.headers.free();
}

// 释放 ApiResponse 负载（Agent 处理完响应后调用）。
fn void api_response_free(ApiResponse* resp, Allocator heap)
{
	if (resp.request_id.len > 0) resp.request_id.free(heap);
	if (resp.message) context::message_free(heap, resp.message);
	if (resp.finish_reason.len > 0) resp.finish_reason.free(heap);
	if (resp.error_detail.len > 0) resp.error_detail.free(heap);
}

// API worker 线程：执行一次 HTTP 请求并解析为 Message。
// 阶段 2：curl multi 事件循环（每请求独立 easy handle，multi_poll 100ms 轮询窗口 +
// multi_perform + multi_info_read 收 CURLMSG_DONE），每轮检查 cancel_flag——
// 取消延迟上限 100ms（实测约 30ms）。SSE 解析逻辑原样（read_stream_to_message）。
// 结果（message / finish_reason / error_detail）全部 heap 分配，随 ApiResponse 移交 Agent。
fn void execute_api_request(ApiRequest* req, Allocator heap, ApiResponse* resp, Atomic{bool}* cancel_flag)
{
	resp.request_id = req.request_id.copy(heap);
	resp.message = null;
	resp.usage = {};
	resp.has_usage = false;
	resp.finish_reason = "";
	resp.error_detail = "";
	resp.cancelled = false;
	resp.latency_ms = 0;
	resp.has_partial_content = false;

	@pool()
	{
		DString response_buffer = dstring::new(tmem);

		Curl* easy = curl::easy_init();
		// 传入 curl 的字符串必须 NUL 结尾（build_api_request 产物均为堆分配 + NUL 安全）。
		curl::easy_setopt(easy, (curl::CurlOption)10002, req.url);                    // URL
		curl::easy_setopt(easy, (curl::CurlOption)20011, &write_callback);            // WRITEFUNCTION
		curl::easy_setopt(easy, (curl::CurlOption)10001, &response_buffer);           // WRITEDATA
		curl::easy_setopt(easy, (curl::CurlOption)47, 1);                             // POST
		curl::easy_setopt(easy, (curl::CurlOption)10015, req.body_json);              // POSTFIELDS

		CurlSlist* header_list = null;
		foreach (String header : req.headers)
		{
			header_list = curl::slist_append(header_list, header);
		}
		if (header_list) curl::easy_setopt(easy, (curl::CurlOption)10023, header_list); // HTTPHEADER

		CurlM* multi = curl::multi_init();
		(void)curl::multi_add_handle(multi, easy);

		Clock started = clock::now();
		bool cancelled = false;
		while (true)
		{
			int running = 0;
			(void)curl::multi_poll(multi, null, 0, 100, &running); // 100ms 取消检查窗口
			(void)curl::multi_perform(multi, &running);

			if (cancel_flag != null && cancel_flag.load())
			{
				cancelled = true;
				break;
			}
			if (running == 0) break;
		}

		// 收集结果消息（CURLMSG_DONE → easy_getinfo 取状态码）
		int response_code = 0;
		int msgs = 0;
		while (CurlMsg* msg = curl::multi_info_read(multi, &msgs))
		{
			if (msg.msg == curl::CurlMsgType.DONE)
			{
				int code = 0;
				curl::easy_getinfo(easy, (curl::CurlInfoType)2097154, &code); // RESPONSE_CODE
				response_code = code;
			}
		}

		resp.latency_ms = started.to_now().to_ms();

		(void)curl::multi_remove_handle(multi, easy);
		if (header_list) curl::slist_free_all(header_list);
		curl::easy_cleanup(easy);
		(void)curl::multi_cleanup(multi);

		if (cancelled)
		{
			log::debug("API request cancelled (request_id = %s, elapsed = %dms)", req.request_id, resp.latency_ms);
			resp.cancelled = true;
			resp.has_partial_content = response_buffer.str_view().len > 0;
			return;
		}

		log::debug("> Remote reply: status = %d", response_code);
		if (response_code != 200)
		{
			log::warn("LLM API HTTP error: status=%d", response_code);
			resp.error_detail = string::format(heap, "LLM API HTTP error: status=%d", response_code);
			return;
		}

		ApiMeta meta;
		meta.finish_reason = "";
		meta.usage = {};
		meta.has_usage = false;

		Message? parsed = read_stream_to_message(heap, response_buffer.str_view(), &meta);
		if (catch parsed)
		{
			// 响应解析失败：无法获得 usage，由 Agent 记 api_error 而非零值 api_usage。
			resp.error_detail = "LLM API response parse failed".copy(heap);
			return;
		}
		// parsed 的字符串已由 read_stream_to_message 分配在 heap，直接移交（浅拷贝结构体）。
		resp.message = alloc::new(heap, Message);
		*resp.message = parsed;
		resp.usage = meta.usage;
		resp.has_usage = meta.has_usage;
		resp.finish_reason = meta.finish_reason; // 已 heap 分配，直接移交
	};
}

// 构造 /chat/completions 请求体 JSON。
//
// 依据 docs/chat-completion-api.md 的 ChatRequest schema：
//   - required: [messages]；model 虽未列入 required 但实际必传
//   - 不存在 "thinking" 字段（非标准，严格 provider 会 400/422）
//   - assistant 消息的推理内容使用标准字段 "reasoning"（ChatAssistantMessage.reasoning）
//   - 非流式 tool_calls 使用标准 ChatToolCall 结构：required = [id, type, function]
//     不带 index（index 只存在于流式 ChatStreamToolCall delta）
//   - tool_choice / tools 仅在有可用工具时才下发
//   - tools schema 取 AppContext.tools_schema_json（hub 初始化时预计算，只读）
fn String build_request_body(Allocator allocator, AppContext* app)
{
	@pool()
	{
		CJsonItem* messages = cjson::new_array(tmem);
		// defer messages.free();

		foreach (&msg : &app.messages)
		{
			CJsonItem* message = cjson::new_object(tmem);
			messages.push_back(message);

			message.set("role", msg.role);
			message.set("content", msg.content);

			if (msg.role == "assistant")
			{
				// 标准 ChatAssistantMessage.reasoning（非 DeepSeek 私有的 reasoning_content）
				if (msg.reasoning_content.len > 0)
				{
					message.set("reasoning", msg.reasoning_content);
				}

				// 回传模型产生的全部 tool_calls（单个或多个），供模型继续对话。
				if (msg.tool_calls.len() > 0)
				{
					CJsonItem* tool_calls = cjson::new_array(tmem);
					message.set("tool_calls", tool_calls);

					foreach (&tc : msg.tool_calls)
					{
						CJsonItem* tool_call = cjson::new_object(tmem);
						tool_calls.push_back(tool_call);

						// 标准 ChatToolCall: required = [id, type, function]
						tool_call.set("id", tc.id);
						tool_call.set("type", "function");
						CJsonItem* function = cjson::new_object(tmem);
						tool_call.set("function", function);

						function.set("name", tc.name);
						function.set("arguments", tc.arguments);
					}
				}
			}
			else if (msg.role == "tool")
			{
				// 工具结果消息只携带 tool_call_id，标识它回应的是哪一个 tool_call。
				if (msg.tool_call_id != "")
				{
					message.set("tool_call_id", msg.tool_call_id);
				}
			}
		}

		CJsonItem* enable_thinking = cjson::new_object(tmem);
		// defer enable_thinking.free();
		enable_thinking.set("type", "enabled");

		CJsonItem* request_body = cjson::new_object(tmem);
		// defer request_body.free();
		request_body.set("model", app.flag.model);
		request_body.set("messages", messages);
		request_body.set("stream", true);
		request_body.set("thinking", enable_thinking);

		// tools / tool_choice 仅在有可用工具时才下发。
		// 部分 provider 在收到空 tools 数组 + tool_choice 时会报错。
		String tools_schema = app.tools_schema_json;
		if (tools_schema.len > 0 && tools_schema != "[]")
		{
			request_body.set("tools", "{{tools_schema}}"); // 模板占位，序列化后替换
			request_body.set("tool_choice", "auto");
		}

		String request_body_json = string::format(tmem, "%s", request_body);
		request_body_json = request_body_json.replace(tmem, "\"{{tools_schema}}\"", tools_schema);

		return request_body_json.copy(allocator);
	};
}
