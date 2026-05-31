module tool;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;

import c3x::object;
import util::cmd;
import util;
import global;

fn Path load_store_dir(Allocator allocator, String task_id)
{
	Path store_dir;
	Path config_dir = global::config_dir();
	if (config_dir != "")
	{
		store_dir = config_dir.append(allocator, "task_store")!!;
	}
	else
	{
		Path user_home  = path::home_directory(allocator)!!;
		store_dir = user_home.append(allocator, ".config/mp/task_store")!!;
	}

	if (!path::exists(store_dir))
	{
		path::mkdir(store_dir, true)!!;
	}

	return store_dir;
}


fn void? execute_task(Allocator allocator, DString out, String agent_name, String prompt, String description)
{
	String task_id =  util::timestamp_id(tmem);
	Path store_dir = load_store_dir(tmem, task_id);

	Path output_file = store_dir.append(tmem, string::format(tmem, "%s_output.txt", task_id))!!;
	Path input_file = store_dir.append(tmem, string::format(tmem, "%s_input.txt", task_id))!!;
	file::save(input_file, prompt)!;

	String[] final_command = { "mp", "--agent", agent_name, "--headless", "-f", input_file, "-o", output_file };
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		if (try output = (String)file::load_path(tmem, output_file))
		{
			io::printfn("> Subagent completed, output saved to %s", output_file);
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
	return "task";
}

fn String TaskTool.schema(&self) @dynamic
{
	return TASK_SCHEMA;
}

fn void? TaskTool.execute(&self, Allocator allocator, DString out, Object* args) @dynamic
{
	String agent_name  = args.get_string("agent") ?? "default";
	String prompt      = args.get_string("prompt") ?? "";
	String description = args.get_string("description") ?? "";

	if (agent_name == "") return INVALID_AGENT_PARAM~;
	if (prompt == "") return INVALID_PROMPT_PARAM~;
	if (description == "") return INVALID_DESCRIPTION_PARAM~;

	execute_task(allocator, out, agent_name, prompt, description)!;
}
