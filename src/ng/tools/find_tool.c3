module ng::tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;

fn void? find(Allocator allocator, DString out, String pattern, String file_path = "", int limit = 1000)
{
	List{String} final_command;
	final_command.init(tmem);

	final_command.push("fd");

	if (pattern != "" && pattern.contains("*"))
	{
		final_command.push("-g");
	}

	final_command.push(pattern);

	if (file_path != "")
	{
		final_command.push(file_path);
	}

	CommandResult result = cmd::execute(allocator, final_command.to_array(tmem))!;
	if (result.code == 0)
	{
		out.append(result.output.trim());
		return;
	}

	return EXECUTE_FD_COMMAND_ERROR~;
}

const String FIND_SCHEMA = (String)$embed("find_tool_schema.json");

struct FindTool (Tool)
{
	bool _pad;
}

fn String FindTool.name(&self) @dynamic
{
	return "find";
}

fn String FindTool.schema(&self) @dynamic
{
	return FIND_SCHEMA;
}

fn void? FindTool.execute(&self, Allocator allocator, DString out, Object* args) @dynamic
{
	String pattern = args.get_string("pattern") ?? "";
	String file_path = args.get_string("path") ?? "";
	find(allocator, out, pattern, file_path)!;
}
