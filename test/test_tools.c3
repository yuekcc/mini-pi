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

fn void test_read_tool_offset_limit() @test
{
	// 测试 offset 功能 - 从第3行开始读取
	String content = tools::read(tmem, "test_read_lines.txt", 3, -1)!!;
	io::printfn("content with offset=3 -> \n%s", content);
	// 应该显示第3-7行
	assert(content.count("Line 3:") == 1);
	assert(content.count("Line 1:") == 0);
	
	// 测试 limit 功能 - 只读取3行
	content = tools::read(tmem, "test_read_lines.txt", -1, 3)!!;
	io::printfn("content with limit=3 -> \n%s", content);
	// 应该只显示第1-3行
	assert(content.count("Line 1:") == 1);
	assert(content.count("Line 3:") == 1);
	assert(content.count("Line 4:") == 0);
	
	// 测试 offset + limit 组合
	content = tools::read(tmem, "test_read_lines.txt", 2, 3)!!;
	io::printfn("content with offset=2, limit=3 -> \n%s", content);
	// 应该显示第2-4行
	assert(content.count("Line 2:") == 1);
	assert(content.count("Line 4:") == 1);
	assert(content.count("Line 1:") == 0);
	assert(content.count("Line 5:") == 0);
	
	// 测试 offset 超出范围
	content = tools::read(tmem, "test_read_lines.txt", 100, -1)!!;
	io::printfn("content with offset=100 (out of range) -> \n%s", content);
	assert(content.contains("Error"));
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

fn void test_subagent_python_version() @test
{
	// 使用子代理方式检查 Python 版本号
	String prompt = "请执行 `python --version` 命令来检查 Python 版本，并将结果以纯文本形式返回。只需要返回版本号，例如：Python 3.x.x";
	String result = tools::execute_task(tmem, "default", prompt, "检查 Python 版本号")!!;
	io::printfn("子代理返回结果: %s", result);
	
	// 验证结果包含 Python 版本信息
	assert(result.contains("Python"));
	assert(result.contains("3."));
}
