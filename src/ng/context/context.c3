module ng::context;

import std::collections::list;

import ng::skill;
import ng::tool;

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
	String topic;
	List{Message} messages;
	String cwd;
	String config_dir;
	String log_file;
	
	SkillHub* skill_hub;
	ToolHub* tool_hub;
}
