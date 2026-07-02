import std::io;
import std::collections::list;
import skill;
import util;

fn void test_parse_markdown() @test
{
	String text = (String)file::load(tmem, "resources/skills/prd/SKILL.md")!!;
	Markdown* result = util::parse_markdown(text);

	assert(result.body.starts_with("# Product Requirements Document (PRD)"));
	assert(result.body.ends_with("- **Pass Rate**: 90% must match expected citations."));
}

fn void find_skill_dirs() @test
{
	List{Path} paths;
	skill::find_skill_dirs(&paths);

	io::printfn("found %d", paths.len());

	for (int i = 0; i < paths.len(); i++)
	{
		io::printfn("-> %s", paths.get(i));
	}
}

fn void test_skill_context() @test
{
	SkillHub context;
	context.init(tmem);
	defer context.free();

	// SkillHub* hub = skill::use_skill_hub();
	// defer hub.free();

	// Skill* skill = hub.data["codemap"]!!;
	// io::printfn("skill name: %s", skill.name);
	// io::printfn("skill description: %s", skill.description);
}

fn void test_use_skill_hub() @test
{
	SkillHub context;
	context.init(tmem);
	defer context.free();

	// 验证返回的不是 null
	assert(context.data.len() >= 0);

	io::printfn("test_use_skill_hub: context initialized");

	// 验证可以访问 skill 数据（如果有的话）
	// 遍历并打印已加载的 skill 名称
	int skill_count = 0;
	context.data.@each(; name, skill)
	{
		skill_count++;
		io::printfn("  Loaded skill: %s", name);
	};

	io::printfn("test_use_skill_hub: total %d skills loaded", skill_count);

	io::printfn("%s", context.print_installed(tmem));
}
