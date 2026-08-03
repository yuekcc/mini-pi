---
title: "Inside a Claude Code Transcript: How Turns, Tokens & Actors Actually Work"
description: "A line-by-line anatomy of the Claude Code .jsonl session format — how turns are reconstructed, what a token count really means, and the seven things that masquerade as a user prompt — audited against 1,107 real transcripts."
pubDatetime: 2026-07-01T09:45:00Z
lang: en
tags:
  - claude-code
  - transcript
  - jsonl
  - llm
  - ai-agents
multiLangKey: "transcript-anatomy"
url: https://github.com/hieplam/memo/blob/main/src/content/posts/claude-code-transcript-anatomy.md
---

<aside class="ev-legend" data-pagefind-ignore aria-label="Evidence-tag legend">
  <span class="ev-legend__title">Evidence tags — hover or tap for meaning</span>
  <span class="ev-legend__item" tabindex="0" aria-label="Green — file-verified: observed directly in the 1,107 real transcripts." data-tip="File-verified — observed directly in the 1,107 real transcripts, reproducible from the corpus.">
    <span class="ev-legend__dot" aria-hidden="true">🟢</span><span class="ev-legend__label">file-verified</span><span class="ev-legend__info" aria-hidden="true">ⓘ</span>
  </span>
  <span class="ev-legend__item" tabindex="0" aria-label="Check — docs-verified: backed by official Anthropic documentation." data-tip="Docs-verified — backed by official Anthropic documentation.">
    <span class="ev-legend__dot" aria-hidden="true">✅</span><span class="ev-legend__label">docs-verified</span><span class="ev-legend__info" aria-hidden="true">ⓘ</span>
  </span>
  <span class="ev-legend__item" tabindex="0" aria-label="Yellow — inference: reasoned, not directly observable because Claude Code is closed-source." data-tip="Inference — reasoned, not directly observable (Claude Code is closed-source).">
    <span class="ev-legend__dot" aria-hidden="true">🟡</span><span class="ev-legend__label">inference</span><span class="ev-legend__info" aria-hidden="true">ⓘ</span>
  </span>
  <span class="ev-legend__item" tabindex="0" aria-label="Red — refuted: a claim from the original survey that the audit disproved." data-tip="Refuted — a claim from the original survey the audit disproved outright. See the Errata (→ E#) table below.">
    <span class="ev-legend__dot" aria-hidden="true">🔴</span><span class="ev-legend__label">refuted</span><span class="ev-legend__info" aria-hidden="true">ⓘ</span>
  </span>
</aside>

Every Claude Code session writes itself to disk as a `.jsonl` file — one JSON object per line, appended in real time. It looks simple enough to reverse-engineer in an afternoon: find the user line, find the assistant line, count the tokens, done.

It isn't that simple. A line that says `role:"user"` is not necessarily a human. A "turn" is not one API call. A tiny `input_tokens` count doesn't mean a small prompt. And an entire subagent can run, compact its own context, and report back — without a single byte of it appearing in the file you started with.

