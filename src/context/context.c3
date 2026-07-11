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
	String id;       // 模型返回的 tool_call id，例如 "call_xxx"
	usz index;       // 模型返回的工具调用序号，从 0 递增
	String name;
	String arguments;
}

struct Message
{
	String id;
	String role;
	String content;
	String reasoning_content;
	String tool_call_id;        // 仅 role=tool 消息使用，指向其回应的 tool_call id
	List{ToolCall} tool_calls; // 仅 role=assistant 消息使用，支持单次回复中的多个工具调用
	DateTime timestamp;
}

// 初始化一个 Message，role 拷贝进 allocator，tool_calls 列表也用同一 allocator 建立。
// 其余字段留空，调用方按需填充。
fn void message_init(Message* m, Allocator allocator, String role)
{
	m.id = "";
	m.role = role.copy(allocator);
	m.content = "";
	m.reasoning_content = "";
	m.tool_call_id = "";
	m.tool_calls.init(allocator);
	m.timestamp = datetime::now();
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

	DateTime started_at;
	DateTime updated_at;
}

fn Context* Context.init(&self, Allocator allocator, String session_id, Flag* flag, ToolHub* tool_hub, SkillHub* skill_hub, Path log_file)
{
	self.allocator = allocator;

	self.session_id = session_id;
	self.cwd = flag.cwd;
	self.config_dir = flag.config_dir;
	self.log_file = log_file;

	self.messages.init(self.allocator);

	self.tool_hub = tool_hub;
	self.skill_hub = skill_hub;
	self.flag = flag;

	DateTime now = datetime::now();
	self.started_at = now;
	self.updated_at = now;

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

	Message system_msg;
	message_init(&system_msg, tmem, "system");

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
	Message* cloned = alloc::new(self.allocator, Message);
	cloned.id = message.id.copy(self.allocator);
	cloned.role = message.role.copy(self.allocator);
	cloned.content = message.content.copy(self.allocator);
	cloned.reasoning_content = message.reasoning_content.copy(self.allocator);
	cloned.tool_call_id = message.tool_call_id.copy(self.allocator);
	cloned.timestamp = message.timestamp;

	cloned.tool_calls.init(self.allocator);
	foreach (&tc : message.tool_calls)
	{
		ToolCall cloned_tc;
		cloned_tc.id = tc.id.copy(self.allocator);
		cloned_tc.index = tc.index;
		cloned_tc.name = tc.name.copy(self.allocator);
		cloned_tc.arguments = tc.arguments.copy(self.allocator);
		cloned.tool_calls.push(cloned_tc);
	}

	self.messages.push(*cloned);
	self.updated_at = datetime::now();
}


fn String Context.render_to_markdown(&self, Allocator allocator)
{
	DString buf = dstring::new(allocator);

	buf.appendfn("---");
	buf.appendfn("Session ID: %s", self.session_id);
	buf.appendfn("Started At: %s", self.started_at.to_local().format(allocator, DateTimeFormat.DATETIME));
	buf.appendfn("Updated At: %s", self.updated_at.to_local().format(allocator, DateTimeFormat.DATETIME));
	buf.appendfn("---\n");

	foreach (message : self.messages)
	{
		buf.appendfn("# %s %s\n", message.timestamp.to_local().format(allocator, DateTimeFormat.DATETIME), message.role);

		String reasoning_content = message.reasoning_content.trim();
		String content = message.content.trim();

		if (message.tool_call_id != "")
		{
			buf.appendfn("(Tool call ID: `%s`)\n", message.tool_call_id);
		}


		if (reasoning_content != "")
		{
			buf.appendfn("> Thinking:");
			buf.appendfn("> ");
			foreach (line : reasoning_content.split(allocator, "\n"))
			{
				buf.appendfn("> %s", line);
			}
		}

		if (content != "")
		{
			bool should_pack = message.tool_call_id != "";
			if (should_pack) buf.appendfn("```");

			buf.appendfn("%s\n", content);

			if (should_pack) buf.appendfn("```");
		}

		if (message.tool_calls.len() > 0)
		{
			foreach (tool_call: message.tool_calls)
			{
				buf.appendfn("(Call tool, id = `%s`, name = `%s`, arguments = `%s`)\n", tool_call.id, tool_call.name, tool_call.arguments);
			}
		}
	}

	return buf.str_view();
}
