module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;
import util;

fn void? edit(Allocator allocator, DString* out, String file_path, String old_text, String new_text)
{
	Path path_obj = path::new(tmem, file_path)!;

	String content            = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);
	String normalized_old     = util::normalize_line_endings(tmem, old_text);
	String normalized_new     = util::normalize_line_endings(tmem, new_text);

	if (catch excuse = normalized_content.index_of(normalized_old))
	{
		out.appendf("Could not find the exact text in %s. The old text must match exactly including all whitespace and newlines", path_obj);
		return;
	}
	
	String updated = normalized_content.replace(tmem, normalized_old, normalized_new);

	file::save(path_obj, updated)!;
	out.appendf("(Success, saved to %s)", path_obj);
}

const String EDIT_SCHEMA = (String)$embed("edit_file_tool_schema.json");

struct EditTool (Tool)
{
	bool _pad;
}

fn String EditTool.name(&self) @dynamic
{
	return "EditFile";
}

fn String EditTool.description(&self) @dynamic
{
	return "Edit a file by replacing exact text. The oldText must match exactly (including whitespace). Use this for precise, surgical edits.";
}

fn String EditTool.schema(&self) @dynamic
{
	return EDIT_SCHEMA;
}

fn void? EditTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? "";
	String old_text  = args.get_key_string("oldText", tmem) ?? "";
	String new_text  = args.get_key_string("newText", tmem) ?? "";

	if (file_path == "") return INVALID_PATH_PARAM~;
	if (old_text == "") return INVALID_OLD_TEXT_PARAM~;

	edit(allocator, out, file_path, old_text, new_text)!;
}
