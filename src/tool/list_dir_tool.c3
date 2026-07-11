module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
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

struct ListDirTool (Tool)
{
	bool _pad;
}

fn String ListDirTool.name(&self) @dynamic
{
	return "ListDir";
}

fn String ListDirTool.description(&self) @dynamic
{
	return "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries.";
}

fn String ListDirTool.schema(&self) @dynamic
{
	return LS_SCHEMA;
}

fn void? ListDirTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? ".";
	ls(allocator, out, file_path)!;
}
