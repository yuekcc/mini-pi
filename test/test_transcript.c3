import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;
import std::os::process;
import std::thread;

import cjson;
import message;
import transcript;
import util;
import util::cmd;

// ---------------------------------------------------------------------------
// transcript 单元测试：序列化、resume 重建（丢弃未收尾 turn / 保留完整会话）。
// 集成测试（需要先 c3c build 产出 build/mp.exe + python 可用）：
//   进程级跑一次 headless 会话，断言落盘 .jsonl 的内容结构与 resume roundtrip。
// ---------------------------------------------------------------------------

fn String tmp_cfg(String name)
{
	return string::tformat("testdata/tmp_%s_%s", name, util::timestamp_id(tmem));
}

// 构造一个最小 TranscriptWriter（单测只需要 config_dir/session_id/enabled）。
fn TranscriptWriter* make_writer(String cfg, String session_id)
{
	TranscriptWriter* w = alloc::new(tmem, TranscriptWriter);
	w.init(tmem, path::new(tmem, cfg)!!, session_id, true);
	return w;
}

fn String read_transcript(TranscriptWriter* w)
{
	Path file = w.file_path(tmem);
	return (String)file::load(tmem, file)!!;
}

fn String[] nonempty_lines(String content)
{
	List{String} result;
	result.init(tmem);
	foreach (line : content.split(tmem, "\n"))
	{
		if (line.trim().len > 0) result.push(line);
	}
	return result.to_array(tmem);
}

// ---------------------------------------------------------------------------
// 1. 序列化：7 类事件各自字段齐全、单行 JSON、可被 cjson 反解析
// ---------------------------------------------------------------------------

