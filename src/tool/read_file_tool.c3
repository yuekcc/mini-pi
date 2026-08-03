module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;
import util;

fn void? read(Allocator allocator, DString* out, String file_path, int offset = -1, int limit = -1)
{
	Path path_obj = path::new(tmem, file_path)!;
	String content = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);

	String[] all_lines = normalized_content.split(tmem, "\n");
	usz total_lines = all_lines.len;

	// 处理 offset (1-indexed, -1 表示不使用)
	usz start_idx = 0;
	if (offset > 0)
	{
		start_idx = (usz)(offset - 1);
		if (start_idx >= total_lines)
		{
			out.appendf("Error: File has only %d lines, but offset %d is out of range.", total_lines, offset);
			return;
		}
	}

	// 处理 limit (-1 表示不使用)
	usz end_idx = total_lines;
	if (limit > 0)
	{
		end_idx = start_idx + (usz)limit;
		if (end_idx > total_lines)
		{
			end_idx = total_lines;
		}
	}

	// 截取需要显示的行，输出 hashline 格式：行号:哈希|内容
	for (usz i = start_idx; i < end_idx; i++)
	{
		int line_num = (int)(i + 1); // 1-indexed
		String h = util::line_hash(tmem, all_lines[i], i + 1);
		out.appendf("%d:%s|%s\n", line_num, h, all_lines[i]);
	}

	out.appendf(
		"\n(End of file. Total lines: %d, showing lines %d-%d. Each line is tagged as `line:hash|content`. To edit, reference the exact line:hash with HashEditFile.)",
		total_lines,
		start_idx + 1,
		end_idx
	);
}

const String READ_SCHEMA = (String)$embed("read_file_tool_schema.json");

struct ReadFileTool (Tool)
{
	bool _pad;
}

fn String ReadFileTool.name(&self) @dynamic
{
	return "ReadFile";
}

fn String ReadFileTool.description(&self) @dynamic
{
	return "Read the contents of a text file. For text files, output is truncated to 2000 lines. Use offset/limit for large files. When you need the full file, continue with offset until complete.";
}

fn String ReadFileTool.schema(&self) @dynamic
{
	return READ_SCHEMA;
}

fn void? ReadFileTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? "";
	int offset = args.get_key_int("offset") ?? -1;
	int limit = args.get_key_int("limit") ?? 2000;
	read(allocator, out, file_path, offset, limit)!;
}
