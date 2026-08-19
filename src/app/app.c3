module app;

// AppContext：mp v2 的统一全局状态挂载点（arch-next-spec 决策 2）。
//
// 取代 v1 散落的五处状态（tlocal GlobalStore、Context、tlocal 日志文件、无状态
// transcript 函数、skill 预留全局变量）。字段按所有权分为四区：
//   - 配置区（初始化后只读）：Flag 拷贝、allocator、cwd、config_dir；
//   - 会话状态区（仅 Agent 线程写）：session_id、messages、
//     turns_total、started_at/updated_at、resumed 标记；
//   - 资源区（初始化后只读）：ToolHub/SkillHub 指针、system_prompt_snapshot、
//     tools_schema_json（schema_cache 预计算产物）；
//   - 子系统区：TokenLedger、TranscriptWriter、Logger 指针（+ 阶段 1 起的
//     atomic cancel_flag 与线程句柄）。
//
// 内存规则：messages 及其中全部字符串用堆分配器（&allocators::LIBC_ALLOCATOR），
// tmem 仅限线程内短生命周期临时值。

import std::collections::list;
import std::io::path;
import std::time::datetime;
import std::core::mem::allocators;
import std::atomic;
import std::thread;
import std::thread::channel;

import cli;
import skill;
import tool;
import message;
import transcript;
import log;
import util;

struct AppContext
{
	// ---- 配置区（初始化后只读）----
	Flag flag;            // Flag 拷贝（不再传 Flag*，避免生命周期纠缠）
	Allocator allocator;  // &allocators::LIBC_ALLOCATOR（堆），非 tmem
	Path cwd;
	Path config_dir;

	// ---- 会话状态区（仅 Agent 线程写）----
	String session_id;
	List{Message} messages;
	int turns_total;
	DateTime started_at;
	DateTime updated_at;
	bool resumed;

	// ---- 资源区（初始化后只读）----
	ToolHub* tool_hub;
	SkillHub* skill_hub;
	String system_prompt_snapshot; // 装配产物（session_start/resume 用）
	String tools_schema_json;      // schema_cache 预计算产物

	// ---- 子系统区 ----
	TokenLedger* token_ledger;
	TranscriptWriter* transcript;
	Logger* logger;

	// ---- 运行时信号区（阶段 1 起：三线程拓扑）----
	UnboundedChannel{UiEvent}* ui_to_agent;     // ui → agent（unbounded）
	UnboundedChannel{UiOutEvent}* agent_to_ui;  // agent → ui（unbounded）
	BufferedChannel{ApiRequest}* agent_to_api;  // agent → api（容量 1，天然背压）
	UnboundedChannel{ApiResponse}* api_to_agent;// api → agent（unbounded）
	Atomic{bool}* cancel_flag;                  // Ctrl+C 取消信号（阶段 2 起使用）
	Thread agent_thread;
	Thread api_thread;
}

// ---- Agent → UI 事件推送辅助（自 rat_loop 移入；文本 heap 分配，UI 释放）----

fn void push_notice(AppContext* app, String text)
{
	UiOutEvent ev = {
		.kind = UiOutKind.NOTICE,
		.text = text.copy(app.allocator),
	};
	(void)app.agent_to_ui.push(ev);
}

fn void push_render(AppContext* app, Message* msg, String tool_name)
{
	UiOutEvent ev = {
		.kind = UiOutKind.RENDER_MESSAGE,
		.msg = msg.clone(app.allocator),
		// 空串不拷贝（保持静态 ""），与释放端 len 守卫配对。
		.tool_name = tool_name.len > 0 ? tool_name.copy(app.allocator) : "",
	};
	(void)app.agent_to_ui.push(ev);
}

fn void push_shutdown(AppContext* app, int exit_code)
{
	UiOutEvent ev = { .kind = UiOutKind.SHUTDOWN, .exit_code = exit_code };
	(void)app.agent_to_ui.push(ev);
}

fn void push_ready(AppContext* app)
{
	// 回到 IDLE：清除残留取消信号（L1 中断处理完 / 工具阶段遗留），避免污染下一轮请求。
	app.cancel_flag.store(false);
	UiOutEvent ev = { .kind = UiOutKind.READY };
	(void)app.agent_to_ui.push(ev);
}

