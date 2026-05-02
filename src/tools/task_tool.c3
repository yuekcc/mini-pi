module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;


fn String? execute_task(Allocator allocator, String agent_name, String prompt, String description)
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
		output_file.str_view()
	};
	io::printfn(
		util::system_message("> Launch subagent '%s' for %s, result will save to %s"),
		agent_name,
		description,
		output_file.str_view()
	);
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		if (try output = (String)file::load_path(tmem, output_file))
		{
			io::printfn(util::system_message("> Subagent completed, output saved to %s"), output_file);
			if (output != "") return output.copy(allocator);
		}
	}

	io::printfn(util::system_message("> Subagent failed, %s"), result.output);
	return "ERROR, launch task failed";
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

fn String? TaskTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String agent_name = args.get_string("agent") ?? "default";
	String prompt = args.get_string("prompt") ?? "";
	String description = args.get_string("description") ?? "";

	if (agent_name == "") return "ARGUMENT INVALID, REQUIRE 'agent'";
	if (prompt == "") return "ARGUMENT INVALID, REQUIRE 'prompt'";
	if (description == "") return "ARGUMENT INVALID, REQUIRE 'description'";

	return execute_task(allocator, agent_name, prompt, description);
}
