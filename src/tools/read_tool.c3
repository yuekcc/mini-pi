module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;

fn String pad_line_numbers(Allocator allocator, String content)
{
	String[] lines = content.split(tmem, "\n");
	usz width = (usz)string::format(tmem, "%d", lines.len).len;

	DString buf = dstring::new(tmem);
	foreach (i, &line : lines)
	{
		String line_num = string::format(tmem, "%d", i+1);
		buf.appendf("%s%s: %s\n", util::pad_start(tmem, width - line_num.len, "0"), line_num, *line);
	}

	buf.appendf("\n(End of file, total %d lines)", lines.len);
	return buf.copy_str(allocator);
}


fn String? read(Allocator allocator, String file_path, int offset = 1, int limit = -1)
{
	Path path_obj = path::new(tmem, file_path)!;
	String content = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);
	return pad_line_numbers(allocator, normalized_content);
}

const String READ_SCHEMA = (String)$embed("read_tool_schema.json");

struct ReadTool (Tool)
{
	bool _pad;
}

fn String ReadTool.name(&self) @dynamic
{
	return "read";
}

fn String ReadTool.schema(&self) @dynamic
{
	return READ_SCHEMA;
}

fn String? ReadTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String file_path = args.get_string("path") ?? "";
	int offset = args.get_int("offset") ?? -1;
	int limit = args.get_int("limit") ?? -1;
	return read(allocator, file_path, offset, limit);
}
