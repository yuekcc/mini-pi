import std::io;
import context;

fn void test_create_context() @test
{
	InitOptions init_options;
	Context cx;
	cx.init(tmem, &init_options);
	defer cx.free();

	Message message;
	cx.push_message(&message);
	assert(cx.messages.len() == 2);

	io::printfn("id = %s, log_file_path = %s", cx.id, cx.log_file_path);
}
