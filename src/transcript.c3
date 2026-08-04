module transcript;

// 会话 transcript：每事件一行 JSONL，追加写盘，支撑 resume session 与审计。
// 设计见 docs/transcript.md（v1，schema version = 1）。
//
// 约定：
// - 事件「发生即追加」落盘，不缓冲、不批量；打开-写入-flush-关闭，崩溃安全。
// - 全部写入静默失败：transcript 只是记录层，任何 IO 错误不影响主流程。
// - --no-transcript 时所有 write_* 为 no-op。
// - JSON 由 cjson 构建，单行序列化（换行符会被 cJSON 转义，天然 JSONL 安全）。

import std::io;
import std::io::file;
import std::io::path;
import std::time::datetime;
import std::os::env;

import cjson;
import global;
import context;
import tool;

// ---- schema 常量 ------------------------------------------------------------

const int VERSION = 1;

const String TYPE_SESSION_START = "session_start";
const String TYPE_USER_MESSAGE = "user_message";
const String TYPE_ASSISTANT_MESSAGE = "assistant_message";
const String TYPE_TOOL_RESULT = "tool_result";
const String TYPE_API_USAGE = "api_usage";
const String TYPE_SYSTEM_EVENT = "system_event";
const String TYPE_SESSION_END = "session_end";

const String SUBTYPE_API_ERROR = "api_error";
const String SUBTYPE_LOCAL_COMMAND = "local_command";
const String SUBTYPE_RESUME = "resume";
const String SUBTYPE_COMPACT_BOUNDARY = "compact_boundary"; // 预留占位，v1 不实现

const String ENV_PARENT_SESSION = "MP_PARENT_SESSION";

// ---- 公共类型 ---------------------------------------------------------------

struct Usage
{
	long prompt_tokens;
	long completion_tokens;
	long reasoning_tokens;
}

struct ParentSession
{
	String session_id;
	String request_id;
}

// ---- 开关与路径 -------------------------------------------------------------

fn bool enabled()
{
	return global::transcript_enabled();
}

// 事件文件路径：<config_dir>/transcripts/<session_id>.jsonl
fn Path file_path(Allocator allocator, String session_id)
{
	Path config_dir = global::config_dir();
	if (config_dir.len == 0) return (Path)"";
	Path dir = config_dir.append(allocator, "transcripts")!!;
	return dir.append(allocator, string::tformat("%s.jsonl", session_id))!!;
}

fn bool ensure_transcript_dir(Path file)
{
	if (try parent = file.parent())
	{
		if (!path::exists(parent))
		{
			if (catch path::mkdir(parent, true)) return false;
		}
	}
	return true;
}

// ISO 8601 本地时间戳。注意：DateTime.format(tmem) 返回 str_view（无 NUL 结尾），
// cjson 按 C 字符串读取会越界，必须经 string::format 转为 NUL 结尾再使用。
fn String iso_timestamp(Allocator allocator)
{
	String raw = datetime::now().to_local().format(tmem, DateTimeFormat.RFC3339Z);
	return string::format(allocator, "%s", raw);
}

// 从环境变量 MP_PARENT_SESSION（格式 父session_id:父request_id）读取父会话信息。
fn ParentSession read_parent_session(Allocator allocator)
{
	ParentSession result;
	String? raw = env::tget_var(ENV_PARENT_SESSION);
	if (try raw && raw.len > 0)
	{
		sz colon = 0;
		for (sz i = 0; i < raw.len; i++)
		{
			if (raw[i] == ':')
			{
				colon = i;
				break;
			}
		}
		if (colon > 0)
		{
			result.session_id = raw[:colon].copy(allocator);
			result.request_id = raw[colon + 1:raw.len].copy(allocator);
		}
	}
	return result;
}

// 当前启用的工具名列表（session_start.assembly.tools 快照用）。
fn String[] tool_names(Allocator allocator, ToolHub* hub)
{
	String[] names = alloc::alloc_array(allocator, String, hub.tools.len);
	sz i = 0;
	foreach (tool : hub.tools)
	{
		names[i] = tool.name();
		i++;
	}
	return names;
}

