module util;

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