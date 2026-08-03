import std::io;
import std::io::file;

import api;
import context;

// 验证单次流式响应中包含多个 tool_call 时，解析逻辑能按 index 正确拆分并识别。
// 参考示例：logs/req_20260711_092017_200.json（一次返回 git diff 与 git status --short 两个 Bash 调用）
fn void test_read_stream_multiple_tool_calls() @test
{
	if (try String sse = (String)file::load(tmem, "logs/req_20260711_092017_200.json"))
	{
		api::ApiMeta meta;
		meta.finish_reason = "";
		meta.usage = {};
		meta.has_usage = false;
		if (try Message msg = api::read_stream_to_message(tmem, sse, &meta))
		{
			io::printfn("parsed tool_calls: %d", msg.tool_calls.len());
			assert(msg.tool_calls.len() == 2, "should detect exactly 2 tool calls in the example");

			assert(msg.tool_calls[0].name == "Bash", "first tool_call name should be Bash");
			assert(msg.tool_calls[0].arguments.contains("git diff"),
				"first tool_call arguments should contain 'git diff'");
			assert(msg.tool_calls[0].index == 0, "first tool_call index should be 0");

			assert(msg.tool_calls[1].name == "Bash", "second tool_call name should be Bash");
			assert(msg.tool_calls[1].arguments.contains("git status --short"),
				"second tool_call arguments should contain 'git status --short'");
			assert(msg.tool_calls[1].index == 1, "second tool_call index should be 1");

			io::printfn("multi tool_call parse OK");
		}
		else
		{
			assert(false, "read_stream_to_message should succeed on the example response");
		}
	}
	else
	{
		assert(false, "failed to load example log file");
	}
}

// 验证单个 tool_call 的流式响应依然被正确解析（回归保护）。
fn void test_read_stream_single_tool_call() @test
{
	// 构造一个只含一个 tool_call 的精简 SSE 响应。
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_abc\",\"index\":0,\"type\":\"function\",\"function\":{\"name\":\"Bash\",\"arguments\":\"\"}}]},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":null,\"index\":0,\"type\":\"function\",\"function\":{\"name\":null,\"arguments\":\"{\\\"command\\\":\\\"ls\\\"}\"}}]},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"tool_calls\"}]}\n");
	body.append("data: [DONE]\n");

	api::ApiMeta meta;
	meta.finish_reason = "";
	meta.usage = {};
	meta.has_usage = false;
	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), &meta))
	{
		assert(msg.tool_calls.len() == 1, "single tool_call response should yield exactly 1 tool call");
		assert(msg.tool_calls[0].name == "Bash", "tool name should be Bash");
		assert(msg.tool_calls[0].arguments == "{\"command\":\"ls\"}", "arguments should be concatenated correctly");
		// finish_reason 捕获链路
		assert(meta.finish_reason == "tool_calls", "finish_reason should be captured from SSE chunk");
		io::printfn("single tool_call parse OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed on the single tool_call response");
	}
}

// 验证流式终止 chunk 中的 usage 与 finish_reason 被捕获（api_usage 事件的硬前置）。
fn void test_read_stream_captures_usage() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"hi\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":123,\"completion_tokens\":45,\"reasoning_tokens\":6}}\n");
	body.append("data: [DONE]\n");

	api::ApiMeta meta;
	meta.finish_reason = "";
	meta.usage = {};
	meta.has_usage = false;
	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), &meta))
	{
		assert(msg.content == "hi", "content should be parsed");
		assert(meta.has_usage, "usage should be captured");
		assert(meta.usage.prompt_tokens == 123, "prompt_tokens should be 123");
		assert(meta.usage.completion_tokens == 45, "completion_tokens should be 45");
		assert(meta.usage.reasoning_tokens == 6, "reasoning_tokens should be 6");
		assert(meta.finish_reason == "stop", "finish_reason should be stop");
		io::printfn("usage capture OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed on usage response");
	}
}

// 回归保护：OpenAI 风格独立 usage chunk（choices 为空数组）也必须捕获 usage，
// 不能因 delta/choices 守卫被跳过（规格 L141：usage 可能在终止 chunk 中）。
fn void test_read_stream_captures_usage_only_chunk() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"ok\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":2,\"reasoning_tokens\":1}}\n");
	body.append("data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}]}\n");
	body.append("data: [DONE]\n");

	api::ApiMeta meta;
	meta.finish_reason = "";
	meta.usage = {};
	meta.has_usage = false;
	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), &meta))
	{
		assert(msg.content == "ok", "content should be parsed");
		assert(meta.has_usage, "usage-only chunk (empty choices) should still be captured");
		assert(meta.usage.prompt_tokens == 7, "prompt_tokens should be 7");
		assert(meta.usage.completion_tokens == 2, "completion_tokens should be 2");
		assert(meta.finish_reason == "stop", "finish_reason should be stop from delta-less frame");
		io::printfn("usage-only chunk capture OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed on usage-only chunk response");
	}
}
