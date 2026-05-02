import std::io;
import cmd;

fn void test_cmd_execute_to_string() @test
{
	String[] final_command_line = {"curl", "-k", "https://www.baidu.com"};
	String result = cmd::execute_to_string(tmem, final_command_line)!!;

	assert(result.contains("<html>") && result.contains("</html>"));
}

fn void test_cmd_non_zero_return_code() @test
{
	String[] final_command_line = {"curl", "-k"};

	CommandResult? result = cmd::execute(tmem, final_command_line);
	if (try result)
	{
		io::printfn("exit code is %d, output is %s", result.code, result.output);
		assert(result.output.contains("no URL specified"));
	}
}