// ---- 底层写入 ---------------------------------------------------------------

fn CJsonItem* new_event(String type, String session_id, String turn_id, String request_id)
{
	CJsonItem* event = cjson::new_object(tmem);
	event.set("version", VERSION);
	event.set("type", type);
	event.set("session_id", session_id);
	event.set("timestamp", iso_timestamp(tmem));
	if (turn_id.len == 0)
	{
		event.set_item("turn_id", cjson::new_null(tmem));
	}
	else
	{
		event.set("turn_id", turn_id);
	}
	if (request_id.len == 0)
	{
		event.set_item("request_id", cjson::new_null(tmem));
	}
	else
	{
		event.set("request_id", request_id);
	}
	return event;
}

// 序列化 event 为单行 JSON 并追加写盘。event 的所有权移交本函数，写完后释放。
fn void append_event(String session_id, CJsonItem* event)
{
	if (!enabled())
	{
		event.free();
		return;
	}

	Path file = file_path(tmem, session_id);
	if (file == "") return;
	if (!ensure_transcript_dir(file)) return;

	String json = string::format(tmem, "%s", event);
	event.free();

	if (try File f = file::open_path(file, "a"))
	{
		(void)io::fprintf(&f, "%s\n", json);
		(void)f.flush();
		(void)f.close();
	}
}

// ---- 事件写入入口 -----------------------------------------------------------

fn void write_session_start(
	Allocator allocator,
	String session_id,
	String model,
	String agent,
	String cwd,
	String system_prompt,
	String[] tools
)
{
	ParentSession parent = read_parent_session(tmem);

	CJsonItem* event = new_event(TYPE_SESSION_START, session_id, "", "");
	event.set("model", model);
	event.set("agent", agent);
	event.set("cwd", cwd);
	event.set("system_prompt", system_prompt);

	CJsonItem* assembly = cjson::new_object(tmem);
	String date_raw = datetime::now().to_local().format(tmem, DateTimeFormat.DATEONLY);
	assembly.set("date", string::format(tmem, "%s", date_raw));
	String os_uname = "Linux + Bash";
	$if env::WIN32:
		os_uname = "Windows 11 + Bash (bundled in Git for windows)";
	$endif
	assembly.set("os", os_uname);
	CJsonItem* tools_arr = cjson::new_array(tmem);
	foreach (t : tools) tools_arr.push_back(t);
	assembly.set_item("tools", tools_arr);
	event.set_item("assembly", assembly);

	if (parent.session_id.len == 0)
	{
		event.set_item("parent_session_id", cjson::new_null(tmem));
	}
	else
	{
		event.set("parent_session_id", parent.session_id);
	}
	if (parent.request_id.len == 0)
	{
		event.set_item("parent_request_id", cjson::new_null(tmem));
	}
	else
	{
		event.set("parent_request_id", parent.request_id);
	}

	append_event(session_id, event);
}

fn void write_user_message(Allocator allocator, String session_id, String turn_id, String content, bool is_command)
{
	CJsonItem* event = new_event(TYPE_USER_MESSAGE, session_id, turn_id, "");
	event.set("content", content);
	event.set("is_command", is_command);
	append_event(session_id, event);
}

fn void write_assistant_message(Allocator allocator, String session_id, String turn_id, String request_id, Message* msg)
{
	CJsonItem* event = new_event(TYPE_ASSISTANT_MESSAGE, session_id, turn_id, request_id);
	event.set("content", msg.content);
	if (msg.reasoning_content.len > 0) event.set("reasoning_content", msg.reasoning_content);
	if (msg.tool_calls.len() > 0)
	{
		CJsonItem* calls = cjson::new_array(tmem);
		foreach (&tc : msg.tool_calls)
		{
			CJsonItem* c = cjson::new_object(tmem);
			c.set("id", tc.id);
			c.set("name", tc.name);
			c.set("arguments", tc.arguments);
			calls.push_back(c);
		}
		event.set_item("tool_calls", calls);
	}
	append_event(session_id, event);
}

