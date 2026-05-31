module context;

import std::collections::list;
import std::io::path;
import std::io::file;
import std::time::datetime;

import skill;
import tool;
import util;
import cli;

const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

fn String load_system_prompt(Allocator allocator) @local
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);
	Path cwd = path::cwd(tmem)!!;

	String final_system_prompt = SYSTEM_PROMPT_TPL.replace(tmem, "{{cwd}}", cwd)
		.replace(tmem, "{{date}}", now_str)
		.replace(tmem, "{{os}}", "Windows 11 + Msys2 + GNU Bash 5.2 (x86_64-pc-msys)");

	return final_system_prompt.copy(allocator);
}

fn String load_agents_md(Allocator allocator)
{
	if (try content = (String)file::load(tmem, "AGENTS.md"))
	{
		return content.trim().copy(allocator);
	}

	return "";
}

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

fn void Context.reset(&self)
{
	// TODO 内存问题？
	self.messages.clear();

	Message system_msg = { .role = "system", };

	DString buf = dstring::new(tmem);

	buf.appendf("%s", load_system_prompt(tmem));
	String agents_md = load_agents_md(tmem);
	if (agents_md != "")
	{
		buf.appendf("\n----\n%s", agents_md);
	}
	
	if (self.skill_hub != null)
	{
		String skill_list = self.skill_hub.print_installed(tmem);
		if (skill_list != "")
		{
			buf.appendf("\n----\n%s", skill_list);
		}
	}

	system_msg.content = buf.copy_str(tmem);
	self.add_message(&system_msg);
}

fn void Context.add_message(&self, Message* message)
{
	Message* cloned = alloc::clone(self.allocator, *message);
	self.messages.push(*cloned);
}
