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
	defer (void)process.destroy();

	int exit_code = process.join()!;

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
		
		return { .code = exit_code, .output = result.copy_str(allocator) };
	};
}

fn String? execute_to_string(Allocator allocator, String[] command_line)
{
	CommandResult cmd_result = execute(allocator, command_line)!;
	return cmd_result.output;
}
