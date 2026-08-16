module mini_pi;

import std::os;
import std::io;
import std::thread;
import std::core::mem::allocators;

import cjson;
import cli;
import curl;
import tool;
import skill;
import context;
import rat_loop;
import api;
import app;
import util;
import util::input;
import util::ctrl_c;
import version;
import ui;
import log;
import transcript;

// UI 事件循环共用：排空 agent→ui 通道并渲染。
// 返回：-1 = 未收到 SHUTDOWN；>= 0 = SHUTDOWN 携带的进程退出码。
// ready_seen：本次排空期间是否收到 READY（Agent 回到 IDLE）。
// 事件负载（text/tool_name/msg）为 heap 分配，渲染后释放。
fn int drain_and_render(AppContext* app, bool* ready_seen)
{
	int exit_code = -1;
	UiOutEvent? maybe = app.agent_to_ui.try_pop();
	while (try ev = maybe)
	{
		switch (ev.kind)
		{
			case UiOutKind.SHUTDOWN:
				exit_code = ev.exit_code;
			case UiOutKind.READY:
				*ready_seen = true;
			default:
				ui::render_event(&ev);
		}
		// 释放事件负载
		if (ev.kind == UiOutKind.RENDER_MESSAGE)
		{
			if (ev.msg) context::message_free(app.allocator, ev.msg);
			if (ev.tool_name.len > 0) ev.tool_name.free(app.allocator);
		}
		else if (ev.text.len > 0)
		{
			ev.text.free(app.allocator);
		}
		maybe = app.agent_to_ui.try_pop();
	}
	return exit_code;
}

// 交互模式 UI 主循环：渲染事件 + stdin 轮询输入 + Ctrl+C 分流。
// Ctrl+C 语义（arch-next-spec 决策 12）：
//   - Agent 空闲（等待输入）：L3，等价 /exit（session_end(exit)）；
//   - Agent 忙（等 API 响应）：L1，置 cancel_flag，worker 取消请求 →
//     request_cancelled 事件 → 回输入态（工具执行中的中断语义见阶段 4）。
fn int ui_loop_interactive(AppContext* app)
{
	bool waiting_input = false;

	while (true)
	{
		bool ready_seen = false;
		int exit_code = drain_and_render(app, &ready_seen);
		if (exit_code >= 0) return exit_code;
		if (ready_seen)
		{
			waiting_input = true;
			ui::print_prompt();
		}

		// Ctrl+C 分流
		if (util::ctrl_c::pressed())
		{
			UiEvent ev = {
				.text = "/exit".copy(app.allocator),
			};
			if (waiting_input)
			{
				// L3：空闲时 Ctrl+C = /exit
				ev.type = UiEventType.COMMAND_EXIT;
			}
			else
			{
				// L1/L2：Agent 忙——置取消标志（worker 取消请求）；若有工具子进程
				// 在跑则杀进程树并投递 CANCEL_TOOL（L2），否则 CANCEL_REQUEST（L1）。
				app.cancel_flag.store(true);
				if (util::cmd::kill_current_child())
				{
					ev.type = UiEventType.CANCEL_TOOL;
				}
				else
				{
					ev.type = UiEventType.CANCEL_REQUEST;
				}
			}
			(void)app.ui_to_agent.push(ev);
			// 本轮不再读 stdin：Ctrl+C 时缓冲可能残留字符，同轮再读会投出第二条
			// 事件与取消事件竞态（L3 时尤为危险——先 /exit 后 USER_INPUT）。
			continue;
		}

		// 等输入（Agent 空闲）：stdin 就绪即读取并投递
		if (waiting_input && util::input::stdin_has_data())
		{
			UiEvent ev;
			String? maybe_line = ui::read_input(tmem);
			waiting_input = false;
			if (util::ctrl_c::pressed())
			{
				// ^C 打断输入读取：丢弃本次输入，L3 等价 /exit
				ev.type = UiEventType.COMMAND_EXIT;
				ev.text = "/exit".copy(app.allocator);
				(void)app.ui_to_agent.push(ev);
				continue;
			}
			if (catch e = maybe_line)
			{
				// EOF（管道关闭等）：等价 /exit
				ev.type = UiEventType.COMMAND_EXIT;
				ev.text = "/exit".copy(app.allocator);
			}
			else
			{
				String trimmed = maybe_line.trim();
				if (trimmed == "/clear")
				{
					ev.type = UiEventType.COMMAND_CLEAR;
				}
				else if (trimmed == "/export")
				{
					ev.type = UiEventType.COMMAND_EXPORT;
				}
				else if (trimmed == "/usage")
				{
					ev.type = UiEventType.COMMAND_USAGE;
				}
				else if (trimmed == "/exit" || trimmed == "/e")
				{
					ev.type = UiEventType.COMMAND_EXIT;
				}
				else
				{
					ev.type = UiEventType.USER_INPUT;
				}
				ev.text = trimmed.copy(app.allocator);
			}
			(void)app.ui_to_agent.push(ev);
		}
		thread::sleep_ms(10);
	}
}

