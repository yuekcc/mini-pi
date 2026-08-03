# Transcript 会话记录格式规范

> 状态：设计共识（2026-08-03 grill-me 会话产出）
> 目的：支撑 **resume session（恢复会话）** 与 **审计（audit）**

---

## Problem Statement

mp 目前没有任何会话持久化机制：

- 会话数据只活在内存 `Context.messages` 里，进程退出即丢失。长会话（如多轮调试）一旦被中断/崩溃，只能重新开一个会话从头再来，模型上下文和历史决策全部作废。
- 审计无从谈起：`usage`（token/成本）、`finish_reason`、模型 ID、工具调用延迟等关键数据在 `api.c3` 解析层就被丢弃；`logs/req_*.json` 只是 `--debug` 下的 per-request 转储，无会话分组、无顺序关联、无结构性。
- 现有 `/export` 只产出人类可读 Markdown，不可机器解析，无法支撑恢复与审计。

## Solution

mp 每个会话默认写一份结构化 transcript：**JSONL 文件，每事件一行，发生即追加落盘**，存放于 `<config_dir>/transcripts/<session_id>.jsonl`。

- **7 类事件**：`session_start` / `user_message` / `assistant_message` / `tool_result` / `api_usage` / `system_event` / `session_end`。
- **双键贯穿**：`turn_id`（一轮的标识）+ `request_id`（一次 API round-trip 的标识），所有事件携带，是 turn 分组与审计关联的基础。
- **resume 保真**：`session_start` 快照完整 system prompt 字符串（装配产物）+ 装配输入（cwd/日期/工具列表），`--resume <session_id>` 时原样回放。
- **默认常开**，`--no-transcript` 显式关闭（敏感场景整文件关闭）。

## User Stories

1. 作为交互用户，我想在会话被中断/崩溃后用 `mp --resume <session_id>` 恢复会话，以便不丢失已完成的推理和工具执行，从断点继续工作。
2. 作为交互用户，我想在跨天继续同一个长会话，以便在多日任务中保持上下文连续性。
3. 作为交互用户，我想在 resume 后看到与中断前完全一致的模型行为（同样的 system prompt、同样的历史消息），以便恢复的会话与原有会话无缝衔接。
4. 作为交互用户，我想明确知道当前会话中断的尾巴 turn 会被丢弃重来，以便不困惑于为什么最后一个不完整的回复消失了。
5. 作为 headless 调用方，我想让 Task 工具递归 spawn 的子进程也写自己的 transcript，以便子代理的行为可审计、可恢复。
6. 作为审计者，我想查看一次会话的 token 消耗（prompt/completion/reasoning 分开统计），以便核算成本。
7. 作为审计者，我想知道每次 API 调用的耗时，以便定位慢请求。
8. 作为审计者，我想查看每个工具调用「模型当时实际看到」的输入与输出，以便还原模型做决策的依据。
9. 作为审计者，我想在需要时找到工具输出的原始完整内容（如被截断的 bash 输出），以便做深度排查。
10. 作为审计者，我想查看模型当时的完整 system prompt（含 AGENTS.md 快照、工具列表），以便确认模型被赋予了哪些指令。
11. 作为审计者，我想定位 API 错误与重试事件，以便排查稳定性问题。
12. 作为开发者，我想查看模型每轮的 thinking（reasoning）与最终回复，以便调试模型行为。
13. 作为用户，我想用 `--no-transcript` 关闭记录，以便在敏感场景下不留痕迹。
14. 作为审计者，我想顺着 `parent_session_id` 找到某个 Task 子代理对应的父会话，以便还原子代理树的调用关系。
15. 作为开发者，我想在 `/clear` 之后仍然知道原会话与新会话的对应关系，以便追溯。
16. 作为开发者，我想让 transcript 文件是纯文本可 `tail`/`grep` 的，以便不依赖专用工具就能快速排查。

## Implementation Decisions

### 新模块：`src/transcript.c3`

事件序列化与追加写盘模块。职责：

- 以追加模式打开 `<config_dir>/transcripts/<session_id>.jsonl`（首次写时创建）。
- 提供事件写入入口，每个事件序列化为单行 JSON 立即落盘（不缓冲、不批量）。
- 提供 `session_end` 收尾（进程正常退出 / 崩溃前的 finally 路径）。
- 使用现有 `cjson` 库构建 JSON；不引入新依赖。

### 事件 JSON Schema（v1）

所有事件公共字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| `version` | ✅ | schema 版本，固定 `1` |
| `type` | ✅ | 事件类型（下见 7 类） |
| `session_id` | ✅ | 本文件所属会话 |
| `turn_id` | ✅ | 所属轮次标识（该轮 user 消息的 timestamp_id） |
| `request_id` | 条件 | 仅 assistant_message / tool_result / api_usage 必有；user_message 为 null |
| `timestamp` | ✅ | ISO 8601 本地时间 |

> 设计取舍：不设 `uuid`/`parentUuid`（线性模型不需要）；**每事件独立完整**（含 session_id/version），保证未来加 fork 时无需迁移旧文件——届时新增 `parentUuid` 字段即可。

