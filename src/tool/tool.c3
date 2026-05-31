module ng::tool;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;

faultdef
	EXECUTE_LS_COMMAND_ERROR, EXECUTE_RIPGREP_COMMAND_ERROR, EXECUTE_FD_COMMAND_ERROR, EXECUTE_BASH_COMMAND_ERROR, UNKNOWN_TOOL, INVALID_COMMAND_PARAM, INVALID_PATH_PARAM, INVALID_OLD_TEXT_PARAM, INVALID_AGENT_PARAM, INVALID_PROMPT_PARAM, INVALID_DESCRIPTION_PARAM, LAUNCH_TASK_ERROR,
;

interface Tool
{
	fn String name();
	fn String schema();
	fn void? execute(Allocator allocator, DString out, Object* args);
}

struct ToolHub
{
	Allocator allocator;
	String schema_cache;
	Tool[] tools;
}

fn ToolHub* ToolHub.init(&self, Allocator allocator, String[] allowed_tools)
{
	List{Tool} tools;
	tools.init(tmem);

	foreach (tool_name : allowed_tools)
	{
		switch (tool_name.trim())
		{
			case "read": tools.push((Tool)alloc::new(allocator, ReadTool));
			case "bash": tools.push((Tool)alloc::new(allocator, BashTool));
			case "edit": tools.push((Tool)alloc::new(allocator, EditTool));
			case "write": tools.push((Tool)alloc::new(allocator, WriteTool));
			case "grep": tools.push((Tool)alloc::new(allocator, GrepTool));
			case "find": tools.push((Tool)alloc::new(allocator, FindTool));
			case "ls": tools.push((Tool)alloc::new(allocator, LsTool));
			case "task": tools.push((Tool)alloc::new(allocator, TaskTool));
			default: unreachable(string::format(tmem, "UNKNOWN_TOOL: %s", tool_name.trim()));
		}
	}

	self.allocator = allocator;
	self.schema_cache = "";
	self.tools = tools.to_array(allocator);
	return self;
}

fn void ToolHub.free(&self)
{
	foreach (&tool : self.tools)
	{
		alloc::free(self.allocator, tool);
	}
}

fn String ToolHub.schema(&self, Allocator allocator)
{
	if (self.schema_cache != "")
	{
		return self.schema_cache.copy(allocator);
	}

	DString buf     = dstring::new(tmem);
	bool tool_added = false;
	buf.append("[");
	foreach (tool : self.tools)
	{
		if (tool_added)
		{
			buf.append(",");
		}
		buf.append(tool.schema());
		tool_added = true;
	}
	buf.append("]");

	// 利用序列化/反序列化进行格式化
	Object* schema_arr = object::parse(tmem, buf.str_view())!!;

	self.schema_cache = schema_arr.to_json(self.allocator);
	return self.schema_cache.copy(allocator);
}

fn void? ToolHub.do_dispatch(&self, Allocator allocator, DString out, String name, Object* args)
{
	foreach (&tool : self.tools)
	{
		if (tool.name() == name)
		{
			tool.execute(allocator, out, args)!;
		}
	}

	return UNKNOWN_TOOL~;
}