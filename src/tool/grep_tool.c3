module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;


fn void? grep(
	Allocator allocator,
	DString* out,
	String pattern,
	String file_path = "",
	String glob = "",
	bool ignore_case = false,
	bool literal = false,
	int context = 0,
	int limit = 100
)
{
	List{String} final_command;
	final_command.init(tmem);

	final_command.push("rg");
	final_command.push("--vimgrep");
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
		String trimmed = result.output.trim();
		if (limit > 0)
		{
			String[] lines = trimmed.split(tmem, "\n");
			if ((usz)lines.len > (usz)limit)
			{
				DString buf = dstring::new(tmem);
				for (usz i = 0; i < (usz)limit; i++)
				{
					if (i > 0) buf.append("\n");
					buf.append(lines[i]);
				}
				out.append(buf.str_view());
				return;
			}
		}
		out.append(trimmed);
		return;
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
	return "Grep";
}

fn String GrepTool.description(&self) @dynamic
{
	return "Search file contents for a pattern. Returns matching lines with file paths, line and column numbers. Respects .gitignore. Output is truncated to 100 matches. Long lines are truncated to 500 chars.";
}

fn String GrepTool.schema(&self) @dynamic
{
	return GREP_SCHEMA;
}

fn void? GrepTool.execute(&self, ToolContext* ctx, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String pattern   = args.get_key_string("pattern", tmem) ?? "";
	String file_path = args.get_key_string("path", tmem) ?? "";
	String glob      = args.get_key_string("glob", tmem) ?? "";
	bool ignore_case = args.get_key_bool("ignoreCase") ?? false;
	bool literal     = args.get_key_bool("literal") ?? false;
	int context      = args.get_key_int("context") ?? 0;
	int limit        = args.get_key_int("limit") ?? 100;
	grep(allocator, out, pattern, file_path, glob, ignore_case, literal, context, limit)!;
}
