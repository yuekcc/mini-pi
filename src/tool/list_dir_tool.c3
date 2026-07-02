module tool;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import util::cmd;


fn String? ls(Allocator allocator, DString* out, String file_path = "", int limit = 500)
{
	String[] final_command = file_path != "" ? { "ls", "-ahl", file_path } : { "ls", "-ahl" };
	CommandResult result   = cmd::execute(allocator, final_command)!;
	// io::printfn("result = %s\n\nreturn code = %d", result.output.trim(), result.code);

	if (result.code == 0)
	{
		out.append(result.output.trim());
		return "";
	}

	return EXECUTE_LS_COMMAND_ERROR~;
}

const String LS_SCHEMA = (String)$embed("list_dir_tool_schema.json");

struct LsTool (Tool)
{
	bool _pad;
}

fn String LsTool.name(&self) @dynamic
{
	return "ListDir";
}

fn String LsTool.schema(&self) @dynamic
{
	return LS_SCHEMA;
}

fn void? LsTool.execute(&self, Allocator allocator, DString* out, Object* args) @dynamic
{
	String file_path = args.get_string("path") ?? ".";
	ls(allocator, out, file_path)!;
}
