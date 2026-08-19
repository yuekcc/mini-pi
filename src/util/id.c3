module util;

import std::io::path;
import std::time;
import std::atomic;

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

// 进程内单调递增序号：解决同一进程内同秒并发的 id 碰撞（Agent 线程单写；
// 原子化以防未来被多线程复用）。零填充定宽，保证同秒内字典序递增。
Atomic{int} g_timestamp_seq;

// 跨进程唯一性：并发 mp 进程同秒会得到相同时间戳，必须追加 pid 区分
// （否则两个 session_id 相同、会追加写同一个 transcript 文件造成损坏）。
// 无条件声明、仅在对应平台分支引用（模式见 cmd.c3）。
extern fn uint get_current_pid() @cname("GetCurrentProcessId"); // Windows
extern fn int getpid(); // POSIX

fn String timestamp_id(Allocator allocator)
{
	int seq = g_timestamp_seq.add(1);
	String ts = timestamp(tmem, datetime::now());
	$if env::WIN32:
		return string::format(allocator, "%s_%04d_%d", ts, seq, (int)get_current_pid());
	$else
		return string::format(allocator, "%s_%04d_%d", ts, seq, getpid());
	$endif
}
