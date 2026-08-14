module mini_pi;

import std::os;
import std::io;
import std::core::mem::allocators;

import cli;
import tool;
import skill;
import context;
import rat_loop;
import app;
import util;
import version;
import ui;
import log;
import transcript;

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

	// AppContext：统一全局状态挂载点（配置/会话状态/资源/子系统，按所有权分区）。
	// allocator 用 LIBC 堆（跨线程存活，阶段 1 起 Agent 线程直接使用）。
	Allocator heap = &allocators::LIBC_ALLOCATOR;
	AppContext app;
	app.init(flag, heap, session_id, &tool_hub, &skill_hub, &logger, flag.max_tokens);

	// --resume：先从 transcript 重建消息序列（system prompt 快照 + 历史消息，丢弃未收尾 turn）。
	if (flag.resume_session != "")
	{
		if (!app.transcript.resume_into(&app.messages, &app.turns_total))
		{
			log::error("Failed to resume session '%s'", flag.resume_session);
			os::exit(1);
		}
		app.resumed = true;
	}

	rat_loop::run(&app);

	logger.close();
	return 0;
}