fn void test_transcript_serialization() @test
{
	String cfg = tmp_cfg("ser");
	String session_id = string::tformat("ses_test_ser_%s", util::timestamp_id(tmem));
	TranscriptWriter* w = make_writer(cfg, session_id);

	w.write_session_start("mock-model", "default", "/tmp/work", "SYSTEM PROMPT SNAPSHOT", { "ReadFile", "Bash" });
	w.write_user_message("turn_1", "hello", false);

	Message msg;
	message::message_init(&msg, tmem, "assistant");
	msg.content = "hi there";
	msg.reasoning_content = "think step";
	msg.tool_calls.push({ .id = "call_1", .index = 0, .name = "Bash", .arguments = "{\"command\":\"ls\"}" });
	w.write_assistant_message("turn_1", "req_1", &msg);

	w.write_tool_result(
		"turn_1", "req_1",
		"call_1", "Bash", "{\"command\":\"ls\"}",
		"$ ls\nfile.txt", "task_store/xxx_output.txt", 12, 0, true
	);

	transcript::Usage usage = { .prompt_tokens = 100, .completion_tokens = 20, .reasoning_tokens = 5 };
	w.write_api_usage("turn_1", "req_1", usage, 54084, "mock-model", "tool_calls");

	CJsonItem* detail = cjson::new_object(tmem);
	detail.set("message", "Request timed out.");
	detail.set("retry_attempt", 1);
	w.write_system_event("turn_1", "req_1", "api_error", "error", detail);

	w.write_session_end("turn_1", "exit", 1);

	String content = read_transcript(w);
	String[] lines = nonempty_lines(content);
	assert(lines.len == 7, "should write 7 event lines, got %d", lines.len);

	String session_seen = "";
	bool saw_session_start = false;
	bool saw_user = false;
	bool saw_assistant = false;
	bool saw_tool = false;
	bool saw_usage = false;
	bool saw_system = false;
	bool saw_end = false;

	foreach (raw : lines)
	{
		CJsonItem* event = cjson::parse(raw.zstr_copy(tmem));
		assert(event != null, "each line must be parseable JSON");
		defer event.free();

		String type = event.get_key_string("type", tmem) ?? "";
		assert((event.get_key_int("version") ?? 0) == 1, "version field is 1");
		String ts = event.get_key_string("timestamp", tmem) ?? "";
		assert(ts.len > 0, "timestamp present");
		String sid = event.get_key_string("session_id", tmem) ?? "";
		assert(sid == session_id, "session_id present and consistent");
		if (session_seen == "") session_seen = sid;

		switch (type)
		{
			case "session_start":
			{
				saw_session_start = true;
				assert(event.get_key("turn_id").is_null(), "session_start turn_id is null");
				assert(event.get_key("request_id").is_null(), "session_start request_id is null");
				assert((event.get_key_string("model", tmem) ?? "") == "mock-model", "model");
				assert((event.get_key_string("system_prompt", tmem) ?? "") == "SYSTEM PROMPT SNAPSHOT", "system_prompt snapshot");
				CJsonItem* assembly = event.get_key("assembly");
				assert(assembly != null, "assembly present");
				assert(assembly.get_key("tools").get_len() == 2, "assembly.tools length 2");
				assert(event.get_key("parent_session_id").is_null(), "parent_session_id null");
			}
			case "user_message":
			{
				saw_user = true;
				assert((event.get_key_string("turn_id", tmem) ?? "") == "turn_1", "user turn_id");
				assert(event.get_key("request_id").is_null(), "user request_id null");
				assert((event.get_key_string("content", tmem) ?? "") == "hello", "user content");
				assert((event.get_key_bool("is_command") ?? true) == false, "is_command false");
			}
			case "assistant_message":
			{
				saw_assistant = true;
				assert((event.get_key_string("request_id", tmem) ?? "") == "req_1", "assistant request_id");
				assert((event.get_key_string("content", tmem) ?? "") == "hi there", "assistant content");
				assert((event.get_key_string("reasoning_content", tmem) ?? "") == "think step", "reasoning_content");
				CJsonItem* calls = event.get_key("tool_calls");
				assert(calls != null && calls.get_len() == 1, "tool_calls length 1");
				assert((calls.get_at(0).get_key_string("name", tmem) ?? "") == "Bash", "tool_call name");
			}
			case "tool_result":
			{
				saw_tool = true;
				assert((event.get_key_string("request_id", tmem) ?? "") == "req_1", "tool request_id");
				assert((event.get_key_string("tool_call_id", tmem) ?? "") == "call_1", "tool_call_id");
				assert((event.get_key_string("output", tmem) ?? "") == "$ ls\nfile.txt", "tool output byte-exact");
				assert((event.get_key_string("output_file", tmem) ?? "") == "task_store/xxx_output.txt", "output_file");
				assert((event.get_key_int("duration_ms") ?? -1) == 12, "duration_ms");
				assert((event.get_key_int("exit_code") ?? -1) == 0, "exit_code");
			}
			case "api_usage":
			{
				saw_usage = true;
				CJsonItem* u = event.get_key("usage");
				assert(u != null, "usage object present");
				assert((u.get_key_int("prompt_tokens") ?? 0) == 100, "prompt_tokens");
				assert((u.get_key_int("completion_tokens") ?? 0) == 20, "completion_tokens");
				assert((u.get_key_int("reasoning_tokens") ?? 0) == 5, "reasoning_tokens");
				assert((event.get_key_int("latency_ms") ?? 0) == 54084, "latency_ms");
				assert((event.get_key_string("finish_reason", tmem) ?? "") == "tool_calls", "finish_reason");
			}
			case "system_event":
			{
				saw_system = true;
				assert((event.get_key_string("subtype", tmem) ?? "") == "api_error", "subtype");
				assert((event.get_key_string("level", tmem) ?? "") == "error", "level");
				CJsonItem* d = event.get_key("detail");
				assert(d != null, "detail present");
				assert((d.get_key_string("message", tmem) ?? "") == "Request timed out.", "detail message");
				assert((d.get_key_int("retry_attempt") ?? -1) == 1, "detail retry_attempt");
			}
			case "session_end":
			{
				saw_end = true;
				assert((event.get_key_string("reason", tmem) ?? "") == "exit", "session_end reason");
				assert((event.get_key_int("turns_total") ?? -1) == 1, "turns_total");
			}
			default: assert(false, "unexpected event type %s", type);
		}
	}

	assert(saw_session_start && saw_user && saw_assistant && saw_tool && saw_usage && saw_system && saw_end,
		"all 7 event types written");
}

// ---------------------------------------------------------------------------
// 2. resume 重建：丢弃最后一个未收尾 turn
// ---------------------------------------------------------------------------

