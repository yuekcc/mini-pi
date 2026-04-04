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
			.tool_call_id = "",
			.tool_call = null,
		};
		if (try Object* tool_calls = message.get("tool_calls"))
		{
		    // 保存工具调用的原文件（字符串方式）
		    // result.tool_call_raw = string::format(ctx.allocator, "%s", tool_calls);
			io::printfn("----\ncall_calls = %s\n----", string::format(ctx.allocator, "%s", tool_calls));
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

struct FunctionCallView
{
    String name;
    String arguments;
}

struct ToolCallView
{
    String id;
    String type;
    FunctionCallView function;
    int index;
}

struct MessageView
{
    String role;
    String content;
    String tool_call_id;
    ToolCallView[] tool_calls;
}

struct ThinkingConfig
{
    String type;
}

struct RequestBody
{
    String model;
    String tools;
    String tool_choice;
    bool stream;
    ThinkingConfig thinking;
    MessageView[] messages;
}


alias MessageViewList = List{MessageView};

fn Message? send_completion_request(Context* ctx, String tools_schema)
{
	@pool()
	{
	    MessageViewList messages;
		messages.init(tmem);

		foreach (&msg : &ctx.messages)
		{
            MessageView mv;
            mv.role = msg.role.copy(tmem);
            mv.content = msg.content.copy(tmem);

            if (msg.tool_call_id != "")
            {
                mv.tool_call_id = msg.tool_call_id.copy(tmem);

                if (msg.tool_call != null)
                {
                    ToolCallView tcv;
                    tcv.id = msg.tool_call_id.copy(tmem);
                    tcv.function.name = msg.tool_call.name.copy(tmem);
                    tcv.function.arguments = msg.tool_call.arguments.copy(tmem);
                    tcv.index = 0;

                    mv.tool_calls = {tcv};
                }
            }

            messages.push(mv);
		}

		RequestBody request_body;
		request_body.model = ctx.init_options.model_id;
		request_body.tools = "{{tools_schema}}";
		request_body.tool_choice = "auto";
		request_body.stream = false;
		request_body.thinking.type = "enabled";
		request_body.messages = messages.to_array(tmem);

		String request_body_json = json::marshal(tmem, request_body);
		request_body_json = request_body_json.replace(tmem, "\"{{tools_schema}}\"", tools_schema);

		util::dump("logs/req_%s.json", request_body_json);

		HttpStringList headers;
		headers.init(tmem);
		defer headers.free();
		headers.push(string::format(tmem, "Authorization: Bearer %s", ctx.init_options.api_key));
		headers.push("Content-Type: application/json");

		HttpClient client;
		client.init();
		defer client.free();

		if (try Response response = client.post(ctx.init_options.url, request_body_json, &headers))
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
