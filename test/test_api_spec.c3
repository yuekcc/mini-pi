// 依据 docs/chat-completion-api.md（OpenAI/OpenRouter 兼容 /chat/completions）
// 对 src/api/api.c3 的请求构造与响应解析做合规性测试。
//
// 设计原则：先写测试暴露 bug，再修实现让测试通过（TDD）。
// 每个测试都引用文档中的具体 schema 条目，方便追溯。

import std::io;
import std::io::file;

import api;
import context;
import cjson;
import cli;
import tool;
import skill;

// =============================================================================
// 响应解析：流式（read_stream_to_message）
// =============================================================================

// 文档 ChatStreamDelta: reasoning 字段（标准）用于推理内容增量。
// 现实中 OpenAI/o-series、OpenRouter 上游使用 "reasoning"，而 DeepSeek 系使用
// "reasoning_content"。实现应优先读标准字段 "reasoning"，兼容回退 "reasoning_content"。
//
// 参考：docs/chat-completion-api.md ChatStreamDelta.reasoning
fn void test_stream_reads_standard_reasoning_field() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning\":\"let me think\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"content\":\"hello\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{},\"index\":0,\"finish_reason\":\"stop\"}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.reasoning_content == "let me think",
			"standard 'reasoning' field should be captured into reasoning_content; got: '%s'", msg.reasoning_content);
		assert(msg.content == "hello", "content should be 'hello'");
		io::printfn("stream standard reasoning field OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamDelta: 同时支持 reasoning 与 reasoning_content。
// 当只有 reasoning_content（DeepSeek 风格）时也应能解析（兼容回退）。
fn void test_stream_falls_back_to_reasoning_content() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"deepseek style\"},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.reasoning_content == "deepseek style",
			"reasoning_content fallback should work; got: '%s'", msg.reasoning_content);
		io::printfn("stream reasoning_content fallback OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamDelta.content: nullable: true。
// 某些 provider 会下发 content: null（尤其是首帧只有 role、或 tool_calls 帧）。
// 解析不应崩溃，且应视为空增量。
fn void test_stream_handles_null_content() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":null},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"content\":\"hi\"},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.content == "hi", "null content delta should be treated as empty; got: '%s'", msg.content);
		io::printfn("stream null content OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamChunk.choices: 可能为空数组（keep-alive / usage-only 帧）。
// 部分 provider（如 Azure OpenAI）会发送 choices: [] 的帧携带 usage。
// 解析器应跳过空 choices 而非崩溃。
fn void test_stream_handles_empty_choices() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":10}}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.content == "ok", "empty-choices frame should be skipped; got: '%s'", msg.content);
		io::printfn("stream empty choices OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamChoice: delta 是 required，但部分 provider 在 finish_reason 帧里
// 不带 delta 或 delta 为 null。解析器应安全跳过。
fn void test_stream_handles_missing_delta() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"content\":\"x\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"index\":0,\"finish_reason\":\"stop\"}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.content == "x", "missing-delta frame should be skipped; got: '%s'", msg.content);
		io::printfn("stream missing delta OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamToolCall: 流式 tool_call delta 的 required 字段只有 index。
// id / function.name / function.arguments 都可能缺失或为 null（分片）。
// 这里验证 id 为 null 时不会覆盖已累积的值。
fn void test_stream_tool_call_null_id_does_not_overwrite() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_1\",\"index\":0,\"type\":\"function\",\"function\":{\"name\":\"Bash\",\"arguments\":\"\"}}]},\"index\":0}]}\n");
	// 后续分片 id 为 null，不应覆盖已收到的 "call_1"
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":null,\"index\":0,\"function\":{\"arguments\":\"{\\\"cmd\\\":\\\"ls\\\"}\"}}]},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.tool_calls.len() == 1, "should have 1 tool call");
		assert(msg.tool_calls[0].id == "call_1", "null id should not overwrite; got: '%s'", msg.tool_calls[0].id);
		assert(msg.tool_calls[0].name == "Bash", "name should be Bash");
		assert(msg.tool_calls[0].arguments == "{\"cmd\":\"ls\"}", "arguments should concatenate");
		io::printfn("stream null id no-overwrite OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 SSE 格式：某些 provider 在 data: 后无空格，某些有空格。
// 二者都应正确解析。
fn void test_stream_handles_data_prefix_with_or_without_space() @test
{
	DString body = dstring::new(tmem);
	body.append("data:{\"choices\":[{\"delta\":{\"content\":\"a\"},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"content\":\"b\"},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.content == "ab", "both data: and data: prefixes should work; got: '%s'", msg.content);
		io::printfn("stream data prefix variants OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// 文档 ChatStreamDelta.tool_calls[].function: 部分窄实现里 function 可能缺失
// （只有 index + id 的占位帧）。不应崩溃。
fn void test_stream_tool_call_without_function_field() @test
{
	DString body = dstring::new(tmem);
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_x\",\"index\":0}]},\"index\":0}]}\n");
	body.append("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"Read\",\"arguments\":\"{}\"}}]},\"index\":0}]}\n");
	body.append("data: [DONE]\n");

	if (try Message msg = api::read_stream_to_message(tmem, body.str_view(), null))
	{
		assert(msg.tool_calls.len() == 1, "should have 1 tool call");
		assert(msg.tool_calls[0].name == "Read", "name should be Read");
		io::printfn("stream tool_call without function field OK");
	}
	else
	{
		assert(false, "read_stream_to_message should succeed");
	}
}

// =============================================================================
// 响应解析：非流式（read_response_to_message）
// =============================================================================

// 文档 ChatAssistantMessage.reasoning: 标准推理字段是 "reasoning"（字符串）。
// 非流式响应同样应优先读 "reasoning"，回退 "reasoning_content"。
fn void test_non_stream_reads_standard_reasoning_field() @test
{
	String json_doc =
		"{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"finish_reason\":\"stop\",\"message\":{\"role\":\"assistant\",\"content\":\"Paris\",\"reasoning\":\"capital of France\"}}]}";

	if (try Message msg = api::read_response_to_message(tmem, json_doc, null))
	{
		assert(msg.content == "Paris", "content should be Paris");
		assert(msg.reasoning_content == "capital of France",
			"standard 'reasoning' should be captured; got: '%s'", msg.reasoning_content);
		io::printfn("non-stream standard reasoning OK");
	}
	else
	{
		assert(false, "read_response_to_message should succeed");
	}
}

// 文档 ChatToolCall（非流式）: required = [id, type, function]。
// 非流式 tool_call 应带 type: "function"。解析器对此应容忍（不依赖 type）。
fn void test_non_stream_parses_tool_calls() @test
{
	String json_doc =
		"{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_abc\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"loc\\\":\\\"SF\\\"}\"}}]}}]}";

	if (try Message msg = api::read_response_to_message(tmem, json_doc, null))
	{
		assert(msg.tool_calls.len() == 1, "should have 1 tool call");
		assert(msg.tool_calls[0].id == "call_abc", "id should be call_abc");
		assert(msg.tool_calls[0].name == "get_weather", "name should be get_weather");
		io::printfn("non-stream tool_calls OK");
	}
	else
	{
		assert(false, "read_response_to_message should succeed");
	}
}

// 文档 ChatAssistantMessage.content: nullable: true（tool_calls 时 content 常为 null）。
fn void test_non_stream_handles_null_content() @test
{
	String json_doc =
		"{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[]}}]}";

	if (try Message msg = api::read_response_to_message(tmem, json_doc, null))
	{
		assert(msg.content == "", "null content should default to empty");
		io::printfn("non-stream null content OK");
	}
	else
	{
		assert(false, "read_response_to_message should succeed");
	}
}

// =============================================================================
// 请求体构造：build_request_body
// 文档 ChatRequest schema 要求：
//   - required: [messages]
//   - model: 必须是字符串
//   - 不存在 "thinking" 字段（非标准，会被严格 provider 拒绝）
//   - 推理配置应使用 "reasoning" 或 "reasoning_effort"
//   - tool_calls（assistant 消息回传）应使用标准 ChatToolCall 结构：
//     required = [id, type, function]，不带 index（index 只在流式 delta 中）
//   - assistant 消息的推理内容字段应为 "reasoning"（标准），非 "reasoning_content"
// =============================================================================

// 验证请求体不包含非标准的 "thinking" 字段。
// 这是导致严格 provider（OpenAI 等）返回 400/422 的首要原因。
// fn void test_request_body_has_no_thinking_field() @test
// {
// 	String body = api::build_request_body(tmem, fixture_ctx(tmem));
// 	CJsonItem* root = cjson::parse((ZString)body);
// 	defer root.free();

// 	CJsonItem* thinking = root.get_key("thinking");
// 	assert(thinking == null,
// 		"request body must NOT contain non-standard 'thinking' field (causes 400/422 on strict providers)");
// 	io::printfn("no thinking field OK");
// }

// 验证 assistant 消息回传时，tool_calls 使用标准结构：
//   - 必须有 "type": "function"（文档 ChatToolCall.required = [id, type, function]）
//   - 不应带 "index"（index 只存在于流式 ChatStreamToolCall）
fn void test_request_body_tool_calls_are_standard() @test
{
	String body = api::build_request_body(tmem, fixture_ctx_with_tool_calls(tmem));
	CJsonItem* root = cjson::parse((ZString)body);
	defer root.free();

	CJsonItem* messages = root.get_key("messages");
	assert(messages != null, "messages must exist");

	bool found_assistant_tc = false;
	usz msg_len = messages.get_len();
	for (usz i = 0; i < msg_len; i++)
	{
		CJsonItem* msg = messages.get_at((sz)i);
		if (msg.get_key_string("role", tmem) ?? "" != "assistant") continue;
		CJsonItem* tcs = msg.get_key("tool_calls");
		if (!tcs) continue;

		usz tc_len = tcs.get_len();
		for (usz j = 0; j < tc_len; j++)
		{
			found_assistant_tc = true;
			CJsonItem* tc = tcs.get_at((sz)j);

			// 必须有 type: "function"
			String tc_type = tc.get_key_string("type", tmem) ?? "";
			assert(tc_type == "function",
				"non-streaming tool_call must have \"type\": \"function\"; got: '%s'", tc_type);

			// 不应有 index（index 只在流式 delta 中）
			CJsonItem* idx = tc.get_key("index");
			assert(idx == null,
				"non-streaming tool_call must NOT have 'index' (only in streaming deltas)");
		}
	}
	assert(found_assistant_tc, "test fixture should contain at least one assistant tool_call");
	io::printfn("standard tool_calls OK");
}

// 验证 assistant 消息回传时，推理内容使用标准字段 "reasoning"，
// 而非 DeepSeek 私有的 "reasoning_content"。
fn void test_request_body_uses_standard_reasoning_field() @test
{
	String body = api::build_request_body(tmem, fixture_ctx_with_reasoning(tmem));
	CJsonItem* root = cjson::parse((ZString)body);
	defer root.free();

	CJsonItem* messages = root.get_key("messages");
	assert(messages != null, "messages must exist");

	bool found = false;
	usz msg_len = messages.get_len();
	for (usz i = 0; i < msg_len; i++)
	{
		CJsonItem* msg = messages.get_at((sz)i);
		if (msg.get_key_string("role", tmem) ?? "" != "assistant") continue;

		CJsonItem* reasoning_content = msg.get_key("reasoning_content");
		assert(reasoning_content == null,
			"assistant message must NOT use non-standard 'reasoning_content'; use 'reasoning' instead");

		CJsonItem* reasoning = msg.get_key("reasoning");
		if (reasoning) found = true;
	}
	assert(found, "test fixture should contain assistant message with reasoning content");
	io::printfn("standard reasoning field in request OK");
}

// =============================================================================
// 辅助：构造测试用 Context
// =============================================================================

fn Context* fixture_ctx(Allocator allocator) @local
{
	return fixture_ctx_full(allocator, false, false);
}

fn Context* fixture_ctx_with_tool_calls(Allocator allocator) @local
{
	return fixture_ctx_full(allocator, true, false);
}

fn Context* fixture_ctx_with_reasoning(Allocator allocator) @local
{
	return fixture_ctx_full(allocator, false, true);
}

fn Context* fixture_ctx_full(Allocator allocator, bool with_tool_calls, bool with_reasoning) @local
{
	ToolHub* tool_hub = alloc::new(allocator, ToolHub);
	tool_hub.init(allocator, { "ReadFile", "Bash" });

	SkillHub* skill_hub = alloc::new(allocator, SkillHub);
	skill_hub.init(allocator);

	Flag* flag = alloc::new(allocator, Flag);
	flag.init(allocator, { "mp", "--model", "test-model", "--api-key", "sk-test", "--base-url", "http://localhost/v1" })!!;

	Path log_file = flag.config_dir.append(allocator, "log/test.log")!!;

	Context* ctx = alloc::new(allocator, Context);
	ctx.init(allocator, "test-session", flag, tool_hub, skill_hub, log_file);

	// system message
	Message sys;
	context::message_init(&sys, allocator, "system");
	sys.content = "You are a test assistant.";
	ctx.add_message(&sys);

	// user message
	Message user;
	context::message_init(&user, allocator, "user");
	user.content = "Hello";
	ctx.add_message(&user);

	if (with_reasoning)
	{
		Message asst;
		context::message_init(&asst, allocator, "assistant");
		asst.reasoning_content = "I should greet back";
		asst.content = "Hi there!";
		ctx.add_message(&asst);
	}

	if (with_tool_calls)
	{
		Message asst;
		context::message_init(&asst, allocator, "assistant");
		asst.content = "";
		ToolCall tc;
		tc.id = "call_test1";
		tc.index = 0;
		tc.name = "Bash";
		tc.arguments = "{\"command\":\"ls\"}";
		asst.tool_calls.push(tc);
		ctx.add_message(&asst);

		Message tool_msg;
		context::message_init(&tool_msg, allocator, "tool");
		tool_msg.content = "file1\nfile2";
		tool_msg.tool_call_id = "call_test1";
		ctx.add_message(&tool_msg);
	}

	return ctx;
}

