module c3x::object;

import std::io;

fn String Object.to_json(&self, Allocator allocator)
{
	return string::format(allocator, "%s", self);
}

fn sz? Object.to_format(&self, Formatter* formatter) @dynamic
{
	switch (self.type)
	{
		case String:
			return formatter.printf(`"%s"`, escape(tmem, self.s))!;
		default:
			return self.to_format_default(formatter);
	}
}
