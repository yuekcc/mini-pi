module api;

import std::io;
import std::collections::list;

import c3x::object;
import context;
import util;
import global;

faultdef
	API_ERROR, EMPTY_RESPONSE
;

fn Message? read_response_to_message(Context* ctx, String json_doc)
{
	Object* res = object::parse(tmem, json_doc)!;
	Object* choices = res.get("choices")!;
	Object* last_choice = choices.get_at(0);

	if (try Object* message = last_choice.get("message"))
	{
		String role = message.get_string("role") ?? "assistant";
		String content = message.get_string("content") ?? "";
		String reasoning_content = message.get_string("reasoning_content") ?? "";
		Message result = {
			.id = util::timestamp_id(ctx.allocator),
			.role = role.copy(ctx.allocator),
			.content = content.copy(ctx.allocator),
			.reasoning_content = reasoning_content.copy(ctx.allocator),
			.tool_call_id = "",
			.tool_call = null,
		};
		if (try Object* tool_calls = message.get("tool_calls"))
		{
			io::printfn("> Detect tool calls, %s", tool_calls);
			Object* tool_call = tool_calls.get_at(0);
			if (tool_call != null)
			{
				result.tool_call_id = tool_call.get_string("id")!!.copy(ctx.allocator);
				result.tool_call = alloc::new(ctx.allocator, ToolCall);
				Object* function = tool_call.get("function")!!;
				result.tool_call.name = function.get_string("name")!!.copy(ctx.allocator);
				result.tool_call.arguments = function.get_string("arguments")!!.copy(ctx.allocator);
			}
		}

		return result;
	}

	return EMPTY_RESPONSE~;
}

fn Message? completions(Context* ctx)
{
	@pool()
	{
		String request_id = util::timestamp_id(tmem);

		Object* messages = object::new_obj(tmem);

		foreach (&msg : &ctx.messages)
		{
			Object* message = object::new_obj(tmem);
			messages.push(message);

			message.set("role", msg.role.copy(tmem));
			message.set("content", msg.content.copy(tmem));

			if (msg.role == "assistant")
			{
				message.set("reasoning_content", msg.reasoning_content.copy(tmem));
			}

			if (msg.tool_call_id != "")
			{
				message.set("tool_call_id", msg.tool_call_id.copy(tmem));

				if (msg.tool_call != null)
				{
					Object* tool_calls = object::new_obj(tmem);
					message.set("tool_calls", tool_calls);

					Object* tool_call = object::new_obj(tmem);
					tool_calls.push(tool_call);

					tool_call.set("id", msg.tool_call_id.copy(tmem));
					tool_call.set("index", 0);
					Object* function = object::new_obj(tmem);
					tool_call.set("function", function);

					function.set("name", msg.tool_call.name.copy(tmem));
					function.set("arguments", msg.tool_call.arguments.copy(tmem));
				}
			}
		}

		Object* request_body = object::new_obj(tmem);
		request_body.set("model", ctx.flag.model);
		request_body.set("tools", "{{tools_schema}}"); // 设置为模板
		request_body.set("tool_choice", "auto");
		request_body.set("stream", false);

		Object* thinking_config = object::new_obj(tmem);
		thinking_config.set("type", "enabled");
		request_body.set("thinking", thinking_config);
		request_body.set("messages", messages);

		String request_body_json = request_body.to_json(tmem);
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
			return read_response_to_message(ctx, response.body);
		}
		else
		{
			io::printfn("HTTP request failed");
			return API_ERROR~;
		}
	};
}
