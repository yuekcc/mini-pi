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
import flags;

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


fn void agent_loop(Context* ctx, ToolPool* tool_pool)
{
    print_last_message(ctx);

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
			// 再次循环到用户输入的回合，如果已经添加过初始消息，说明 LLM 已经执行结束
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
    InitOptions init_options;
	if (catch err = init_options.init(mem, args))
	{
	    io::printfn("Flags parse error, %s", err);
		return 1;
	}

	if (init_options.print_help)
	{
        flags::print_help();
        return 0;
	}

	if (init_options.print_version)
	{
	    flags::print_version();
        return 0;
	}

	io::printfn("%s", init_options);

	// 工具池初始化
	ToolPool tool_pool;
	tool_pool.init(mem, &init_options);
	defer tool_pool.free();

	// 全局上下文
	Context ctx;
	ctx.init(mem, &init_options);
	defer ctx.free();

    // 初始化
	agent_loop(&ctx, &tool_pool);
	return 0;
}
