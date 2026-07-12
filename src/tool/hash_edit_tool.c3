module tool;

import std::io;
import std::io::path;
import std::collections::list;

import cjson;
import util::cmd;
import util;

struct EditOp
{
	int    line;         // 1-based 锚点行号
	String hash;         // 锚点行内容哈希（2 字符）
	String content;      // 新内容（空串表示删除）
	int    end_line;     // 区间编辑的结束行（0 表示单行）
	String end_hash;     // 区间编辑结束行的哈希
	bool   insert_after; // true 时在锚点行之后插入
}

// 把 content（可能多行）拆成多行追加到 out_lines
fn void append_content_lines(List{String}* out_lines, String content, Allocator allocator)
{
	String[] parts = content.split(allocator, "\n");
	foreach (p : parts)
	{
		out_lines.push(p.copy(allocator));
	}
}

// 统计 content 折合多少行（对齐 split("\n") 的语义：非空串 = 换行数 + 1，空串 = 0）
fn usz content_line_count(String content)
{
	if (content.len == 0) return 0;
	usz n = 1;
	foreach (c : content)
	{
		if (c == '\n') n++;
	}
	return n;
}

fn void? hash_edit(Allocator allocator, DString* out, String file_path, EditOp[] edits)
{
	Path path_obj = path::new(tmem, file_path)!;

	String content            = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = util::normalize_line_endings(tmem, content);
	String[] lines            = normalized_content.split(tmem, "\n");
	usz     total             = lines.len;

	// ---- 1) 应用前：原子校验所有锚点 ----
	DString errors = dstring::new(tmem);
	foreach (&op : edits)
	{
		if (op.line < 1 || (usz)op.line > total)
		{
			errors.appendf("\n  - line %d out of range (file has %d lines)", op.line, total);
			continue;
		}
		String actual = util::line_hash(tmem, lines[op.line - 1], (usz)op.line);
		if (actual != op.hash)
		{
			errors.appendf(
				"\n  - line %d: hash mismatch. You supplied '%s' but the current file has '%s'. The file may have changed since you read it.",
				op.line, op.hash, actual);
		}
		if (op.end_line != 0)
		{
			if ((usz)op.end_line < (usz)op.line || (usz)op.end_line > total)
			{
				errors.appendf("\n  - endLine %d is invalid (must be >= line %d and <= %d)", op.end_line, op.line, total);
			}
			else
			{
				String actual_end = util::line_hash(tmem, lines[op.end_line - 1], (usz)op.end_line);
				if (actual_end != op.end_hash)
				{
					errors.appendf(
						"\n  - endLine %d: hash mismatch. You supplied '%s' but the current file has '%s'.",
						op.end_line, op.end_hash, actual_end);
				}
			}
		}
	}

	// ---- 1b) 校验：insertAfter/endLine 互斥 + 重叠/重复锚点 ----
	// edits 已按 line 升序排列，逐条计算其覆盖区间 [line .. end]，下一 edit 的 line 必须 > 上一 edit 的 end
	int prev_end = 0;
	foreach (op : edits)
	{
		if (op.insert_after && op.end_line != 0)
		{
			errors.appendf("\n  - line %d: insertAfter and endLine cannot be combined (insertAfter only inserts after a single anchor line)", op.line);
		}
		if (op.line >= 1 && op.line <= prev_end)
		{
			errors.appendf("\n  - line %d: overlaps or duplicates a previous edit (previous edit covered up to line %d)", op.line, prev_end);
		}
		if (op.end_line != 0 && !op.insert_after)
		{
			prev_end = op.end_line;
		}
		else
		{
			prev_end = op.line;
		}
	}

	if (errors.len() > 0)
	{
		out.appendf("HashEdit rejected: invalid or stale edits detected. No changes were made.%s", errors.str_view());
		return;
	}

	// ---- 2) 应用：自顶向下流式处理，锚点按原行号顺序处理，避免行号漂移 ----
	// edits 已按 line 升序排列
	List{String} out_lines;
	out_lines.init(tmem);

	// 记录每条 edit 的应用结果，最终一并返回给模型
	DString report = dstring::new(tmem);

	usz ei = 0;
	for (usz i = 0; i < total; i++)
	{
		if (ei < edits.len && (usz)edits[ei].line - 1 == i)
		{
			EditOp op = edits[ei];
			if (op.insert_after)
			{
				out_lines.push(lines[i].copy(tmem));
				if (op.content != "")
				{
					append_content_lines(&out_lines, op.content, tmem);
					report.appendf("\n  - line %d: inserted %d line(s) after", op.line, content_line_count(op.content));
				}
				else
				{
					report.appendf("\n  - line %d: insertAfter with empty content (no-op)", op.line);
				}
			}
			else if (op.end_line != 0)
			{
				// 区间替换：用 content 替换 [line .. endLine]，跳过被替换的行
				usz removed = (usz)op.end_line - (usz)op.line + 1;
				if (op.content != "")
				{
					append_content_lines(&out_lines, op.content, tmem);
					report.appendf("\n  - lines %d-%d: range replaced (%d line(s) -> %d line(s))", op.line, op.end_line, removed, content_line_count(op.content));
				}
				else
				{
					report.appendf("\n  - lines %d-%d: range deleted (%d line(s))", op.line, op.end_line, removed);
				}
				i = (usz)op.end_line - 1; // 循环 i++ 后跳过区间内剩余行
			}
			else
			{
				// 单行替换 / 删除
				if (op.content != "")
				{
					append_content_lines(&out_lines, op.content, tmem);
					usz added = content_line_count(op.content);
					if (added == 1)
					{
						report.appendf("\n  - line %d: replaced", op.line);
					}
					else
					{
						report.appendf("\n  - line %d: replaced with %d line(s)", op.line, added);
					}
				}
				else
				{
					report.appendf("\n  - line %d: deleted", op.line);
				}
			}
			ei++;
		}
		else
		{
			out_lines.push(lines[i].copy(tmem));
		}
	}

	// ---- 3) 拼回并保存 ----
	DString buf = dstring::new(tmem);
	for (usz i = 0; i < (usz)out_lines.len(); i++)
	{
		if (i > 0) buf.append("\n");
		buf.append(out_lines[(sz)i]);
	}
	String updated = buf.copy_str(tmem);
	file::save(path_obj, updated)!;

	out.appendf("(Success, saved to %s, %d edit(s) applied:%s)", path_obj, edits.len, report.str_view());
}

