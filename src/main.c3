module mini_pi;
import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::object;
import std::collections::list;
import std::encoding::json;

import core;
import cmd;
import util;
import tools;

/** 故障定义：命令执行错误、空响应 */
faultdef
	EXECUTE_COMMAND_ERROR,
	EMPTY_RESPONSE;

/** 嵌入的模板文件内容 */
const String REQUEST_TPL = (String)$embed("request_template.json");
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");
const String TOOLS_SCHEMA = (String)$embed("tools_schema.json");

/**
 * 打印完整的对话历史
 * @ctx: Context 指针
 */
fn void print_history(Context* ctx)
{
    foreach (&msg : &ctx.messages)
    {
        io::printfn("# %s", msg.role);
        io::printfn("%s\n", msg.content.trim());
    }
}

/**
 * 打印最近一条消息
 * @ctx: Context 指针
 */
fn void print_last_message(Context* ctx)
{
	if (try msg = ctx.messages.last())
	{
		io::printfn("# %s", msg.role);
		io::printfn("%s\n\n", msg.content.trim());
	}
}

/**
 * 读取用户输入
 * @ctx: Context 指针
 * @return: 用户输入构建的 Message
 */
fn Message* read_input(Context* ctx)
{
	io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	String input = io::readline(tmem)!!;
	io::print(Ansi.RESET);

	Message* result = allocator::new(ctx.allocator, Message);
	result.role = "user";
	result.content = input.copy(ctx.allocator);
	return result;
}

/**
 * 解析 API 响应 JSON 为 Message
 * @ctx: Context 指针
 * @json_doc: API 返回的 JSON 文档
 * @return: 解析出的 Message，解析失败返回 fault
 */
fn Message? read_to_message(Context* ctx, String json_doc)
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
fn Message? send_messages(Context* ctx)
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
		String request_body = REQUEST_TPL.replace(tmem, "{{tools}}", TOOLS_SCHEMA)
		.replace(tmem, "{{model_id}}", util::escape(tmem, ctx.init_options.model_id, false))
		.replace(tmem, "{{messages}}", string::format(tmem, "%s", messages));

		// 保存请求体到临时文件
		String filename = string::format(tmem,"logs/req_%s.json", util::timestamp_id(tmem));
		file::save(filename, request_body)!;

		// 构建 curl 命令
		String[] cmd = {
			"curl",
			"-s",                      // 不显示进度
			"-X", "POST",              // POST 方法
			"-H", string::format(tmem, "Authorization: %s", ctx.init_options.api_key), // 认证头
			"-H", "Content-Type: application/json",
			"--data-binary", string::format(tmem, "@%s", filename), // 通过文件传入请求体
			ctx.init_options.url,
		};

		CommandResult curl_result = cmd::execute(tmem, cmd)!;
		io::printfn("Execute curl\ncode = %d\nresult =%s \n\n", curl_result.code, curl_result.output);

		if (curl_result.code != 0)
		{
			io::printfn("Failed to run curl. Code = %d, message = %s", curl_result.code, curl_result.output);
			return EXECUTE_COMMAND_ERROR~;
		}

		return read_to_message(ctx, curl_result.output);
	};
}

/**
 * 执行工具调用
 * @ctx: Context 指针
 * @tool_call: 工具调用信息
 * @return: 工具执行结果构建的 Message
 */
fn Message* dispatch_tool_calls(Context* ctx, ToolCall* tool_call)
{
	Object* arguments = json::parse_string(tmem, tool_call.arguments)!!;
	String call_tool_result = tools::dispatch(tmem, tool_call.name, arguments);

	Message* result = allocator::new(ctx.allocator, Message);
	result.id = tool_call.id.copy(ctx.allocator);
	result.role = "tool";
	result.content = call_tool_result.copy(ctx.allocator);
	return result;
}

/**
 * Agent 主循环：处理用户输入、调用 API、执行工具
 * @ctx: Context 指针
 */
fn void agent_loop(Context* ctx)
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);

	// 填充系统提示模板
	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", ctx.cwd.str_view())
		.replace(tmem, "{{date}}", now_str);

	// 添加系统消息
	Message system_msg = {
		.role = "system",
		.content = final_system_prompt,
	};
	ctx.push_message(&system_msg);
	print_last_message(ctx);

	// Headless 模式：使用初始化消息作为第一条用户消息
	if (ctx.init_options.headless)
	{
		Message user_msg = {
			.role = "user",
			.content = ctx.init_options.init_message.copy(ctx.allocator),
		};
		ctx.push_message(&user_msg);
		print_last_message(ctx);
	}

	bool calling_tools = false;

	while AGENT_LOOP: (true) @pool()
	{
		if (calling_tools)
		{
			// 执行工具调用
			Message* last_msg = ctx.last_message(ctx.allocator);
			if (last_msg != null && last_msg.tool_call != null)
			{
				Message* tool_result = dispatch_tool_calls(ctx, last_msg.tool_call);
				ctx.push_message(tool_result);
				print_last_message(ctx);
			}
			calling_tools = false;
		}
		else if (!ctx.init_options.headless)
		{
			// 读取用户输入
			Message* user_input = read_input(ctx);
			ctx.push_message(user_input);
		}

		// 发送消息并获取响应
		if (try Message message = send_messages(ctx))
		{
			ctx.push_message(&message);
			print_last_message(ctx);
			// 检查是否需要继续调用工具
			calling_tools = (message.tool_call != null);
		}

		continue AGENT_LOOP;
	};
}


/**
 * 程序入口点
 * @args: 命令行参数
 * @return: 退出码
 */
fn int main(String[] args)
{
	InitOptions init_options = {
		.agent_name = "default",
		.init_message = "",
		.model_id = "LongCat-Flash-Thinking",
		.url = "http://127.0.0.1:5678/chat/completions",
		.api_key = "sk-1234",
		.headless = false,
	};

	Context ctx;
	ctx.init(mem, init_options);
	defer ctx.free();

	agent_loop(&ctx);
	return 0;
}