// headless 模式 UI 主循环：只等 SHUTDOWN（渲染仍走事件）。
// Ctrl+C = 优雅停机：置 cancel_flag → worker 取消在途请求 → Agent 写
// session_end(interrupted) → SHUTDOWN(exit 1)（headless 中断语义，决策 12）。
fn int ui_loop_headless(AppContext* app)
{
	while (true)
	{
		bool ready_seen = false;
		int exit_code = drain_and_render(app, &ready_seen);
		if (exit_code >= 0) return exit_code;

		if (util::ctrl_c::pressed())
		{
			app.cancel_flag.store(true);
			(void)util::cmd::kill_current_child();
		}
		thread::sleep_ms(10);
	}
}

// 统一 shutdown 协议（arch-next-spec 决策 14）：
// 停止 Agent → close 输入通道 → close 请求通道 + 置 cancel_flag → join 两线程
// → logger.close()（由 main 收尾）。三种退出路径均无 hang、无孤儿线程。
fn void shutdown(AppContext* app)
{
	app.cancel_flag.store(true);
	app.ui_to_agent.close();
	app.agent_to_api.close();
	(void)app.agent_thread.join();
	(void)app.api_thread.join();
}

fn int main(String[] args)
{
	Flag flag;
	flag.init(tmem, args)!!;

	String session_id = string::format(tmem, "ses_%s", util::timestamp_id(tmem));
	// --resume：沿用被恢复会话的 session_id，transcript 继续追加到同一文件。
	if (flag.resume_session != "")
	{
		session_id = flag.resume_session.copy(tmem);
	}

	Path log_file = flag.config_dir.append(tmem, string::tformat("log/%s.log", session_id))!!;

	// Logger 对象化：main 早期显式初始化（文件 sink 追加模式，失败静默降级为仅控制台）。
	Logger logger;
	logger.init(log_file, flag.enable_debug);
	log::set_default(&logger);

	// 冲突规则：--resume 与 --task/--task-file 互斥（headless 下允许组合，用于 Task 子进程续跑）。
	if (flag.resume_session != "" && !flag.enable_headless && (flag.task != "" || flag.task_file != ""))
	{
		log::error("--resume conflicts with --task/--task-file in interactive mode");
		os::exit(1);
	}

	if (flag.show_help)
	{
		flag.print_help();
		os::exit(0);
	}
	else if (flag.show_version)
	{
		flag.print_version();
		os::exit(0);
	}
	else if (flag.show_skills)
	{
		SkillHub skill_hub;
		skill_hub.init(tmem);
		io::printfn("%s", skill_hub.print_installed(tmem));
		os::exit(0);
	}

	ui::init();
	if (!flag.enable_headless)
	{
		ui::banner(version::VERSION, flag.config_dir, log_file, flag.enable_debug);
	}

	SkillHub skill_hub;
	skill_hub.init(tmem);

	ToolHub tool_hub;
	tool_hub.init(tmem, flag.tools.split(tmem, ","));

	// cjson 内存钩子：main 调用一次（多线程下独立树并发安全，已实验验证）。
	cjson::init_mem_hooks();

	// curl_global_init 必须在创建任何线程前、在 main 显式调用一次（多线程下 libcurl 硬要求）。
	(void)curl::global_init(curl::CurlGlobal.ALL);

	// AppContext：统一全局状态挂载点（配置/会话状态/资源/子系统/运行时信号）。
	Allocator heap = &allocators::LIBC_ALLOCATOR;
	AppContext app;
	app.init(flag, heap, session_id, &tool_hub, &skill_hub, &logger, flag.max_tokens);
	// --resume 判定在 Agent 线程启动时自行计算（会话状态区仅 Agent 写，决策 2）。

	// Ctrl+C 捕获（handler 只置 atomic 标志；交互与 headless 均安装）。
	util::ctrl_c::install();

	// 非主线程控制台日志与 notice 转发（注册在 UI 事件循环启动前）。
	logger.set_console_sink(&ui::forward_log_event, &app);
	ui::set_notice_sink(&ui::forward_notice, &app);

	// 三线程拓扑：Agent 线程 + API worker 线程（headless 与交互共用，OQ-4）。
	app.agent_thread.create(&rat_loop::agent_main, &app)!!;
	app.api_thread.create(&api::api_worker_main, &app)!!;

	int exit_code = 0;
	if (flag.enable_headless)
	{
		// headless：主线程投递初始任务（读失败 exit 1，与 v1 语义一致），
		// 随后等待 SHUTDOWN + join。
		String init = rat_loop::load_init_message(tmem, &app.flag);
		UiEvent ev = { .type = UiEventType.USER_INPUT, .text = init.copy(heap) };
		(void)app.ui_to_agent.push(ev);
		exit_code = ui_loop_headless(&app);
		shutdown(&app);
	}
	else
	{
		// 交互模式
		exit_code = ui_loop_interactive(&app);
		shutdown(&app);
	}

	logger.close();
	log::debug("main: returning %d", exit_code);
	return exit_code;
}
