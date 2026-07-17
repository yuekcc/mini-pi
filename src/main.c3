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

fn int main(String[] args)
{
	Flag flag;
	flag.init(tmem, args)!!;

	String session_id = string::format(tmem, "ses_%s", util::timestamp_id(tmem));
	Path log_file = flag.config_dir.append(tmem, string::tformat("log/%s.log", session_id))!!;
	global::update(flag.config_dir, log_file, flag.enable_debug);

	// 打开日志文件句柄（追加模式），后续 log::info/warn/error/debug 会同时写入文件。
	// 失败时静默降级为仅控制台输出，不影响运行。
	log::init();
	
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

	rat_loop::run(&context);

	return 0;
}
