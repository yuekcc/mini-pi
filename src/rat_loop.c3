module rat_loop;

import std::io;
import std::os;
import std::time::datetime;

import cjson;

import context;
import cli;
import util;
import api;
import global;

fn void print_message(Message* msg)
{
	if (msg)
	{
		defer io::print("\n");

		io::printfn(Ansi.BOLD +++ "%s %s:" +++ Ansi.RESET, msg.timestamp.to_local().format(tmem, DateTimeFormat.DATETIME), msg.role);

		String content = msg.content.trim().replace(tmem, "\t", "    ");
		String reasoning_content = msg.reasoning_content.trim().replace(tmem, "\t", "    ");
		if (msg.role == "tool" && content != "" )
		{
			io::printfn(Ansi.BG_BRIGHT_BLACK +++ Ansi.WHITE +++ "\n%s" +++ Ansi.RESET, content);
			return;
		}

		if (reasoning_content != "")
		{
			io::printfn(Ansi.BRIGHT_BLACK +++ Ansi.ITALIC +++ "\nThinking ... %s" +++ Ansi.RESET, reasoning_content);
			
		}

		if (content != "")
		{
			io::printfn("\n%s", content);
		}

		// assistant 调用工具
		if (msg.role == "assistant" && msg.tool_calls.len() > 0)
		{
			io::print("\n");
			foreach (&tc : msg.tool_calls)
			{
				io::printfn(Ansi.BRIGHT_YELLOW +++ "(Call tool: %s with %s)" +++ Ansi.RESET, tc.name, tc.arguments);
			}
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

fn Message* read_input(Allocator allocator, Context* context)
{
	bool should_quit = false;
	while (true)
	{
		io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
		String input = io::readline(tmem)!!;
		io::print(Ansi.RESET);

		String input_trimmed = input.trim();

		@pool()
		{
			if (input_trimmed == "/export")
			{
				String markdown = context.render_to_markdown(tmem);
				Path output_file = context.cwd.append(tmem, string::format(tmem, "%s.md", context.session_id))!!;
				file::save(output_file, markdown)!!;
				io::printfn(Ansi.BRIGHT_YELLOW +++ "(Saved to %s)" +++ Ansi.RESET +++ "\n", output_file);
				continue;
			}
			else if (input_trimmed == "/clear")
			{
				context.reset();
				context.session_id = string::format(context.allocator, "ses_%s", util::timestamp_id(tmem));
				io::printfn(Ansi.BRIGHT_YELLOW +++ "(Start new session, session ID is %s)" +++ Ansi.RESET +++ "\n", context.session_id);
				continue;
			}
			else if (input_trimmed == "/exit" || input_trimmed == "/e")
			{
				io::printfn(Ansi.BRIGHT_YELLOW +++ "(Bye, last session ID is %s)" +++ Ansi.RESET +++ "\n", context.session_id);
				should_quit = true;
				break;
			}
		};

		Message* result = alloc::new(allocator, Message);
		context::message_init(result, allocator, "user");
		result.content = input_trimmed.copy(allocator);
		return result;
	}

	if (should_quit)
	{
		os::exit(0);
	}

	return null;
}


fn void run(Context* context)
{
	bool calling_tools = false;
	bool init_message_added = false;
	sz tool_call_cursor = 0;     // 当前 assistant 消息中已执行的 tool_call 数量
	sz pending_assistant_idx = 0; // 待执行 tool_call 所属的 assistant 消息在列表中的下标

	context.reset();

	while RAT_LOOP: (true) @pool()
	{
		if (calling_tools)
		{
			// 逐个执行当前 assistant 消息中的 tool_call，全部执行完后再向模型请求。
			Message* assistant = context.messages.get_ref(pending_assistant_idx);
			if (tool_call_cursor < assistant.tool_calls.len())
			{
				ToolCall* tc = assistant.tool_calls.get_ref(tool_call_cursor);

				// 先复制所需字段，避免后续 add_message 触发列表重分配后指针失效。
				String tc_id = tc.id.copy(tmem);
				String tc_name = tc.name.copy(tmem);
				String tc_args = tc.arguments.copy(tmem);
				usz tc_index = tc.index;

				DString buf = dstring::new(tmem);
				Message reply;
				context::message_init(&reply, tmem, "tool");
				reply.tool_call_id = tc_id.copy(tmem);

				CJsonItem* tool_args = cjson::parse((ZString)tc_args);
				if (!tool_args)
				{
					reply.content = string::format(tmem, "Execute tool '%s' fault, malformed JSON arguments.", tc_name);
					print_message(&reply);
					context.add_message(&reply);
					tool_call_cursor++;
					continue RAT_LOOP;
				}
				defer tool_args.free();

				if (catch excuse = context.tool_hub.do_dispatch(tmem, &buf, tc_name, tool_args))
				{
					reply.content = string::format(tmem, "Execute tool '%s' fault, %s. You should retry carefully", tc_name, excuse);
				}
				else
				{
					global::debug_log("Tool '%s' (index %d) output: %s", tc_name, tc_index, buf.tcopy());
					reply.content = buf.copy_str(tmem);
				}

				print_message(&reply);
				context.add_message(&reply);
				tool_call_cursor++;
				continue RAT_LOOP;
			}
			// 所有 tool_call 均已执行，落入下方继续向模型请求
		}
		else if (context.flag.enable_headless)
		{
			if (init_message_added)
			{
				io::printfn(Ansi.BRIGHT_YELLOW +++ "(DONE)" +++ Ansi.RESET);
				os::exit(0);
			}
			else
			{
				Message reply;
				context::message_init(&reply, tmem, "user");
				reply.content = load_init_message(tmem, context.flag);
				print_message(&reply);
				context.add_message(&reply);
				init_message_added = true;
			}
		}
		else
		{
			// 非 headless 模式，支持用户输入
			Message* user_input = read_input(tmem, context);
			context.add_message(user_input);
		}

		// 发送请求
		if (try Message message =  api::completions(context))
		{
			print_message(&message);
			context.add_message(&message);
			if (message.tool_calls.len() > 0)
			{
				calling_tools = true;
				tool_call_cursor = 0;
				pending_assistant_idx = context.messages.len() - 1;
			}
			else
			{
				calling_tools = false;
			}
		}
		continue RAT_LOOP;
	};
}
