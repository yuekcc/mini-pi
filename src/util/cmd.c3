module util::cmd;

import std::os::process;
import std::os::win32;
import std::io;
import libc;

struct CommandResult
{
	int code;
	String output;
}

fn void close_stdin(Process process)
{
	if (process.stdin_file)
	{
		libc::fclose(process.stdin_file);
		process.stdin_file = null;
	}
	$if env::WIN32:
		if (process.hStdInput)
		{
			win32::closeHandle(process.hStdInput);
			process.hStdInput = null;
		}
	$endif
}

fn CommandResult? execute(Allocator allocator, String[] command_line)
{
	Process process = process::spawn(command_line, STDERR_TO_STDOUT | INHERIT_ENV | NO_WINDOW)!;
	defer (void)process.destroy();

	// 手工关闭 stdin，避免一直在等待输入
	close_stdin(process);

	@pool()
	{
		DString result = dstring::new(tmem);
		while (true)
		{
			char[512] buf @noinit;
			sz len = process.read_stdout(&buf, buf.len)!;
			if (len == 0)
			{
				break;
			}

			result.write(buf[:len])!;
		}

		int exit_code = process.join()!;
		return { .code = exit_code, .output = result.copy_str(allocator) };
	};
}

fn String? execute_to_string(Allocator allocator, String[] command_line)
{
	CommandResult cmd_result = execute(allocator, command_line)!;
	return cmd_result.output;
}
