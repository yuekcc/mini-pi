module ng::context;

import std::collections::list;
import std::io::path;

import ng::skill;
import ng::tool;
import ng::util;
import ng::cli;

struct ToolCall
{
	String name;
	String arguments;
}

struct Message
{
	String id;
	String role;
	String content;
	String reasoning_content;
	String tool_call_id;
	ToolCall* tool_call;
}

struct Context
{
	Allocator allocator;

	String session_id;
	
	Path cwd;
	Path config_dir;
	Path log_file;

	List{Message} messages;

	SkillHub* skill_hub;
	ToolHub* tool_hub;
	Flag* flag;
}

fn Context* Context.init(&self, Allocator allocator, Flag* flag, ToolHub* tool_hub, SkillHub* skill_hub)
{
	self.allocator = allocator;

	self.session_id = util::timestamp_id(self.allocator);
	self.cwd = flag.cwd;
	self.config_dir = flag.config_dir;
	self.log_file = self.config_dir.append(self.allocator, string::tformat("log/%s.log", self.session_id))!!;

	self.messages.init(self.allocator);

	self.tool_hub = tool_hub;
	self.skill_hub = skill_hub;
	self.flag = flag;

	return self;
}

fn bool Context.debug(&self)
{
	return self.flag.enable_debug;
}

fn void Context.add_message(&self, Message* message)
{
	Message* cloned = alloc::clone(self.allocator, *message);
	self.messages.push(*cloned);
}
