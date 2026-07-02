import std::io;
import util::cmd;

fn void test_cmd_execute_to_string() @test
{
	String[] final_command_line = {"curl", "-k", "https://www.baidu.com"};
	String result = cmd::execute_to_string(tmem, final_command_line)!!;

	test::eq(true, result.contains("<html>"));
	test::eq(true, result.contains("</html>"));
}

fn void test_cmd_non_zero_return_code() @test
{
	String[] final_command_line = {"curl", "-k"};

	CommandResult? result = cmd::execute(tmem, final_command_line);
	if (try result)
	{
		test::ne(0, result.code);
		test::eq(true, result.output.contains("no URL specified"));
	}
}

fn void test_coreutils_version() @test
{
	String[] final_command_line = {"coreutils", "--version"};

	CommandResult? result = cmd::execute(tmem, final_command_line);
	if (try result)
	{
		io::printfn("output = %s\n\nreturn code = %d", result.output, result.code);

		test::eq(0, result.code);
		test::eq(true, result.output.contains("coreutils"));
	}
}
