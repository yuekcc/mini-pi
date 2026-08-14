import std::io;

import app;

// TokenLedger 单元测试：累计正确性 + OK/WARN/EXCEEDED 三态判定（arch-next-spec 测试矩阵）。
fn void test_ledger_accumulation() @test
{
	TokenLedger ledger;
	ledger.init(tmem, 0);

	ledger.record("req_1", { .prompt_tokens = 100, .completion_tokens = 20, .reasoning_tokens = 5 });
	ledger.record("req_2", { .prompt_tokens = 50, .completion_tokens = 30, .reasoning_tokens = 0 });

	assert(ledger.session_total.prompt_tokens == 150, "session prompt sum");
	assert(ledger.session_total.completion_tokens == 50, "session completion sum");
	assert(ledger.session_total.reasoning_tokens == 5, "session reasoning sum");

	assert(ledger.turn_total.prompt_tokens == 150, "turn total accumulates until begin_turn");
	assert(ledger.last_request.prompt_tokens == 50, "last request");
	assert(ledger.last_request.completion_tokens == 30, "last request completion");
	assert(ledger.history.len() == 2, "history has 2 records");
	assert(ledger.history[0].request_id == "req_1", "history order");
	assert(ledger.estimated_prompt_tokens() == 205, "estimated = total tokens 150+50+5");

	// begin_turn 清零本轮
	ledger.begin_turn();
	assert(ledger.turn_total.prompt_tokens == 0, "turn total reset");
	assert(ledger.session_total.prompt_tokens == 150, "session total preserved");

	// reset 清零全部
	ledger.reset();
	assert(ledger.session_total.prompt_tokens == 0, "session reset");
	assert(ledger.history.len() == 0, "history reset");
}

fn void test_ledger_history_cap() @test
{
	TokenLedger ledger;
	ledger.init(tmem, 0);
	ledger.history_cap = 3;

	for (int i = 0; i < 5; i++)
	{
		ledger.record(string::tformat("req_%d", i), { .prompt_tokens = 1, .completion_tokens = 0, .reasoning_tokens = 0 });
	}
	assert(ledger.history.len() == 3, "history capped at 3");
	assert(ledger.history[0].request_id == "req_2", "oldest retained");
	assert(ledger.history[2].request_id == "req_4", "newest kept");
	assert(ledger.session_total.prompt_tokens == 5, "accumulation unaffected by cap");
}

fn void test_ledger_budget_verdict() @test
{
	// limit == 0：不启用，恒 OK
	TokenLedger disabled;
	disabled.init(tmem, 0);
	assert(disabled.check_budget() == BudgetVerdict.OK, "disabled budget always OK");

	// 硬阈值 0.95、软阈值 0.8，limit 1000
	TokenLedger ledger;
	ledger.init(tmem, 1000);

	// 600 tokens → OK（< 800）
	ledger.record("r1", { .prompt_tokens = 600, .completion_tokens = 0, .reasoning_tokens = 0 });
	assert(ledger.check_budget() == BudgetVerdict.OK, "600/1000 OK");

	// 累计 850 → WARN（>= 800 且 < 950）
	ledger.record("r2", { .prompt_tokens = 250, .completion_tokens = 0, .reasoning_tokens = 0 });
	assert(ledger.check_budget() == BudgetVerdict.WARN, "850/1000 WARN");

	// 累计 960 → EXCEEDED（>= 950）
	ledger.record("r3", { .prompt_tokens = 110, .completion_tokens = 0, .reasoning_tokens = 0 });
	assert(ledger.check_budget() == BudgetVerdict.EXCEEDED, "960/1000 EXCEEDED");

	// 软阈值边界：恰好 800 → WARN
	TokenLedger edge;
	edge.init(tmem, 1000);
	edge.record("r1", { .prompt_tokens = 800, .completion_tokens = 0, .reasoning_tokens = 0 });
	assert(edge.check_budget() == BudgetVerdict.WARN, "exactly 800/1000 WARN");

	// 硬阈值边界：恰好 950 → EXCEEDED
	TokenLedger edge2;
	edge2.init(tmem, 1000);
	edge2.record("r1", { .prompt_tokens = 950, .completion_tokens = 0, .reasoning_tokens = 0 });
	assert(edge2.check_budget() == BudgetVerdict.EXCEEDED, "exactly 950/1000 EXCEEDED");

	io::printfn("token ledger budget verdicts verified");
}