This post is a full anatomy of the format: what the original inspection found, and what held up (or didn't) when it was adversarially audited against **1,107 real transcripts** spanning CLI versions 2.1.168 → 2.1.197.

Evidence tags (🟢 / ✅ / 🟡 / 🔴) are pinned in the legend at the top of the page — hover, tab to, or tap any tag to see what it means. Corrections found by the audit are tagged **→ E#** and collected in the Errata table below.

## TL;DR

- **The transcript is a tree, not a clean chain.** ~15% of lines in a real file are `uuid`-less bookkeeping records interleaved between the real conversation — and 59.2% of files actually branch (forks), not just append.
- **`tool_result` looks exactly like a user message** (`type:"user"`, `role:"user"`) even though the harness produced it — and it's only **1 of at least 7** things that wear `role:"user"` without a human behind them.
- **A turn is not one API call.** One real turn spanned 4 distinct `requestId`s under a single `turn_duration` anchor — and that anchor is only present on ~9% of session files.
- **`message.usage` has grown from 4 fields to ~10** (`server_tool_use`, `service_tier`, `cache_creation`, `inference_geo`, `iterations`, `speed`), and a small `input_tokens` reading does _not_ mean a small context window.
- **Six whole subsystems never made it into the first pass**: subagents/sidechains, compaction, the full 8-subtype `system` catalog, the identity-field zoo, the tree topology, and the structured `toolUseResult` payload.
- **The audit tally**, across 22 falsifiable claims checked against the full corpus: **6 CONFIRMED**, **14 PARTIAL** (right in spirit, wrong in detail), **2 REFUTED** outright.

---

## 1. What a transcript file actually is

Every Claude Code session is written to `~/.claude/projects/<project>/<sessionId>.jsonl`. **JSONL** means one complete JSON object per line, appended as the session runs. ✅

The core fields on a conversational line:

| Field                                      | Meaning                                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `type`                                     | Event discriminator: `user`, `assistant`, `system`, `attachment`, …                                     |
| `uuid`                                     | Unique ID of this line                                                                                  |
| `parentUuid`                               | Points back to the previous line — forms the conversation **tree** (see §10 for the overloading nuance) |
| `timestamp`                                | UTC, ISO 8601                                                                                           |
| `message`                                  | Payload — `role`, `content`, and `usage` on user/assistant lines                                        |
| `requestId`                                | On `assistant` lines — identifies one API call (absent on synthetic error lines, see §4)                |
| `sessionId`, `cwd`, `gitBranch`, `version` | Session metadata — but a _per-line snapshot_, not a fixed constant (§10.6)                              |

Inside `message.content` are **content blocks**: `text`, `thinking`, `tool_use`, `tool_result` — and also **`image`** (§11.4), which most write-ups skip entirely. ✅🟢

> 🟡 **One logical message, split across lines.** Claude Code usually writes _each content block as its own line_: two consecutive `assistant` lines can share the same `requestId` **and** `message.id`, one holding `thinking` and the other `text`, roughly a millisecond apart. This is the dominant pattern — 74.6% of assistant `message.id`s are split across 2–16 lines — but it is **not an invariant**. The harness sometimes bundles multiple blocks onto one line, even on the newest build.

> ⚠️ **Not every physical line is in the chain.** Around 15% of lines in a real file are `uuid`-less bookkeeping records (`mode`, `last-prompt`, `ai-title`, `file-history-snapshot`, `started`, `result`, `pr-link`, …) interleaved throughout the file. "One JSON object per line, chained via `uuid → parentUuid`" is true **for the four conversational types** (user/assistant/system/attachment) — not for the whole file.

---

## 2. Three actors, or four — and the `tool_result` trap

| Actor           | `type` it produces                                                        | Calls the API? | Role                                             |
| --------------- | ------------------------------------------------------------------------- | :------------: | ------------------------------------------------ |
| 🧑 **User**     | `user` (role=user, plain text)                                            |       ❌       | Submits the prompt that opens a turn             |
| 🤖 **Model**    | `assistant` (has `requestId`)                                             |       ✅       | Thinks, replies, requests tools                  |
| ⚙️ **Harness**  | `attachment`, `system`, **`tool_result`**, plus a dozen bookkeeping types |       ❌       | Injects context, runs tools, times the turn      |
| 🤝 **Teammate** | `user` (plain string, `<teammate-message>`)                               |   indirectly   | A _different_ Claude session reporting in (§7.5) |

### The big trap: `tool_result` looks like a user 🟢 CONFIRMED

A `tool_result` line carries `type:"user"`, `role:"user"` — even though the harness produced it, not a human. This is exhaustively confirmed: **16,255** `tool_result` lines across the corpus, 100% with `type/role = user/user`, **zero** exceptions. The tell that it's harness-origin: it also carries a top-level `toolUseResult` object and a `sourceToolAssistantUUID` backlink (§10.5, §11.1) that a human-typed line never has.

Filtering by "split turns on `role == user`" picks the wrong start — and that warning is correct but **incomplete**. There are at least **seven** things wearing `role:"user"` that aren't a human prompt. The full list is in §12.

### Harness stage-setting after a prompt

Right after your prompt, the harness injects `attachment` lines. A first-glance read of the format usually names three of these (`deferred_tools_delta`, `mcp_instructions_delta`, `opened_file_in_ide`) and calls the field `subtype`. **Both are wrong**: the field is `attachment.type`, there are **23** distinct values, and the most common one (`skill_listing`) _outnumbers_ `deferred_tools_delta`. The full zoo is in §11.

---

## 3. What a token actually is, and what `usage` really contains

A token is a sub-word chunk (BPE or a proprietary variant), not a word. ✅ The transcript stores token **counts** in `message.usage` (assistant lines only) — **never the token strings themselves**. To see the word↔token mapping you have to re-tokenize yourself. 🟢 CONFIRMED — exhaustively: no token-array field exists anywhere in the corpus, and the newest builds even add `cache_missed_input_tokens`, still just a scalar.

### `message.usage` — the real shape

A shallow pass over this format usually lists 4 fields. Current transcripts (2.1.172+) carry roughly **10**:

```json
{"input_tokens":8436, "cache_creation_input_tokens":5065, "cache_read_input_tokens":16537,
 "output_tokens":478, "server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},
 "service_tier":"standard", "cache_creation":{"ephemeral_1h_input_tokens":5065,"ephemeral_5m_input_tokens":0},
 "inference_geo":"not_available", "iterations":[ … per-round-trip mirror … ], "speed":"standard"}
```

> 🟢 A tiny `input_tokens` reading (e.g. 65) does **not** mean little context — the rest arrived via `cache_read_input_tokens` (warm cache) **or** `cache_creation_input_tokens` (cold cache: a session's first turn, and right after every `compact_boundary`). It only _tends_ toward single digits deep into a long session; a big new paste or tool-result can spike it back up regardless of how warm the cache is.

---

## 4. How a turn is actually calculated

### 4.1 Definition

> **A turn = one prompt-processing lifecycle.** It opens when the user submits a prompt and closes when the harness decides the agent loop is done. ✅🟡

The agent loop: while the assistant message contains `tool_use` block(s), the harness runs the tool, feeds the result back, and calls the model again — until it doesn't. ✅ The real driver of the loop is "the message contains a `tool_use` block," not literally `stop_reason == "tool_use"` — subagent transcripts sometimes record `stop_reason:null` on a message that still has a `tool_use` and is still looping.

A turn also does **not** always close on `stop_reason:"end_turn"`. Across a corpus of 480 turn-closes: 91.9% ended on `end_turn`, **7.9% closed on a synthetic API-error message** (`model:"<synthetic>"`, `stop_reason:"stop_sequence"`), and some closed directly off a scheduling tool's `tool_result` ("Nothing more to do this turn").

### 4.2 The anchor field 🟢 CONFIRMED (with conditions)

The end of a turn is marked by `type:"system"`, `subtype:"turn_duration"`, carrying `durationMs` and `messageCount` (cumulative, **strictly increasing** per session). A real example (v2.1.197):

```json
{
  "type": "system",
  "subtype": "turn_duration",
  "durationMs": 118342,
  "messageCount": 35,
  "version": "2.1.197"
}
```

But two conditions the audit surfaced:

- `turn_duration` is **not universal** — only ~9% of session files contain any (turns that finish cleanly). Interrupted (`[Request interrupted by user]`) or abandoned (session closed mid-turn) prompts get **no** anchor at all. Its **absence is not a parser bug**.
- When a **Stop hook** is configured, the turn-end becomes **two** chained system lines: `stop_hook_summary` _then_ `turn_duration` (`turn_duration.parentUuid` = `stop_hook_summary.uuid`). More on this in §9.

### 4.3 A turn is NOT one API call 🟢 CONFIRMED

A real, traceable example: one pensieve session, one turn, **4 distinct `requestId`s**, but exactly **1** `turn_duration` (`durationMs=54084, messageCount=33`). A mid-turn WebFetch self-correction (301 redirect → refetch the corrected URL on the next round-trip, same turn) is verified verbatim in the data.

> 🟡 `requestId` also hides transport retries. An `api_error` retry-storm can stretch a single "round-trip" over ~60 minutes with `retryAttempt` 1…10 before it resolves (§9). So "`requestId` = one round-trip" is really the _success-path_ view of things.

### 4.4 Timing 🔴 REFUTED as "stable ~0.2s"

An earlier claim held that the residual between wall-clock time and `durationMs` is a stable ~0.2 s. It isn't. Those two numbers (0.218 s, 0.198 s) turned out to be **2 cherry-picked turns out of 6** in the same session; the other four were 111 ms, 249 ms, 3297 ms, and 5071 ms. Across 472 corpus turns the residual ranges from ~0 ms to several seconds, and only ~10% land in the claimed 150–250 ms band. The first turn of a session pays much more (bootstrap cost). It's a **variable per-turn overhead**, not a constant.

Likewise, "`turn_duration` written 3–7 ms after the final assistant line" only holds when nothing sits between them — true for 63% of turns. With a Stop hook, or an idle/away gap, the delta balloons to hundreds of milliseconds, and in extreme cases up to ~24 minutes.

---

## 5. Finding turn boundaries — the practical rule, corrected

- 🔴 **Turn end:** the `subtype == "turn_duration"` line — _when present_ (only ~9% of files have one).
- 🟢 **Turn start:** the nearest preceding _genuine_ `user` prompt — but the naive filter ("not `isMeta`, not `tool_result`") is **necessary but not sufficient**. It mis-locates ~13% of turns because other harness lines also wear `role:"user"` with no `isMeta` and no `tool_result` block: task-notifications, bash I/O, local-command stdout, teammate messages. Use the full exclusion list in §12.
- ✅ **The clean shortcut that's easy to miss:** every line of one logical turn — the real prompt _and every downstream `tool_result`_ — shares one **`promptId`** (`null` on assistant lines). Turn membership is a `group by promptId`, not a backward graph-walk. See §10.3.

---

## 6. The Errata: what the original pass got wrong

The adversarial audit extracted 22 falsifiable claims from the original inspection and checked each against the full 1,107-transcript corpus. Six survived unchanged; fourteen needed a qualifier; two were flatly wrong.

| #       | Original claim                                              | Verdict        | Corrected reality                                                                                                                                                                                                                                                       |
| ------- | ----------------------------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **E1**  | "one JSON object per line, chained via `uuid → parentUuid`" | 🟡 PARTIAL     | True for the 4 conversational types (100% of 45,767 lines). But ~15.5% of file lines are `uuid`-less bookkeeping records (11 types) interleaved throughout.                                                                                                             |
| **E2**  | 3 actors; Harness = `attachment`/`system` + `tool_result`   | 🟡 PARTIAL     | Harness also disguises as `user` via `isMeta` wrapper text (454 lines), and writes ≥9 more top-level types (`last-prompt`, `mode`, `ai-title`, …). Add a 4th actor: Teammate.                                                                                           |
| **E3**  | `usage` has 4 fields                                        | 🟡 PARTIAL     | Location (assistant-only, in `message.usage`) is exact; but current `usage` carries ~10 keys (adds `server_tool_use`, `service_tier`, `cache_creation`, `inference_geo`, `iterations`, `speed`).                                                                        |
| **E4**  | small `input_tokens` ⇒ rest came from `cache_read`          | 🟡 PARTIAL     | Also `cache_creation_input_tokens` (cold cache: first turn / post-compaction). "Shrinks to single digits" is a tendency, not a rule.                                                                                                                                    |
| **E6**  | `requestId` on assistant lines = one API call               | 🟡 PARTIAL     | Grouping is solid (1 req → 1..16 lines, never interleaved). But ~48 synthetic error assistant lines (`model:"<synthetic>"`, `isApiErrorMessage`) have `requestId:null`.                                                                                                 |
| **E7**  | each content block = its own line, ~1 ms apart              | 🟡 PARTIAL     | Dominant (74.6%) but not invariant: 3 corpus lines bundle 2–4 blocks (including on the newest v2.1.197). "~1 ms" only holds for thinking→text; `tool_use` splits lag seconds→minutes.                                                                                   |
| **E10** | 3 attachment **subtypes** injected after prompt             | 🔴 **REFUTED** | No `subtype` key — it's `attachment.type`, with **23** values. `skill_listing` (1128) > `deferred_tools_delta` (1117); `opened_file_in_ide` only 22. The exact trio is one _conditional_ combo, not the fixed set.                                                      |
| **E11** | stage-setting attachments written in ~0 ms                  | 🟡 PARTIAL     | True for the 3 named types (≤28 ms). **Hook-origin** attachments in the same slot lag up to ~1.1 s (they wait on a real shell hook).                                                                                                                                    |
| **E12** | turn closes at `stop_reason:"end_turn"`                     | 🟡 PARTIAL     | 91.9% end_turn; 7.9% close on synthetic `stop_sequence` API-error; some off a scheduling `tool_result`. 36.7% of `turn_duration`s parent off a `stop_hook_summary`/`away_summary`, not the assistant line.                                                              |
| **E13** | loop condition = `stop_reason == "tool_use"`                | 🟡 PARTIAL     | Sequence is exact (0 violations). But the driver is "has a `tool_use` block"; subagent transcripts show `stop_reason:null` + tool_use still looped (13 lines / 6 files).                                                                                                |
| **E14** | turn end = a single `turn_duration` line                    | 🟡 PARTIAL     | Only ~9% of files have any `turn_duration`. With a Stop hook it's **two** lines (`stop_hook_summary` → `turn_duration`). Also carries `messageCount`, `version`, sometimes `pendingWorkflowCount`.                                                                      |
| **E16** | `turn_duration` is undocumented / discovered by inspection  | 🟡 PARTIAL     | It's `@internal`-documented in the shipped CLI binary (with a richer field set: `budget`, `pending_workflow_count`, …) plus a `tengu_show_turn_duration_setting_changed` flag. No _public_ docs page; the community deepwiki simply never covers `system` lines at all. |
| **E19** | wall-clock − `durationMs` ≈ stable ~0.2 s                   | 🔴 **REFUTED** | Cherry-picked 2/6 turns; real residuals 111 ms–5071 ms in the same session, ~0 ms–seconds across 472 turns. First-turn bootstrap dominates. Variable overhead, not a constant.                                                                                          |
| **E20** | `turn_duration` 3–7 ms after final assistant line           | 🟡 PARTIAL     | Only in the 63% "direct" case (and only 71% of those are 3–7 ms). With a Stop hook or idle gap: 50 ms → ~24 min.                                                                                                                                                        |
| **E21** | turn start = nearest `user` not `isMeta`/`tool_result`      | 🟡 PARTIAL     | Misses ~13% — also exclude `<task-notification>`, `<bash-input/stdout>`, `<local-command-stdout/caveat>`, `<teammate-message>`. Better: `group by promptId`.                                                                                                            |
| **E22** | every line carries `sessionId/cwd/gitBranch/version`        | 🟡 PARTIAL     | Only the 4 core types (100%). Bookkeeping types omit `cwd/gitBranch/version` (and some omit `sessionId`). These fields are **per-line snapshots** — `version`/`gitBranch` change mid-file.                                                                              |

CONFIRMED with no change: **C5** (counts-only, no token strings), **C8** (`tool_result` = user), **C9** (5-of-6 sample), **C15** (`messageCount` monotonic), **C17** (4 requestIds / 1 turn), **C18** (mid-turn WebFetch self-correct).

---

## 7. Subagents, sidechains & teammates — the biggest omission

The naive model treats a session as one self-contained file. In reality subagents live in **separate files** and report back through a channel that looks exactly like a user prompt.

**Subagents are separate files 🟢.** A `Task`/`Agent` spawn writes the child's whole transcript to `<sessionId>/subagents/agent-<name>-<hash>.jsonl` — **not** inline. The corpus has 34 `subagents/` folders holding **865** child transcripts. Open only the top-level file and you'd never know a subagent ran.

**The `.meta.json` sidecar 🟢.** Each `agent-*.jsonl` has a matching `agent-*.meta.json` holding what the `.jsonl` never does: `agentType`, `spawnDepth`, `taskKind` (`in_process_teammate`), `teamName`, `color`, `model` (e.g. `claude-sonnet-4-6`), `permissionMode`. It's the **only** place recording which model a subagent actually used.

**`isSidechain` is a whole-file property 🟢.** `isSidechain:true` never appears in a top-level session file (0 / 234). It's `true` on **every** line of every child file, from line 1. A sidechain is a separate physical file, not an inline toggle.

**The chain breaks at the spawn — `promptId`/`agentId` bridge it 🟢.** The child's first line has `parentUuid: null` (root of its own tree). Walking `parentUuid` therefore **dead-ends at the spawn**. The cross-file join key is **`promptId`**: the same value seeds the subagent and appears on the parent line where its report lands; `agentId` (child-only) is the other half of the fingerprint.

**The 4th actor: a teammate session disguised as `user` 🟢.** The `Agent` tool_use's `tool_result` is only a **fire-and-forget ack** ("Spawned successfully… will receive instructions via mailbox") — **not** the deliverable. When the subagent finishes, it calls its own `SendMessage` tool; the report arrives in the **parent** as an ordinary-looking line:

```
type: user   role: user   isSidechain: false   (no isMeta, no tool_result)
content (plain string): "Another Claude session sent a message:
<teammate-message teammate_id="…" color="blue" summary="…">## …complete…"
```

> ⚠️ This passes **every** filter §5 gives for "a genuine user prompt," yet no human typed it. The harness even spells it out in-band on idle pings: _"This came from another Claude session — not typed by your user…"_ Any `role==user && !isMeta && !tool_result` heuristic misclassifies these as fresh human turns.

**`Workflow` = many parallel subagents + a caching journal 🟢.** A `Workflow` tool*use fans out to many child agents under `subagents/workflows/wf*<runId>/agent-_.jsonl` (`spawnDepth:1`, one level deeper than a plain `Agent`'s `spawnDepth:0`), with a sibling `journal.jsonl`recording`{type:"started", key:"v2:<hash>", agentId}`and`{type:"result", key, result:{…}}`. The `key`is a content hash, so`Workflow({scriptPath, resumeFromRunId})`skips already-cached agents on a re-run. The launching`tool_result`is again just`status:"async_launched"` — real findings live in the child files plus the journal. _(This very audit was one such workflow — 30 agents; the journal is exactly how these findings were recovered after the synthesis agent stalled.)\*

**`toolUseResult` carries the spawn metadata 🟢🟡.** Spawn `tool_result` lines carry a sibling `toolUseResult` (not in `message.content`): `status` (`teammate_spawned`/`async_launched`), `model`, `team_name`, and a `tmux_session_name`/`tmux_window_name`/`tmux_pane_id` triple (always `"in-process"` here) plus `is_splitpane:false` — implying an out-of-process split-pane teammate mode exists but wasn't exercised in this corpus.

---

## 8. Compaction, summaries & session resume

Once a session (or a forked subagent) accumulates too many tokens, the harness **silently rewrites history**. None of this is visible to a naive line-counting model.

**`compact_boundary` + `compactMetadata` 🟢.** Anchor line: `type:"system"`, `subtype:"compact_boundary"`. The corpus has 4 (all inside subagent files, all `trigger:"auto"`):

| Field                                    |                            Example | Meaning                                                                                     |
| ---------------------------------------- | ---------------------------------: | ------------------------------------------------------------------------------------------- |
| `preTokens` → `postTokens`               |                    597,661 → 9,297 | a **95–98% token drop** every time                                                          |
| `durationMs`                             |                       115k–244k ms | compaction takes **2–4 minutes** — hidden, uncounted by any `turn_duration`                 |
| `preservedSegment`                       | `{headUuid, anchorUuid, tailUuid}` | the raw window kept verbatim                                                                |
| `preservedMessages.uuids` vs `.allUuids` |                             5 vs 6 | `.allUuids` always has one more — the **2nd** message in the window is the one dropped 🟢🟡 |

**The synthetic recap line (`isCompactSummary`) 🟢.** Right after the boundary comes a manufactured `user` line, flagged `isCompactSummary:true` + `isVisibleInTranscriptOnly:true`, whose `content` is a large model-written recap (fixed sections: _Primary Request, Key Technical Concepts, Files…, Errors and Fixes, … Optional Next Step_). Every instance ends with byte-identical boilerplate: _"…read the full transcript at: <path>. Continue… do not acknowledge the summary…"_

> This is a **third** `role:"user"` disguise beyond `tool_result` and `isMeta` — neither human nor tool. The "read the full transcript at" path is always the _top-level_ session file, even when compaction fired inside a subagent — the only cross-file pointer to fuller history.

**`logicalParentUuid` — the field that patches the broken chain 🟢.** At `compact_boundary`, `parentUuid` is `null` (the chain is deliberately cut). The bridge is `logicalParentUuid`, pointing at the last surviving pre-compaction line. It exists in **exactly** the 4 files that contain `compact_boundary` and **nowhere else**.

**A fork can compact _before doing any work_ 🟢.** Every `subagents/agent-*.jsonl` starts with a `fork-context-ref` line (`parentSessionId`, `parentLastUuid`, `contextLength`) — the fork **inherits the parent's history**. If that's already large, the fork's first act is to compact: the real sequence is `fork-context-ref → one user directive → compact_boundary (preTokens 197,644, 115 s)` with **zero** assistant/tool_use/turn_duration in between. That cost is invisible to any `turn_duration`/`requestId` accounting.

**`away_summary` — a _different_ resume line 🟢.** `subtype:"away_summary"` is a one-line "welcome back" recap on returning to an idle session — it does **not** rewrite history. It can itself become a turn's parent with no fresh human prompt (one real `turn_duration` of ~52 minutes chains straight off an `away_summary` whose trigger was an idle-notification from another teammate). It's distinct from `isCompactSummary`; both break the "nearest genuine user prompt" rule from §5.

---

## 9. The full `system` subtype catalog

A shallow read of the format usually builds everything on **one** of **eight** real `system` subtypes:

| subtype               | count | sits…                                    | role                                                                    |
| --------------------- | ----: | ---------------------------------------- | ----------------------------------------------------------------------- |
| `turn_duration`       |   479 | closes a turn                            | the hard anchor (§4.2)                                                  |
| `stop_hook_summary`   |   207 | between last assistant & `turn_duration` | reports Stop-hook(s); can _veto_ the stop (see below)                   |
| `away_summary`        |   181 | after a turn closed                      | idle "welcome back" recap (§8)                                          |
| `local_command`       |   112 | between turns                            | a client-side slash command; no model call                              |
| `api_error`           |    16 | inside a turn                            | transport failure + backoff retries                                     |
| `scheduled_task_fire` |     9 | opens a turn                             | a cron tick re-injecting a prompt, no human present                     |
| `compact_boundary`    |     4 | between turns                            | context compaction (§8)                                                 |
| `informational`       |     3 | inside/between                           | ad-hoc user nudges (`"Backgrounding after the current tool finishes…"`) |

There's also a **`level`** severity axis orthogonal to `subtype` (`info`/`warning`/`error`/`suggestion` — corpus: 208/116/16/3). Filter on `level`, not `subtype`, if what you want is "what needs attention."

**Stop hooks sit between the assistant and `turn_duration` 🟢.**

```json
{
  "subtype": "stop_hook_summary",
  "hookCount": 1,
  "hookInfos": [
    {
      "command": "python3 ~/.claude/scripts/wf-export.py --hook …",
      "durationMs": 193
    }
  ],
  "hookErrors": [],
  "hookAdditionalContext": [],
  "preventedContinuation": false,
  "level": "suggestion"
}
```

The "~0.2 s gap" from §4.4 **is the hook's own runtime**: final assistant line at `…14.137Z` → `stop_hook_summary` at `…14.333Z` (196 ms ≈ its `durationMs` 193) → `turn_duration` at `…14.335Z`. 🟡 `preventedContinuation` means a hook can _refuse_ to let the turn end (re-entering the loop) — so "model returned no more tool_use" is necessary but **not sufficient** to end a turn. (No `true` example appeared in this corpus.)

**`local_command` — a system pair that opens no turn 🟢.** Slash commands like `/config`, `/model`, `/fork` are two consecutive `system`/`local_command` lines (invocation + `<local-command-stdout>`), with no model call and no `turn_duration`. When scanning backward for a turn start, **skip these too**.

**`api_error` — the retries a `requestId` hides 🟢.**

```json
{
  "subtype": "api_error",
  "level": "error",
  "error": { "message": "Request timed out." },
  "retryInMs": 613.14,
  "retryAttempt": 1,
  "maxRetries": 10
}
```

One prompt produced 4 `api_error`s over ~61 minutes before the model responded — and **no `turn_duration` was ever written** for that turn. ⚠️ Version caveat: all 16 examples are from one v2.1.168 session; unconfirmed on current builds.

---

## 10. Identity fields & the tree topology

**It's a TREE, not a chain — and forks are common 🟢.** **655 / 1106** files (59.2%) contain a `parentUuid` referenced by ≥2 lines (5,271 branch points). The #1 cause is **not** prompt-editing: it's sequential `tool_use` content blocks. Blocks chain `text → tool_use#1 → tool_use#2`, but each block's `tool_result` _also_ parents off its own `tool_use` — so a non-last block gets a `tool_result` sibling competing with the next block for the same parent. Only one child is extended; the other becomes a **permanent childless leaf** with real tool output sitting in it. Naive single-child `parentUuid` walking drops tool output on roughly 6 of every 10 sessions.

**Two real fork fingerprints 🟢:**

1. **Session-resume fork** — resuming and typing a new prompt re-attaches to the last _checkpoint_ node (often a `system/away_summary`); resuming twice creates two divergent children of one parent, days apart.
2. **Queued-requeue fork** — a `promptSource:"queued"` prompt requeued after an error appears twice (same text, new `uuid`) before the real next prompt (new `promptId`, `promptSource:"typed"`) becomes its sibling.

There's no UI "edit" event anywhere in the JSON — forks come from ordinary resume/retry mechanics.

**`promptId` — the real turn key 🟢.** Every `user` line of one turn (prompt + all its `tool_result`s) shares one `promptId`; it's `null` on assistant lines. Turn membership is `group by promptId`, replacing the fragile backward walk from §5.

**`leafUuid` & `uuid`-less bookmarks 🟢.** `last-prompt`, `ai-title`, `mode`, `permission-mode`, `file-history-snapshot` carry **no `uuid`/`parentUuid`** — keyed only by `sessionId`. `last-prompt.leafUuid` names the tree-tip to resume from; `file-history-snapshot.messageId` aliases a real line's `uuid`.

**`parentUuid` is overloaded; `sourceToolAssistantUUID` disambiguates 🟢.** `parentUuid` means three different things depending on line type: the previous block of the same message / the `tool_use` a `tool_result` answers / the last thing seen before a fresh prompt. The harness ships a purpose-built field on every `tool_result` — **`sourceToolAssistantUUID`** (923/1107 files) — pointing at the originating `tool_use` line. Treat it (or the `tool_use_id ↔ block id` pair) as the canonical call↔result link; treat `parentUuid` as tree-position only.

**Metadata is a per-line snapshot 🟢.** `version`/`gitBranch`/`cwd` change **mid-file**: one session logged `2.1.185` then `2.1.186` fourteen minutes later (a CLI auto-update with no restart); 30 files carry ≥2 `gitBranch` values, one shows four transitions. **Read these fields from the specific line**, not once from line 1.

**Identity cheat-sheet:**

| Field                                          | Scope                                                   |
| ---------------------------------------------- | ------------------------------------------------------- |
| `uuid`                                         | this line                                               |
| `parentUuid`                                   | tree position (meaning varies by line type)             |
| `message.id` / `requestId`                     | one API call (1:1)                                      |
| `promptId`                                     | one logical turn                                        |
| `sessionId`                                    | the whole file                                          |
| `leafUuid` / `file-history-snapshot.messageId` | pointers _into_ the tree, for resume/rewind bookkeeping |

---

## 11. `toolUseResult`, spilled payloads, images & the attachment zoo

**`toolUseResult` — the structured twin of `message.content` 🟢.** `content` is what the **model** reads; `toolUseResult` (top-level, same line) is the harness's structured copy, shaped per tool:

| Tool           | `toolUseResult` shape                                                      |
| -------------- | -------------------------------------------------------------------------- |
| `Read` (text)  | `{type:"text", file:{filePath, content, numLines, startLine, totalLines}}` |
| `Read` (image) | `{type:"image", file:{base64, type, originalSize, dimensions:{…}}}`        |
| `Bash`         | `{stdout, stderr, interrupted, isImage, noOutputExpected}`                 |
| `SlashCommand` | `{success, commandName}`                                                   |

Some data lives **only** here — image pixel `dimensions`, `Read`'s `totalLines`, `Bash`'s `interrupted`. 280/1107 files carry it.

**Large payloads spill to `tool-results/` sidecars 🟢.** Big or binary results are written to `<sessionId>/tool-results/<tool_use_id>.txt` (or `webfetch-<ts>.pdf`) and referenced from the line: a WebFetch PDF's `tool_result` text literally says _"[Binary content (application/pdf, 749.9KB) also saved to …/tool-results/webfetch-….pdf]"_. 21 such folders exist, with files up to 3.35 MB. ⚠️ Not universal — a 2.4 MB PNG was inlined as base64 with **no** sidecar; the cutoff is a 🟡 size/type heuristic. One nuance worth knowing: the model-facing text copy carries `N\t` line-number prefixes (`cat -n` style); `toolUseResult.file.content` is the raw original.

**`isApiErrorMessage` — a fake assistant line 🟢.** On **terminal** API failure (rate-limit, billing, auth, bad model id) the harness fabricates an assistant line: `model:"<synthetic>"`, `isApiErrorMessage:true`, `stop_reason:"stop_sequence"`, human-readable `content` (_"You've hit your session limit…"_). 98 in corpus, across 6 error kinds. It's distinct from the transient `system/api_error` (which retries, §9). The tell: `model=="<synthetic>"`.

**`isMeta` and images 🟢.** `isMeta:true` is a harness-injected caveat wrapping local-command output (e.g. `<local-command-caveat>`), `role:"user"` — the second impostor after `tool_result`. 454 lines carry it. And there's a **fifth content-block type, `image`** (7 files): user-pasted (top-level, with a `[Image #1]` marker in the text block) or tool-produced (nested in a `tool_result.content` array). `file` attachments have two shapes: `content.type:"text"` (full body) vs `"file_unchanged"` (a cache-hit stub — a file-level analog of `cache_read_input_tokens`).

**The attachment zoo — 23 types, not 3 🟢:**

| `attachment.type`                                                                                                                                                |                             count | what                                                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------: | ------------------------------------------------------ |
| `skill_listing`                                                                                                                                                  |                              1128 | every installed skill's description, re-sent each turn |
| `deferred_tools_delta`                                                                                                                                           |                              1117 | newly-available deferred tool schemas                  |
| `task_reminder`                                                                                                                                                  |                               506 | current TaskList snapshot, injected mid-loop           |
| `mcp_instructions_delta`                                                                                                                                         |                               141 | MCP usage instructions                                 |
| `output_style`                                                                                                                                                   |                               137 | active style, e.g. `{"style":"Explanatory"}`           |
| `agent_listing_delta`                                                                                                                                            |                                84 | available subagent types                               |
| `command_permissions`                                                                                                                                            |                                82 | `{"allowedTools":[…]}`                                 |
| `hook_success` / `_non_blocking_error` / `_cancelled`                                                                                                            |                        75 / 7 / 1 | hook outcomes                                          |
| `queued_command`                                                                                                                                                 |                                71 | a command waiting to be delivered                      |
| `edited_text_file` / `nested_memory` / `diagnostics` / `file`                                                                                                    |                  58 / 43 / 36 / 3 | IDE & file signals                                     |
| `date_change`, `ultra_effort_*`, `ultrathink_effort`, `selected_lines_in_ide`, `opened_file_in_ide`, `workflow_keyword_request`, `plan_mode_exit`, `goal_status` | 19 / 14 / 2 / 10 / 22 / 4 / 1 / 1 | mode/session markers                                   |

**Slash commands: two families, one inconsistent wrapper 🟢.** A typed `/command` is an ordinary `type:"user"` line whose `content` is a **plain string** (not a block array) wrapped in `<command-name>/<command-message>/<command-args>`.

- **Built-ins** (`/clear`, `/model`): `command-name` first, 12-space-indented, empty `command-args`; the reply comes back as `<local-command-stdout>` on a line whose outer `type` is _inconsistent_ — `system/local_command` **or** plain `user` (corpus split: 106 user / 67 system / 18 assistant).
- **Skill-backed** (`/deep-research`, `/c3`, custom): reversed tag order, populated `command-args`, and the wrapper is immediately followed by a **second `isMeta:true` `user` line injecting the skill's file body** — _that_ line, not the wrapper, is the real prompt driving the loop.
- **`!`-bash mode**: a third channel entirely — `<local-command-caveat>` (isMeta) then `<bash-input>` / `<bash-stdout><bash-stderr>` lines, **no model round-trip**, and the bash lines carry **no `isMeta`** — another trap for the §5 filter.

---

## 12. Master list: everything wearing `role:"user"` that isn't a human prompt

A shallow read finds one impostor (`tool_result`). The audit found **seven**. A robust turn-start / "what did the human actually ask" filter must exclude **all** of these:

| #   | Impostor                       | How to detect                                                                  |
| --- | ------------------------------ | ------------------------------------------------------------------------------ |
| 1   | Tool result                    | `message.content[].type == "tool_result"` (also has `toolUseResult`)           |
| 2   | Harness caveat / injected text | `isMeta == true`                                                               |
| 3   | Post-compaction recap          | `isCompactSummary == true` (+ `isVisibleInTranscriptOnly`)                     |
| 4   | Background task/workflow ping  | content starts `<task-notification>`                                           |
| 5   | `!`-bash mode I/O              | content starts `<bash-input>` / `<bash-stdout>`                                |
| 6   | Slash-command stdout           | content starts `<local-command-stdout>` / `<local-command-caveat>`             |
| 7   | Another Claude session         | content starts `Another Claude session sent a message:` / `<teammate-message>` |

> ✅ **The clean signal that makes this whole list unnecessary:** `promptSource` (`typed`/`sdk`/`queued`/`suggestion_accepted` = has a human origin; **`system`** = harness-synthesized, no human present) and `origin.kind` (`human`/`task-notification`/`coordinator`). A turn can open with **no human action at all** — a `scheduled_task_fire` re-injects the prompt verbatim with `promptSource:"system"`. Prefer `promptSource`/`origin` over string-sniffing whenever the field is present.

---

## Sources

- Stop reasons & the tool-use loop, and prompt caching & usage fields — official Anthropic API docs.
- A community JSONL reference (deepwiki `simonw/claude-code-transcripts`) was checked too, but it only covers `summary`/`user`/`assistant`/`file-history-snapshot` — no `system` lines at all.
- The `@internal` `turn_duration` doc string was extracted directly from the shipped CLI binary.
- **Ground truth for everything tagged 🟢**: 1,107 real `.jsonl` transcripts under `~/.claude/projects`, spanning CLI versions 2.1.168 → 2.1.197.
