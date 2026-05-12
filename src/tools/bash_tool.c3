module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;

// TODO 超长输出时截断
fn String? bash(Allocator allocator, String command, int timeout_s = -1)
{
	DString output = dstring::new(tmem);

	String[] final_command = { "sh", "-c", command };
	output.appendf("$ sh -c %s\n\n");

	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		output.append(result.output.trim());
	}
	else
	{
		output.append(result.output.trim());
		output.appendf("\n\nCommand exited with code %d", result.code);
	}

	return output.copy_str(allocator);
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
