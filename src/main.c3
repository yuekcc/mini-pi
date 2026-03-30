module mini_pi;

import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::object;
import std::collections::list;

import core;
import cmd;
import util;
import tools;
import http;
import openai_completions;

/** 嵌入的模板文件内容 */
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

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
				Message* tool_result = tools::dispatch_tool_call(ctx, last_msg.tool_call);
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
		if (try Message message = openai_completions::send_completion_request(ctx))
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
