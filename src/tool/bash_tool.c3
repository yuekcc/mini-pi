module tool;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import util::cmd;

fn void? bash(Allocator allocator, DString out, String command)
{
	String[] final_command = { "sh", "-c", command };
	out.appendf("$ %s\n\n", command);

	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		out.append(result.output.trim());
	}
	else
	{
		out.append(result.output.trim());
		out.appendf("\n\nCommand exited with code %d", result.code);
	}
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

fn void? BashTool.execute(&self, Allocator allocator, DString out, Object* args) @dynamic
{
	String command = args.get_string("command") ?? "";
	if (command == "") return INVALID_COMMAND_PARAM~;
	bash(allocator, out, command)!;
}
