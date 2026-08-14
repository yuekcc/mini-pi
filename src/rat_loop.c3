module rat_loop;

// Agent 线程主函数（v2 三线程拓扑，arch-next-spec 决策 8/10）。
//
// 职责：turn 管理、工具游标调度、消息装配、请求体快照构造、transcript 全部事件
// 写入、token 记账、/clear /export 处理。禁止：阻塞等 stdin、直接执行 HTTP。
//
// 显式状态机（取代 v1 隐式游标状态）：
//   IDLE           等 UI 输入（阻塞点 1：ui_to_agent.pop）
//   AWAITING_API   已投递请求，等 API 响应（阻塞点 2：api_to_agent.pop）
//   EXECUTING_TOOLS 逐个执行 tool_calls（永久串行，OQ-2）
//   CANCELLING     丢弃半成品 turn（阶段 2 起进入）
//   SHUTDOWN       写 session_end → 线程退出
// 空闲零 CPU：两个阻塞点都在通道 pop 上。
//
// 线程常驻：turn 状态（turn_id / tool_call_cursor / pending_assistant_idx）留在
// 状态机局部变量，这是「messages/token/transcript 由 Agent 单写、无需锁」的前提。

import std::io;
import std::os;
import std::time::clock;
import std::thread;
import std::core::mem::allocators;

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

const sz AGENT_POOL_SIZE = 8 * 1024 * 1024;

enum AgentState
{
	IDLE,
	AWAITING_API,
	EXECUTING_TOOLS,
	CANCELLING,
	SHUTDOWN,
}

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

// ---- UI 事件推送辅助（Agent → UI 通道；文本 heap 分配，UI 释放）----------------

fn void push_notice(AppContext* app, String text)
{
	UiOutEvent ev = {
		.kind = UiOutKind.NOTICE,
		.text = text.copy(app.allocator),
	};
	(void)app.agent_to_ui.push(ev);
}

fn void push_render(AppContext* app, Message* msg, String tool_name)
{
	UiOutEvent ev = {
		.kind = UiOutKind.RENDER_MESSAGE,
		.msg = context::message_clone(app.allocator, msg),
		.tool_name = tool_name.copy(app.allocator),
	};
	(void)app.agent_to_ui.push(ev);
}

fn void push_shutdown(AppContext* app, int exit_code)
{
	UiOutEvent ev = { .kind = UiOutKind.SHUTDOWN, .exit_code = exit_code };
	(void)app.agent_to_ui.push(ev);
}

fn void push_ready(AppContext* app)
{
	UiOutEvent ev = { .kind = UiOutKind.READY };
	(void)app.agent_to_ui.push(ev);
}

// ---- Agent 状态机 -----------------------------------------------------------

// 一轮用户输入的公共起点：生成 turn_id、累计轮次、写 user_message 事件、开启新轮记账。
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
			push_notice(
				app,
				string::tformat(
					"Token budget warning: ~%d/%d tokens used (soft threshold %.0f%%)",
					app.token_ledger.estimated_prompt_tokens(),
					app.token_ledger.context_window_limit,
					app.token_ledger.soft_ratio * 100
				)
			);
			return true;
		}
		case BudgetVerdict.EXCEEDED:
			push_notice(
				app,
				string::tformat(
					"Token budget exceeded: ~%d/%d tokens (hard threshold %.0f%%). Please /clear or start a new session.",
					app.token_ledger.estimated_prompt_tokens(),
					app.token_ledger.context_window_limit,
					app.token_ledger.hard_ratio * 100
				)
			);
			return false;
	}
}

// 构造请求快照并投递 API worker，进入 AWAITING_API。request_id 由 Agent 生成
// （heap 分配，跨 turn 存活）。
fn void dispatch_api_request(AppContext* app, String turn_id, String* request_id)
{
	*request_id = util::timestamp_id(app.allocator);
	ApiRequest* req = api::build_api_request(app, app.allocator, *request_id);
	(void)app.agent_to_api.push(*req);
	alloc::free(app.allocator, req);
}

// 收到成功响应后的公共处理：记账 + api_usage + assistant_message（v1 事件顺序：
// api_usage 先于 assistant_message，golden diff 护栏）+ 渲染 + 入消息列表。
fn void handle_api_success(AppContext* app, String turn_id, String request_id, ApiResponse* resp)
{
	Message* message = resp.message;

	if (resp.has_usage)
	{
		app.token_ledger.record(
			request_id,
			{
				.prompt_tokens = resp.usage.prompt_tokens,
				.completion_tokens = resp.usage.completion_tokens,
				.reasoning_tokens = resp.usage.reasoning_tokens,
			}
		);
		app.transcript.write_api_usage(
			turn_id, request_id,
			resp.usage, resp.latency_ms, app.flag.model, resp.finish_reason
		);
	}

	app.transcript.write_assistant_message(turn_id, request_id, message);
	app.active_request_id = request_id;

	push_render(app, message, "");
	app.add_message(message);
}

