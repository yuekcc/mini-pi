module mini_pi;

import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::list;
import std::os;

import c3x::object;
import context;
import util;
import tools;
import http;
import getopts;

const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

fn void print_last_message(Context* ctx)
{
	if (try msg = ctx.messages.last())
	{
		io::printfn(util::bold("# %s"), msg.role);

		String content = msg.content.trim();
		if (content == "")
		{
		    io::printfn("");
			return;

		}

		if (msg.role == "tool")
		{
		    io::printfn(util::system_message("%s\n"), content);
		}
		else
		{
		    io::printfn("%s\n", content);
		}
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

fn void init_context(Context* ctx)
{
   	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);

	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", ctx.cwd.str_view())
		.replace(tmem, "{{date}}", now_str)
        .replace(tmem, "{{os}}", "Windows 11 + Msys2 + GNU Bash 5.2 (x86_64-pc-msys)");

	Message system_msg = {
		.role = "system",
		.content = final_system_prompt,
	};
	ctx.push_message(&system_msg);
	print_last_message(ctx);
}

fn void agent_loop(Context* ctx, ToolPool* tool_pool)
{
    // 是否需要调用工具
	bool calling_tools = false;
	bool init_message_added = false;

	while AGENT_LOOP: (true) @pool()
	{
	    // 调用工具
		if (calling_tools)
		{
			Message* last_msg = ctx.last_message(ctx.allocator);
			if (last_msg != null && last_msg.tool_call != null)
			{
				Message* tool_result = tool_pool.dispatch(ctx.allocator, last_msg.tool_call_id, last_msg.tool_call);
				ctx.push_message(tool_result);
				print_last_message(ctx);
			}
			calling_tools = false;
		}
		else if (ctx.init_options.headless)
		{
		    if (init_message_added)
			{
			    io::printfn(util::system_message("> DONE"));
				os::exit(0);
			}
			else
			{
                Message message = {
                   	.role = "user",
                   	.content = ctx.init_options.init_message,
                };
                ctx.push_message(&message);
                print_last_message(ctx);
                init_message_added = true;
			}
		}
		else
		{
			// 非 headless 模式，支持用户输入
    		Message* user_input = read_input(ctx);
    		ctx.push_message(user_input);
		}

		// 发送请求
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
	InitOptions*? init_options = getopts::parse(mem, args);
	if (catch err = init_options)
	{
	    io::printfn("Flags parse error, %s", err);
		return 1;
	}

	// 工具池初始化
	ToolPool tool_pool;
	tool_pool.init(mem, init_options);
	defer tool_pool.free();

	// 全局上下文
	Context ctx;
	ctx.init(mem, init_options);
	defer ctx.free();

    // 初始化
    init_context(&ctx);
	agent_loop(&ctx, &tool_pool);
	return 0;
}
