import cjson;
import std::io;


const TEST_DATA = `{"name":"Grep","arguments":"{\"path\":\"src/tool\",\"pattern\":\"return \\\\\\\"\"}"}`;

fn void test_cjson() @test
{
	CJsonItem* obj = cjson::parse((ZString)TEST_DATA);
	defer obj.free();

	CJsonItem* arguments_obj =  obj.get_key("arguments");
	io::printfn("arguments is %s", arguments_obj.get_string(tmem));

	io::printfn("reformatted:\n%s\ntest data:\n%s", obj.to_string(tmem), TEST_DATA);

	test::eq(obj.to_string(tmem), TEST_DATA);
}
