// 验证 c3 内置 std::encoding::json 是否可以替换 lib/cjson.c3l。
//
// 核心场景：外层 JSON 文档的某个字段是「JSON 序列化后的字符串」——
// 即 OpenAI 风格 tool_call 的 function.arguments（内层 JSON 的字符串形式）。
// 此前 c3 内置 json 在「字符串内嵌 JSON」场景有转义问题（序列化不做转义）。
//
// 结论（c3 0.8.3）：
//   - 解析路径：std::json 可替换 cjson（转义解码正确）。
//   - 序列化路径：json::marshal 正确转义，可替换；但 Object.to_format
//     （string::format("%s", obj) 走的路径）不转义字符串内容，输出非法 JSON，
//     不可替换 —— 详见 test_std_json_format_roundtrip。

import cjson;
import std::io;
import std::encoding::json;
import std::collections::object;

// --- 测试数据 ---------------------------------------------------------------

// 注意：c3 反引号字符串是原始字符串（MANUAL: raw string literal，不做转义处理），
// 因此下面的字面量直接书写 JSON 文本本身（单层反斜杠）。

// 内层 JSON 的文本（get_string 后应得到的值，含引号与反斜杠）。
const INNER_ARGS = `{"cmd":"echo \"hi\"","cwd":"C:\\temp"}`;

// 外层文档：arguments 字段是 INNER_ARGS 经 JSON 转义后的字符串。
const NESTED_DOC = `{"id":"call_1","type":"function","function":{"name":"Bash","arguments":"{\"cmd\":\"echo \\\"hi\\\"\",\"cwd\":\"C:\\\\temp\"}"}}`;

// 转义边界用例：\n、\t、\uXXXX、\\、代理对 \uD83D\uDE00（😀）。
const ESCAPE_DOC = `{"a":"line1\nline2","b":"\u0041","c":"tab\there","d":"a\\b","e":"\uD83D\uDE00"}`;

// --- cjson 基线（当前实现，应全部通过） --------------------------------------

fn void test_cjson() @test
{
	CJsonItem* obj = cjson::parse((ZString)TEST_DATA);
	defer obj.free();

	CJsonItem* arguments_obj = obj.get_key("arguments");
	String json_doc = string::format(tmem, "%s", obj);

	io::printfn("arguments is %s", arguments_obj.get_string(tmem));
	io::printfn("reformatted:\n%s\ntest data:\n%s", json_doc, TEST_DATA);
	test::eq(json_doc, TEST_DATA);
}

const TEST_DATA = `{"name":"Grep","arguments":"{\"path\":\"src/tool\",\"pattern\":\"return \\\\\\\"\"}"}`;

// 解析外层文档并下钻取出内层 JSON 字符串。
fn void test_cjson_parse_nested() @test
{
	CJsonItem* obj = cjson::parse((ZString)NESTED_DOC);
	defer obj.free();

	String args = obj.get_key("function").get_key_string("arguments", tmem)!!;
	io::printfn("cjson parsed arguments: %s", args);
	test::eq(args, INNER_ARGS);
}

// 构造 → 序列化 → 再解析：内层 JSON 字符串必须无损还原（转义正确）。
fn void test_cjson_build_roundtrip() @test
{
	@pool()
	{
		CJsonItem* doc = cjson::new_object(tmem);
		CJsonItem* function_obj = cjson::new_object(tmem);
		doc.set("id", "call_1");
		doc.set("type", "function");
		doc.set("function", function_obj);
		function_obj.set("name", "Bash");
		function_obj.set("arguments", INNER_ARGS); // 字段值是 JSON 序列化后的字符串

		String out = string::format(tmem, "%s", doc);
		io::printfn("cjson serialized: %s", out);

		CJsonItem* re = cjson::parse((ZString)out);
		defer re.free();
		test::eq(re.get_key("function").get_key_string("arguments", tmem)!!, INNER_ARGS);
	};
}

// --- std::json 解析路径 ------------------------------------------------------

fn void test_std_json_parse_nested() @test
{
	Object* obj = NESTED_DOC.tparse_json()!!;

	String args = obj.get("function")!!.get_string("arguments")!!;
	io::printfn("std::json parsed arguments: %s", args);
	test::eq(args, INNER_ARGS);
}

fn void test_std_json_parse_escapes() @test
{
	Object* obj = ESCAPE_DOC.tparse_json()!!;

	// 普通转义：\n \t \uXXXX \\
	test::eq(obj.get_string("a")!!, "line1\nline2");
	test::eq(obj.get_string("b")!!, "A");
	test::eq(obj.get_string("c")!!, "tab\there");
	test::eq(obj.get_string("d")!!, "a\\b"); // 值: a\b

	// 代理对 \uD83D\uDE00 → U+1F600 😀
	DString emoji = dstring::new_with_capacity(tmem, 4);
	emoji.append_char32(0x1F600);
	test::eq(obj.get_string("e")!!, emoji.str_view());
}

// --- std::json 序列化路径 ----------------------------------------------------

// json::marshal：内部走 serialize_string（json_marshal.c3:536），转义正确。
fn void test_std_json_marshal_roundtrip() @test
{
	@pool()
	{
		Object* doc = object::new_obj(tmem);
		Object* function_obj = object::new_obj(tmem);
		doc.set("id", "call_1");
		doc.set("type", "function");
		doc.set("function", function_obj);
		function_obj.set("name", "Bash");
		function_obj.set("arguments", INNER_ARGS);

		String out = json::marshal(tmem, doc);
		io::printfn("std::json marshal output: %s", out);

		Object* re = out.tparse_json()!!;
		test::eq(re.get("function")!!.get_string("arguments")!!, INNER_ARGS);
	};
}

// Object.to_format（string::format("%s", obj)）：0.8.3 不转义字符串内容，
// 输出非法 JSON，无法再解析 —— 这是当初迁移到 cjson 的转义问题所在。
// 若未来 c3 修复 to_format，本用例会转为验证「输出可解析且无损还原」。
fn void test_std_json_format_roundtrip() @test
{
	@pool()
	{
		Object* doc = object::new_obj(tmem);
		Object* function_obj = object::new_obj(tmem);
		doc.set("id", "call_1");
		doc.set("type", "function");
		doc.set("function", function_obj);
		function_obj.set("name", "Bash");
		function_obj.set("arguments", INNER_ARGS);

		String out = string::format(tmem, "%s", doc);
		io::printfn("std::json %%s output (broken): %s", out);

		if (catch out.tparse_json())
		{
			// 预期：反序列化失败（内层引号未被转义，输出不是合法 JSON）。
			io::printfn("-> %s", "输出无法重新解析，确认 std::json(%%s) 不可替换 cjson");
			return;
		}
		// 未来修复后的断言：输出应可解析且 arguments 无损还原。
		Object* re = out.tparse_json()!!;
		test::eq(re.get("function")!!.get_string("arguments")!!, INNER_ARGS);
	};
}