const String HASH_EDIT_SCHEMA = (String)$embed("hash_edit_tool_schema.json");

struct HashEditFileTool (Tool)
{
	bool _pad;
}

fn String HashEditFileTool.name(&self) @dynamic
{
	return "HashEditFile";
}

fn String HashEditFileTool.description(&self) @dynamic
{
	return "Edit a file using hash-anchored line references (read the file first with ReadFile to get line:hash tags). Atomic: all anchors are verified before writing; stale hashes reject the whole batch.";
}

fn String HashEditFileTool.schema(&self) @dynamic
{
	return HASH_EDIT_SCHEMA;
}

fn void? HashEditFileTool.execute(&self, Allocator allocator, DString* out, CJsonItem* args) @dynamic
{
	String      file_path = args.get_key_string("path", tmem) ?? "";
	CJsonItem*  edits_arr = args.get_key("edits");

	if (file_path == "") return INVALID_PATH_PARAM~;
	if (edits_arr == null || !edits_arr.is_array())
	{
		out.append("Missing or invalid 'edits' array.");
		return;
	}

	usz n = edits_arr.get_len();
	if (n == 0)
	{
		out.append("'edits' array is empty; nothing to do.");
		return;
	}

	List{EditOp} ops;
	ops.init(tmem);
	for (usz i = 0; i < n; i++)
	{
		CJsonItem* e = edits_arr.get_at((sz)i);
		EditOp op;
		op.line         = e.get_key_int("line") ?? 0;
		op.hash         = (e.get_key_string("hash", tmem) ?? "").copy(tmem);
		op.content      = (e.get_key_string("content", tmem) ?? "").copy(tmem);
		op.end_line     = e.get_key_int("endLine") ?? 0;
		op.end_hash     = (e.get_key_string("endHash", tmem) ?? "").copy(tmem);
		op.insert_after = e.get_key_bool("insertAfter") ?? false;
		ops.push(op);
	}

	EditOp[] edits = ops.to_array(allocator);

	// 按 line 升序排序（选择排序，规模很小）
	for (usz i = 0; i < edits.len; i++)
	{
		usz min = i;
		for (usz j = i + 1; j < edits.len; j++)
		{
			if (edits[j].line < edits[min].line) min = j;
		}
		if (min != i)
		{
			EditOp tmp  = edits[i];
			edits[i]    = edits[min];
			edits[min]  = tmp;
		}
	}

	hash_edit(allocator, out, file_path, edits)!;
}
