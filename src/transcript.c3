module transcript;

// 会话 transcript：每事件一行 JSONL，追加写盘，支撑 resume session 与审计。
// 设计见 docs/transcript.md（schema version = 1，v2 保持兼容）。
//
// v2 对象化（arch-next-spec 决策 4）：TranscriptWriter 持有 allocator / config_dir /
// session_id / enabled，方法签名不再散传 session_id；全部事件写入只在 Agent 线程
// 发生（写点线程唯一、无需锁）。--no-transcript 时内部全 no-op。
//
// 约定：
// - 事件「发生即追加」落盘，不缓冲、不批量；打开-写入-flush-关闭，崩溃安全。
// - 全部写入静默失败：transcript 只是记录层，任何 IO 错误不影响主流程。
// - JSON 由 cjson 构建，单行序列化（换行符会被 cJSON 转义，天然 JSONL 安全）。

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;
import std::time::datetime;
import std::os::env;

import cjson;
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
const String SUBTYPE_REQUEST_CANCELLED = "request_cancelled"; // v2 新增（additive）
const String SUBTYPE_TOOL_CANCELLED = "tool_cancelled";       // v2 新增（additive）
const String SUBTYPE_TOKEN_WARNING = "token_warning";         // v2 新增（additive）

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

// ---- TranscriptWriter（对象化）-----------------------------------------------

struct TranscriptWriter
{
	Allocator allocator;
	Path config_dir;
	String session_id; // /clear 时经 set_session_id 更换
	bool enabled;      // --no-transcript 时为 false，全部写入 no-op
}

fn TranscriptWriter* TranscriptWriter.init(
	&self,
	Allocator allocator,
	Path config_dir,
	String session_id,
	bool enabled
)
{
	self.allocator = allocator;
	self.config_dir = config_dir.copy(allocator);
	self.session_id = session_id.copy(allocator);
	self.enabled = enabled;
	return self;
}

// /clear 开启新会话时更换 session_id（同一 writer 对象，后续事件写入新文件）。
fn void TranscriptWriter.set_session_id(&self, String session_id)
{
	self.session_id.free(self.allocator);
	self.session_id = session_id.copy(self.allocator);
}

