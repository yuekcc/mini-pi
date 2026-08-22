module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;

fn void? find(Allocator allocator, DString* out, String pattern, String file_path = "", int limit = 500)
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

	if (limit > 0)
	{
		final_command.push("--max-results");
		final_command.push(string::format(tmem, "%d", limit));
	}

	CommandResult result = cmd::execute(allocator, final_command.to_array(tmem))!;
	if (result.code == 0)
	{
		out.append(result.output.trim());
		return;
	}

	return EXECUTE_FD_COMMAND_ERROR~;
}

const String FIND_SCHEMA = (String)$embed("glob_tool_schema.json");

struct GlobTool (Tool)
{
	bool _pad;
}

fn String GlobTool.name(&self) @dynamic
{
	return "Glob";
}

fn String GlobTool.description(&self) @dynamic
{
	return "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to at most `limit` results (default: 500).";
}

fn String GlobTool.schema(&self) @dynamic
{
	return FIND_SCHEMA;
}

fn void? GlobTool.execute(&self, ToolContext* ctx, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String pattern   = args.get_key_string("pattern", tmem) ?? "";
	String file_path = args.get_key_string("path", tmem) ?? "";
	int limit = args.get_key_int("limit") ?? 500;
	find(allocator, out, pattern, file_path, limit)!;
}
