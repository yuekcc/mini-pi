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

const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

fn void print_history(Context* ctx)
{
    foreach (&msg : &ctx.messages)
    {
        io::printfn("# %s", msg.role);
        io::printfn("%s\n", msg.content.trim());
    }
}

fn void print_last_message(Context* ctx)
{
	if (try msg = ctx.messages.last())
	{
		io::printfn("# %s", msg.role);
		io::printfn("%s\n\n", msg.content.trim());
	}
}

fn Message* read_input(Context* ctx)
{
	io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	String input = io::readline(tmem)!!;
	io::print(Ansi.RESET);

	Message* result = alloc::new(ctx.allocator, Message);
	result.role = "user";
	result.content = input.copy(ctx.allocator);
	return result;
}

fn void agent_loop(Context* ctx, ToolPool* tool_pool)
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);

	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", ctx.cwd.str_view())
		.replace(tmem, "{{date}}", now_str);

	Message system_msg = {
		.role = "system",
		.content = final_system_prompt,
	};
	ctx.push_message(&system_msg);
	print_last_message(ctx);

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
			Message* last_msg = ctx.last_message(ctx.allocator);
			if (last_msg != null && last_msg.tool_call != null)
			{
				Message* tool_result = tool_pool.dispatch(ctx.allocator, last_msg.tool_call);
				ctx.push_message(tool_result);
				print_last_message(ctx);
			}
			calling_tools = false;
		}
		else if (!ctx.init_options.headless)
		{
			Message* user_input = read_input(ctx);
			ctx.push_message(user_input);
		}

		if (try Message message = http::send_completion_request(ctx, tool_pool.schema(tmem)))
		{
			ctx.push_message(&message);
			print_last_message(ctx);
			calling_tools = (message.tool_call != null);
		}

		continue AGENT_LOOP;
	};
}

fn int main(String[] args)
{
	InitOptions init_options = {
		.agent_name = "default",
		.init_message = "",
		.model_id = "minimax.com/MiniMax-M2.7",
		.url = "http://127.0.0.1:5678/chat/completions",
		.api_key = "sk-1234",
		.headless = false,
	};

	ToolPool tool_pool;
	tool_pool.init(mem, &init_options);
	defer tool_pool.free();

	Context ctx;
	ctx.init(mem, init_options);
	defer ctx.free();

	agent_loop(&ctx, &tool_pool);
	return 0;
}
