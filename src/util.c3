module util;

import std::time::datetime;

/**
 * JSON 字符串转义处理
 * @allocator: 内存分配器
 * @s: 待转义的原始字符串
 * @strip_quotes: 是否去除首尾引号
 * @return: 转义后的字符串，可安全用于 JSON
 */
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

/**
 * 将日期时间转换为时间戳字符串格式
 * @allocator: 内存分配器
 * @dt: 日期时间结构
 * @return: 格式如 "20260327_143052" 的时间戳字符串
 */
fn String timestamp(Allocator allocator, TzDateTime dt) {
    return string::format(allocator, "%04d%02d%02d_%02d%02d%02d", dt.year, dt.month.ordinal + 1, dt.day, dt.hour, dt.min, dt.sec);
}

fn String timestamp_id(Allocator allocator)
{
    DateTime now = datetime::now();
    return timestamp(allocator, now.to_local());
}

/**
 * 生成红色错误消息字符串（带 ANSI 颜色代码）
 */
macro String error_message(String $format)
{
    return Ansi.RED +++ $format +++ Ansi.RESET;
}

/**
 * 生成灰色系统消息字符串（带 ANSI 颜色代码）
 */
macro String system_message(String $format)
{
    return Ansi.BRIGHT_BLACK +++ $format +++ Ansi.RESET;
}
