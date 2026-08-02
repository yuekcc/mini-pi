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

struct WriteFileTool (Tool)
{
	bool _pad;
}

fn String WriteFileTool.name(&self) @dynamic
{
	return "WriteFile";
}

fn String WriteFileTool.description(&self) @dynamic
{
	return "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.";
}

fn String WriteFileTool.schema(&self) @dynamic
{
	return WRITE_SCHEMA;
}

fn void? WriteFileTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? "";
	String content = args.get_key_string("content", tmem) ?? "";
	if (file_path == "") return INVALID_PATH_PARAM~;

	write(allocator, out, file_path, content)!;
}
