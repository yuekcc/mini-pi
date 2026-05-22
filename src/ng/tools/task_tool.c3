module ng::tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;


fn void? execute_task(Allocator allocator, DString out, String agent_name, String prompt, String description)
{
	Path agent_home = util::get_agent_home();
	Path output_file = agent_home.append(tmem, string::format(tmem, "temp/%s.txt", util::timestamp_id(tmem)))!;
	if (!path::exists(output_file.parent()!!))
	{
		path::mkdir(output_file.parent()!!, true)!!;
	}

	String[] final_command = {
		"mp",
		"--agent",
		agent_name,
		"--headless",
		"--task",
		prompt,
		"--output-file",
		output_file
	};
	// io::printfn(
	// 	util::system_message("> Launch subagent '%s' for %s, result will save to %s"),
	// 	agent_name,
	// 	description,
	// 	output_file
	// );
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		if (try output = (String)file::load_path(tmem, output_file))
		{
			io::printfn(util::system_message("> Subagent completed, output saved to %s"), output_file);
			if (output != "") 
			{ 
				out.append(output);
				return;
			}
		}
	}

	// io::printfn(util::system_message("> Subagent failed, %s"), result.output);
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
	String agent_name = args.get_string("agent") ?? "default";
	String prompt = args.get_string("prompt") ?? "";
	String description = args.get_string("description") ?? "";

	if (agent_name == "") return INVALID_AGENT_PARAM~;
	if (prompt == "") return INVALID_PROMPT_PARAM~;
	if (description == "") return INVALID_DESCRIPTION_PARAM~;

	execute_task(allocator, out, agent_name, prompt, description)!;
}
