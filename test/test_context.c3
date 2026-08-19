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

// 卡 1 off-by-one 回归：discard_half_turn 必须保留本轮 user 消息
//（原 discard_messages_after 弹出 >= keep_before，把 user 也丢了；
// user_message 事件已写盘，内存删除会产生 resume 幽灵消息）。
fn void test_discard_half_turn_keeps_user() @test
{
	SkillHub skill_hub;
	skill_hub.init(tmem);
	defer skill_hub.free();

	ToolHub tool_hub;
	tool_hub.init(tmem, { "ReadFile", "Bash" });
	defer tool_hub.free();

	Flag flag;
	flag.init(tmem, { "mp" })!!;

	AppContext cx;
	cx.init(flag, tmem, "test-session", &tool_hub, &skill_hub, null, 0);
	cx.reset(); // system 消息（下标 0）

	// 模拟一轮未收尾 turn：user(1) → assistant(2, 带 tool_call) → tool(3)
	Message user;
	user.init(tmem, "user");
	user.content = "do the thing".copy(tmem);
	cx.add_message(&user);

	Message asst;
	asst.init(tmem, "assistant");
	ToolCall tc;
	tc.id = "call_1".copy(tmem);
	tc.index = 0;
	tc.name = "Bash".copy(tmem);
	tc.arguments = "{}".copy(tmem);
	asst.tool_calls.push(tc);
	cx.add_message(&asst);

	Message tool_msg;
	tool_msg.init(tmem, "tool");
	tool_msg.tool_call_id = "call_1".copy(tmem);
	tool_msg.content = "ok".copy(tmem);
	cx.add_message(&tool_msg);

	// Session 以 user 消息下标（1）为丢弃边界
	Session session;
	session.init(&cx);
	session.turn_start_idx = 1;

	session.discard_half_turn();

	assert(cx.messages.len() == 2, "user kept after discard");
	assert(cx.messages[1].role == "user", "last remaining message is user");
	assert(cx.messages[1].content == "do the thing", "user content intact");
}
