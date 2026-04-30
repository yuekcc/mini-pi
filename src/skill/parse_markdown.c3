module skill;

import std::collections::object;
import std::collections::list;
import std::io;

struct Markdown
{
	Object* front_matter;
	String front_matter_body;
	String body;
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

fn Object* parse_front_matter(String declaration)
{
	Object* result = object::new_obj(tmem);

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

fn Markdown* parse_markdown(String content)
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

	String declaration = string::join(tmem, declaration_lines.to_array(tmem), "\n");
	String body = string::join(tmem, body_lines.to_array(tmem), "\n");

	Markdown* result = mem::tnew(Markdown);
	result.body = body.trim();
	result.front_matter_body = declaration.trim();
	result.front_matter = parse_front_matter(result.front_matter_body);

	return result;
}