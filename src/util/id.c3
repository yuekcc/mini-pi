module util;

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
	// datetime::now() 返回 UTC，这里统一转为本地时间再取分量，
	// 保证 session id / 文件名 / 各类 id 都使用本地时间。
	dt = dt.to_local();
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
