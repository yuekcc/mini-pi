module mini_pi;

import std::os;
import std::io;

import cli;
import tool;
import skill;
import context;
import rat_loop;
import global;
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
	global::update(flag.config_dir, log_file, flag.enable_debug, flag.enable_transcript);
	global::set_session_id(session_id);

	// 打开日志文件句柄（追加模式），后续 log::info/warn/error/debug 会同时写入文件。
	// 失败时静默降级为仅控制台输出，不影响运行。
	log::init();
	
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
		ui::banner(version::VERSION, global::config_dir(), global::log_file(), global::debug());
	}

	SkillHub skill_hub;
	skill_hub.init(tmem);

	ToolHub tool_hub;
	tool_hub.init(tmem, flag.tools.split(tmem, ","));

	Context context;
	context.init(tmem, session_id, &flag, &tool_hub, &skill_hub, log_file);

	// --resume：先从 transcript 重建消息序列（system prompt 快照 + 历史消息，丢弃未收尾 turn）。
	if (flag.resume_session != "")
	{
		if (!transcript::resume_into(tmem, &context))
		{
			log::error("Failed to resume session '%s'", flag.resume_session);
			os::exit(1);
		}
		context.resumed = true;
	}

	rat_loop::run(&context);

	return 0;
}