fn void test_transcript_resume_drops_tail() @test
{
	String cfg = tmp_cfg("resume_tail");
	String session_id = string::tformat("ses_test_tail_%s", util::timestamp_id(tmem));
	TranscriptWriter* w = make_writer(cfg, session_id);

	// 构造：user → assistant(tool_calls) → tool_result → assistant(tool_calls)（被中断，未收尾）
	w.write_session_start("m", "default", "/tmp", "SYS", {});
	w.write_user_message("turn_a", "question", false);

	Message a1;
	message::message_init(&a1, tmem, "assistant");
	a1.tool_calls.push({ .id = "call_1", .index = 0, .name = "Bash", .arguments = "{\"command\":\"ls\"}" });
	w.write_assistant_message("turn_a", "req_a", &a1);
	w.write_tool_result("turn_a", "req_a", "call_1", "Bash", "{\"command\":\"ls\"}", "result content", "", 5, 0, true);

	Message a2;
	message::message_init(&a2, tmem, "assistant");
	a2.tool_calls.push({ .id = "call_2", .index = 0, .name = "Grep", .arguments = "{}" });
	w.write_assistant_message("turn_a", "req_b", &a2);

	List{Message} messages;
	messages.init(tmem);
	int turns = 0;
	bool ok = w.resume_into(&messages, &turns);
	assert(ok, "resume_into should succeed");

	// 整个未收尾 turn（user + assistant + tool_result + 尾巴 assistant）都被丢弃，只留 system
	assert(messages.len() == 1, "interrupted turn fully dropped, only system remains, got %d", messages.len());
	assert(messages[0].role == "system" && messages[0].content == "SYS", "system snapshot kept");

	// resume 标记（tail_dropped=true）已写入
	String content = read_transcript(w);
	bool found_resume = false;
	foreach (raw : nonempty_lines(content))
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "system_event"
			&& (e.get_key_string("subtype", tmem) ?? "") == "resume")
		{
			CJsonItem* d = e.get_key("detail");
			found_resume = d != null && (d.get_key_bool("tail_dropped") ?? false) == true;
			assert((d.get_key_int("turns_rebuilt") ?? 0) == 1, "turns_rebuilt should be 1");
		}
	}
	assert(found_resume, "resume system_event with tail_dropped=true should be written");
}

// ---------------------------------------------------------------------------
// 3. resume 重建：完整会话原样保留（含 session_end）
// ---------------------------------------------------------------------------

fn void test_transcript_resume_keeps_complete() @test
{
	String cfg = tmp_cfg("resume_keep");
	String session_id = string::tformat("ses_test_keep_%s", util::timestamp_id(tmem));
	TranscriptWriter* w = make_writer(cfg, session_id);

	w.write_session_start("m", "default", "/tmp", "SYS", {});
	w.write_user_message("turn_a", "question", false);

	Message a1;
	message::message_init(&a1, tmem, "assistant");
	a1.content = "final answer";
	w.write_assistant_message("turn_a", "req_a", &a1);
	w.write_session_end("turn_a", "exit", 1);

	List{Message} messages;
	messages.init(tmem);
	int turns = 0;
	bool ok = w.resume_into(&messages, &turns);
	assert(ok, "resume_into should succeed");
	assert(messages.len() == 3, "complete session kept: system+user+assistant = 3, got %d", messages.len());
	assert(messages[1].role == "user" && messages[1].content == "question", "user kept");
	assert(messages[2].role == "assistant" && messages[2].content == "final answer", "assistant final reply kept");
	assert(messages[2].tool_calls.len() == 0, "no tool calls");

	String content = read_transcript(w);
	bool tail_dropped_false = false;
	foreach (raw : nonempty_lines(content))
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "system_event"
			&& (e.get_key_string("subtype", tmem) ?? "") == "resume")
		{
			CJsonItem* d = e.get_key("detail");
			tail_dropped_false = d != null && (d.get_key_bool("tail_dropped") ?? true) == false;
		}
	}
	assert(tail_dropped_false, "resume event should mark tail_dropped=false");
}

// ---------------------------------------------------------------------------
// 集成测试辅助：mock OpenAI server
// ---------------------------------------------------------------------------

fn bool start_mock_server(Process* out, int port, String ready_file)
{
	if ((path::exists(path::new(tmem, ready_file)!!)))
	{
		(void)path::delete(path::new(tmem, ready_file))!!;
	}

	String[] cmd = {
		"python",
		"testdata/mock_openai_server.py",
		string::format(tmem, "%d", port),
		ready_file,
		"testdata/mock_requests.log",
	};

	Process? maybe = process::spawn(cmd, NO_WINDOW | INHERIT_ENV);
	if (catch maybe)
	{
		io::printfn("SKIP: cannot start python mock server (is python on PATH?)");
		return false;
	}
	*out = maybe;
	for (int i = 0; i < 100; i++)
	{
		if ((path::exists(path::new(tmem, ready_file)!!))) return true;
		thread::sleep_ms(50);
	}
	(void)maybe.terminate()!!;
	io::printfn("SKIP: mock server not ready in time");
	return false;
}

