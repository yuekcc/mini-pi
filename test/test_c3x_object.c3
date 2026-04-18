import std::io;
import c3x::object;

const String TEST_DATA = `{
	"name": "bash",
	"arguments": "{\"command\": \"python --version\"}"
}`;

fn void test_c3x_object() @test
{
		Object* obj1 = object::parse(tmem, TEST_DATA)!!;
		String doc = obj1.to_json(tmem);
		Object* obj2 = object::parse(tmem, doc)!!;

		assert((obj1.get_string("name")!!) == (obj2.get_string("name")!!));
		assert((obj1.get_string("arguments")!!) == (obj2.get_string("arguments")!!));

		io::printfn("obj1 = %s", obj1);
		io::printfn("obj2 = %s", obj2);
}
