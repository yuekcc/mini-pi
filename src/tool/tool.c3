module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import log;

faultdef
	EXECUTE_LS_COMMAND_ERROR, 
	EXECUTE_RIPGREP_COMMAND_ERROR, 
	EXECUTE_FD_COMMAND_ERROR, 
	EXECUTE_BASH_COMMAND_ERROR, 
	UNKNOWN_TOOL, 
	INVALID_COMMAND_PARAM, 
	INVALID_PATH_PARAM, 
	INVALID_OLD_TEXT_PARAM, INVALID_AGENT_PARAM, INVALID_PROMPT_PARAM, INVALID_DESCRIPTION_PARAM, LAUNCH_TASK_ERROR,
;

interface Tool
{
	fn String name();
	fn String description();
	fn String schema();
	fn void? execute(Allocator allocator, DString* out, CJsonItem* args);
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

	log::debug("init tool hub, allowed_tools = %s", allowed_tools);

	foreach (tool_name : allowed_tools)
	{
		switch (tool_name.trim())
		{
			case "ReadFile": tools.push((Tool)alloc::new(allocator, ReadFileTool));
			case "Bash": tools.push((Tool)alloc::new(allocator, BashTool));
			case "EditFile": tools.push((Tool)alloc::new(allocator, EditTool));
			case "HashEditFile": tools.push((Tool)alloc::new(allocator, HashEditFileTool));
			case "WriteFile": tools.push((Tool)alloc::new(allocator, WriteFileTool));
			case "Grep": tools.push((Tool)alloc::new(allocator, GrepTool));
			case "Glob": tools.push((Tool)alloc::new(allocator, GlobTool));
			case "ListDir": tools.push((Tool)alloc::new(allocator, ListDirTool));
			case "Task": tools.push((Tool)alloc::new(allocator, TaskTool));
			default: unreachable(string::format(tmem, "UNKNOWN_TOOL: %s.", tool_name.trim()));
		}
	}

	self.allocator = allocator;
	self.schema_cache = "";
	self.tools = tools.to_array(allocator);

	log::debug("%d tool enabled", self.tools.len);
	return self;
}

fn String ToolHub.printed_enabled_tools(&self, Allocator allocator)
{
	DString buf = dstring::new(tmem);
	foreach (tool : self.tools)
	{
		buf.appendfn("- %s: %s", tool.name(), tool.description());
	}

	return buf.copy_str(allocator);
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
	CJsonItem* schema_arr = cjson::parse((ZString)buf.str_view());
	defer schema_arr.free();

	self.schema_cache = string::format(self.allocator, "%s", schema_arr);
	return self.schema_cache.copy(allocator);
}

fn void? ToolHub.do_dispatch(&self, Allocator allocator, DString* out, String name, CJsonItem* args)
{
	log::debug("dispatch tool with tool name = %s", name);

	foreach (&tool : self.tools)
	{
		if (tool.name() == name)
		{
			tool.execute(allocator, out, args)!;
			return;
		}
	}

	log::debug("tool not found, tool name = %s", name);
	return UNKNOWN_TOOL~;
}
