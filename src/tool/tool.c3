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
	INVALID_OLD_TEXT_PARAM,
	INVALID_AGENT_PARAM,
	INVALID_PROMPT_PARAM,
	INVALID_DESCRIPTION_PARAM,
	LAUNCH_TASK_ERROR,;

// 工具执行上下文：Agent 线程在 do_dispatch 前从 AppContext 构建的轻量只读视图。
// 设计取舍：不直接传 AppContext*（tool ↔ app 循环 import，c3 0.8.3 不支持），
// 工具只读本视图；字段全部来自 AppContext（Agent 单写）。
struct ToolContext
{
	String session_id;       // 父会话 ID（Task 工具注入 MP_PARENT_SESSION）
	String request_id;       // 父 request_id（与 session_id 同源）
	Path config_dir;         // task_store / 中间产物目录
	bool transcript_enabled; // 子进程是否继承 --no-transcript
}

// 工具执行结果元数据（transcript tool_result 事件的补充字段）。
// 大多数工具不提供，保持零值即可；Bash 类工具提供 output_file 与 exit_code。
struct ToolResultMeta
{
	String output_file;  // 原始完整输出的落盘路径（可选，如 Bash 截断前的完整 stdout）
	int exit_code;       // 退出码（仅 Bash 类工具有值）
	bool has_exit_code;  // exit_code 是否有效
}

interface Tool
{
	fn String name();
	fn String description();
	fn String schema();
	fn void? execute(ToolContext* ctx, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta);
}

struct ToolHub
{
	Allocator allocator;
	String schema_cache;
	Tool[] tools;
	bool enable_bash_tool;
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
			case "Bash":
			{
				tools.push((Tool)alloc::new(allocator, BashTool));
				self.enable_bash_tool = true;
			}
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

	DString buf = dstring::new(tmem);
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

// 串行执行单个工具（永久串行承诺，OQ-2）。ToolContext 由调用方（Agent 线程）
// 从 AppContext 构建（父会话信息、config_dir、transcript 开关）。
fn void? ToolHub.do_dispatch(&self, ToolContext* ctx, Allocator allocator, DString* out, String name, CJsonItem* args, ToolResultMeta* meta)
{
	log::debug("dispatch tool with tool name = %s", name);

	foreach (&tool : self.tools)
	{
		if (tool.name() == name)
		{
			tool.execute(ctx, allocator, out, args, meta)!;
			return;
		}
	}

	log::debug("tool not found, tool name = %s", name);
	return UNKNOWN_TOOL~;
}