fn void run_mp_headless(String cfg, String base_url, String task, String resume)
{
	List{String} cmd;
	cmd.init(tmem);
	cmd.push("build/mp.exe");
	cmd.push("--headless");
	cmd.push("--config");
	cmd.push(cfg);
	cmd.push("--base-url");
	cmd.push(base_url);
	if (resume != "")
	{
		cmd.push("--resume");
		cmd.push(resume);
	}
	cmd.push("-t");
	cmd.push(task);
	String[] final_cmd = cmd.to_array(tmem);

	CommandResult r = cmd::execute(tmem, final_cmd)!!;
	io::printfn("mp headless exit code: %d", r.code);
	assert(r.code == 0, "mp should exit 0");
}

fn Path transcript_file_of(String cfg)
{
	Path tdir = path::new(tmem, cfg).append(tmem, "transcripts")!!;
	PathList entries = path::ls(tmem, tdir, false, false, "*.jsonl", false, false, (Path)"")!!;
	assert(entries.len() == 1, "exactly one transcript file expected, got %d", entries.len());
	return entries[0];
}

// ---------------------------------------------------------------------------
// 4. 集成：进程级结构正确性
// ---------------------------------------------------------------------------

fn void test_transcript_integration_structure() @test
{
	if (!path::exists(path::new(tmem, "build/mp.exe")!!))
	{
		io::printfn("SKIP: build/mp.exe not found, run 'c3c build' first");
		return;
	}

	Process server;
	String cfg = tmp_cfg("it");
	String ready = string::tformat("testdata/tmp_ready_%s.txt", util::timestamp_id(tmem));
	if (!start_mock_server(&server, 5877, ready)) return;

	run_mp_headless(cfg, "http://127.0.0.1:5877", "hello transcript", "");

	String content = (String)file::load(tmem, transcript_file_of(cfg))!!;
	String[] lines = nonempty_lines(content);
	assert(lines.len >= 5, "expected >= 5 events, got %d", lines.len);

	// 首行 session_start、末行 session_end
	CJsonItem* first = cjson::parse(lines[0].zstr_copy(tmem));
	defer first.free();
	assert((first.get_key_string("type", tmem) ?? "") == "session_start", "first event is session_start");
	String session_id = first.get_key_string("session_id", tmem) ?? "";
	assert(session_id.len > 0, "session_id present");

	CJsonItem* last = cjson::parse(lines[lines.len - 1].zstr_copy(tmem));
	defer last.free();
	assert((last.get_key_string("type", tmem) ?? "") == "session_end", "last event is session_end");
	assert((last.get_key_string("reason", tmem) ?? "") == "exit", "session_end reason exit");

	// 逐事件断言公共字段 + 关键内容
	bool saw_user = false;
	bool saw_assistant = false;
	bool saw_usage = false;
	foreach (raw : lines)
	{
		CJsonItem* event = cjson::parse(raw.zstr_copy(tmem));
		defer event.free();
		assert((event.get_key_int("version") ?? 0) == 1, "version 1");
		assert((event.get_key_string("session_id", tmem) ?? "") == session_id, "session_id consistent");
		assert((event.get_key_string("timestamp", tmem) ?? "").len > 0, "timestamp present");

		String type = event.get_key_string("type", tmem) ?? "";
		if (type == "user_message")
		{
			saw_user = true;
			assert((event.get_key_string("content", tmem) ?? "") == "hello transcript", "task content");
			assert((event.get_key_bool("is_command") ?? true) == false, "not a command");
		}
		else if (type == "assistant_message")
		{
			saw_assistant = true;
			// mock 回显消息数：首个请求只有 system + user = 2 条
			assert((event.get_key_string("content", tmem) ?? "").contains("received 2 messages"),
				"mock echo of message count");
		}
		else if (type == "api_usage")
		{
			saw_usage = true;
			CJsonItem* u = event.get_key("usage");
			assert(u != null, "usage present");
			assert((u.get_key_int("prompt_tokens") ?? 0) > 0, "prompt_tokens non-zero");
			assert((u.get_key_int("completion_tokens") ?? 0) > 0, "completion_tokens non-zero");
			assert((u.get_key_int("reasoning_tokens") ?? 0) > 0, "reasoning_tokens non-zero");
			assert((event.get_key_int("latency_ms") ?? -1) >= 0, "latency_ms present");
			assert((event.get_key_string("finish_reason", tmem) ?? "") == "stop", "finish_reason stop");
		}
	}
	assert(saw_user && saw_assistant && saw_usage, "user/assistant/api_usage events present");

	(void)server.terminate()!!;
}

