module app;

// Session：turn / 会话生命周期模块（arch review 卡 1 的深化）。
//
// 吸收状态机里散落的会话生命周期逻辑，统一为小接口：
//   - turn 起点（turn_id 生成 + 记账 + user_message 事件）
//   - 会话收尾（session_end 唯一出口，带 ended 守卫；reason 在此单一化）
//   - 半成品 turn 丢弃（修正原 discard_messages_after 的 off-by-one：保留 user）
//   - token 预算判定（ledger 内部字段不外泄）
//   - headless/交互双出口（原 ×6 重复分支收敛为 finish_*）
//
// turn_id 由 Session 拥有（heap 分配）：start_user_turn / end_and_start_new / free
// 负责释放；request_id 仍由状态机持有（参数传递，见 rat_loop 卡 3-3 修复）。

import std::collections::list;
import cjson;

import message;
import transcript;
import util;

struct Session
{
	AppContext* app;
	String turn_id;    // heap 分配；跨 turn 覆盖时先释放旧值
	sz turn_start_idx; // 当前 turn 的 user 消息下标（discard 边界）
	bool ended;        // session_end 守卫（7 处调用点收敛为一处的前提）
}

fn void Session.init(&self, AppContext* app)
{
	self.app = app;
	self.turn_id = "";
	self.turn_start_idx = 0;
	self.ended = false;
}

// 一轮用户输入的公共起点：turn_id + 累计轮次 + 记账 + user_message 事件。
fn void Session.start_user_turn(&self, String content, bool is_command)
{
	if (self.turn_id.len > 0) self.turn_id.free(self.app.allocator);
	self.turn_id = util::timestamp_id(self.app.allocator);
	self.app.turns_total++;
	self.app.token_ledger.begin_turn();
	self.app.transcript.write_user_message(self.turn_id, content, is_command);
}

// 斜杠命令也需合法 turn_id（会话首命令时为空）。
fn void Session.record_command(&self, String content)
{
	if (self.turn_id.len == 0) self.turn_id = util::timestamp_id(self.app.allocator);
	self.app.transcript.write_user_message(self.turn_id, content, true);
}

// 会话收尾的唯一出口：带 ended 守卫（CHANNEL_CLOSED / /exit / headless 收尾等
// 多处调用不会重复写 session_end）。
fn void Session.end(&self, String reason)
{
	if (self.ended) return;
	self.ended = true;
	self.app.transcript.write_session_end(self.turn_id, reason, self.app.turns_total);
}

// 丢弃半成品 turn：弹出下标 > turn_start_idx 的全部消息（保留本轮 user 消息）。
// 修复原 discard_messages_after 的 off-by-one——user_message 事件已写盘，内存删除
// 会产生 resume 幽灵消息，故 user 一律保留（与 L1 语义统一，见 rat_loop 注释）。
fn void Session.discard_half_turn(&self)
{
	while (self.app.messages.len() > self.turn_start_idx + 1)
	{
		Message* last = self.app.messages.get_ref(self.app.messages.len() - 1);
		last.free_strings(self.app.allocator);
		(void)self.app.messages.pop();
	}
}

// token 预算三态判定（吸收原 check_token_budget）：
// OK → 放行；WARN → 写 system_event(token_warning) + UI 提示后放行；
// EXCEEDED → UI 提示并拒绝继续请求。
fn BudgetVerdict Session.check_budget(&self)
{
	BudgetVerdict verdict = self.app.token_ledger.check_budget();
	switch (verdict)
	{
		case BudgetVerdict.OK:
			return BudgetVerdict.OK;
		case BudgetVerdict.WARN:
		{
			CJsonItem* detail = cjson::new_object(tmem);
			detail.set("estimated_tokens", self.app.token_ledger.estimated_prompt_tokens());
			detail.set("context_window_limit", self.app.token_ledger.context_window_limit);
			detail.set("soft_ratio", self.app.token_ledger.soft_ratio);
			self.app.transcript.write_system_event(
				self.turn_id, "",
				transcript::SUBTYPE_TOKEN_WARNING, "warn", detail
			);
			push_notice(
				self.app,
				string::tformat(
					"Token budget warning: ~%d/%d tokens used (soft threshold %.0f%%)",
					self.app.token_ledger.estimated_prompt_tokens(),
					self.app.token_ledger.context_window_limit,
					self.app.token_ledger.soft_ratio * 100
				)
			);
			return BudgetVerdict.WARN;
		}
		case BudgetVerdict.EXCEEDED:
			push_notice(
				self.app,
				string::tformat(
					"Token budget exceeded: ~%d/%d tokens (hard threshold %.0f%%). Please /clear or start a new session.",
					self.app.token_ledger.estimated_prompt_tokens(),
					self.app.token_ledger.context_window_limit,
					self.app.token_ledger.hard_ratio * 100
				)
			);
			return BudgetVerdict.EXCEEDED;
	}
}

// ---- 完成当前 turn 的统一出口（原 headless/交互 ×6 重复分支收敛于此）----
// 返回 true = 进入 SHUTDOWN（headless），false = 回 IDLE（交互）。
// 交互路径不回写 session_end（会话继续）；headless 路径 end(reason) 后退出。

fn bool Session.finish_error(&self)
{
	if (self.app.flag.enable_headless)
	{
		self.end("error");
		push_shutdown(self.app, 1);
		return true;
	}
	push_ready(self.app);
	return false;
}

fn bool Session.finish_interrupted(&self)
{
	if (self.app.flag.enable_headless)
	{
		self.end("interrupted");
		push_shutdown(self.app, 1);
		return true;
	}
	push_notice(self.app, "interrupted");
	push_ready(self.app);
	return false;
}

fn bool Session.finish_done(&self)
{
	if (self.app.flag.enable_headless)
	{
		self.end("exit");
		push_notice(self.app, "DONE");
		push_shutdown(self.app, 0);
		return true;
	}
	push_ready(self.app);
	return false;
}

// /clear：写命令 user_message（复用当前 turn_id）→ 收尾旧会话（interrupted）→
// 开新会话。顺序由本方法保证（原 start_new_session 的隐式协议——调用方必须先
// end 旧会话）。开新会话后重置 ended，新会话可再次 end。
fn void Session.end_and_start_new(&self, String command_text)
{
	if (self.turn_id.len == 0) self.turn_id = util::timestamp_id(self.app.allocator);
	self.app.transcript.write_user_message(self.turn_id, command_text, true);
	self.end("interrupted");
	self.app.start_new_session();
	if (self.turn_id.len > 0) self.turn_id.free(self.app.allocator);
	self.turn_id = "";
	self.ended = false;
}

// 线程收尾：释放 turn_id（request_id 由状态机负责释放）。
fn void Session.free(&self)
{
	if (self.turn_id.len > 0) self.turn_id.free(self.app.allocator);
}
