module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;

fn String? edit(Allocator allocator, String file_path, String old_text, String new_text)
{
	Path path_obj = path::new(tmem, file_path)!;

	String content = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);
	String normalized_old = util::normalize_line_endings(tmem, old_text);
	String normalized_new = util::normalize_line_endings(tmem, new_text);
	String updated = normalized_content.replace(tmem, normalized_old, normalized_new);

	file::save(path_obj.str_view(), updated)!;
	return string::format(allocator, "(Success, saved to %s)", path_obj.str_view());
}

const String EDIT_SCHEMA = (String)$embed("edit_tool_schema.json");

struct EditTool (Tool)
{
	bool _pad;
}

fn String EditTool.name(&self) @dynamic
{
	return "edit";
}

fn String EditTool.schema(&self) @dynamic
{
	return EDIT_SCHEMA;
}

fn String? EditTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String file_path = args.get_string("path") ?? "";
	String old_text = args.get_string("oldText") ?? "";
	String new_text = args.get_string("newText") ?? "";
	return edit(allocator, file_path, old_text, new_text);
}