// ---------------------------------------------------------------------------
// 6. 集成：golden transcript diff —— 归一化事件流与 v1 基线夹具逐字节一致
//    （arch-next-spec 测试决策 1：NFR-3 确定性回归护栏）。
// ---------------------------------------------------------------------------

fn void test_transcript_golden_diff() @test
{
	if (!path::exists(path::new(tmem, "build/mp.exe")!!))
	{
		io::printfn("SKIP: build/mp.exe not found, run 'c3c build' first");
		return;
	}

	String cfg = tmp_cfg("golden");
	String ready = string::tformat("testdata/tmp_ready_%s.txt", util::timestamp_id(tmem));
	String[] cmd = {
		"python",
		"testdata/golden_check.py",
		"check",
		cfg,
		"5907",
		ready,
	};
	CommandResult r = cmd::execute(tmem, cmd)!!;
	io::printfn("[golden] %s", r.output.trim());
	assert(r.code == 0, "golden transcript diff should pass, output: %s", r.output);
}

// ---------------------------------------------------------------------------
// 5. 集成：resume roundtrip —— 会话 B 的模型所见与 A 末尾逐字节一致
// ---------------------------------------------------------------------------

fn void test_transcript_integration_resume_roundtrip() @test
{
	if (!path::exists(path::new(tmem, "build/mp.exe")!!))
	{
		io::printfn("SKIP: build/mp.exe not found, run 'c3c build' first");
		return;
	}

	Process server;
	String cfg = tmp_cfg("rt");
	String ready = string::tformat("testdata/tmp_ready_%s.txt", util::timestamp_id(tmem));
	if (!start_mock_server(&server, 5878, ready)) return;

	// 会话 A
	run_mp_headless(cfg, "http://127.0.0.1:5878", "hello transcript", "");
	Path tfile = transcript_file_of(cfg);
	String content_a = (String)file::load(tmem, tfile)!!;

	// A 的 session_id 与最后一个 user_message turn_id
	String session_a = tfile.basename().replace(tmem, ".jsonl", "");
	String last_turn_a = "";
	foreach (raw : nonempty_lines(content_a))
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "user_message")
		{
			last_turn_a = e.get_key_string("turn_id", tmem) ?? "";
		}
	}
	assert(last_turn_a.len > 0, "session A has a user turn");

	// 跨秒续号（turn_id 精度为秒）
	thread::sleep_ms(1200);

	// 会话 B：--resume A 续跑
	run_mp_headless(cfg, "http://127.0.0.1:5878", "continue", session_a);

	String content_b = (String)file::load(tmem, tfile)!!;
	String[] lines = nonempty_lines(content_b);

	// 同一 transcript 文件继续追加：session_start 只出现一次
	int session_start_count = 0;
	foreach (raw : lines)
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "session_start") session_start_count++;
	}
	assert(session_start_count == 1, "resume appends to the same transcript file");

	// B 的 turn_id 从 A 之后续号
	String turn_b = "";
	foreach (raw : lines)
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "user_message"
			&& (e.get_key_string("content", tmem) ?? "") == "continue")
		{
			turn_b = e.get_key_string("turn_id", tmem) ?? "";
		}
	}
	assert(turn_b.len > 0, "session B has a 'continue' turn");
	assert(turn_b.compare_to(last_turn_a) > 0, "session B turn_id continues after session A");

	// B 的 assistant 回复回显 "received 4 messages"：
	// 重建的历史（system+user+assistant）加上新 user 消息 = 4 条 → 模型所见与 A 末尾一致
	bool echo_ok = false;
	foreach (raw : lines)
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "assistant_message"
			&& (e.get_key_string("content", tmem) ?? "").contains("received 4 messages"))
		{
			echo_ok = true;
		}
	}
	assert(echo_ok, "rebuilt history visible to model (4 messages)");

	// resume 标记存在
	bool found_resume = false;
	foreach (raw : lines)
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		if ((e.get_key_string("type", tmem) ?? "") == "system_event"
			&& (e.get_key_string("subtype", tmem) ?? "") == "resume")
		{
			found_resume = true;
		}
	}
	assert(found_resume, "resume system_event written");

	// 末行 session_end
	CJsonItem* last = cjson::parse(lines[lines.len - 1].zstr_copy(tmem));
	defer last.free();
	assert((last.get_key_string("type", tmem) ?? "") == "session_end", "session B ends with session_end");
	assert((last.get_key_string("reason", tmem) ?? "") == "exit", "session B exit reason");

	(void)server.terminate()!!;
}
