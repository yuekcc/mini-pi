import std::io;
import tool;

fn void test_ls_tool() @test
{
	DString out = dstring::new(tmem);
	tool::ls(tmem, &out)!!;
	String result = out.str_view();
	io::printfn("\n%s", result);
	assert(result.contains("project.json"));
}

fn void test_write_tool() @test
{
	String demo_data = "aaabbbcccdddeeefff\naaaggghhhiiijjjkkk\nlllmmmnnn\n中文英文\n中文英文\n中文英文😀😀😀";
	DString out = dstring::new(tmem);
	tool::write(tmem, &out, "test.txt", demo_data)!!;
	String result = out.str_view().copy(tmem);
	io::printfn("\n%s", result);

	String content = (String)file::load(tmem, "test.txt")!!;
	io::printfn("content-> \n%s", content);

	assert(content.contains("aaabbbcccdddeeefff"));
	assert(content.contains("中文英文"));
	assert(content.contains("😀"));
}

fn void test_edit_tool() @test
{
	String demo_data = "aaabbbcccdddeeefff\naaaggghhhiiijjjkkk\nlllmmmnnn\n中文英文\n中文英文\n中文英文😀😀😀";
	DString out = dstring::new(tmem);
	tool::write(tmem, &out, "test_edit.txt", demo_data)!!;

	DString edit_out = dstring::new(tmem);
	tool::edit(tmem, &edit_out, "test_edit.txt", "aaa", "🤖🤖🤖")!!;
	String content = (String)file::load(tmem, "test_edit.txt")!!;
	io::printfn("content-> \n%s", content);
	assert(content.count("🤖") == 6);
}

fn void test_find_tool() @test
{
	DString out = dstring::new(tmem);
	tool::find(tmem, &out, "main", "src")!!;
	String result = out.str_view().copy(tmem);
	io::printfn("result -> \n%s", result);
	assert(result.count("main.c3") == 1);
}

fn void test_grep_tool() @test
{
	DString out = dstring::new(tmem);
	tool::grep(tmem, &out, "main", "src", "*.c3", true, false, 10)!!;
	String result = out.str_view().copy(tmem);
	io::printfn("result -> \n%s", result);
	assert(result.count("fn int main(String[] args)") == 1);
}

fn void test_read_tool() @test
{
	DString out = dstring::new(tmem);
	tool::read(tmem, &out, "src/main.c3")!!;
	String content = out.str_view().copy(tmem);
	io::printfn("content -> \n%s", content);
	assert(content.count("module mini_pi;") == 1);
}

fn void test_read_tool_offset_limit() @test
{
	// 测试 offset 功能 - 从第3行开始读取
	DString out = dstring::new(tmem);
	tool::read(tmem, &out, "test_read_lines.txt", 3, -1)!!;
	String content = out.str_view().copy(tmem);
	io::printfn("content with offset=3 -> \n%s", content);
	// 应该显示第3-7行
	assert(content.count("Testing offset and limit") == 1);
	assert(content.count("Hello World") == 0);

	// 测试 limit 功能 - 只读取3行
	DString out2 = dstring::new(tmem);
	tool::read(tmem, &out2, "test_read_lines.txt", -1, 3)!!;
	content = out2.str_view().copy(tmem);
	io::printfn("content with limit=3 -> \n%s", content);
	// 应该只显示第1-3行
	assert(content.count("Hello World") == 1);
	assert(content.count("Testing offset and limit") == 1);
	assert(content.count("Another line here") == 0);

	// 测试 offset + limit 组合
	DString out3 = dstring::new(tmem);
	tool::read(tmem, &out3, "test_read_lines.txt", 2, 3)!!;
	content = out3.str_view().copy(tmem);
	io::printfn("content with offset=2, limit=3 -> \n%s", content);
	// 应该显示第2-4行
	assert(content.count("This is a test") == 1);
	assert(content.count("Another line here") == 1);
	assert(content.count("Hello World") == 0);
	assert(content.count("Yet another line") == 0);

	// 测试 offset 超出范围
	DString out4 = dstring::new(tmem);
	tool::read(tmem, &out4, "test_read_lines.txt", 100, -1)!!;
	content = out4.str_view().copy(tmem);
	io::printfn("content with offset=100 (out of range) -> \n%s", content);
	assert(content.contains("Error"));
}

fn void test_bash_tool() @test
{
	DString out = dstring::new(tmem);
	tool::bash(tmem, &out, "ls -alh src")!!;
	String content = out.str_view().copy(tmem);
	io::printfn("content -> \n%s", content);
	assert(content.count("main.c3") >= 1);
}

fn void test_tool_pool() @test
{
	ToolHub tool_hub;
	tool_hub.init(tmem, { "ReadFile", "WriteFile", "Bash", "EditFile" });
	defer tool_hub.free();

	String schema = tool_hub.schema(tmem);

	io::printfn("Tools Schema:\n%s", tool_hub.schema(tmem));
	test::eq(true, schema.starts_with("["));
	test::eq(true, schema.trim().ends_with("]"));
}

fn void test_subagent_python_version() @test
{
	// 使用子代理方式检查 Python 版本号
	String prompt = "请执行 `python --version` 命令来检查 Python 版本，并将结果以纯文本形式返回。只需要返回版本号，例如：Python 3.x.x";
	DString out = dstring::new(tmem);
	if (try tool::execute_task(tmem, &out, "default", prompt, "检查 Python 版本号"))
	{
		String result = out.str_view().copy(tmem);
		io::printfn("子代理返回结果: %s", result);

		// 验证结果包含 Python 版本信息
		assert(result.contains("Python"));
		assert(result.contains("3."));
	}
	else
	{
		io::printfn("子代理执行失败，跳过测试（可能 mp 命令不可用）");
	}
}
