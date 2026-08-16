import std::io;
import std::io::path;
import std::io::file;

import app;
import skill;
import tool;
import util;

// PromptAssembly 单元测试：模板渲染 + 注入物齐全（arch-next-spec 测试矩阵）。
fn void test_prompt_assembly_basic() @test
{
	ToolHub tool_hub;
	tool_hub.init(tmem, { "ReadFile", "Bash" });
	defer tool_hub.free();

	SkillHub skill_hub;
	skill_hub.init(tmem);
	defer skill_hub.free();

	Path config_dir = path::new(tmem, "testdata/tmp_pa_cfg")!!;
	Path cwd = path::cwd(tmem)!!;

	String prompt = app::build_system_prompt(tmem, config_dir, cwd, &tool_hub, &skill_hub);

	// {{cwd}} 模板渲染
	assert(prompt.contains(cwd), "cwd rendered into prompt");
	// behavioral guideline 注入
	assert(prompt.contains("## Behavioral Guidelines"), "behavioral guideline injected");
	// tools 列表 + tools_memo 注入
	assert(prompt.contains("## Available Tools"), "tools section present");
	assert(prompt.contains("- ReadFile:"), "ReadFile listed");
	assert(prompt.contains("- Bash:"), "Bash listed");
	// AGENTS.md → <project_instructions>（项目根有 AGENTS.md）
	assert(prompt.contains("<project_instructions"), "project instructions injected");
	assert(prompt.contains("AGENTS.md"), "AGENTS.md referenced");
	// skills 列表
	assert(prompt.contains("## Skills"), "skills section present");

	io::printfn("prompt length = %d", prompt.len);
}

fn void test_prompt_assembly_user_template() @test
{
	// 用户 SYSTEM.md 覆盖内置模板
	String cfg = string::tformat("testdata/tmp_pa_user_%s", util::timestamp_id(tmem));
	path::mkdir(path::new(tmem, cfg)!!, true)!!;
	file::save(path::new(tmem, string::tformat("%s/SYSTEM.md", cfg))!!, "CUSTOM SYSTEM TEMPLATE {{cwd}}")!!;

	ToolHub tool_hub;
	tool_hub.init(tmem, {});
	defer tool_hub.free();

	String prompt = app::build_system_prompt(tmem, path::new(tmem, cfg)!!, path::cwd(tmem)!!, &tool_hub, null);
	assert(prompt.starts_with("CUSTOM SYSTEM TEMPLATE"), "user SYSTEM.md wins over embedded template");
}

fn void test_prompt_assembly_no_tools() @test
{
	// 无工具：无 Available Tools 段（与 v1 行为一致）
	ToolHub tool_hub;
	tool_hub.init(tmem, {});
	defer tool_hub.free();

	String prompt = app::build_system_prompt(tmem, path::new(tmem, "testdata/tmp_pa_cfg")!!, path::cwd(tmem)!!, &tool_hub, null);
	assert(!prompt.contains("## Available Tools"), "no tools section when no tools enabled");
}