// 串行执行一个 tool_call（v1 do_dispatch 逻辑原样迁移，运行在 Agent 线程）。
fn void execute_one_tool(AppContext* app, String turn_id, String request_id, Message* assistant, sz cursor)
{
	ToolCall* tc = assistant.tool_calls.get_ref(cursor);

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

	push_render(app, &reply, tc_name);
	app.add_message(&reply);
}

fn void agent_loop(AppContext* app)
{
	Allocator heap = app.allocator;

	if (app.resumed)
	{
		// --resume：从 transcript 重建消息序列（system prompt 快照 + 历史，丢弃未收尾 turn）。
		// 失败：错误日志 + 收尾退出（与 v1 main 中 os::exit(1) 语义一致）。
		if (!app.transcript.resume_into(&app.messages, &app.turns_total))
		{
			log::error("Failed to resume session '%s'", app.session_id);
			push_shutdown(app, 1);
			return;
		}
	}
	else
	{
		app.reset();
		app.write_session_start_event();
	}

	AgentState state = AgentState.IDLE;
	bool session_ended = false;
	int exit_code = 0;

	// turn 状态（状态机局部变量；Agent 单写 messages/token/transcript 的前提）
	String turn_id = "";
	String request_id = "";
	sz tool_call_cursor = 0;
	sz pending_assistant_idx = 0;

	// 交互模式：启动即就绪，UI 打印输入提示
	if (!app.flag.enable_headless) push_ready(app);

	while (state != AgentState.SHUTDOWN)
	{
		switch (state)
		{
			case AgentState.IDLE:
			{
				UiEvent? maybe = app.ui_to_agent.pop();
				if (catch e = maybe)
				{
					// CHANNEL_CLOSED：shutdown 信号（main 关闭输入通道）→ 收尾退出
					if (e != thread::CHANNEL_CLOSED) break;
					if (!session_ended)
					{
						app.transcript.write_session_end(turn_id, "exit", app.turns_total);
						session_ended = true;
					}
					state = AgentState.SHUTDOWN;
					break;
				}
				UiEvent ev = maybe;
				switch (ev.type)
				{
					case UiEventType.USER_INPUT:
					{
						start_user_turn(app, &turn_id, ev.text, false);
						Message* user_msg = alloc::new(heap, Message);
						context::message_init(user_msg, heap, "user");
						user_msg.content = ev.text.copy(heap);
						push_render(app, user_msg, "");
						app.add_message(user_msg);
						context::message_free(heap, user_msg);

						if (!check_token_budget(app, turn_id, request_id))
						{
							// EXCEEDED：拒绝继续请求（headless 收尾退出，交互回输入态）
							if (app.flag.enable_headless)
							{
								app.transcript.write_session_end(turn_id, "error", app.turns_total);
								session_ended = true;
								exit_code = 1;
								push_shutdown(app, exit_code);
								state = AgentState.SHUTDOWN;
							}
							else
							{
								push_ready(app);
								state = AgentState.IDLE;
							}
							break;
						}
						dispatch_api_request(app, turn_id, &request_id);
						state = AgentState.AWAITING_API;
						break;
					}
					case UiEventType.COMMAND_CLEAR:
					{
						// 旧会话收尾（interrupted）→ 新 session_id → 新 transcript 文件
						app.transcript.write_user_message(ensure_turn_id(heap, &turn_id), ev.text, true);
						app.transcript.write_session_end(turn_id, "interrupted", app.turns_total);
						app.start_new_session();
						turn_id = "";
						push_notice(app, string::tformat("Start new session, session ID is %s", app.session_id));
						if (!app.flag.enable_headless) push_ready(app);
						state = AgentState.IDLE;
						break;
					}
					case UiEventType.COMMAND_EXPORT:
					{
						app.transcript.write_user_message(ensure_turn_id(heap, &turn_id), ev.text, true);
						@pool()
						{
							String markdown = app.render_to_markdown(tmem);
							Path output_file = app.cwd.append(tmem, string::format(tmem, "%s.md", app.session_id))!!;
							file::save(output_file, markdown)!!;
							push_notice(app, string::tformat("Saved to %s", output_file));
						};
						if (!app.flag.enable_headless) push_ready(app);
						state = AgentState.IDLE;
						break;
					}
					case UiEventType.COMMAND_EXIT:
					{
						app.transcript.write_user_message(ensure_turn_id(heap, &turn_id), ev.text, true);
						app.transcript.write_session_end(turn_id, "exit", app.turns_total);
						session_ended = true;
						push_notice(app, string::tformat("Bye, last session ID is %s", app.session_id));
						push_shutdown(app, 0);
						state = AgentState.SHUTDOWN;
						break;
					}
					case UiEventType.CANCEL_REQUEST: // 阶段 3 起处理
					case UiEventType.CANCEL_TOOL:
						state = AgentState.IDLE;
						break;
				}
				ev.text.free(heap);
				break;
			}
			case AgentState.AWAITING_API:
			{
				ApiResponse? maybe = app.api_to_agent.pop();
				if (catch e = maybe)
				{
					if (e == thread::CHANNEL_CLOSED)
					{
						if (!session_ended)
						{
							app.transcript.write_session_end(turn_id, "exit", app.turns_total);
							session_ended = true;
						}
						state = AgentState.SHUTDOWN;
					}
					break;
				}
				ApiResponse resp = maybe;

				if (resp.cancelled)
				{
					// L1 请求中断：写 system_event(request_cancelled)（additive），
					// 丢弃半成品 turn（不 add assistant 消息、不写 tool_result），
					// 与「未收尾 turn」语义一致——resume 尾部丢弃逻辑天然兼容。
					CJsonItem* detail = cjson::new_object(tmem);
					detail.set("request_id", request_id);
					detail.set("latency_ms", resp.latency_ms);
					detail.set("has_partial_content", false);
					app.transcript.write_system_event(
						turn_id, request_id,
						transcript::SUBTYPE_REQUEST_CANCELLED, "info",
						detail
					);
					if (app.flag.enable_headless)
					{
						app.transcript.write_session_end(turn_id, "interrupted", app.turns_total);
						session_ended = true;
						push_shutdown(app, 1);
						state = AgentState.SHUTDOWN;
					}
					else
					{
						push_notice(app, "interrupted");
						push_ready(app);
						state = AgentState.IDLE;
					}
				}
				else if (resp.error_detail.len > 0)
				{
					// API 错误：写 system_event(api_error)。headless 直接收尾退出；交互回输入态。
					app.transcript.write_system_event(
						turn_id, request_id,
						transcript::SUBTYPE_API_ERROR, "error",
						api::api_error_detail(resp.error_detail)
					);
					if (app.flag.enable_headless)
					{
						app.transcript.write_session_end(turn_id, "error", app.turns_total);
						session_ended = true;
						exit_code = 1;
						push_shutdown(app, exit_code);
						state = AgentState.SHUTDOWN;
					}
					else
					{
						push_ready(app);
						state = AgentState.IDLE;
					}
				}
				else
				{
					handle_api_success(app, turn_id, request_id, &resp);
					if (resp.message.tool_calls.len() > 0)
					{
						tool_call_cursor = 0;
						pending_assistant_idx = app.messages.len() - 1;
						state = AgentState.EXECUTING_TOOLS;
					}
					else
					{
						if (app.flag.enable_headless)
						{
							app.transcript.write_session_end(turn_id, "exit", app.turns_total);
							session_ended = true;
							push_notice(app, "DONE");
							push_shutdown(app, 0);
							state = AgentState.SHUTDOWN;
						}
						else
						{
							push_ready(app);
							state = AgentState.IDLE;
						}
					}
				}
				api::api_response_free(&resp, heap);
				break;
			}
			case AgentState.EXECUTING_TOOLS:
			{
				Message* assistant = app.messages.get_ref(pending_assistant_idx);
				if (tool_call_cursor < assistant.tool_calls.len())
				{
					execute_one_tool(app, turn_id, request_id, assistant, tool_call_cursor);
					tool_call_cursor++;
					state = AgentState.EXECUTING_TOOLS;
				}
				else
				{
					// 全部执行完 → 再请求（预算检查）
					if (!check_token_budget(app, turn_id, request_id))
					{
						if (app.flag.enable_headless)
						{
							app.transcript.write_session_end(turn_id, "error", app.turns_total);
							session_ended = true;
							exit_code = 1;
							push_shutdown(app, exit_code);
							state = AgentState.SHUTDOWN;
						}
						else
						{
							push_ready(app);
							state = AgentState.IDLE;
						}
						break;
					}
					dispatch_api_request(app, turn_id, &request_id);
					state = AgentState.AWAITING_API;
				}
				break;
			}
			case AgentState.CANCELLING:
			{
				// 阶段 2 起：丢弃半成品 turn（无半截 assistant 消息/无 tool_result），
				// 写 system_event(request_cancelled / tool_cancelled)，回 IDLE。
				state = AgentState.IDLE;
				break;
			}
			case AgentState.SHUTDOWN:
				// 循环条件保证不可达；仅为 switch 穷举
				break;
		}
	}
}

fn int agent_main(void* arg)
{
	AppContext* app = (AppContext*)arg;

	// 新线程必须 @pool_init 包裹才能使用 tmem（否则 panic）。
	@pool_init(&allocators::LIBC_ALLOCATOR, AGENT_POOL_SIZE)
	{
		agent_loop(app);
	};

	return 0;
}
