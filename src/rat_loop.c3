module rat_loop;

import std::io;
import std::os;
import std::time;
import std::time::clock;

import cjson;

import context;
import cli;
import tool;
import util;
import api;
import log;
import ui;
import global;
import transcript;

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
		log::error("Load task file error, %s", excuse);
		os::exit(1);
	}

	message = (String)content;
	if (message == "")
	{
		log::error("Empty task, skipped");
		os::exit(1);
	}
	return message.copy(allocator);
}

// 写入当前会话的 session_start 事件（system_prompt 取 messages[0] 装配产物快照）。
fn void write_session_start_event(Context* context)
{
	String system_prompt = "";
	if (context.messages.len() > 0) system_prompt = context.messages[0].content;

	transcript::write_session_start(
		context.allocator,
		context.session_id,
		context.flag.model,
		context.flag.agent,
		string::format(tmem, "%s", context.cwd),
		system_prompt,
		transcript::tool_names(tmem, context.tool_hub)
	);
}

// 一轮用户输入的公共起点：生成 turn_id、累计轮次、写 user_message 事件。
// 交互输入与 headless 初始任务共用。
fn void start_user_turn(Context* context, String* turn_id, String content, bool is_command)
{
	*turn_id = util::timestamp_id(context.allocator);
	context.turns_total++;
	transcript::write_user_message(context.allocator, context.session_id, *turn_id, content, is_command);
}

// 斜杠命令也需合法 turn_id（会话首命令时为空）。
fn String ensure_turn_id(Allocator allocator, String* turn_id)
{
	if (turn_id.len == 0) *turn_id = util::timestamp_id(allocator);
	return *turn_id;
}

fn Message* read_input(Allocator allocator, Context* context, String* turn_id)
{
	bool should_quit = false;
	while (true)
	{
		String input = ui::read_prompt(tmem);
		String input_trimmed = input.trim();

		@pool()
		{
			if (input_trimmed == "/export")
			{
				String markdown = context.render_to_markdown(tmem);
				Path output_file = context.cwd.append(tmem, string::format(tmem, "%s.md", context.session_id))!!;
				file::save(output_file, markdown)!!;
				ui::notice("Saved to %s", output_file);
				continue;
			}
			else if (input_trimmed == "/clear")
			{
				// 旧会话收尾（interrupted）→ 新 session_id → 新 transcript 文件
				transcript::write_user_message(context.allocator, context.session_id, ensure_turn_id(context.allocator, turn_id), input_trimmed, true);
				transcript::write_session_end(context.allocator, context.session_id, *turn_id, "interrupted", context.turns_total);
				context.reset();
				context.session_id = string::format(context.allocator, "ses_%s", util::timestamp_id(tmem));
				context.turns_total = 0;
				global::set_session_id(context.session_id);
				write_session_start_event(context);
				*turn_id = "";
				ui::notice("Start new session, session ID is %s", context.session_id);
				continue;
			}
			else if (input_trimmed == "/exit" || input_trimmed == "/e")
			{
				transcript::write_user_message(context.allocator, context.session_id, ensure_turn_id(context.allocator, turn_id), input_trimmed, true);
				transcript::write_session_end(context.allocator, context.session_id, *turn_id, "exit", context.turns_total);
				ui::notice("Bye, last session ID is %s", context.session_id);
				should_quit = true;
				break;
			}
		};

		Message* result = alloc::new(allocator, Message);
		context::message_init(result, allocator, "user");
		result.content = input_trimmed.copy(allocator);
		io::printfn("");

		start_user_turn(context, turn_id, input_trimmed, input_trimmed.starts_with("/"));
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

	// 当前 turn / API round-trip 标识（transcript 双键；分配在 context.allocator 上以跨迭代存活）
	String turn_id = "";
	String request_id = "";

	if (!context.resumed)
	{
		context.reset();
		write_session_start_event(context);
	}

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

				Clock tool_started = clock::now();
				ToolResultMeta meta;
				meta.output_file = "";
				meta.exit_code = 0;
				meta.has_exit_code = false;

				DString buf = dstring::new(tmem);
				Message reply;
				context::message_init(&reply, tmem, "tool");
				reply.tool_call_id = tc_id.copy(tmem);

				CJsonItem* tool_args = cjson::parse((ZString)tc_args);
				if (!tool_args)
				{
					reply.content = string::format(tmem, "Execute tool '%s' fault, malformed JSON arguments.", tc_name);
				}
				else
				{
					defer tool_args.free();
					if (catch excuse = context.tool_hub.do_dispatch(tmem, &buf, tc_name, tool_args, &meta))
					{
						reply.content = string::format(tmem, "Execute tool '%s' fault, %s. You should retry carefully", tc_name, excuse);
					}
					else
					{
						log::debug("Tool '%s' (index %d) output: %s", tc_name, tc_index, buf.tcopy());
						reply.content = buf.copy_str(tmem);
					}
				}

				long tool_duration_ms = tool_started.to_now().to_ms();
				transcript::write_tool_result(
					context.allocator, context.session_id, turn_id, request_id,
					tc_id, tc_name, tc_args, reply.content,
					meta.output_file, tool_duration_ms, meta.exit_code, meta.has_exit_code
				);

				ui::render_message(&reply);
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
				transcript::write_session_end(context.allocator, context.session_id, turn_id, "exit", context.turns_total);
				ui::notice("DONE");
				os::exit(0);
			}
			else
			{
				Message reply;
				context::message_init(&reply, tmem, "user");
				reply.content = load_init_message(tmem, context.flag);
				ui::render_message(&reply);
				start_user_turn(context, &turn_id, reply.content, false);
				context.add_message(&reply);
				init_message_added = true;
			}
		}
		else
		{
			// 非 headless 模式，支持用户输入
			Message* user_input = read_input(tmem, context, &turn_id);
			context.add_message(user_input);
		}

		// 发送请求
		Message? result = api::completions(context, turn_id, &request_id);
		if (catch excuse = result)
		{
			// 接口异常（502 / 429 / 网络错误等）：api.c3 已打印一行告警并写 system_event(api_error)。
			// - headless 模式直接退出，避免无意义循环占用。
			// - 交互模式复位工具调用状态后回到用户输入，杜绝卡死。
			if (context.flag.enable_headless)
			{
				transcript::write_session_end(context.allocator, context.session_id, turn_id, "error", context.turns_total);
				os::exit(1);
			}
			calling_tools = false;
			continue RAT_LOOP;
		}
		else
		{
			Message message = result;
			transcript::write_assistant_message(context.allocator, context.session_id, turn_id, request_id, &message);
			global::set_active_request_id(request_id);
			ui::render_message(&message);
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
