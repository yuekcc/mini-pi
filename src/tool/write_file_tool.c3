module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;

const String WRITE_SCHEMA = (String)$embed("write_file_tool_schema.json");


fn void? write(Allocator allocator, DString* out, String file_path, String content)
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

fn void? WriteTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? "";
	String content   = args.get_key_string("content", tmem) ?? "";
	if (file_path == "") return INVALID_PATH_PARAM~;

	write(allocator, out, file_path, content)!;
}
