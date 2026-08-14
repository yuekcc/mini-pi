module rat_loop;

// Agent 主循环（v2）。
//
// 阶段 0：仍为单线程结构（Agent = 主线程），改动为 AppContext 统一挂载 +
// TokenLedger 记账 + transcript 事件经 TranscriptWriter 对象写入。
// 阶段 1 起：本模块整体迁移为 Agent 线程函数，内部升级为显式状态机
// （IDLE / AWAITING_API / EXECUTING_TOOLS / CANCELLING / SHUTDOWN，见 arch-next-spec 决策 10）。

import std::io;
import std::os;
import std::time::clock;

import cjson;

import context;
import cli;
import tool;
import util;
import api;
import log;
import ui;
import app;
import transcript;

fn String load_init_message(Allocator allocator, Flag* flag)
{
	String message = flag.task;
	if (message != "")
	{
		return message;
	}

	char[]? content = file::load(tmem, flag.task_file);
	if (catch ex = content)
	{
		log::error("Load task file error, %s", ex);
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

// 一轮用户输入的公共起点：生成 turn_id、累计轮次、写 user_message 事件、开启新轮记账。
// 交互输入与 headless 初始任务共用。
fn void start_user_turn(AppContext* app, String* turn_id, String content, bool is_command)
{
	*turn_id = util::timestamp_id(app.allocator);
	app.turns_total++;
	app.token_ledger.begin_turn();
	app.transcript.write_user_message(*turn_id, content, is_command);
}

// 斜杠命令也需合法 turn_id（会话首命令时为空）。
fn String ensure_turn_id(Allocator allocator, String* turn_id)
{
	if (turn_id.len == 0) *turn_id = util::timestamp_id(allocator);
	return *turn_id;
}

// 请求前 token 预算检查（TokenLedger 三态判定）：
//   OK → 放行；WARN → 写 system_event(token_warning) + UI 提示后放行；
//   EXCEEDED → 拒绝继续请求并提示（v1 范围只实现 WARN 的落盘与展示，compaction 预留）。
fn bool check_token_budget(AppContext* app, String turn_id, String request_id)
{
	BudgetVerdict verdict = app.token_ledger.check_budget();
	switch (verdict)
	{
		case BudgetVerdict.OK:
			return true;
		case BudgetVerdict.WARN:
		{
			CJsonItem* detail = cjson::new_object(tmem);
			detail.set("estimated_tokens", app.token_ledger.estimated_prompt_tokens());
			detail.set("context_window_limit", app.token_ledger.context_window_limit);
			detail.set("soft_ratio", app.token_ledger.soft_ratio);
			app.transcript.write_system_event(turn_id, request_id, transcript::SUBTYPE_TOKEN_WARNING, "warn", detail);
			ui::notice(
				"Token budget warning: ~%d/%d tokens used (soft threshold %.0f%%)",
				app.token_ledger.estimated_prompt_tokens(),
				app.token_ledger.context_window_limit,
				app.token_ledger.soft_ratio * 100
			);
			return true;
		}
		case BudgetVerdict.EXCEEDED:
			ui::notice(
				"Token budget exceeded: ~%d/%d tokens (hard threshold %.0f%%). Please /clear or start a new session.",
				app.token_ledger.estimated_prompt_tokens(),
				app.token_ledger.context_window_limit,
				app.token_ledger.hard_ratio * 100
			);
			return false;
	}
}

fn Message* read_input(Allocator allocator, AppContext* app, String* turn_id)
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
				String markdown = app.render_to_markdown(tmem);
				Path output_file = app.cwd.append(tmem, string::format(tmem, "%s.md", app.session_id))!!;
				file::save(output_file, markdown)!!;
				ui::notice("Saved to %s", output_file);
				continue;
			}
			else if (input_trimmed == "/clear")
			{
				// 旧会话收尾（interrupted）→ 新 session_id → 新 transcript 文件
				app.transcript.write_user_message(ensure_turn_id(app.allocator, turn_id), input_trimmed, true);
				app.transcript.write_session_end(*turn_id, "interrupted", app.turns_total);
				app.start_new_session();
				*turn_id = "";
				ui::notice("Start new session, session ID is %s", app.session_id);
				continue;
			}
			else if (input_trimmed == "/exit" || input_trimmed == "/e")
			{
				app.transcript.write_user_message(ensure_turn_id(app.allocator, turn_id), input_trimmed, true);
				app.transcript.write_session_end(*turn_id, "exit", app.turns_total);
				ui::notice("Bye, last session ID is %s", app.session_id);
				should_quit = true;
				break;
			}
		};

		Message* result = alloc::new(allocator, Message);
		context::message_init(result, allocator, "user");
		result.content = input_trimmed.copy(allocator);
		io::printfn("");

		start_user_turn(app, turn_id, input_trimmed, input_trimmed.starts_with("/"));
		return result;
	}

	if (should_quit)
	{
		os::exit(0);
	}

	return null;
}


