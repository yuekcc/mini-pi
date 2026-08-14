import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;
import std::os::process;
import std::thread;

import cjson;
import util;
import util::cmd;

// ---------------------------------------------------------------------------
// 中断缝测试（arch-next-spec 测试矩阵：L1/L2 中断的进程级测试）。
//
// headless Ctrl+C 优雅停机（FR-8）：
//   慢速 mock server + send_ctrl_c.py 注入 CTRL_BREAK_EVENT（Windows 下可按进程组
//   定向投递；mp 的 handler 与 CTRL_C 一视同仁）→ 断言：
//     - 退出码非零；
//     - transcript 含 system_event(request_cancelled)（detail 含 request_id/latency）；
//     - 末事件 session_end(reason=interrupted)。
// 注入失败环境（非 Windows / 无控制台）打印 SKIP 跳过。
// ---------------------------------------------------------------------------

fn String tmp_cfg(String name)
{
	return string::tformat("testdata/tmp_%s_%s", name, util::timestamp_id(tmem));
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

fn void test_headless_interrupt() @test
{
	if (!path::exists(path::new(tmem, "build/mp.exe")!!))
	{
		io::printfn("SKIP: build/mp.exe not found, run 'c3c build' first");
		return;
	}

	Process server;
	String cfg = tmp_cfg("intr");
	String ready = string::tformat("testdata/tmp_ready_%s.txt", util::timestamp_id(tmem));
	String[] server_cmd = {
		"python",
		"testdata/mock_openai_server.py",
		"5895",
		ready,
		"testdata/mock_requests.log",
		"10000", // 慢响应 10s：给 Ctrl+C 注入留窗口
	};
	Process? maybe = process::spawn(server_cmd, NO_WINDOW | INHERIT_ENV);
	if (catch maybe)
	{
		io::printfn("SKIP: cannot start python mock server");
		return;
	}
	server = maybe;
	bool ready_ok = false;
	for (int i = 0; i < 100; i++)
	{
		if (path::exists(path::new(tmem, ready)!!))
		{
			ready_ok = true;
			break;
		}
		thread::sleep_ms(50);
	}
	if (!ready_ok)
	{
		(void)server.terminate()!!;
		io::printfn("SKIP: mock server not ready in time");
		return;
	}

	// 注入 Ctrl+C（CTRL_BREAK_EVENT，1.5s 后）
	String[] inject_cmd = {
		"python",
		"testdata/send_ctrl_c.py",
		"1500",
		string::tformat(
			"build/mp.exe --headless --config %s --base-url http://127.0.0.1:5895 -t hello-interrupt",
			cfg
		),
	};
	CommandResult r = cmd::execute(tmem, inject_cmd)!!;
	io::printfn("[interrupt] inject helper exit: %d, output: %s", r.code, r.output);
	if (r.output.contains("INJECT_SKIP"))
	{
		(void)server.terminate()!!;
		io::printfn("SKIP: signal injection unavailable on this platform/console");
		return;
	}
	// 断言子进程退出码非零（优雅停机）
	assert(r.output.contains("exit_code=1"), "interrupted headless run should exit 1, got output '%s'", r.output);

	// 断言 transcript：request_cancelled + session_end(interrupted)
	Path tdir = path::new(tmem, cfg).append(tmem, "transcripts")!!;
	PathList entries = path::ls(tmem, tdir, false, false, "*.jsonl", false, false, (Path)"")!!;
	assert(entries.len() == 1, "exactly one transcript file expected, got %d", entries.len());
	String content = (String)file::load(tmem, entries[0])!!;
	String[] lines = nonempty_lines(content);

	bool saw_cancelled = false;
	bool saw_interrupted_end = false;
	String last_type = "";
	foreach (raw : lines)
	{
		CJsonItem* e = cjson::parse(raw.zstr_copy(tmem));
		defer e.free();
		String type = e.get_key_string("type", tmem) ?? "";
		last_type = type;
		if (type == "system_event" && (e.get_key_string("subtype", tmem) ?? "") == "request_cancelled")
		{
			saw_cancelled = true;
			CJsonItem* d = e.get_key("detail");
			assert(d != null, "request_cancelled detail present");
			assert((d.get_key_string("request_id", tmem) ?? "").len > 0, "request_id in detail");
			assert((d.get_key_int("latency_ms") ?? -1) >= 0, "latency_ms in detail");
		}
		else if (type == "session_end" && (e.get_key_string("reason", tmem) ?? "") == "interrupted")
		{
			saw_interrupted_end = true;
		}
	}
	assert(saw_cancelled, "system_event(request_cancelled) written");
	assert(saw_interrupted_end, "session_end(reason=interrupted) written");
	assert(last_type == "session_end", "last event is session_end, got %s", last_type);

	(void)server.terminate()!!;
}
