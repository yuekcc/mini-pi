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

fn int main(String[] args)
{
	Flag flag;
	flag.init(tmem, args)!!;

	String session_id = util::timestamp_id(tmem);
	Path log_file = flag.config_dir.append(tmem, string::tformat("log/%s.log", session_id))!!;
	global::update(flag.config_dir, log_file, flag.enable_debug);

	io::eprintfn("Using config dir: %s", global::config_dir());
	io::eprintfn("Using log file: %s", global::log_file());
	io::eprintfn("Debug mode: %s", global::debug() ? "on": "off");

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

	SkillHub skill_hub;
	skill_hub.init(tmem);

	ToolHub tool_hub;
	tool_hub.init(tmem, flag.tools.split(tmem, ","));

	Context context;
	context.init(tmem, session_id, &flag, &tool_hub, &skill_hub, log_file);

	rat_loop::run(&context);

	return 0;
}
