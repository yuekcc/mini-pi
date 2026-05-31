module ng::util;

import std::io::path;
import std::time;

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

fn String timestamp(Allocator allocator, DateTime dt)
{
	return string::format(
		allocator,
		"%04d%02d%02d_%02d%02d%02d",
		dt.year,
		dt.month.ordinal + 1,
		dt.day,
		dt.hour,
		dt.min,
		dt.sec
	);
}

fn String timestamp_id(Allocator allocator)
{
	return timestamp(allocator,datetime::now());
}