fn void run(AppContext* app)
{
	bool calling_tools = false;
	bool init_message_added = false;
	sz tool_call_cursor = 0;     // 当前 assistant 消息中已执行的 tool_call 数量
	sz pending_assistant_idx = 0; // 待执行 tool_call 所属的 assistant 消息在列表中的下标

	// 当前 turn / API round-trip 标识（transcript 双键；分配在 app.allocator 上以跨迭代存活）
	String turn_id = "";
	String request_id = "";

	if (!app.resumed)
	{
		app.reset();
		app.write_session_start_event();
	}

	while RAT_LOOP: (true) @pool()
	{
		if (calling_tools)
		{
			// 逐个执行当前 assistant 消息中的 tool_call，全部执行完后再向模型请求。
			Message* assistant = app.messages.get_ref(pending_assistant_idx);
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
					// ToolContext：从 AppContext 构建的轻量只读视图（父会话信息/中间产物目录）。
					ToolContext tctx = {
						.session_id = app.session_id,
						.request_id = app.active_request_id,
						.config_dir = app.config_dir,
						.transcript_enabled = app.transcript.enabled,
					};
					if (catch ex = app.tool_hub.do_dispatch(&tctx, tmem, &buf, tc_name, tool_args, &meta))
					{
						reply.content = string::format(tmem, "Execute tool '%s' fault, %s. You should retry carefully", tc_name, ex);
					}
					else
					{
						log::debug("Tool '%s' (index %d) output: %s", tc_name, tc_index, buf.tcopy());
						reply.content = buf.copy_str(tmem);
					}
				}

				long tool_duration_ms = tool_started.to_now().to_ms();
				app.transcript.write_tool_result(
					turn_id, request_id,
					tc_id, tc_name, tc_args, reply.content,
					meta.output_file, tool_duration_ms, meta.exit_code, meta.has_exit_code
				);

				ui::render_message(&reply, tc_name);
				app.add_message(&reply);
				tool_call_cursor++;
				continue RAT_LOOP;
			}
			// 所有 tool_call 均已执行，落入下方继续向模型请求
		}
		else if (app.flag.enable_headless)
		{
			if (init_message_added)
			{
				app.transcript.write_session_end(turn_id, "exit", app.turns_total);
				ui::notice("DONE");
				os::exit(0);
			}
			else
			{
				Message reply;
				context::message_init(&reply, tmem, "user");
				reply.content = load_init_message(tmem, &app.flag);
				ui::render_message(&reply);
				start_user_turn(app, &turn_id, reply.content, false);
				app.add_message(&reply);
				init_message_added = true;
			}
		}
		else
		{
			// 非 headless 模式，支持用户输入
			Message* user_input = read_input(tmem, app, &turn_id);
			app.add_message(user_input);
		}

		// token 预算检查（请求前）
		if (!check_token_budget(app, turn_id, request_id))
		{
			// EXCEEDED：拒绝继续请求。交互模式回到输入；headless 直接收尾退出。
			if (app.flag.enable_headless)
			{
				app.transcript.write_session_end(turn_id, "error", app.turns_total);
				os::exit(1);
			}
			calling_tools = false;
			continue RAT_LOOP;
		}

		// 发送请求（latency 由 Agent 计时，供 api_usage 事件使用）
		Clock request_started = clock::now();
		api::ApiMeta meta;
		meta.finish_reason = "";
		meta.usage = {};
		meta.has_usage = false;
		String error_detail = "";

		Message? result = api::completions(app, turn_id, &request_id, &meta, &error_detail);
		if (catch ex = result)
		{
			// 接口异常（502 / 429 / 网络错误等）：写 system_event(api_error)。
			// - headless 模式直接退出，避免无意义循环占用。
			// - 交互模式复位工具调用状态后回到用户输入，杜绝卡死。
			app.transcript.write_system_event(
				turn_id, request_id,
				transcript::SUBTYPE_API_ERROR, "error",
				api::api_error_detail(error_detail)
			);
			if (app.flag.enable_headless)
			{
				app.transcript.write_session_end(turn_id, "error", app.turns_total);
				os::exit(1);
			}
			calling_tools = false;
			continue RAT_LOOP;
		}
		else
		{
			Message message = result;
			long latency_ms = request_started.to_now().to_ms();

			// token 记账（Agent 单写）+ api_usage 事件——先于 assistant_message 落盘，
			// 保持与 v1 一致的事件顺序（golden diff 护栏，User Story 29）。
			if (meta.has_usage)
			{
				app.token_ledger.record(
					request_id,
					{
						.prompt_tokens = meta.usage.prompt_tokens,
						.completion_tokens = meta.usage.completion_tokens,
						.reasoning_tokens = meta.usage.reasoning_tokens,
					}
				);
				app.transcript.write_api_usage(
					turn_id, request_id,
					meta.usage, latency_ms, app.flag.model, meta.finish_reason
				);
			}

			app.transcript.write_assistant_message(turn_id, request_id, &message);
			app.active_request_id = request_id;

			ui::render_message(&message);
			app.add_message(&message);
			if (message.tool_calls.len() > 0)
			{
				calling_tools = true;
				tool_call_cursor = 0;
				pending_assistant_idx = app.messages.len() - 1;
			}
			else
			{
				calling_tools = false;
			}
		}
		continue RAT_LOOP;
	};
}
