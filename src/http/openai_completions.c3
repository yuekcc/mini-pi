module http;

import std::io;
import std::encoding::json;
import std::collections::object;
import std::collections::list;

import core;
import util;

alias HttpStringList = List{String};

const String REQUEST_TPL = (String)$embed("request_template.json");

faultdef
	API_ERROR,
	EMPTY_RESPONSE;

fn Message? read_response_to_message(Context* ctx, String json_doc)
{
	Object* res = json::parse_string(tmem, json_doc)!;
	Object* choices = res.get("choices")!;
	Object* last_choice = choices.get_at(0);

	if (try Object* message = last_choice.get("message"))
	{
		String role = message.get_string("role") ?? "assistant";
		String content = message.get_string("content") ?? "";
		Message result = {
			.id = util::timestamp_id(ctx.allocator),
			.role = role.copy(ctx.allocator),
			.content = content.copy(ctx.allocator),
		};
		if (try Object* tool_calls = message.get("tool_calls"))
		{
		    // 保存工具调用的原文件（字符串方式）
		    result.tool_call_raw = string::format(ctx.allocator, "%s", tool_calls);
			io::printfn("----\ncall_calls = %s\n----", result.tool_call_raw);
			Object* tool_call = tool_calls.get_at(0);
			if (tool_call != null)
			{
				result.tool_call = allocator::new(ctx.allocator, ToolCall);
				result.tool_call.id = tool_call.get_string("id")!!.copy(ctx.allocator);
				Object* function = tool_call.get("function")!!;
				result.tool_call.name = function.get_string("name")!!.copy(ctx.allocator);
				result.tool_call.arguments = function.get_string("arguments")!!.copy(ctx.allocator);
			}
		}

		return result;
	}

	return EMPTY_RESPONSE~;
}

fn Message? send_completion_request(Context* ctx, String tool_schemas)
{
	@pool()
	{
		Object* messages = object::new_obj(tmem);
		foreach (&msg : &ctx.messages)
		{
            Object* message = object::new_obj(tmem);
            message.set("role", msg.role);
            message.set("content", util::escape(tmem, msg.content, true));

            if (msg.tool_call_id != "")
            {
                message.set("tool_call_id", util::escape(tmem, msg.tool_call_id, true));
            }

            if (msg.tool_call_raw != "")
            {
                Object* tool_calls = json::parse_string(tmem, msg.tool_call_raw)!!;
                message.set("tool_calls", string::format(tmem, "%s", tool_calls));
            }

            messages.push(message);
		}

		String request_body = REQUEST_TPL.replace(tmem, "{{tools}}", tool_schemas)
		.replace(tmem, "{{model_id}}", util::escape(tmem, ctx.init_options.model_id, false))
		.replace(tmem, "{{messages}}", string::format(tmem, "%s", messages));

		util::dump("logs/req_%s.json", request_body);

		HttpStringList headers;
		headers.init(tmem);
		defer headers.free();
		headers.push(string::format(tmem, "Authorization: Bearer %s", ctx.init_options.api_key));
		headers.push("Content-Type: application/json");

		HttpClient client;
		client.init();
		defer client.free();

		if (try Response response = client.post(ctx.init_options.url, request_body, &headers))
		{
			io::printfn("HTTP Response\nstatus = %d\nbody =%s \n\n", response.status_code, response.body);

			if (response.status_code != 200)
			{
				io::printfn("HTTP request failed with status code: %d", response.status_code);
				return API_ERROR~;
			}

			util::dump("logs/resp_%s.json", response.body);
			return read_response_to_message(ctx, response.body);
		}
		else
		{
			io::printfn("HTTP request failed");
			return API_ERROR~;
		}
	};
}
