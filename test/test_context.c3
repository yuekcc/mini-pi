import std::io;

import message;
import skill;
import tool;
import util;
import cli;
import app;

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

	// logger 传 null：测试中不登记默认 logger（g_default 生命周期不跨测试）。
	AppContext cx;
	cx.init(flag, tmem, "test-session", &tool_hub, &skill_hub, null, 0);

	// reset() adds system message
	cx.reset();

	Message message;
	cx.add_message(&message);
	assert(cx.messages.len() == 2);
	assert(cx.messages[0].role == "system", "first message is system");

	io::printfn("id = %s, config_dir = %s", cx.session_id, cx.config_dir);
}
