module context;

// 系统提示词装配（PromptAssembly）：从 Context.reset() 抽出的可重入纯函数。
// 产物 = 模板渲染（{{cwd}}/{{date}}/{{os}}）+ behavioral guideline + tools 列表
//        + tools_memo + AGENTS.md（<project_instructions>）+ 已安装 skill 列表。
// 调用点：AppContext.reset()（新会话与 /clear 时重新装配）；--resume 用 transcript
// 快照不重装。产物存入 AppContext.system_prompt_snapshot，session_start 直接引用。

import std::io::path;
import std::io::file;
import std::time::datetime;

import skill;
import tool;
import util;

const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");
const String TOOLS_MEMO_TPL = (String)$embed("tools_memo_template.md");
const String BEHAVIORAL_GUIDELINE_TPL = (String)$embed("behavioral_guideline_template.md");

// 尝试从 <config_dir>/SYSTEM.md 获取用户的系统提示词模板，失败则用内置模板。
fn String load_system_prompt_template(Path config_dir) @local
{
	Path user_system_prompt_tpl = config_dir.append(tmem, "SYSTEM.md")!!;
	if (try content = (String)file::load_path(tmem, user_system_prompt_tpl))
	{
		return content.trim();
	}

	return SYSTEM_PROMPT_TPL.trim();
}

fn String load_system_prompt(Path config_dir, Path cwd, String tools_list, bool enable_tools) @local
{
	DateTime now = datetime::now().to_local();
	String now_str = now.format(tmem, DateTimeFormat.DATEONLY);

	String os_uname = "Linux + Bash shell";
	$if env::WIN32:
		os_uname = "Windows 11 + Bash shell (bundled version in Git for Windows)";
	$endif

	DString final_system_prompt = dstring::new(tmem);
	final_system_prompt.append(load_system_prompt_template(config_dir));
	final_system_prompt.replace("{{cwd}}", cwd);
	final_system_prompt.replace("{{date}}", now_str);
	final_system_prompt.replace("{{os}}", os_uname);
	final_system_prompt.replace("{{cwd}}", cwd);

	final_system_prompt.appendf("\n\n%s", BEHAVIORAL_GUIDELINE_TPL.trim());

	if (enable_tools)
	{
		final_system_prompt.append("\n\n## Available Tools\n\n");
		final_system_prompt.append(tools_list.trim());
		final_system_prompt.append("\n\n");
		final_system_prompt.append(TOOLS_MEMO_TPL.trim());
	}

	return final_system_prompt.copy_str(tmem);
}

fn String load_agents_md(Allocator allocator)
{
	if (try content = (String)file::load(tmem, "AGENTS.md"))
	{
		return content.trim().copy(allocator);
	}

	return "";
}

// 装配完整 system prompt（含 Project Context 与 Skills 段），结果分配在 allocator。
// 可重入：无任何全局状态依赖（config_dir/cwd/hubs 全部入参）。
fn String build_system_prompt(Allocator allocator, Path config_dir, Path cwd, ToolHub* tool_hub, SkillHub* skill_hub)
{
	DString buf = dstring::new(tmem);

	buf.append(load_system_prompt(config_dir, cwd, tool_hub.printed_enabled_tools(tmem), tool_hub.tools.len > 0));

	String agents_md = load_agents_md(tmem);
	if (agents_md != "")
	{
		buf.append("\n\n## Project Context");
		buf.append("\n\nScan `<project_instructions>` for project-specific instructions and guidelines.");
		buf.appendf("\n\n<project_instructions path=\"AGENTS.md\">\n%s\n</project_instructions>", agents_md);
	}

	if (skill_hub != null)
	{
		String skill_list = skill_hub.print_installed(tmem);
		if (skill_list != "")
		{
			buf.append("\n\n## Skills");
			buf.appendf("\n\n%s", skill_list);
		}
	}

	return buf.copy_str(allocator);
}
