module skill;

import std::collections::map;
import std::collections::list;
import std::io::path;
import std::os::env;
import std::io;

struct Skill
{
	String name;
	String description;
	String content;
	String path;
	bool ready;
}

fn void Skill.free(&self, Allocator allocator)
{
	if (self.path != "") self.path.free(allocator);
	if (self.name != "") self.name.free(allocator);
	if (self.description != "") self.description.free(allocator);
	if (self.content != "") self.content.free(allocator);
}

fn Skill* Skill.init(&self, Allocator allocator, Path dir)
{
	Path skill_file = dir.append(tmem, "SKILL.md")!!;
	if (!path::exists(skill_file))
	{
		self.ready = false;
		return self;
	}

	// 记录 SKILL.md 的路径
	self.path = skill_file.str_view().copy(allocator);

	String text = (String)file::load_path(tmem, skill_file)!!;

	Markdown* markdown = parse_markdown(text);

	// 记录 SKILL.md 的正文
	self.content = markdown.body.copy(allocator);

	String name = markdown.front_matter.get_string("name") ?? "";
	String description = markdown.front_matter.get_string("description") ?? "";

	// 记录名称
	if (name != "") self.name = name.copy(allocator);

	// 记录描述
	if (description != "") self.description = description.copy(allocator);

	// 名称、描述、正文三者非空都是合法的 skill
	if (self.name != "" && self.description != "" && self.content != "")
	{
		self.ready = true;
	}

	return self;
}

struct SkillHub
{
	HashMap{String, Skill*} data;
	Allocator allocator;
}

fn SkillHub* SkillHub.init(&self, Allocator allocator, Path[] paths)
{
	self.allocator = allocator;
	self.data.init(allocator);

	foreach (path : paths)
	{
		Skill* skill = alloc::new(allocator, Skill);
		skill.init(allocator, path);
		if (skill.ready)
		{
			self.data.set(skill.name, skill);
		}
		else
		{
			// 释放未 ready 的 skill
			skill.free(allocator);
			alloc::free(allocator, skill);
		}
	}

	return self;
}

fn String SkillHub.print_installed(&self, Allocator allocator)
{
	if (self.data.len() == 0)
	{
		return "";
	}

	DString buf = dstring::new(tmem);
	buf.append("The following skills provide specialized instructions for specific tasks.\n");
	buf.append("Use the read tool to load a skill's file when the task matches its description.\n");
	buf.append("When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.\n");
	buf.append("\n");

	self.data.@each(; name, skill)
	{
		buf.append("<skill>\n");
		buf.appendf("  <name>%s</name>\n", escape_xml(name));
		buf.appendf("  <description>%s</description>\n", escape_xml(skill.description));
		buf.appendf("  <location>%s</location>\n", escape_xml(skill.path));
		buf.append("</skill>\n");
	};
	defer buf.free();

	return buf.copy_str(allocator);
}

fn void SkillHub.free(&self)
{
	self.data.@each(; name, skill)
	{
		skill.free(self.allocator);
		alloc::free(self.allocator, skill);
	};
	self.data.free();
}

SkillHub _global_context;
bool _context_initialized = false;

fn SkillHub* use_skill_context()
{
	if (_context_initialized)
	{
		return &_global_context;
	}

	@pool()
	{
		List{Path} paths;
		paths.init(tmem);
		find_skill_dirs(&paths);
		_global_context.init(mem, paths.to_array(tmem));
		_context_initialized = true;
		return &_global_context;
	};
}

fn void free_skill_context()
{
	if (_context_initialized)
	{
		_global_context.free();
		_context_initialized = false;
	}
}

fn void find_skill_dirs(List{Path}* paths)
{
	Path global_skills_home = path::home_directory(tmem)!!.append(tmem, ".agents/skills")!!;
	if (path::exists(global_skills_home))
	{
		PathList global_skills = path::ls(tmem, global_skills_home)!!;
		foreach (global_skill : global_skills)
		{
			Path dir = global_skills_home.append(tmem, global_skill.str_view())!!;
			paths.push(dir);
		}
	}

	Path local_skills_home = path::cwd(tmem)!!.append(tmem, ".agents/skills")!!;
	if (path::exists(local_skills_home))
	{
		PathList local_skills = path::ls(tmem, local_skills_home)!!;
		foreach (local_skill : local_skills)
		{
			Path dir = local_skills_home.append(tmem, local_skill.str_view())!!;
			paths.push(dir);
		}
	}
}

fn String escape_xml(String str)
{
	return str
		.treplace("&", "&amp;")
		.treplace("<", "&lt;")
		.treplace(">", "&gt;")
		.treplace("\"", "&quot;")
		.treplace("'", "&apos;");
}
