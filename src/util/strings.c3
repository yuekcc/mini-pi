module util;


fn String normalize_line_endings(Allocator allocator, String str)
{
	return str.replace(allocator, "\r\n", "\n");
}

fn String pad_start(Allocator allocator, usz target_length, String pad_str)
{
	DString buf = dstring::new(tmem);
	for (usz i = 0; i < target_length; i++)
	{
		buf.append(pad_str);
	}

	return buf.copy_str(allocator);
}