fn void write_tool_result(
	Allocator allocator,
	String session_id,
	String turn_id,
	String request_id,
	String tool_call_id,
	String name,
	String arguments,
	String output,
	String output_file,
	long duration_ms,
	int exit_code,
	bool has_exit_code
)
{
	CJsonItem* event = new_event(TYPE_TOOL_RESULT, session_id, turn_id, request_id);
	event.set("tool_call_id", tool_call_id);
	event.set("name", name);
	event.set("arguments", arguments);
	event.set("output", output);
	if (output_file.len > 0) event.set("output_file", output_file);
	event.set("duration_ms", duration_ms);
	if (has_exit_code) event.set("exit_code", exit_code);
	append_event(session_id, event);
}

fn void write_api_usage(
	Allocator allocator,
	String session_id,
	String turn_id,
	String request_id,
	Usage usage,
	long latency_ms,
	String model,
	String finish_reason
)
{
	CJsonItem* event = new_event(TYPE_API_USAGE, session_id, turn_id, request_id);
	CJsonItem* usage_item = cjson::new_object(tmem);
	usage_item.set("prompt_tokens", usage.prompt_tokens);
	usage_item.set("completion_tokens", usage.completion_tokens);
	usage_item.set("reasoning_tokens", usage.reasoning_tokens);
	event.set_item("usage", usage_item);
	event.set("latency_ms", latency_ms);
	event.set("model", model);
	if (finish_reason.len > 0) event.set("finish_reason", finish_reason);
	append_event(session_id, event);
}

// detail 的所有权移交本函数（并入事件树，随 event 释放）。
fn void write_system_event(
	Allocator allocator,
	String session_id,
	String turn_id,
	String request_id,
	String subtype,
	String level,
	CJsonItem* detail
)
{
	CJsonItem* event = new_event(TYPE_SYSTEM_EVENT, session_id, turn_id, request_id);
	event.set("subtype", subtype);
	event.set("level", level);
	if (detail) event.set_item("detail", detail);
	append_event(session_id, event);
}

fn void write_session_end(Allocator allocator, String session_id, String turn_id, String reason, int turns_total)
{
	CJsonItem* event = new_event(TYPE_SESSION_END, session_id, turn_id, "");
	event.set("reason", reason);
	event.set("turns_total", turns_total);
	append_event(session_id, event);
}

// ---- resume 重建 ------------------------------------------------------------