**1. `session_start`** — 会话创建时写一条：

```json
{
  "version": 1, "type": "session_start", "session_id": "ses_20260705_153242",
  "timestamp": "...", "turn_id": null,
  "model": "deepseek-r1", "agent": "default",
  "cwd": "/path/to/project",
  "system_prompt": "<完整装配后的 system prompt 字符串>",
  "assembly": {"date": "...", "os": "Windows 11 + Bash", "tools": ["ReadFile", "Bash", "..."]},
  "parent_session_id": null, "parent_request_id": null
}
```

- `system_prompt` = 装配产物，resume 时原样回放（A 方案，保真第一）。
- `assembly` = 装配输入快照，供审计理解（不含 AGENTS.md 内容，避免冗余；需要时从 cwd 现场读）。
- `parent_session_id`/`parent_request_id`：Task 工具 spawn 子进程时，通过环境变量 `MP_PARENT_SESSION`（格式 `父session_id:父request_id`）注入，子进程读取写入。

**2. `user_message`** — 用户输入落盘（含斜杠命令，但标记 `is_command`）：

```json
{
  "version": 1, "type": "user_message", "session_id": "...", "turn_id": "20260705_153242",
  "request_id": null, "timestamp": "...",
  "content": "请帮我修复这个 bug", "is_command": false
}
```

**3. `assistant_message`** — 每次模型回复落盘：

```json
{
  "version": 1, "type": "assistant_message", "session_id": "...", "turn_id": "...",
  "request_id": "20260705_153245", "timestamp": "...",
  "content": "我来看看这个文件…", "reasoning_content": "...",
  "tool_calls": [{"id": "call_1", "name": "ReadFile", "arguments": "{\"filePath\":\"src/main.c3\"}"}]
}
```

- 字段与 `Message` 结构一一对应，resume 时直接重建 assistant 消息。
- 每条 assistant 消息 = 一次 API 调用，其 `request_id` 即为该次 `completions()` 生成的 timestamp_id。

**4. `tool_result`** — 工具执行完落盘：

```json
{
  "version": 1, "type": "tool_result", "session_id": "...", "turn_id": "...",
  "request_id": "...", "timestamp": "...",
  "tool_call_id": "call_1", "name": "Bash",
  "arguments": "{\"cmd\":\"ls -la\"}",
  "output": "<模型实际看到的内容（截断/加工后，与 role=tool 消息完全一致）>",
  "output_file": "task_store/20260705_153246_output.txt",
  "duration_ms": 1234, "exit_code": 0
}
```

- **`output` = 模型所见**，resume 才能逐字节重建 `role=tool` 消息；`output_file` 可选，指向原始完整输出（如 Bash 截断前的完整 stdout）。
- `exit_code` 仅 Bash 类工具有值。

**5. `api_usage`** — 每次 API 调用结束落盘：

```json
{
  "version": 1, "type": "api_usage", "session_id": "...", "turn_id": "...",
  "request_id": "...", "timestamp": "...",
  "usage": {"prompt_tokens": 8436, "completion_tokens": 478, "reasoning_tokens": 512},
  "latency_ms": 54084, "model": "deepseek-r1", "finish_reason": "tool_calls"
}
```

- 审计成本/延迟的核心事件。
- **硬前置**：`usage`/`finish_reason` 目前在 `api.c3` 解析层被丢弃，实现时必须在流式解析（`read_stream_to_message`）与响应解析（`read_response_to_message`）中捕获并上抛给调用方。注意流式模式下 usage 可能在终止 chunk 中。

**6. `system_event`** — 异常与特殊事件：

```json
{
  "version": 1, "type": "system_event", "session_id": "...", "turn_id": "...",
  "request_id": "...", "timestamp": "...",
  "subtype": "api_error", "level": "error",
  "detail": {"message": "Request timed out.", "retry_attempt": 1, "retry_in_ms": 613}
}
```

- `subtype` 取值：`api_error`（含重试信息）、`local_command`（斜杠命令 stdout）、`resume`（resume 标记，记录来源 session 与重建的 turn 范围）、`compact_boundary`（**仅预留占位，v1 不实现**）。

**7. `session_end`** — 会话关闭：

```json
{
  "version": 1, "type": "session_end", "session_id": "...", "turn_id": "...",
  "request_id": null, "timestamp": "...",
  "reason": "exit" | "error" | "interrupted", "turns_total": 12
}
```

### 写入钩子位置

- `rat_loop.c3`：语义事件（session_start / user_message / assistant_message / tool_result / session_end）在循环各节点写入；turn 起点 = 交互读入或 headless 初始任务；`/clear` 后新 session_id → 新 transcript 文件。
- `api.c3`：`completions()` 结束后写 `api_usage`（顺带复用其已生成的 request_id）；捕获 `api_error` 写 `system_event`。
- `main.c3`：`--resume` 时先重建再进循环。

### resume 流程（`--resume <session_id>`）

