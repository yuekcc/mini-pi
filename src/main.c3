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

// 交互模式 UI 主循环：渲染事件 + stdin 轮询输入。
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

		// 等输入（Agent 空闲）：stdin 就绪即读取并投递
		if (waiting_input && util::input::stdin_has_data())
		{
			UiEvent ev;
			String? maybe_line = ui::read_input(tmem);
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
			waiting_input = false;
			(void)app.ui_to_agent.push(ev);
		}
		thread::sleep_ms(10);
	}
}

// headless 模式 UI 主循环：只等 SHUTDOWN（渲染仍走事件）。
fn int ui_loop_headless(AppContext* app)
{
	while (true)
	{
		bool ready_seen = false;
		int exit_code = drain_and_render(app, &ready_seen);
		if (exit_code >= 0) return exit_code;
		thread::sleep_ms(10);
	}
}

// 统一 shutdown 协议（arch-next-spec 决策 14）：
// 停止 Agent → close 输入通道 → close 请求通道 → join 两线程 → logger.close()。
fn void shutdown(AppContext* app)
{
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
	// --resume：Agent 线程启动时从 transcript 重建（system prompt 快照 + 历史消息，
	// 丢弃未收尾 turn），不重新装配提示词。
	app.resumed = flag.resume_session != "";

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
	return exit_code;
}
