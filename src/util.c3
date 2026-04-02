module util;

import std::time::datetime;
import std::io;
import std::io::path;

fn String escape(Allocator allocator, String s, bool strip_quotes = true)
{
    usz initial_capacity = s.len + s.len / 5 + 2;
    DString result = dstring::new_with_capacity(tmem, initial_capacity);

    if (!strip_quotes) result.append_char('"');

    foreach (char c : s)
    {
        switch (c)
        {
            case '"':  result.append(`\"`);
            case '\\': result.append(`\\`);
            case '\b': result.append(`\b`);
            case '\f': result.append(`\f`);
            case '\n': result.append(`\n`);
            case '\r': result.append(`\r`);
            case '\t': result.append(`\t`);
            case '\v': result.append(`\v`);
            case '\0': result.append(`\0`);
            default:
                result.append_char(c);
        }
    }

    if (!strip_quotes) result.append_char('"');
    return result.str_view().copy(allocator);
}

fn String timestamp(Allocator allocator, TzDateTime dt) {
    return string::format(allocator, "%04d%02d%02d_%02d%02d%02d", dt.year, dt.month.ordinal + 1, dt.day, dt.hour, dt.min, dt.sec);
}

fn String timestamp_id(Allocator allocator)
{
    DateTime now = datetime::now();
    return timestamp(allocator, now.to_local());
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
