module util;

import std::time::datetime;
import std::io;
import std::io::path;
import std::os::env;

fn String hash_path(Path file_path)
{
	$if env::WIN32:
		String[] parts = file_path.str_view().tsplit("\\");
	$else
		String[] parts = file_path.str_view().tsplit("/");
	$endif

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

fn String normalize_line_endings(Allocator allocator, String str)
{
	return str.replace(allocator, "\r\n", "\n");
}

fn String pad_start(Allocator allocator, usz target_length, String pad_str)
{
	DString buf = dstring::new(tmem);
	for(usz i = 0; i < target_length; i++)
	{
		buf.append(pad_str);
	}

	return buf.copy_str(allocator);
}

fn String timestamp(Allocator allocator, TzDateTime dt) {
	return string::format(allocator, "%04d%02d%02d_%02d%02d%02d", dt.year, dt.month.ordinal + 1, dt.day, dt.hour, dt.min, dt.sec);
}

fn String timestamp_id(Allocator allocator)
{
	DateTime now = datetime::now();
	return timestamp(allocator, now.to_local());
}

macro String bold(String $format)
{
	return Ansi.BOLD +++ $format +++ Ansi.RESET;
}

macro String error_message(String $format)
{
	return Ansi.RED +++ $format +++ Ansi.RESET;
}

macro String system_message(String $format)
{
	return Ansi.BRIGHT_BLACK +++ $format +++ Ansi.RESET;
}

macro void? do_dump(String $file_name_template, String content) @local
{
	String file_name = string::format(tmem, $file_name_template, timestamp_id(tmem));
	Path file_path = path::new(tmem, file_name)!;
	Path dir = file_path.parent()!;
	if (!path::exists(dir))
	{
		path::mkdir(dir, true)!;
	}

	file::save(file_path.str_view(), content)!;
}

macro bool dump(String $file_name_template, String content)
{
	return @ok(do_dump($file_name_template, content));
}


fn Path? get_agent_home()
{
	String home_dir_str = env::get_home_dir(tmem)!;
	Path home_dir = path::new(tmem, home_dir_str)!;
	Path mp_home = home_dir.append(tmem, string::format(tmem, ".config/mp"))!;
	return mp_home;
}

fn String get_config_file(Allocator allocator)
{
	Path agent_home = get_agent_home()!!;
	return agent_home.append(tmem, string::format(tmem, "mp.json"))!!.str_view().copy(allocator);
}

