module api;

import std::io;
import std::collections::list;

import cjson;
import context;
import util;
import global;

faultdef
	API_ERROR, EMPTY_RESPONSE
;

fn Message? read_response_to_message(Context* ctx, String json_doc)
{
	CJsonItem* res = cjson::parse((ZString)json_doc);
	if (!res) return EMPTY_RESPONSE~;
	defer res.free();

	CJsonItem* choices = res.get_key("choices");
	if (!choices) return EMPTY_RESPONSE~;
	CJsonItem* last_choice = choices.get_at(0);

	if (CJsonItem* message = last_choice.get_key("message"))
	{
		String role = message.get_key_string("role", tmem) ?? "assistant";
		String content = message.get_key_string("content", tmem) ?? "";
		String reasoning_content = message.get_key_string("reasoning_content", tmem) ?? "";
		Message result = {
			.id = util::timestamp_id(ctx.allocator),
			.role = role.copy(ctx.allocator),
			.content = content.copy(ctx.allocator),
			.reasoning_content = reasoning_content.copy(ctx.allocator),
			.tool_call_id = "",
			.tool_call = null,
		};
		if (CJsonItem* tool_calls = message.get_key("tool_calls"))
		{
			io::printfn("> Detect tool calls, %s", tool_calls.to_string(tmem));
			CJsonItem* tool_call = tool_calls.get_at(0);
			if (tool_call != null)
			{
				result.tool_call_id = tool_call.get_key_string("id", tmem)!!.copy(ctx.allocator);
				result.tool_call = alloc::new(ctx.allocator, ToolCall);
				CJsonItem* function = tool_call.get_key("function");
				if (!function) return EMPTY_RESPONSE~;
				result.tool_call.name = function.get_key_string("name", tmem)!!.copy(ctx.allocator);
				result.tool_call.arguments = function.get_key_string("arguments", tmem)!!.copy(ctx.allocator);
			}
		}

		return result;
	}

	return EMPTY_RESPONSE~;
}

// 解析 OpenAI 兼容的 SSE 流式响应。
// HttpClient 已经把整个响应体累积进 DString 并作为 response.body 返回，
// 因此这里在请求结束后，一次性处理完整的 SSE 文本，不做打字机效果。
fn Message? read_stream_to_message(Context* ctx, String sse_body)
{
	@pool()
	{
		DString content_buf = dstring::new(tmem);
		DString reasoning_buf = dstring::new(tmem);
		DString tool_args_buf = dstring::new(tmem);

		String role = "assistant";
		String tool_id = "";
		String tool_name = "";
		bool has_tool_call = false;

		usz event_count = 0;
		usz skipped = 0;

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

			global::debug_log("stream event #%d: content +%d bytes, reasoning +%d bytes",
				event_count, content_part.len, reasoning_part.len);

			if (CJsonItem* tool_calls = delta.get_key("tool_calls"))
			{
				CJsonItem* tool_call = tool_calls.get_at(0);
				if (tool_call != null)
				{
					has_tool_call = true;

					// id 与 name 通常只在第一个分片中出现，arguments 则跨分片拼接。
					String id_part = tool_call.get_key_string("id", tmem) ?? "";
					if (id_part.len > 0) tool_id = id_part.copy(tmem);

					if (CJsonItem* function = tool_call.get_key("function"))
					{
						String name_part = function.get_key_string("name", tmem) ?? "";
						if (name_part.len > 0) tool_name = name_part.copy(tmem);

						String args_part = function.get_key_string("arguments", tmem) ?? "";
						if (args_part.len > 0) tool_args_buf.append(args_part);

						global::debug_log("stream event #%d: tool_call delta (id=%s name=%s, +%d args bytes)",
							event_count, tool_id, tool_name, args_part.len);
					}
				}
			}
		}

		Message result = {
			.id = util::timestamp_id(ctx.allocator),
			.role = role.copy(ctx.allocator),
			.content = content_buf.copy_str(ctx.allocator),
			.reasoning_content = reasoning_buf.copy_str(ctx.allocator),
			.tool_call_id = "",
			.tool_call = null,
		};

		global::debug_log("stream parse complete: %d events parsed, %d skipped, content=%d chars, reasoning=%d chars, tool_call=%s",
			event_count, skipped, content_buf.str_view().len, reasoning_buf.str_view().len,
			has_tool_call ? "yes" : "no");

		if (has_tool_call)
		{
			io::printfn("> Detect tool calls, name = %s, arguments = %s", tool_name, tool_args_buf.str_view());
			result.tool_call_id = tool_id.copy(ctx.allocator);
			result.tool_call = alloc::new(ctx.allocator, ToolCall);
			result.tool_call.name = tool_name.copy(ctx.allocator);
			result.tool_call.arguments = tool_args_buf.copy_str(ctx.allocator);
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
			}

			if (msg.tool_call_id != "")
			{
				message.set("tool_call_id", msg.tool_call_id);

				if (msg.tool_call != null)
				{
					CJsonItem* tool_calls = cjson::new_array(tmem);
					message.set("tool_calls", tool_calls);

					CJsonItem* tool_call = cjson::new_object(tmem);
					tool_calls.push_back(tool_call);

					tool_call.set("id", msg.tool_call_id);
					tool_call.set("index", 0);
					CJsonItem* function = cjson::new_object(tmem);
					tool_call.set("function", function);

					function.set("name", msg.tool_call.name);
					function.set("arguments", msg.tool_call.arguments);
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

		String request_body_json = request_body.to_string(tmem);
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
			io::printfn("> Remote reply: status = %d, body = %s", response.status_code, response.body);
			if (global::debug())
			{
				file::save(string::tformat("logs/req_%s_%d.json", request_id, response.status_code), response.body)!!;
			}

			if (response.status_code != 200)
			{
				io::printfn("HTTP request failed with status code: %d", response.status_code);
				return API_ERROR~;
			}
			return read_stream_to_message(ctx, response.body);
		}
		else
		{
			io::printfn("HTTP request failed");
			return API_ERROR~;
		}
	};
}
