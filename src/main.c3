module mini_pi;

import ng::cli;
import ng::tool;
import ng::skill;
import ng::context;
import ng::rat_loop;

fn int main(String[] args)
{
	Flag flag;
	flag.init(tmem, args)!!;

	SkillHub skill_hub;
	skill_hub.init(tmem);

	ToolHub tool_hub;
	tool_hub.init(tmem, flag.tools.split(tmem, ","));

	Context context;
	context.init(tmem, &flag, &tool_hub, &skill_hub);

	rat_loop::run(&context);

	return 0;
}
