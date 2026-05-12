module mini_pi;

import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::list;
import std::os;

import c3x::object;
import context;
import util;
import tools;
import http;
import cli;
import skill;


fn int main(String[] args)
{
	CliOptions cli_opts;
	cli_opts.init(args)!!;

	if (cli_opts.help)
	{
		cli::print_help();
		return 0;
	}

	if (cli_opts.version)
	{
		cli::print_version();
		return 0;
	}

	SkillHub* skill_hub = skill::use_skill_hub();
	defer skill::free_skill_context();

	if (cli_opts.list_skills)
	{
		io::printfn("%s", skill_hub.print_installed(tmem));
		return 0;
	}

	InitOptions init_options;
	init_options.init(mem, &cli_opts);

	io::printfn("%s", init_options);

	// 工具池初始化
	ToolPool tool_pool;
	tool_pool.init(mem, init_options.tools.split(tmem, ","));
	defer tool_pool.free();

	// 全局上下文
	Context ctx;
	ctx.init(mem, &init_options, skill_hub);
	defer ctx.free();

	// 初始化
	agent_loop(&ctx, &tool_pool);
	return 0;
}
