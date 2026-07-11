import cjson;
import std::io;


const TEST_DATA = `{"name":"Grep","arguments":"{\"path\":\"src/tool\",\"pattern\":\"return \\\\\\\"\"}"}`;

fn void test_cjson() @test
{
	CJsonItem* obj = cjson::parse((ZString)TEST_DATA);
	defer obj.free();

	CJsonItem* arguments_obj =  obj.get_key("arguments");
	String json_doc = string::format(tmem, "%s", obj);

	io::printfn("arguments is %s", arguments_obj.get_string(tmem));
	io::printfn("reformatted:\n%s\ntest data:\n%s", json_doc, TEST_DATA);
	test::eq(json_doc, TEST_DATA);
}
