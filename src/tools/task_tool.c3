module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;


fn String? execute_task(Allocator allocator, String agent_name, String prompt, String description)
{
	String output_file = "subagent_output.txt";

	String[] final_command = {"mp", "--agent", agent_name, "--headless", "--init-message", prompt, "--output-file", output_file};
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		if (try output = (String)file::load(tmem, output_file))
		{
			if (output != "") return output.copy(allocator);
		}
	}

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
	String agent_name = args.get_string("agent") ?? "";
	String prompt = args.get_string("prompt") ?? "";
	String description = args.get_string("description") ?? "";

	if (agent_name == "") return "ARGUMENT INVALID, REQUIRE 'agent'";
	if (prompt == "") return "ARGUMENT INVALID, REQUIRE 'prompt'";
	if (description == "") return "ARGUMENT INVALID, REQUIRE 'description'";

	return execute_task(allocator, agent_name, prompt, description);
}
