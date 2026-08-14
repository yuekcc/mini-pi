module app;

// Token 账本：会话级 token 累计与预算判定（arch-next-spec 决策 3）。
//
// 数据流：API 请求回报 usage → Agent 线程调用 record() 记账（并写 transcript api_usage
// 事件，见 rat_loop）。每次新 turn 开始调用 begin_turn() 清零本轮累计。
//
// 预算判定：context_window_limit == 0 表示不启用；否则以 estimated_prompt_tokens()
// 与 limit 的比值对照 soft_ratio / hard_ratio 返回三态判定：
//   OK / WARN（写 system_event(token_warning) + UI 提示）/ EXCEEDED（拒绝继续请求）。
// v1 范围只实现到 WARN 的落盘与展示，compaction 预留（见 docs/arch-next-spec.md）。

import std::collections::list;

const double DEFAULT_SOFT_RATIO = 0.8;
const double DEFAULT_HARD_RATIO = 0.95;
const int DEFAULT_HISTORY_CAP = 32;

struct TokenUsage
{
	long prompt_tokens;
	long completion_tokens;
	long reasoning_tokens;
}

struct UsageRecord
{
	String request_id;
	TokenUsage usage;
}

enum BudgetVerdict
{
	OK,
	WARN,
	EXCEEDED,
}

struct TokenLedger
{
	Allocator allocator;
	TokenUsage session_total;  // 会话累计
	TokenUsage turn_total;     // 当前 turn 累计
	TokenUsage last_request;   // 最近一次请求
	List{UsageRecord} history; // 最近 N 条明细（供 UI 状态行/告警）
	long context_window_limit; // 上下文窗口上限（0 = 不启用）
	double soft_ratio;         // 软阈值比例（默认 0.8）
	double hard_ratio;         // 硬阈值比例（默认 0.95）
	int history_cap;           // history 最大条数
}

fn TokenLedger* TokenLedger.init(&self, Allocator allocator, long context_window_limit)
{
	self.allocator = allocator;
	self.session_total = {};
	self.turn_total = {};
	self.last_request = {};
	self.history.init(allocator);
	self.context_window_limit = context_window_limit;
	self.soft_ratio = DEFAULT_SOFT_RATIO;
	self.hard_ratio = DEFAULT_HARD_RATIO;
	self.history_cap = DEFAULT_HISTORY_CAP;
	return self;
}

fn long TokenLedger.total_tokens(&self, TokenUsage* usage)
{
	return usage.prompt_tokens + usage.completion_tokens + usage.reasoning_tokens;
}

// 记录一次请求的 usage：累计会话/本轮/最近一次，并保留最近 history_cap 条明细。
fn void TokenLedger.record(&self, String request_id, TokenUsage usage)
{
	self.session_total.prompt_tokens += usage.prompt_tokens;
	self.session_total.completion_tokens += usage.completion_tokens;
	self.session_total.reasoning_tokens += usage.reasoning_tokens;

	self.turn_total.prompt_tokens += usage.prompt_tokens;
	self.turn_total.completion_tokens += usage.completion_tokens;
	self.turn_total.reasoning_tokens += usage.reasoning_tokens;

	self.last_request = usage;

	UsageRecord rec = {
		.request_id = request_id.copy(self.allocator),
		.usage = usage,
	};
	self.history.push(rec);
	if (self.history.len() > self.history_cap)
	{
		UsageRecord dropped = self.history[0];
		dropped.request_id.free(self.allocator);
		self.history.remove_at(0);
	}
}

// 新 turn 开始：本轮累计清零。
fn void TokenLedger.begin_turn(&self)
{
	self.turn_total = {};
}

// /clear 开启新会话：账本整体清零（新会话独立记账）。
fn void TokenLedger.reset(&self)
{
	self.session_total = {};
	self.turn_total = {};
	self.last_request = {};
	foreach (rec : self.history) rec.request_id.free(self.allocator);
	self.history.clear();
}

// 估算下轮 prompt 大小（近似）：取会话累计总 token（prompt + completion + reasoning）。
// 说明：下一请求的 prompt 即整个对话历史，其 token 量与累计用量同量级，作为
// 上下文窗口占用的近似上界足够用于软/硬阈值告警。
fn long TokenLedger.estimated_prompt_tokens(&self)
{
	return self.session_total.prompt_tokens
		+ self.session_total.completion_tokens
		+ self.session_total.reasoning_tokens;
}

// 预算三态判定：OK / WARN / EXCEEDED。limit == 0（未启用）恒为 OK。
fn BudgetVerdict TokenLedger.check_budget(&self)
{
	if (self.context_window_limit <= 0) return BudgetVerdict.OK;

	long estimated = self.estimated_prompt_tokens();
	long limit = self.context_window_limit;

	if (estimated >= (long)(limit * self.hard_ratio)) return BudgetVerdict.EXCEEDED;
	if (estimated >= (long)(limit * self.soft_ratio)) return BudgetVerdict.WARN;
	return BudgetVerdict.OK;
}

// ---- compaction 预留（v2 不实现，见 arch-next-spec Out of Scope）------------
// 触发时机：check_budget() == EXCEEDED。将来实现：
//   1. 调用方（Agent）从 messages 裁掉早期 turn（保留 system + 最近 N 轮）；
//   2. 写 system_event(compact_boundary)（subtype 常量已在 transcript 模块占位，
//      SUBTYPE_COMPACT_BOUNDARY），detail 记录裁剪前后 turn 范围；
//   3. TokenLedger 依据保留区间重算会话累计（本模块提供 session_total 直接可调）。
