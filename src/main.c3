module mini_pi;

import std::os;
import std::io;

import cli;
import tool;
import skill;
import context;
import rat_loop;

fn int main(String[] args)
{
	Flag flag;
	flag.init(tmem, args)!!;

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
	context.init(tmem, &flag, &tool_hub, &skill_hub);

	rat_loop::run(&context);

	return 0;
}
