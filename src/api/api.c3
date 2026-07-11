module api;

import std::io;
import std::collections::list;
import std::time::datetime;

import cjson;
import context;
import util;
import global;

faultdef
	API_ERROR, EMPTY_RESPONSE;

fn Message? read_response_to_message(Allocator allocator, String json_doc)
{
	CJsonItem* res = cjson::parse((ZString)json_doc);
	if (!res) return EMPTY_RESPONSE~;
	defer res.free();

	CJsonItem* choices = res.get_key("choices");
	if (!choices) return EMPTY_RESPONSE~;
	CJsonItem* last_choice = choices.get_at(0);

	if (CJsonItem* message = last_choice.get_key("message"))
	{
		String role              = message.get_key_string("role", tmem) ?? "assistant";
		String content           = message.get_key_string("content", tmem) ?? "";
		String reasoning_content = message.get_key_string("reasoning_content", tmem) ?? "";
		Message result = {
			.id = util::timestamp_id(allocator),
			.role = role.copy(allocator),
			.content = content.copy(allocator),
			.reasoning_content = reasoning_content.copy(allocator),
			.tool_call_id = "",
			.timestamp = datetime::now(),
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
				global::debug_log("> Detect %d tool calls", result.tool_calls.len());
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
fn Message? read_stream_to_message(Allocator allocator, String sse_body)
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
		global::debug_log("parsing SSE stream response: %d lines", lines.len);
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
				global::debug_log("skipping unparseable SSE chunk: %s", payload);
				skipped++;
				continue;
			}
			defer chunk.free();

			CJsonItem* choices = chunk.get_key("choices");
			if (!choices) continue;
			CJsonItem* choice = choices.get_at(0);
			if (!choice) continue;

			CJsonItem* delta = choice.get_key("delta");
			if (!delta) continue;

			event_count++;

			String role_part = delta.get_key_string("role", tmem) ?? "";
			if (role_part.len > 0) role = role_part.copy(tmem);

			String content_part = delta.get_key_string("content", tmem) ?? "";
			if (content_part.len > 0) content_buf.append(content_part);

			String reasoning_part = delta.get_key_string("reasoning_content", tmem) ?? "";
			if (reasoning_part.len > 0) reasoning_buf.append(reasoning_part);

			global::debug_log(
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

						global::debug_log(
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
		};
		result.tool_calls.init(allocator);

		global::debug_log(
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

				global::debug_log(
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

fn Message? completions(Context* ctx)
{
	@pool()
	{
		String request_id = util::timestamp_id(tmem);

		CJsonItem* messages = cjson::new_array(tmem);

		foreach (&msg : &ctx.messages)
		{
			CJsonItem* message = cjson::new_object(tmem);
			messages.push_back(message);

			message.set("role", msg.role);
			message.set("content", msg.content);

			if (msg.role == "assistant")
			{
				message.set("reasoning_content", msg.reasoning_content);

				// 回传模型产生的全部 tool_calls（单个或多个），供模型继续对话。
				if (msg.tool_calls.len() > 0)
				{
					CJsonItem* tool_calls = cjson::new_array(tmem);
					message.set("tool_calls", tool_calls);

					foreach (&tc : msg.tool_calls)
					{
						CJsonItem* tool_call = cjson::new_object(tmem);
						tool_calls.push_back(tool_call);

						tool_call.set("id", tc.id);
						tool_call.set("index", (int)tc.index);
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

		CJsonItem* request_body = cjson::new_object(tmem);
		request_body.set("model", ctx.flag.model);
		request_body.set("tools", "{{tools_schema}}"); // 设置为模板
		request_body.set("tool_choice", "auto");
		request_body.set("stream", true);

		CJsonItem* thinking_config = cjson::new_object(tmem);
		thinking_config.set("type", "enabled");
		request_body.set("thinking", thinking_config);
		request_body.set("messages", messages);

		String request_body_json = string::format(tmem, "%s", request_body);
		request_body.free();
		request_body_json = request_body_json.replace(tmem, "\"{{tools_schema}}\"", ctx.tool_hub.schema(tmem));
		if (global::debug())
		{
			file::save(string::tformat("logs/req_%s.json", request_id), request_body_json)!!;
		}

		List{String} headers;
		headers.init(tmem);
		defer headers.free();

		// TODO 从配置读出 api-key，而不是直接使用 .flag.apiKey
		headers.push(string::format(tmem, "Authorization: Bearer %s", ctx.flag.apiKey));
		headers.push("Content-Type: application/json");

		HttpClient client;
		client.init();
		defer client.free();

		// TODO 从配置读出 baseUrl，而不是直接使用 .flag.baseUrl
		String url = string::format(tmem, "%s/chat/completions", ctx.flag.baseUrl);

		global::debug_log("streaming completions request: model=%s -> %s", ctx.flag.model, url);

		if (try Response response = client.post(url, request_body_json, &headers))
		{
			global::debug_log("> Remote reply: status = %d, body = %s", response.status_code, response.body);
			if (global::debug())
			{
				file::save(string::tformat("logs/req_%s_%d.json", request_id, response.status_code), response.body)!!;
			}

			if (response.status_code != 200)
			{
				global::debug_log("HTTP request failed with status code: %d", response.status_code);
				return API_ERROR~;
			}
			return read_stream_to_message(ctx.allocator, response.body);
		}
		else
		{
			global::debug_log("HTTP request failed");
			return API_ERROR~;
		}
	};
}
