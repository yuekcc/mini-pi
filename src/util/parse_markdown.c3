module util;

import std::collections::object;
import std::collections::list;
import std::io;
import std::core::mem::allocators;

struct Markdown
{
	Object* front_matter;
	String front_matter_body;
	String body;
}

// 释放 parse_markdown 在 allocator 上分配的全部内容：
//   - body / front_matter_body（String，.copy(allocator) 出的独立串）
//   - front_matter（Object*，Object.free 用其内部记录的 allocator 递归释放 entries 与自身）
//   - 结构体本身
// 契约：
//   - 仅当 parse_markdown 传入堆 allocator（如 &LIBC_ALLOCATOR / app.allocator）时才需调用；
//   - 传入 tmem 时无需调用——tmem pool 退出自动回收，调本方法会 double-free。
//   - 字段均为 .copy(allocator) 出的独立串（空串亦是堆空串），String.free 的 ptr 守卫可安全释放。
fn void Markdown.free(&self, Allocator allocator)
{
	self.body.free(allocator);
	self.front_matter_body.free(allocator);
	self.front_matter.free(); // Object 自带 allocator，递归释放 entries 与自身
	alloc::free(allocator, self);
}

fn String try_unescape(String str)
{
	String trimmed = str.trim();
	if (trimmed.starts_with("\"") && trimmed.ends_with("\""))
	{
		return trimmed.tunescape()!!;
	}

	return trimmed;
}

// front_matter 的 Object 及其全部 entry value 都分配在 allocator：
// object::new_obj(allocator) + set 内部 new_string(allocator, ...) 会 copy value。
fn Object* parse_front_matter(Allocator allocator, String declaration)
{
	Object* result = object::new_obj(allocator);

	String[] lines = declaration.tsplit("\n", skip_empty: false);
	foreach (line : lines)
	{
		if (try colon_index = line.index_of(":"))
		{
			String key = line[0..colon_index - 1];
			// io::printfn("key = %s, colon_index = %d", key, colon_index);

			String value = line[colon_index + 1..];
			// io::printfn("value = %s, colon_index = %d", try_unescape(value), colon_index);

			result.set(key, try_unescape(value));
		}
	}

	return result;
}

// 解析结果（结构体 + body + front_matter_body + front_matter Object）全部落在 allocator。
// 中间解析值仍用 tmem（临时，函数返回后由调用方 tmem 作用域回收）。
// allocator 可传 tmem（零管理，pool 退出回收，勿调 Markdown.free）或堆 allocator
// （调用方消费完负责 Markdown.free(allocator)）。
fn Markdown* parse_markdown(Allocator allocator, String content)
{
	String formatted_content = content.trim().treplace("\r\n", "\n");
	String[] lines = formatted_content.tsplit("\n", skip_empty: false);

	bool get_start_separator = false;
	bool get_end_separator = false;

	List{String} declaration_lines;
	defer declaration_lines.free();

	List{String} body_lines;
	defer body_lines.free();

	foreach (line : lines)
	{
		if (line.starts_with("---") && !get_start_separator)
		{
			get_start_separator = true;
			continue;
		}

		if (line.starts_with("---") && get_start_separator && !get_end_separator)
		{
			get_end_separator = true;
			continue;
		}

		if (get_start_separator && !get_end_separator)
		{
			declaration_lines.push(line);
			continue;
		}

		if (get_start_separator && get_end_separator)
		{
			body_lines.push(line.trim_right());
			continue;
		}
	}

	// 中间 join 用 tmem；trim 为 @pure 视图，.copy(allocator) 落到目标分配器为独立可 free 串。
	String declaration = string::join(tmem, declaration_lines.to_array(tmem), "\n");
	String body = string::join(tmem, body_lines.to_array(tmem), "\n");

	Markdown* result = alloc::new(allocator, Markdown);
	result.body = body.trim().copy(allocator);
	result.front_matter_body = declaration.trim().copy(allocator);
	result.front_matter = parse_front_matter(allocator, result.front_matter_body);

	return result;
}
