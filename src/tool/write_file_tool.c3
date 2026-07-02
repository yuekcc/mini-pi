module tool;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import util::cmd;

const String WRITE_SCHEMA = (String)$embed("write_tool_schema.json");


fn void? write(Allocator allocator, DString out, String file_path, String content)
{
	Path path_obj = path::new(tmem, file_path)!;
	file::save(path_obj, content)!;
	out.appendf("(Saved to %s)", path_obj);
}

struct WriteTool (Tool)
{
	bool _pad;
}

fn String WriteTool.name(&self) @dynamic
{
	return "WriteFile";
}

fn String WriteTool.schema(&self) @dynamic
{
	return WRITE_SCHEMA;
}

fn void? WriteTool.execute(&self, Allocator allocator, DString out, Object* args) @dynamic
{
	String file_path = args.get_string("path") ?? "";
	String content   = args.get_string("content") ?? "";
	if (file_path == "") return INVALID_PATH_PARAM~;

	write(allocator, out, file_path, content)!;
}
