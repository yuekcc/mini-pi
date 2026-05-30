module ng::rat_loop;

import std::io;
import std::os;

import c3x::object;

import ng::context;
import ng::cli;
import ng::util;
import ng::api;

fn void print_message(Message* msg)
{
	if (msg)
	{
		String content = msg.content.trim();
		String reasoning_content = msg.reasoning_content.trim();
		if (msg.role == "tool" && content != "" )
		{
			io::printfn("%s\n", content);
			return;
		}
		if (reasoning_content != "")
		{
			io::printfn("Thinking ...");
			io::printfn("%s\n", reasoning_content);
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


fn void run(Context* context)
{
	bool calling_tools = false;
	bool init_message_added = false;

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
				context.add_message(&reply);
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

				if (catch excuse = context.tool_hub.do_dispatch(tmem, buf, message.tool_call.name, tool_args))
				{
					reply.content = string::format(tmem, "Execute tool '%s' fault, %s. You should retry carefully", message.tool_call.name, excuse);
				}
				else
				{
					reply.content = buf.copy_str(tmem);
				}

				context.add_message(&reply);
			}
		}
		else
		{
			// TODO
			io::printfn("未实现，目前只支持 headless 模式");
			os::exit(2);
		}

		// 发送请求

		if (try Message message =  api::completions(context))
		{
			context.add_message(&message);
			calling_tools = message.tool_call != null;
		}
		continue RAT_LOOP;
	};
}