// 从 <config_dir>/transcripts/<session_id>.jsonl 重建消息序列到 ctx.messages：
// - session_start.system_prompt 快照 → messages[0]（不重新装配，A 方案保真第一）。
// - user_message → role=user（is_command=true 跳过）；assistant_message → role=assistant
//   （content + reasoning_content + tool_calls）；tool_result → role=tool（output 逐字节重建）。
// - 遇到 session_end 停止；丢弃最后一个未收尾 turn。
// - 重建成功后写入一条 system_event(resume) 标记。
// 返回是否成功（文件缺失/无 system_prompt 视为失败）。
fn bool resume_into(Allocator allocator, Context* ctx)
{
	Path file = file_path(allocator, ctx.session_id);
	if (file == "") return false;
	if (!path::exists(file)) return false;

	char[]? loaded = file::load(allocator, file);
	if (catch ex = loaded) return false;
	String file_content = (String)loaded;

	String[] lines = file_content.split(allocator, "\n");
	ctx.messages.clear();

	bool system_seen = false;
	sz last_user_idx = 0;
	int turns_rebuilt = 0;
	String first_turn = "";
	String last_turn = "";

	foreach (raw : lines)
	{
		String line = raw.trim();
		if (line.len == 0) continue;

		CJsonItem* event = cjson::parse(line.zstr_copy(tmem));
		if (!event) continue;

		String type = event.get_key_string("type", tmem) ?? "";
		if (type == TYPE_SESSION_START)
		{
			String sp = event.get_key_string("system_prompt", tmem) ?? "";
			if (!system_seen && sp.len > 0)
			{
				Message sys;
				context::message_init(&sys, allocator, "system");
				sys.content = sp.copy(allocator);
				ctx.add_message(&sys);
				system_seen = true;
			}
		}
		else if (type == TYPE_USER_MESSAGE)
		{
			bool is_cmd = event.get_key_bool("is_command") ?? false;
			if (!is_cmd)
			{
				String content_val = event.get_key_string("content", tmem) ?? "";
				Message user;
				context::message_init(&user, allocator, "user");
				user.content = content_val.copy(allocator);
				ctx.add_message(&user);
				last_user_idx = ctx.messages.len() - 1;
				turns_rebuilt++;
				String turn_id = event.get_key_string("turn_id", tmem) ?? "";
				if (first_turn.len == 0) first_turn = turn_id.copy(allocator);
				last_turn = turn_id.copy(allocator);
			}
		}
		else if (type == TYPE_ASSISTANT_MESSAGE)
		{
			Message asst;
			context::message_init(&asst, allocator, "assistant");
			asst.content = (event.get_key_string("content", tmem) ?? "").copy(allocator);
			asst.reasoning_content = (event.get_key_string("reasoning_content", tmem) ?? "").copy(allocator);
			if (CJsonItem* calls = event.get_key("tool_calls"))
			{
				usz n = calls.get_len();
				for (usz i = 0; i < n; i++)
				{
					CJsonItem* c = calls.get_at((sz)i);
					if (!c) continue;
					ToolCall tc;
					tc.id = (c.get_key_string("id", tmem) ?? "").copy(allocator);
					tc.index = i;
					tc.name = (c.get_key_string("name", tmem) ?? "").copy(allocator);
					tc.arguments = (c.get_key_string("arguments", tmem) ?? "").copy(allocator);
					asst.tool_calls.push(tc);
				}
			}
			ctx.add_message(&asst);
		}
		else if (type == TYPE_TOOL_RESULT)
		{
			Message tool_msg;
			context::message_init(&tool_msg, allocator, "tool");
			tool_msg.tool_call_id = (event.get_key_string("tool_call_id", tmem) ?? "").copy(allocator);
			tool_msg.content = (event.get_key_string("output", tmem) ?? "").copy(allocator);
			ctx.add_message(&tool_msg);
		}
		else if (type == TYPE_SESSION_END)
		{
			event.free();
			break;
		}
		event.free();
	}

	if (!system_seen) return false;

	// 丢弃最后一个未收尾 turn：最后一条不是「无 tool_calls 的 assistant 终答」即视为未收尾，
	// 连同其 user 消息一起丢弃，保证恢复后的会话从完整边界继续。
	bool tail_dropped = false;
	if (last_user_idx > 0)
	{
		Message* last = ctx.messages.get_ref(ctx.messages.len() - 1);
		bool unfinished = last.role != "assistant" || last.tool_calls.len() > 0;
		if (unfinished)
		{
			while (ctx.messages.len() > last_user_idx)
			{
				(void)ctx.messages.pop();
			}
			tail_dropped = true;
		}
	}

	// 记录 resume 标记（来源 session、重建的 turn 范围与是否丢弃未收尾尾巴）
	CJsonItem* detail = cjson::new_object(tmem);
	detail.set("source_session", ctx.session_id);
	detail.set("turns_rebuilt", turns_rebuilt);
	if (first_turn.len > 0) detail.set("first_turn_id", first_turn);
	if (last_turn.len > 0) detail.set("last_turn_id", last_turn);
	detail.set("tail_dropped", tail_dropped);
	write_system_event(allocator, ctx.session_id, "", "", SUBTYPE_RESUME, "info", detail);

	// 续跑的 session_end.turns_total 应包含重建的轮次
	ctx.turns_total = turns_rebuilt;

	return true;
}
