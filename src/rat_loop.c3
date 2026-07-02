module rat_loop;

import std::io;
import std::os;

import c3x::object;

import context;
import cli;
import util;
import api;
import global;

fn void print_message(Message* msg)
{
	if (msg)
	{
		io::printfn(Ansi.BOLD +++ "%s:" +++ Ansi.RESET, msg.role);

		String content = msg.content.trim();
		String reasoning_content = msg.reasoning_content.trim();
		if (msg.role == "tool" && content != "" )
		{
			io::printfn("%s\n", content);
			return;
		}

		if (reasoning_content != "")
		{
			io::printfn(Ansi.BRIGHT_BLACK +++ "Thinking ... %s\n" +++ Ansi.RESET, reasoning_content.trim_left());
			
		}

		if (content != "")
		{
			io::printfn("%s\n", content);
		}
	}
}

fn String load_init_message(Allocator allocator, Flag* flag)
{
	String message = flag.task;
	if (message != "")
	{
		return message;
	}

	char[]? content = file::load(tmem, flag.task_file);
	if (catch excuse = content)
	{
		io::eprintfn("Load task file error, %s", excuse);
		os::exit(1);
	}

	message = (String)content;
	if (message == "")
	{
		io::eprintfn("Empty task, skipped");
		os::exit(1);
	}
	return message.copy(allocator);
}

fn Message* read_input(Allocator allocator)
{
	io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	String input = io::readline(tmem)!!;
	io::print(Ansi.RESET);

	Message* result = alloc::new(allocator, Message);
	result.role = "user";
	result.content = input.copy(allocator);
	return result;
}


fn void run(Context* context)
{
	bool calling_tools = false;
	bool init_message_added = false;

	context.reset();

	while RAT_LOOP: (true) @pool()
	{
		if (context.flag.enable_headless)
		{
			if (init_message_added)
			{
				io::printfn("DONE");
				os::exit(0);
			}
			else
			{
				Message reply = {
					.id = util::timestamp_id(tmem),
					.role = "user",
					.content = load_init_message(tmem, context.flag),
				};
				print_message(&reply);
				context.add_message(&reply);
				init_message_added = true;
			}
		}
		else if (calling_tools)
		{
			Message message = context.messages.last()!!;
			if (message.tool_call != null)
			{
				DString buf = dstring::new(tmem);
				Message reply = {
					.id = util::timestamp_id(tmem),
					.role = "tool",

					.tool_call_id = message.tool_call_id,
				};

				Object* tool_args = object::parse(tmem, message.tool_call.arguments)!!;

				if (catch excuse = context.tool_hub.do_dispatch(tmem, &buf, message.tool_call.name, tool_args))
				{
					reply.content = string::format(tmem, "Execute tool '%s' fault, %s. You should retry carefully", message.tool_call.name, excuse);
				}
				else
				{
					reply.content = buf.copy_str(tmem);
				}

				print_message(&reply);
				context.add_message(&reply);
			}
		}
		else
		{
			// 非 headless 模式，支持用户输入
			Message* user_input = read_input(tmem);
			context.add_message(user_input);
		}

		// 发送请求

		if (try Message message =  api::completions(context))
		{
			print_message(&message);
			context.add_message(&message);
			calling_tools = message.tool_call != null;
		}
		continue RAT_LOOP;
	};
}