fn AppContext* AppContext.init(
	&self,
	Flag flag,
	Allocator allocator,
	String session_id,
	ToolHub* tool_hub,
	SkillHub* skill_hub,
	Logger* logger,
	long max_tokens
)
{
	self.flag = flag;
	self.allocator = allocator;
	self.cwd = flag.cwd;
	self.config_dir = flag.config_dir;

	self.session_id = session_id.copy(allocator);
	self.messages.init(allocator);
	self.turns_total = 0;
	DateTime now = datetime::now().to_local();
	self.started_at = now;
	self.updated_at = now;
	self.resumed = false;

	self.tool_hub = tool_hub;
	self.skill_hub = skill_hub;
	self.system_prompt_snapshot = "";
	// schema_cache 预计算：init 时一次付清，之后 hub 只读、schema 无锁访问。
	self.tools_schema_json = tool_hub.schema(allocator);

	self.token_ledger = alloc::new(allocator, TokenLedger);
	self.token_ledger.init(allocator, max_tokens);

	self.transcript = alloc::new(allocator, TranscriptWriter);
	self.transcript.init(allocator, self.config_dir, self.session_id, flag.enable_transcript);

	self.logger = logger;

	// ---- 运行时信号（三线程拓扑）：通道创建 + 取消标志 ----
	self.ui_to_agent = channel::create_unbounded{UiEvent}(allocator)!!;
	self.agent_to_ui = channel::create_unbounded{UiOutEvent}(allocator)!!;
	self.agent_to_api = channel::create_buffered{ApiRequest}(allocator, 1)!!;
	self.api_to_agent = channel::create_unbounded{ApiResponse}(allocator)!!;
	self.cancel_flag = alloc::new(allocator, Atomic{bool});

	return self;
}

fn bool AppContext.debug(&self)
{
	return self.flag.enable_debug;
}

// 装配并保存系统提示词快照（PromptAssembly 产物），追加 system 消息。
// 新会话与 /clear 均调用；--resume 不调用（用 transcript 快照）。
fn void AppContext.reset(&self)
{
	self.messages.clear();

	String system_prompt = build_system_prompt(self.allocator, self.config_dir, self.cwd, self.tool_hub, self.skill_hub);
	// 初次为静态 ""（len 0），不可 free；此后均为堆分配。
	if (self.system_prompt_snapshot.len > 0) self.system_prompt_snapshot.free(self.allocator);
	self.system_prompt_snapshot = system_prompt;

	Message system_msg;
	system_msg.init(self.allocator, "system");
	system_msg.content = system_prompt.copy(self.allocator);
	self.messages.push(system_msg);
	self.updated_at = datetime::now().to_local();
}

// /clear：收尾旧会话（session_end(interrupted)）→ 新 session_id → 重新装配提示词
// → 写 session_start。调用方（Agent 线程）负责保证 transcript/ledger 单写；
// 「先收尾旧会话再调用」的顺序由 Session.end_and_start_new 保证（arch review 卡 1）。
fn void AppContext.start_new_session(&self)
{
	self.session_id.free(self.allocator);
	self.session_id = string::format(self.allocator, "ses_%s", util::timestamp_id(self.allocator));
	self.turns_total = 0;

	self.transcript.set_session_id(self.session_id);
	self.token_ledger.reset();

	self.reset();
	self.write_session_start_event();
}

// 写入当前会话的 session_start 事件（system_prompt 取装配产物快照）。
fn void AppContext.write_session_start_event(&self)
{
	self.transcript.write_session_start(
		self.flag.model,
		self.flag.agent,
		string::format(tmem, "%s", self.cwd),
		self.system_prompt_snapshot,
		transcript::tool_names(tmem, self.tool_hub)
	);
}

fn void AppContext.add_message(&self, Message* message)
{
	Message* cloned = message.clone(self.allocator);
	self.messages.push(*cloned);
	alloc::free(self.allocator, cloned);
	self.updated_at = datetime::now().to_local();
}

fn String AppContext.render_to_markdown(&self, Allocator allocator)
{
	DString buf = dstring::new(allocator);

	buf.appendfn("---");
	buf.appendfn("Session ID: %s", self.session_id);
	buf.appendfn("Started At: %s", self.started_at.to_local().format(allocator, DateTimeFormat.DATETIME));
	buf.appendfn("Updated At: %s", self.updated_at.to_local().format(allocator, DateTimeFormat.DATETIME));
	buf.appendfn("---\n");

	foreach (message : self.messages)
	{
		buf.appendfn("# %s %s\n", message.timestamp.to_local()
			.format(allocator, DateTimeFormat.DATETIME), message.role);

		String reasoning_content = message.reasoning_content.trim();
		String content = message.content.trim();

		if (message.tool_call_id != "")
		{
			buf.appendfn("(Tool call ID: `%s`)\n", message.tool_call_id);
		}

		if (reasoning_content != "")
		{
			buf.appendfn("> Thinking:");
			buf.appendfn("> ");
			foreach (line : reasoning_content.split(allocator, "\n"))
			{
				buf.appendfn("> %s", line);
			}

			buf.appendfn("");
		}

		if (content != "")
		{
			bool should_pack = message.tool_call_id != "";
			if (should_pack) buf.appendfn("```");

			buf.appendfn("%s\n", content);

			if (should_pack) buf.appendfn("```\n");
		}

		if (message.tool_calls.len() > 0)
		{
			foreach (tool_call : message.tool_calls)
			{
				buf.appendfn(
					"(Call tool, id = `%s`, name = `%s`, arguments = `%s`)\n",
					tool_call.id,
					tool_call.name,
					tool_call.arguments
				);
			}
		}
	}

	return buf.str_view();
}
