module tool;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;
import std::os::env;

import cjson;
import util::cmd;
import util;
import ui;
import transcript;

fn void? execute_task(ToolContext* ctx, Allocator allocator, DString* out, String agent_name, String prompt, String description, ToolResultMeta* meta)
{
	String task_id =  util::timestamp_id(tmem);
	Path store_dir = load_store_dir(tmem, ctx.config_dir);

	Path output_file = store_dir.append(tmem, string::tformat("%s_output.txt", task_id))!!;
	Path input_file = store_dir.append(tmem, string::tformat("%s_input.txt", task_id))!!;
	file::save(input_file, prompt)!;

	// 注入父会话信息（格式 父session_id:父request_id），子进程 session_start 据此关联。
	// 父会话状态来自 AppContext 的轻量视图（Agent 线程单写，无 tlocal 全局）。
	String parent_value = "";
	if (ctx.session_id != "" && ctx.request_id != "")
	{
		parent_value = string::tformat("%s:%s", ctx.session_id, ctx.request_id);
		env::set_var(transcript::ENV_PARENT_SESSION, parent_value);
	}

	// 子进程继承 transcript 关闭语义（--no-transcript），并保持 headless 续跑。
	List{String} cmd;
	cmd.init(tmem);
	cmd.push("mp");
	cmd.push("--agent");
	cmd.push(agent_name);
	cmd.push("--headless");
	if (!ctx.transcript_enabled) cmd.push("--no-transcript");
	cmd.push("-f");
	cmd.push(string::tformat("%s", input_file));
	cmd.push("-o");
	cmd.push(string::tformat("%s", output_file));
	String[] final_command = cmd.to_array(tmem);

	CommandResult result = cmd::execute(allocator, final_command)!;

	// 恢复父进程环境（若原本无该变量则清除）
	if (parent_value != "") env::clear_var(transcript::ENV_PARENT_SESSION);

	if (meta)
	{
		meta.exit_code = result.code;
		meta.has_exit_code = true;
	}

	if (result.code == 0)
	{
		if (try output = (String)file::load_path(tmem, output_file))
		{
			ui::notice("Subagent completed, output saved to %s", output_file);
			if (output != "")
			{
				out.append(output);
				return;
			}
		}
	}

	return LAUNCH_TASK_ERROR~;
}


const String TASK_SCHEMA = (String)$embed("task_tool_schema.json");

struct TaskTool (Tool)
{
	bool _pad;
}


fn String TaskTool.name(&self) @dynamic
{
	return "Task";
}

fn String TaskTool.description(&self) @dynamic
{
	return "Run a subagent in a clean context and return a summary.";
}

fn String TaskTool.schema(&self) @dynamic
{
	return TASK_SCHEMA;
}

fn void? TaskTool.execute(&self, ToolContext* ctx, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String agent_name  = args.get_key_string("agent", tmem) ?? "default";
	String prompt      = args.get_key_string("prompt", tmem) ?? "";
	String description = args.get_key_string("description", tmem) ?? "";

	if (agent_name == "") return INVALID_AGENT_PARAM~;
	if (prompt == "") return INVALID_PROMPT_PARAM~;
	if (description == "") return INVALID_DESCRIPTION_PARAM~;

	execute_task(ctx, allocator, out, agent_name, prompt, description, meta)!;
}
