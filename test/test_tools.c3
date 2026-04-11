import std::io;
import tools;

fn void test_ls_tool() @test
{
	String result = tools::ls(tmem)!!;
	io::printfn("\n%s", result);
	assert(result.contains("project.json"));
}

fn void test_write_tool() @test
{
	String demo_data = "aaabbbcccdddeeefff\naaaggghhhiiijjjkkk\nlllmmmnnn\n中文英文😀😀😀";
	String result = tools::write(tmem, "test.txt", demo_data)!!;
	io::printfn("\n%s", result);

	String content = (String)file::load(tmem, "test.txt")!!;
	io::printfn("content-> \n%s", content);

	assert(content.contains("aaabbbcccdddeeefff"));
	assert(content.contains("中文英文😀😀😀"));
}

fn void test_edit_tool() @test
{
	String demo_data = "aaabbbcccdddeeefff\naaaggghhhiiijjjkkk\nlllmmmnnn\n中文英文😀😀😀";
	String result = tools::write(tmem, "test_edit.txt", demo_data)!!;

	tools::edit(tmem,"test_edit.txt", "aaa", "🤖🤖🤖")!!;
	String content = (String)file::load(tmem, "test_edit.txt")!!;
	io::printfn("content-> \n%s", content);
	assert(content.count("🤖") == 6);
}

fn void test_find_tool() @test
{
	String result = tools::find(tmem, "main", "src")!!;
	io::printfn("result -> \n%s", result);
	assert(result.count("main.c3") == 1);
}

fn void test_grep_tool() @test
{
	String result = tools::grep(tmem, "main", "src", "*.c3", true, false, 10)!!;
	io::printfn("result -> \n%s", result);
	assert(result.count("fn int main(String[] args)") == 1);
}

fn void test_read_tool() @test
{
	String content = tools::read(tmem,"src/main.c3")!!;
	io::printfn("content -> \n%s", content);
	assert(content.count("fn int main(String[] args)") == 1);
}

fn void test_bash_tool() @test
{
	String content = tools::bash(tmem,"ls -alh src")!!;
	assert(content.count("main.c3") == 1);
}

fn void test_tool_pool() @test
{
	ToolPool tool_pool;
	tool_pool.init(tmem, null);
	defer tool_pool.free();

	io::printfn("Tools Schema:\n%s", tool_pool.schema(tmem));
}
