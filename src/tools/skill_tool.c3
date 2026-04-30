module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;
import skill;

fn String? load_skill(Allocator allocator, String name)
{
	SkillHub* cx = skill::use_skill_context();
	Skill* skill = cx.data.get(name)!!;
	return skill.content.copy(allocator);
}

const String SKILL_SCHEMA = (String)$embed("skill_tool_schema.json");

struct SkillTool (Tool)
{
	bool _pad;
}

fn String SkillTool.name(&self) @dynamic
{
	return "skill";
}

fn String SkillTool.schema(&self) @dynamic
{
	return SKILL_SCHEMA;
}

fn String? SkillTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String skill_name = args.get_string("name") ?? "";
	if (skill_name == "") return "ARGUMENT INVALID, REQUIRE 'name'";
	return load_skill(allocator, skill_name);
}