// 事件文件路径：<config_dir>/transcripts/<session_id>.jsonl
fn Path TranscriptWriter.file_path(&self, Allocator allocator)
{
	if (self.config_dir.len == 0) return (Path)"";
	Path dir = self.config_dir.append(allocator, "transcripts")!!;
	return dir.append(allocator, string::tformat("%s.jsonl", self.session_id))!!;
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
fn void TranscriptWriter.append_event(&self, CJsonItem* event)
{
	if (!self.enabled)
	{
		event.free();
		return;
	}

	Path file = self.file_path(tmem);
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

fn void TranscriptWriter.write_session_start(
	&self,
	String model,
	String agent,
	String cwd,
	String system_prompt,
	String[] tools
)
{
	ParentSession parent = read_parent_session(tmem);

	CJsonItem* event = new_event(TYPE_SESSION_START, self.session_id, "", "");
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

	self.append_event(event);
}

fn void TranscriptWriter.write_user_message(&self, String turn_id, String content, bool is_command)
{
	CJsonItem* event = new_event(TYPE_USER_MESSAGE, self.session_id, turn_id, "");
	event.set("content", content);
	event.set("is_command", is_command);
	self.append_event(event);
}

fn void TranscriptWriter.write_assistant_message(&self, String turn_id, String request_id, Message* msg)
{
	CJsonItem* event = new_event(TYPE_ASSISTANT_MESSAGE, self.session_id, turn_id, request_id);
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
	self.append_event(event);
}

fn void TranscriptWriter.write_tool_result(
	&self,
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
	CJsonItem* event = new_event(TYPE_TOOL_RESULT, self.session_id, turn_id, request_id);
	event.set("tool_call_id", tool_call_id);
	event.set("name", name);
	event.set("arguments", arguments);
	event.set("output", output);
	if (output_file.len > 0) event.set("output_file", output_file);
	event.set("duration_ms", duration_ms);
	if (has_exit_code) event.set("exit_code", exit_code);
	self.append_event(event);
}

fn void TranscriptWriter.write_api_usage(
	&self,
	String turn_id,
	String request_id,
	Usage usage,
	long latency_ms,
	String model,
	String finish_reason
)
{
	CJsonItem* event = new_event(TYPE_API_USAGE, self.session_id, turn_id, request_id);
	CJsonItem* usage_item = cjson::new_object(tmem);
	usage_item.set("prompt_tokens", usage.prompt_tokens);
	usage_item.set("completion_tokens", usage.completion_tokens);
	usage_item.set("reasoning_tokens", usage.reasoning_tokens);
	event.set_item("usage", usage_item);
	event.set("latency_ms", latency_ms);
	event.set("model", model);
	if (finish_reason.len > 0) event.set("finish_reason", finish_reason);
	self.append_event(event);
}

// detail 的所有权移交本函数（并入事件树，随 event 释放）。
fn void TranscriptWriter.write_system_event(
	&self,
	String turn_id,
	String request_id,
	String subtype,
	String level,
	CJsonItem* detail
)
{
	CJsonItem* event = new_event(TYPE_SYSTEM_EVENT, self.session_id, turn_id, request_id);
	event.set("subtype", subtype);
	event.set("level", level);
	if (detail) event.set_item("detail", detail);
	self.append_event(event);
}

fn void TranscriptWriter.write_session_end(&self, String turn_id, String reason, int turns_total)
{
	CJsonItem* event = new_event(TYPE_SESSION_END, self.session_id, turn_id, "");
	event.set("reason", reason);
	event.set("turns_total", turns_total);
	self.append_event(event);
}

// ---- resume 重建 ------------------------------------------------------------

// 从 <config_dir>/transcripts/<session_id>.jsonl 重建消息序列到 messages：
// - session_start.system_prompt 快照 → messages[0]（不重新装配，A 方案保真第一）。
// - user_message → role=user（is_command=true 跳过）；assistant_message → role=assistant
//   （content + reasoning_content + tool_calls）；tool_result → role=tool（output 逐字节重建）。
// - 遇到 session_end 停止；丢弃最后一个未收尾 turn。
// - 重建成功后写入一条 system_event(resume) 标记，turns_total 更新为重建轮次数。
// 返回是否成功（文件缺失/无 system_prompt 视为失败）。
fn bool TranscriptWriter.resume_into(&self, List{Message}* messages, int* turns_total)
{
	Path file = self.file_path(tmem);
	if (file == "") return false;
	if (!path::exists(file)) return false;

	char[]? loaded = file::load(self.allocator, file);
	if (catch ex = loaded) return false;
	String file_content = (String)loaded;

	String[] lines = file_content.split(self.allocator, "\n");
	messages.clear();

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
				context::message_init(&sys, self.allocator, "system");
				sys.content = sp.copy(self.allocator);
				messages.push(sys);
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
				context::message_init(&user, self.allocator, "user");
				user.content = content_val.copy(self.allocator);
				messages.push(user);
				last_user_idx = messages.len() - 1;
				turns_rebuilt++;
				String turn_id = event.get_key_string("turn_id", tmem) ?? "";
				if (first_turn.len == 0) first_turn = turn_id.copy(self.allocator);
				last_turn = turn_id.copy(self.allocator);
			}
		}
		else if (type == TYPE_ASSISTANT_MESSAGE)
		{
			Message asst;
			context::message_init(&asst, self.allocator, "assistant");
			asst.content = (event.get_key_string("content", tmem) ?? "").copy(self.allocator);
			asst.reasoning_content = (event.get_key_string("reasoning_content", tmem) ?? "").copy(self.allocator);
			if (CJsonItem* calls = event.get_key("tool_calls"))
			{
				usz n = calls.get_len();
				for (usz i = 0; i < n; i++)
				{
					CJsonItem* c = calls.get_at((sz)i);
					if (!c) continue;
					ToolCall tc;
					tc.id = (c.get_key_string("id", tmem) ?? "").copy(self.allocator);
					tc.index = i;
					tc.name = (c.get_key_string("name", tmem) ?? "").copy(self.allocator);
					tc.arguments = (c.get_key_string("arguments", tmem) ?? "").copy(self.allocator);
					asst.tool_calls.push(tc);
				}
			}
			messages.push(asst);
		}
		else if (type == TYPE_TOOL_RESULT)
		{
			Message tool_msg;
			context::message_init(&tool_msg, self.allocator, "tool");
			tool_msg.tool_call_id = (event.get_key_string("tool_call_id", tmem) ?? "").copy(self.allocator);
			tool_msg.content = (event.get_key_string("output", tmem) ?? "").copy(self.allocator);
			messages.push(tool_msg);
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
		Message* last = messages.get_ref(messages.len() - 1);
		bool unfinished = last.role != "assistant" || last.tool_calls.len() > 0;
		if (unfinished)
		{
			while (messages.len() > last_user_idx)
			{
				(void)messages.pop();
			}
			tail_dropped = true;
		}
	}

	// 记录 resume 标记（来源 session、重建的 turn 范围与是否丢弃未收尾尾巴）
	CJsonItem* detail = cjson::new_object(tmem);
	detail.set("source_session", self.session_id);
	detail.set("turns_rebuilt", turns_rebuilt);
	if (first_turn.len > 0) detail.set("first_turn_id", first_turn);
	if (last_turn.len > 0) detail.set("last_turn_id", last_turn);
	detail.set("tail_dropped", tail_dropped);
	self.write_system_event("", "", SUBTYPE_RESUME, "info", detail);

	// 续跑的 session_end.turns_total 应包含重建的轮次
	*turns_total = turns_rebuilt;

	return true;
}
