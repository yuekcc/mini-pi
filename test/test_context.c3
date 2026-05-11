import std::io;

import context;
import skill;

fn void test_create_context() @test
{
	SkillHub* context1 = skill::use_skill_hub();
	defer 	skill::free_skill_context();

	InitOptions init_options;
	Context cx;
	cx.init(tmem, &init_options, context1);
	defer cx.free();

	Message message;
	cx.push_message(&message);
	assert (cx.messages.len() == 2);

	io::printfn("id = %s, log_file_path = %s", cx.id, cx.log_file_path);
}
