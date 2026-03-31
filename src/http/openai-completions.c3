module http;

import std::io;
import std::encoding::json;
import std::collections::object;
import std::collections::list;

import core;
import util;

/** String 列表类型别名 */
alias HttpStringList = List{String};

/** 嵌入的模板文件内容 */
const String REQUEST_TPL = (String)$embed("request_template.json");

/** 故障定义：API 错误、空响应 */
faultdef
	API_ERROR,
	EMPTY_RESPONSE;

/**
 * 解析 API 响应 JSON 为 Message
 * @ctx: Context 指针
 * @json_doc: API 返回的 JSON 文档
 * @return: 解析出的 Message，解析失败返回 fault
 */
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

/**
 * 发送消息到 API 并获取响应
 * @ctx: Context 指针
 * @return: API 响应转换的 Message
 */
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
            messages.push(message);
		}

		// 构建请求体，替换模板中的占位符
		String request_body = REQUEST_TPL.replace(tmem, "{{tools}}", tool_schemas)
		.replace(tmem, "{{model_id}}", util::escape(tmem, ctx.init_options.model_id, false))
		.replace(tmem, "{{messages}}", string::format(tmem, "%s", messages));

		// 保存请求体到临时文件
		String filename = string::format(tmem,"logs/req_%s.json", util::timestamp_id(tmem));
		file::save(filename, request_body)!;

		// 构建 HTTP 请求头
		HttpStringList headers;
		headers.init(tmem);
		defer headers.free();
		headers.push(string::format(tmem, "Authorization: Bearer %s", ctx.init_options.api_key));
		headers.push("Content-Type: application/json");

		// 使用 HTTP 客户端发送请求
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

			return read_response_to_message(ctx, response.body);
		}
		else
		{
			io::printfn("HTTP request failed");
			return API_ERROR~;
		}
	};
}
