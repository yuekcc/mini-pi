import std::io;
import cmd;

fn void test_execute_to_string() @test
{
    String[] final_command_line = {"./curl", "-k", "https://www.baidu.com"};
    String result = cmd::execute_to_string(tmem, final_command_line)!!;

    // io::printfn("%s", result);
    assert(result.contains("<html>") && result.contains("</html>"));
}

fn void test_non_zero_return_code() @test
{
    String[] final_command_line = {"./curl", "-k"};
    String result = cmd::execute_to_string(tmem, final_command_line)!!;

    io::printfn("%s", result);
    assert(result.contains("no URL specified"));
}