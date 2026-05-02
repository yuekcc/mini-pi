module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;

fn String? read(Allocator allocator, String file_path, int offset = -1, int limit = -1)
{
	Path path_obj = path::new(tmem, file_path)!;
	String content = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);
	
	String[] all_lines = normalized_content.split(tmem, "\n");
	usz total_lines = all_lines.len;
	
	// 处理 offset (1-indexed, -1 表示不使用)
	usz start_idx = 0;
	if (offset > 0) {
		start_idx = (usz)(offset - 1);
		if (start_idx >= total_lines) {
			String msg = string::format(tmem, "Error: File has only %d lines, but offset %d is out of range.", total_lines, offset);
			return msg.copy(allocator);
		}
	}
	
	// 处理 limit (-1 表示不使用)
	usz end_idx = total_lines;
	if (limit > 0) {
		end_idx = start_idx + (usz)limit;
		if (end_idx > total_lines) {
			end_idx = total_lines;
		}
	}
	
	// 计算行号宽度
	usz width = (usz)string::format(tmem, "%d", total_lines).len;
	
	// 截取需要显示的行并添加行号
	DString buf = dstring::new(tmem);
	for (usz i = start_idx; i < end_idx; i++) {
		int line_num = (int)(i + 1);  // 1-indexed
		String line_num_str = string::format(tmem, "%d", line_num);
		buf.appendf("%s%s: %s\n", util::pad_start(tmem, width - line_num_str.len, "0"), line_num_str, all_lines[i]);
	}
	
	buf.appendf("\n(End of file. Total lines: %d, showing lines %d-%d)", total_lines, start_idx + 1, end_idx);
	return buf.copy_str(allocator);
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
