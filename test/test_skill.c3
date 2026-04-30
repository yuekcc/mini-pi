import std::io;
import std::collections::list;
import skill;

fn void test_parse_markdown() @test
{
	String text = (String)file::load(tmem, "resources/skills/prd/SKILL.md")!!;
	Markdown* result = skill::parse_markdown(text);

	// io::printfn("front_matter_body:\n***********************\n%s\n***********************", result.front_matter_body);

	// io::printfn("\n\nbody:\n***********************\n%s\n***********************", result.body);

	assert(result.body.starts_with("# Product Requirements Document (PRD)"));
	assert(result.body.ends_with("- **Pass Rate**: 90% must match expected citations."));
}

fn void test_find_skill_dirs() @test
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
	SkillContext context;

	List{Path} paths;
	skill::find_skill_dirs(&paths);

	context.init(mem, paths.to_array(tmem));
	defer context.free();

	// SkillContext* hub = skill::use_skill_context();
	// defer hub.free();

	// Skill* skill = hub.data["codemap"]!!;
	// io::printfn("skill name: %s", skill.name);
	// io::printfn("skill description: %s", skill.description);ukn
}

fn void test_use_skill_context() @test
{
	// 第一次调用，应该初始化并返回 context
	SkillContext* context1 = skill::use_skill_context();
	
	// 验证返回的不是 null
	assert(context1 != null);
	
	// 再次调用，应该返回相同的实例（静态变量）
	SkillContext* context2 = skill::use_skill_context();
	assert(context1 == context2);
	
	io::printfn("test_use_skill_context: context1 == context2 (same pointer)");
	
	// 验证可以访问 skill 数据（如果有的话）
	// 遍历并打印已加载的 skill 名称
	int skill_count = 0;
	context1.data.@each(; name, skill)
	{
		skill_count++;
		io::printfn("  Loaded skill: %s", name);
	};
	
	io::printfn("test_use_skill_context: total %d skills loaded", skill_count);
	
	// 释放静态 context，避免内存泄漏检测失败
	skill::free_skill_context();
}

fn void test_print_installed_skills() @test
{
	SkillContext* context = skill::use_skill_context();
	defer skill::free_skill_context();

	io::printfn("%s", context.print_installed(tmem));
}