1. 打开 `<config_dir>/transcripts/<session_id>.jsonl`。
2. 读 `session_start`，取 `system_prompt` 快照 → 作为 `messages[0]`（**不重新装配**，A 方案）。
3. 依序过滤 user_message / assistant_message / tool_result 事件，重建 Message 数组：
   - user_message → `role=user`（`is_command=true` 的跳过，不重建）
   - assistant_message → `role=assistant`（content + reasoning_content + tool_calls）
   - tool_result → `role=tool`（content=output，tool_call_id 回链）
4. **丢弃最后一个未收尾 turn**（该 turn 最后一条 assistant 仍带 tool_calls，即被中断）。
5. 重建完成后进入交互循环正常继续。
6. 冲突规则：`--resume` 与 `--task` / `--task-file` 互斥，同时出现报错退出。
7. headless 模式允许 `mp --headless --resume <id> -t "继续任务"`（Task 子进程续跑场景）。

### CLI 变更

- 新增 `--resume <session_id>`（见上）。
- 新增 `--no-transcript`：关闭本会话 transcript 写入（子进程也继承关闭语义时，同样传递环境变量标记）。
- `/resume` 斜杠命令（会话列表选择续跑）：**v1.1 后置**，不进 v1。

### 文件与权限

- 路径：`<config_dir>/transcripts/<session_id>.jsonl`（`config_dir` 默认 `~/.config/mp/`）。
- 追加模式打开，每事件立即 flush 落盘（崩溃安全）。
- 权限对齐 config_dir 默认策略（Unix 下 700/600 语义），与 `log/` 平级。
- transcript 目录不应被 git 追踪（与现有 `logs/req_*.json` 一致，`--debug` 转储保留不动）。

## Testing Decisions

### 测试接缝（seam）

推荐**单接缝：进程级集成测试**——以 headless 方式完整跑一次 mp 会话，断言落盘的 `.jsonl` 文件内容。理由：transcript 的价值在「完整会话的可恢复性与可审计性」，单元测序列化函数只能证明格式对，测不出生命周期与重建正确性；进程级 seam 是能同时覆盖两者的最高层接缝。

两类用例：

1. **结构正确性**：`mp --headless --task "..."` 跑完后读 transcript 文件，断言：
   - 首行 `session_start`、末行 `session_end`，中间事件类型序列符合生命周期（user → assistant → (tool_result → assistant)* → user …）；
   - 所有事件含 `session_id`/`version`/`timestamp`；assistant/tool_result/api_usage 的 `request_id` 连续可关联；
   - 同一 turn 内 `turn_id` 一致，跨 turn 不同；
   - `api_usage.usage` 非零且字段齐全（验证 usage 捕获链路）。
2. **resume roundtrip**：跑完会话 A（transcript 存盘）→ `mp --resume <A> --headless -t "继续"` 跑完会话 B → 断言 B 的 transcript 中重建的消息序列与 A 末尾一致（模型所见逐字节相同），且 B 的 `turn_id` 从 A 之后续号。

### 单元级补充

- `transcript.c3` 序列化函数：给定结构化事件 → 断言单行 JSON 字段齐全、可被 `cjson` 反解析。
- resume 重建函数：构造含中断尾巴 turn 的 transcript → 断言重建后该 turn 被丢弃。

### 现有先例

- 沿用 `test/` 目录下现有 15 个测试文件的风格（`c3c test`，`--test-filter` 单测调试）。
- 进程级用例放在 `test/` 中与集成测试同级，或独立 `test/integration/`，视现有组织方式归位。

## Out of Scope

- **上下文压缩 / token 预算管理**（明确不做；`compact_boundary` 仅预留事件占位）。
- **fork 支持**：不实现树结构；格式设计保证未来可加 `parentUuid` 而不迁移旧文件。
- `/resume` 斜杠命令（v1.1）。
- inspect 工具 / 审计 UI / 统计报表导出（只写 spec，不做工具）。
- 选择性脱敏（隐私场景用 `--no-transcript` 整文件关闭）。
- transcript 加密。
- `gitBranch`、agent 角色快照之外的元数据扩展。

## Further Notes

- **usage 捕获是硬前置**：`api.c3` 现在丢弃 `usage`/`finish_reason`，这是实现第一步，否则 `api_usage` 事件为空壳。
- 与 `logs/req_*.json`（`--debug` 转储）的关系：保留不动，transcript 是规范记录，两者互补（debug 转储看请求级原始报文，transcript 看会话级语义流）。
- 与 `/export` Markdown 的关系：export 继续作为人类可读视图；transcript 是机器可解析的规范数据，两者不合并。
- 超长会话：transcript 逐行追加、resume 全量重放；无压缩意味着超长会话 resume 时 messages 可能逼近 API 上下文上限——这是「不做 compaction」的已知代价，v1 接受。
- `reasoning_content` 字段名沿用现有 `Message` 结构（DeepSeek 兼容），resume 重建时原样保留；若未来 API 层改用标准 `reasoning` 字段，transcript 字段名跟随 `Message` 结构演进（version 号递增）。
