import std::io;

import context;
import skill;
import tool;
import util;
import cli;

fn void test_create_context() @test
{
	SkillHub skill_hub;
	skill_hub.init(tmem);
	defer skill_hub.free();

	ToolHub tool_hub;
	tool_hub.init(tmem, { "ReadFile", "Bash" });
	defer tool_hub.free();

	Flag flag;
	flag.init(tmem, { "mp" })!!;

	Path log_file = flag.config_dir.append(tmem, "log/test.log")!!;
	Context cx;
	cx.init(tmem, "test-session", &flag, &tool_hub, &skill_hub, log_file);

	// reset() adds system message
	cx.reset();

	Message message;
	cx.add_message(&message);
	assert(cx.messages.len() == 2);

	io::printfn("id = %s, log_file_path = %s", cx.session_id, cx.log_file);
}
