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
	bool ready;
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

	self.ready = true;

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

fn SkillContext* use_skill_context()
{
	static SkillContext context;

	if (context.ready)
	{
		return &context;
	}

	@pool()
	{
		List{Path} paths;
		find_skill_dirs(&paths);
		context.init(mem, paths.to_array(mem));
		return &context;
	};
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

