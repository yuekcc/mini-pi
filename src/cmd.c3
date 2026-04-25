module cmd;

import std::os::process;
import std::io;

struct CommandResult
{
	int code;
	String output;
}

fn CommandResult? execute(Allocator allocator, String[] command_line)
{
	Process process = process::spawn(command_line, STDERR_TO_STDOUT | INHERIT_ENV | NO_WINDOW)!;

	@pool()
	{
		DString result = dstring::new(tmem);
		while (true)
		{
			char[512] buf @noinit;
			usz len = process.read_stdout(&buf, buf.len)!;
			if (len == 0)
			{
				break;
			}

			result.write(buf[:len])!;
		}

		while (true)
		{
			if (!process.is_running()!)
			{
				process.destroy();
				break;
			}
		}

		return { .code = 0, .output = result.copy_str(allocator) };
	};
}

fn String? execute_to_string(Allocator allocator, String[] command_line)
{
	CommandResult cmd_result = execute(allocator, command_line)!;
	return cmd_result.output;
}