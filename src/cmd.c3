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
    Process process = process::spawn(
        command_line,
        STDERR_TO_STDOUT | INHERIT_ENV | NO_WINDOW
    )!;

    @pool()
    {
        DString result = dstring::new(tmem);
        while(true)
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
            if (!process.is_running()!) {
                process.destroy();
                break;
            }
        }

        return {
            .code = 0,
            .output = result.copy_str(allocator)
        };
    };
}

fn String? execute_to_string(Allocator allocator, String[] command_line)
{
    CommandResult cmd_result = execute(allocator, command_line)!;
    return cmd_result.output;
}

fn void test_execute_to_string() @test
{
    String[] final_command_line = {"curl", "-k", "https://www.baidu.com"};
    String result = cmd::execute_to_string(tmem, final_command_line)!!;

    assert(result.contains("<html>") && result.contains("</html>"));
}

fn void test_non_zero_return_code() @test
{
    String[] final_command_line = {"curl", "-k"};
    String result = cmd::execute_to_string(tmem, final_command_line)!!;

    io::printfn("%s", result);
    assert(result.contains("no URL specified"));
}
