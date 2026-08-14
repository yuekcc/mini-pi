module api;

// API worker 线程：收 ApiRequest → 执行 HTTP（阶段 1：blocking easy_perform；
// 阶段 2 换 curl multi 事件循环 + cancel_flag）→ SSE 解析 → 回传 ApiResponse。
// 轮询 cancel_flag 支持取消（阶段 2 起）。

import std::thread;
import std::core::mem::allocators;

import app;
import log;
import util;

const sz WORKER_POOL_SIZE = 8 * 1024 * 1024;

fn int api_worker_main(void* arg)
{
	AppContext* app = (AppContext*)arg;

	// 新线程必须 @pool_init 包裹才能使用 tmem（否则 panic）。
	@pool_init(&allocators::LIBC_ALLOCATOR, WORKER_POOL_SIZE)
	{
		Allocator heap = &allocators::LIBC_ALLOCATOR;

		while (true)
		{
			ApiRequest? maybe = app.agent_to_api.pop();
			if (catch e = maybe)
			{
				// close() 先排空队列剩余元素，随后 CHANNEL_CLOSED → 退出。
				if (e == thread::CHANNEL_CLOSED) break;
				continue;
			}
			ApiRequest req = maybe;

			ApiResponse* resp = alloc::new(heap, ApiResponse);
			execute_api_request(&req, heap, resp, app.cancel_flag);
			api_request_free(&req, heap);

			(void)app.api_to_agent.push(*resp);
			alloc::free(heap, resp);
		}
	};

	return 0;
}
