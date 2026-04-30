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
	// io::printfn("skill description: %s", skill.description);
}
