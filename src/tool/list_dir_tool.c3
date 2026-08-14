module tool;

import std::io;
import std::io::path;
import std::collections::list;
import std::sort;

import cjson;
import libc;


// 单条目录条目：名称、是否为目录、文件大小、权限位（仅 Linux 下采集）。
struct LsEntry
{
	String name;
	bool is_dir;
	long size;
	uint mode;
}

// 扩展名分组统计。
struct ExtGroup
{
	String ext;
	int count;
}

fn int _entry_cmp(LsEntry a, LsEntry b)
{
	// 目录在前，组内按名称升序（大小写敏感，与 ASCII 排序一致）。
	if (a.is_dir != b.is_dir) return a.is_dir ? -1 : 1;
	return a.name.compare_to(b.name);
}

fn int _ext_group_cmp(ExtGroup a, ExtGroup b)
{
	// 按文件数降序，数量相同按扩展名升序。
	if (a.count != b.count) return a.count > b.count ? -1 : 1;
	return a.ext.compare_to(b.ext);
}

fn int _str_cmp(String a, String b) => a.compare_to(b);

// 将字节数格式化为人类可读形式：193B / 3.2K / 3.3M / 1.0G。
fn void _append_human_size(DString* out, long size)
{
	if (size < 1024)
	{
		out.appendf("%dB", size);
		return;
	}
	double bytes = (double)size;
	if (bytes < 1024.0 * 1024.0)
	{
		out.appendf("%.1fK", bytes / 1024.0);
		return;
	}
	if (bytes < 1024.0 * 1024.0 * 1024.0)
	{
		out.appendf("%.1fM", bytes / (1024.0 * 1024.0));
		return;
	}
	out.appendf("%.1fG", bytes / (1024.0 * 1024.0 * 1024.0));
}

// 提取扩展名（含前导点），无扩展名返回空串。点文件（如 ".c3fmt"）整体视为扩展名。
fn String _ext_of(String name)
{
	usz i = name.len;
	while (i > 0)
	{
		i--;
		if (name[i] == '.') return name[i..];
	}
	return "";
}

// 输出单条目录条目行。权限码仅在 Linux 下输出。
fn void _append_entry_line(DString* out, LsEntry* e)
{
	$if env::LINUX:
		uint perm = e.mode & 0o777;
		out.appendf("%d%d%d  ", (int)((perm >> 6) & 7), (int)((perm >> 3) & 7), (int)(perm & 7));
	$endif
	if (e.is_dir)
	{
		out.appendf("%s/", e.name);
		return;
	}
	out.appendf("%s  ", e.name);
	_append_human_size(out, e.size);
}

// 列出目录内容（纯 c3 实现，不再调用外部 ls 命令）：
//   - 目录在前、文件在后，各自按名称升序；
//   - 目录行：{权限码}  {名称}/；文件行：{权限码}  {名称}  {大小}；
//   - 权限码仅在 Linux 下输出；
//   - 末尾输出 Summary 行（文件/目录计数 + 扩展名分组统计）。
fn void? ls(Allocator allocator, DString* out, String file_path = "", int limit = 500)
{
	String dir_path = file_path == "" ? "." : file_path;
	Path? maybe_dir = path::new(allocator, dir_path);
	if (catch ex = maybe_dir)
	{
		out.appendf("Error listing directory '%s': %s", dir_path, ex);
		return;
	}
	Path dir = maybe_dir;
	PathList? maybe_entries = path::ls(allocator, dir);
	if (catch ex = maybe_entries)
	{
		out.appendf("Error listing directory '%s': %s", dir_path, ex);
		return;
	}
	PathList entries = maybe_entries;

	List{LsEntry} list;
	list.init(allocator);
	foreach (entry : entries)
	{
		LsEntry e;
		e.name = entry.copy(allocator);
		@pool()
		{
			Path full = dir.tappend(entry)!!;
			e.is_dir = path::is_dir(full);
			if (!e.is_dir)
			{
				e.size = path::file_size(full) ?? 0;
			}
			$if env::LINUX:
				libc::Stat st;
				if (libc::stat(full.zstr_tcopy(), &st) == 0) e.mode = st.st_mode;
			$endif
		};
		list.push(e);
	}

	sort::quicksort(list.array_view(), &_entry_cmp);

	int files = 0;
	int dirs = 0;
	int shown = 0;
	foreach (&e : list)
	{
		if (e.is_dir) { dirs++; } else { files++; }
		if (shown >= limit) continue;
		_append_entry_line(out, e);
		out.append("\n");
		shown++;
	}

	if (shown < (int)list.len())
	{
		out.appendf("... (%d more entries)", (int)list.len() - shown);
		return;
	}

	// Summary 行：扩展名分组统计（含前 5 组，其余合并为 "+N more"）。
	List{String} exts;
	exts.init(allocator);
	foreach (&e : list)
	{
		if (!e.is_dir) exts.push(_ext_of(e.name));
	}
	sort::quicksort(exts.array_view(), &_str_cmp);

	List{ExtGroup} groups;
	groups.init(allocator);
	sz i = 0;
	while (i < exts.len())
	{
		String ext = exts[i];
		sz j = i;
		while (j < exts.len() && exts[j] == ext) j++;
		ExtGroup g;
		g.ext = ext;
		g.count = (int)(j - i);
		groups.push(g);
		i = j;
	}
	sort::quicksort(groups.array_view(), &_ext_group_cmp);

	out.appendf("Summary: %d files, %d dirs", files, dirs);
	if (files > 0)
	{
		out.append(" (");
		int shown_groups = 0;
		usz remaining = 0;
		foreach (&g : groups)
		{
			if (shown_groups < 5)
			{
				if (shown_groups > 0) out.append(", ");
				out.appendf("%d %s", g.count, g.ext == "" ? "no ext" : g.ext);
				shown_groups++;
			}
			else
			{
				remaining += (usz)g.count;
			}
		}
		if (remaining > 0) out.appendf(", +%d more", remaining);
		out.append(")");
	}
}

const String LS_SCHEMA = (String)$embed("list_dir_tool_schema.json");

struct ListDirTool (Tool)
{
	bool _pad;
}

fn String ListDirTool.name(&self) @dynamic
{
	return "ListDir";
}

fn String ListDirTool.description(&self) @dynamic
{
	return "List directory contents. Directories first, then files, each sorted alphabetically; '/' suffix marks directories, file size shown for files. Permission codes (e.g. 755/644) are shown on Linux only. Ends with a summary of file/dir counts and extension groups. Output is truncated to 500 entries.";
}

fn String ListDirTool.schema(&self) @dynamic
{
	return LS_SCHEMA;
}

fn void? ListDirTool.execute(&self, ToolContext* ctx, Allocator allocator, DString* out, CJsonItem* args, ToolResultMeta* meta) @dynamic
{
	String file_path = args.get_key_string("path", tmem) ?? ".";
	int limit = args.get_key_int("limit") ?? 500;
	ls(allocator, out, file_path, limit)!;
}
