module util;

import std::time::datetime;
import std::io;
import std::io::path;

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

macro void? do_dump(String $file_name_template, String content) @private
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
