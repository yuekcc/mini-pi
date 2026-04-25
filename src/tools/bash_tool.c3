module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;

fn String? bash(Allocator allocator, String command, int timeout_s = -1)
{
	String[] final_command = { "sh", "-c", command };
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		return result.output.copy(allocator);
	}

	return EXECUTE_BASH_COMMAND_ERROR~;
}

const String BASH_SCHEMA = (String)$embed("bash_tool_schema.json");

struct BashTool (Tool)
{
	bool _pad;
}

fn String BashTool.name(&self) @dynamic
{
	return "bash";
}

fn String BashTool.schema(&self) @dynamic
{
	return BASH_SCHEMA;
}

fn String? BashTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String command = args.get_string("command") ?? "";
	if (command == "") return "ARGUMENT INVALID, REQUIRE 'command'";
	return bash(allocator, command);
}