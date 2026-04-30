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
	// skill 的父目录
	self.path = dir.str_view().copy(allocator);

	Path skill_file = dir.append(tmem, "SKILL.md")!!;
	if (!path::exists(skill_file))
	{
		self.ready = false;
		return self;
	}

	String text = (String)file::load_path(tmem, skill_file)!!;

	Markdown*  markdown = parse_markdown(text);
	self.content = markdown.body.copy(allocator);

	String name = markdown.front_matter.get_string("name") ?? "";
	String description = markdown.front_matter.get_string("description") ?? "";

	if (name != "") self.name = name.copy(allocator);
	if (description != "") self.description = description.copy(allocator);

	if (self.name != "" && self.content != "")
	{
		self.ready = true;
	}

	return self;
}

struct SkillContext
{
	HashMap {String, Skill*} data;
	Allocator allocator;
}

fn SkillContext* SkillContext.init(&self, Allocator allocator, Path[] paths)
{
	self.allocator = allocator;
	self.data.init(allocator);

	foreach(path: paths)
	{
		Skill* skill = alloc::new(allocator, Skill);
		skill.init(allocator, path);
		if (skill.ready)
		{
			io::printfn("Add skill, name = %s", skill.name);
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

fn void SkillContext.free(&self)
{
	self.data.@each(; name, skill)
	{
		skill.free(self.allocator);
		alloc::free(self.allocator, skill);
	};
	self.data.free();
}

SkillContext _global_context;
bool _context_initialized = false;

fn SkillContext* use_skill_context()
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
		PathList  global_skills = path::ls(tmem, global_skills_home)!!;
		foreach(global_skill: global_skills)
		{
			paths.push(global_skill.absolute(tmem))!!;
		}
	}

	Path local_skills_home = path::cwd(tmem)!!.append(tmem, ".agents/skills")!!;
	if (path::exists(local_skills_home))
	{
		PathList  local_skills = path::ls(tmem, local_skills_home)!!;
		foreach(local_skill: local_skills)
		{
			paths.push(local_skill.absolute(tmem))!!;
		}
	}
}

