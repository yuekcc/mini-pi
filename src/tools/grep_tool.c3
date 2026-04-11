module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;


fn String? grep(Allocator allocator, String pattern, String file_path = "", String glob = "", bool ignore_case = false, bool literal = false, int context = 0, int limit = 100)
{
	List{String} final_command;
	final_command.init(tmem);

	final_command.push("rg");
	final_command.push(pattern);
	if (file_path != "")
	{
		final_command.push(file_path);
	}
	if (glob != "")
	{
		final_command.push("--glob");
		final_command.push(glob);
	}
	if (ignore_case)
	{
		final_command.push("--ignore-case");
	}
	if (literal)
	{
		final_command.push("--fixed-strings");
	}
	if (context > 0)
	{
		final_command.push("-C");
		final_command.push(string::format(tmem, "%d", context));
	}

	CommandResult result = cmd::execute(allocator, final_command.to_array(tmem))!;
	if (result.code == 0)
	{
		return result.output.copy(allocator);
	}

	return EXECUTE_RIPGREP_COMMAND_ERROR~;
}

const String GREP_SCHEMA = (String)$embed("grep_tool_schema.json");

struct GrepTool (Tool)
{
	bool _pad;
}

fn String GrepTool.name(&self) @dynamic
{
	return "grep";
}

fn String GrepTool.schema(&self) @dynamic
{
	return GREP_SCHEMA;
}

fn String? GrepTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String pattern = args.get_string("pattern") ?? "";
	String file_path = args.get_string("path") ?? "";
	String glob = args.get_string("glob") ?? "";
	bool ignore_case = args.get_bool("ignoreCase") ?? false;
	bool literal = args.get_bool("literal") ?? false;
	int context = args.get_int("context") ?? 0;
	return grep(allocator, pattern, file_path, glob, ignore_case, literal, context);
}
