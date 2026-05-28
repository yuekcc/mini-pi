module ng::util;

import std::io::path;

fn String hash_path(Path file_path)
{
	String[] parts = file_path.treplace("\\", "/").tsplit("/");

	DString buf = dstring::new(tmem);
	foreach (part : parts[:parts.len - 1])
	{
		buf.append(part[0]);
	}

	String basename = file_path.basename();
	buf.append("_");
	buf.append(basename);

	return buf.str_view();
}