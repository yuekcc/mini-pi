module c3x::object;

fn String escape(Allocator allocator, String s, bool strip_quotes = true)
{
	// Conservative allocation: most strings need minimal escaping
	sz initial_capacity = s.len + s.len / 5 + 2; // ~1.2x + quotes

	if (allocator == tmem)
	{
		DString result = dstring::new_with_capacity(tmem, initial_capacity);
		escape_dstring(result, s, strip_quotes);
		return result.str_view();
	}
	@pool()
	{
		DString result = dstring::temp_with_capacity(initial_capacity);
		escape_dstring(result, s, strip_quotes);
		return result.copy_str(allocator);
	};
}

fn void escape_dstring(DString result, String s, bool strip_quotes) @private
{
	if (!strip_quotes) result.append_char('"');

	foreach (char c : s)
	{
		switch (c)
		{
			case '"': result.append(`\"`);
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
}

fn String? unescape(Allocator allocator, String s, bool allow_unquoted = false, bool lenient = false)
{
	if (s.len >= 2 && s[0] == '"' && s[^1] == '"')
	{
		// Remove quotes.
		s = s[1:^2];
	}
	else if (!allow_unquoted) return string::UNTERMINATED_STRING~;

	// Handle empty string case
	if (!s.len)
	{
		return "".copy(allocator);
	}
	if (allocator == tmem)
	{
		DString result = dstring::new_with_capacity(tmem, s.len);
		unescape_dstring(s, result, allow_unquoted, lenient)!;
		return result.str_view();
	}
	@pool()
	{
		DString result = dstring::temp_with_capacity(s.len);
		unescape_dstring(s, result, allow_unquoted, lenient)!;
		return result.copy_str(allocator);
	};
}

fn void? unescape_dstring(String s, DString result, bool allow_unquoted = false, bool lenient = false) @private
{
	usz len = s.len;
	for (usz i = 0; i < len; i++)
	{
		char c = s[i];
		if (c != '\\')
		{
			result.append_char(c);
			continue;
		}

		// Handle escape sequence
		if (i + 1 >= len) return string::INVALID_ESCAPE_SEQUENCE~;

		char escape_char = s[++i];
		switch (escape_char)
		{
			case '"': result.append_char('"');
			case '\\': result.append_char('\\');
			case '/': result.append_char('/');
			case 'b': result.append_char('\b');
			case 'f': result.append_char('\f');
			case 'n': result.append_char('\n');
			case 'r': result.append_char('\r');
			case 't': result.append_char('\t');
			case 'v': result.append_char('\v');
			case '0': result.append_char('\0');
			case 'x':
				// Hex escape \xHH
				if (i + 2 >= len) return string::INVALID_HEX_ESCAPE~;
				char h1 = s[++i];
				char h2 = s[++i];
				if (!h1.is_xdigit() || !h2.is_xdigit()) return string::INVALID_HEX_ESCAPE~;
				uint val = h1 > '9' ? (h1 | 32) - 'a' + 10 : h1 - '0';
				val = val << 4;
				val += h2 > '9' ? (h2 | 32) - 'a' + 10 : h2 - '0';
				result.append_char((char)val);
			case 'u':
				// Unicode escape \uHHHH
				if (i + 4 >= len) return string::INVALID_UNICODE_ESCAPE~;
				uint val;
				for (int j = 0; j < 4; j++)
				{
					char hex_char = s[++i];
					if (!hex_char.is_xdigit()) return string::INVALID_UNICODE_ESCAPE~;
					val = val << 4 + (hex_char > '9' ? (hex_char | 32) - 'a' + 10 : hex_char - '0');
				}
				result.append_char32(val);
			case 'U':
				// Unicode escape \UHHHHHHHH
				if (i + 8 >= len) return string::INVALID_UNICODE_ESCAPE~;
				uint val;
				for (int j = 0; j < 8; j++)
				{
					char hex_char = s[++i];
					if (!hex_char.is_xdigit()) return string::INVALID_UNICODE_ESCAPE~;
					val = val << 4 + (hex_char > '9' ? (hex_char | 32) - 'a' + 10 : hex_char - '0');
				}
				result.append_char32(val);
			default:
				if (!lenient) return string::INVALID_ESCAPE_SEQUENCE~;
				result.append_char(escape_char);
		}
	}
}
