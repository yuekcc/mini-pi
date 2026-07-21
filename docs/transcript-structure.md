# Claude Code Transcript (JSONL) 结构分析

> 分析样本：`docs/transcript-demo.jsonl`（199 行，约 0.4MB）
> 来源：Claude Code v2.8.3 会话记录

## 概述

Transcript 是一个 **JSONL 文件**（每行一个 JSON 对象），按时间顺序记录一次会话中的所有事件。每个对象有一个 `type` 字段标识事件类型。

### 事件类型分布

| type | 数量 | 说明 |
|------|------|------|
| `assistant` | 113 | AI 响应（思考/文本/工具调用） |
| `user` | 60 | 用户输入（纯文本 或 工具执行结果） |
| `file-history-snapshot` | 10 | 文件历史快照（用于 undo/restore） |
| `system` | 7 | 系统事件（缓存警告、耗时统计等） |
| `attribution-snapshot` | 6 | 归因快照（prompt/权限计数） |
| `mode` | 2 | 会话模式声明 |
| `last-prompt` | 1 | 最后一条用户 prompt（用于会话恢复） |

---

## 消息链结构

所有 `user`/`assistant`/`system` 消息通过 **`parentUuid` → `uuid`** 构成链表/树：

```
user(null) → assistant → user(tool_result) → assistant → user(tool_result) → ... → assistant(end_turn)
```

- `parentUuid: null` — 会话根节点（第一条用户消息）
- `isSidechain: false` — 本样本无侧链（子 agent 对话会标记为 `true`）

---

## 各类型详细结构

### 1. `mode` — 会话模式

```json
{
  "type": "mode",
  "mode": "normal",
  "sessionId": "2308e478-..."
}
```

出现在会话开头（和模式切换时）。`mode` 值如 `normal`。

---

### 2. `user` — 用户消息

#### 2a. 纯文本输入

```json
{
  "parentUuid": null,
  "isSidechain": false,
  "promptId": "fd4f2029-...",
  "type": "user",
  "message": {
    "role": "user",
    "content": "cjson 模块，是否可以直接设置使用 c3 的内存分配器？"
  },
  "uuid": "46ca8b85-...",
  "timestamp": "2026-07-11T05:07:41.701Z",
  "permissionMode": "default",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "Z:\\projects\\mini_pi",
  "sessionId": "2308e478-...",
  "version": "2.8.3",
  "gitBranch": "main"
}
```

- `message.content` 为 **字符串** — 用户直接输入的文本
- `promptId` — 关联到发起的 prompt
- `permissionMode` — 权限模式（`default`）
- `parentUuid: null` — 标识为会话根

#### 2b. 工具执行结果（tool_result）

```json
{
  "parentUuid": "d357c89e-...",           // 指向触发工具调用的 assistant 消息
  "isSidechain": false,
  "promptId": "fd4f2029-...",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "call_9c9cd7a9a6f1442594f534d6",
        "type": "tool_result",
        "content": [
          { "type": "text", "text": "API Error: 400 {...}" }
        ]
      }
    ]
  },
  "uuid": "30fdba93-...",
  "timestamp": "2026-07-11T05:08:02.134Z",
  "toolUseResult": "{\"status\": \"completed\", \"prompt\": \"...\"}",
  "sourceToolAssistantUUID": "d357c89e-...",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "Z:\\projects\\mini_pi",
  "sessionId": "2308e478-...",
  "version": "2.8.3",
  "gitBranch": "main"
}
```

- `message.content` 为 **数组**，包含 `tool_result` 块
- `tool_result.content` 可以是：
  - 字符串（`"string"` 形式，56 次）
  - 数组 `[{type:"text", text:"..."}]`（1 次）
- `toolUseResult` — 原始工具调用的输入参数（JSON 字符串），用于审计/回放
- `sourceToolAssistantUUID` — 触发此工具调用的 assistant 消息 UUID

---

### 3. `assistant` — AI 响应

```json
{
  "parentUuid": "46ca8b85-...",
  "isSidechain": false,
  "message": {
    "id": "8e752add53c34f52a6b72b132dcd6f51",
    "type": "message",
    "role": "assistant",
    "model": "LongCat-2.0",
    "content": [
      { "type": "thinking", "thinking": "...", "signature": "" },
      { "type": "text", "text": "..." },
      { "type": "tool_use", "id": "call_...", "name": "Bash", "input": {...} }
    ],
    "stop_reason": "tool_use",
    "stop_sequence": null,
    "usage": { ... }
  },
  "type": "assistant",
  "uuid": "4dea1436-...",
  "timestamp": "2026-07-11T05:07:55.363Z",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "Z:\\projects\\mini_pi",
  "sessionId": "2308e478-...",
  "version": "2.8.3",
  "gitBranch": "main",
  "slug": "dreamy-kindling-planet"
}
```

#### content 块类型（3 种）

| 块类型 | 数量 | 结构 |
|--------|------|------|
| `tool_use` | 57 | `{type, id, name, input}` |
| `thinking` | 44 | `{type, thinking, signature}` |
| `text` | 12 | `{type, text}` |

#### 工具调用（tool_use）

```json
{
  "type": "tool_use",
  "id": "call_9c9cd7a9a6f1442594f534d6",
  "name": "Bash",
  "input": { "command": "...", "description": "...", "timeout": 120000 }
}
```

本样本中出现的工具及输入字段：

| 工具名 | 次数 | input 字段 |
|--------|------|-----------|
| `Bash` | 33 | `command`, `description`, `timeout` |
| `Read` | 15 | `file_path`, `limit`, `offset` |
| `Edit` | 7 | `file_path`, `old_string`, `new_string`, `replace_all` |
| `Agent` | 1 | `description`, `prompt`, `subagent_type` |
| `AskUserQuestion` | 1 | `questions` |

#### usage 结构

```json
{
  "input_tokens": 22582,
  "cache_creation_input_tokens": 0,
  "cache_read_input_tokens": 0,
  "output_tokens": 338,
  "server_tool_use": { "web_search_requests": 0, "web_fetch_requests": 0 },
  "service_tier": "standard",
  "cache_creation": { "ephemeral_1h_input_tokens": 0, "ephemeral_5m_input_tokens": 0 },
  "inference_geo": "",
  "iterations": [],
  "speed": "standard"
}
```

#### stop_reason

| 值 | 次数 | 含义 |
|----|------|------|
| `tool_use` | 40 | 因调用工具而暂停 |
| `end_turn` | 3 | 正常结束本轮 |
| `null` | 70 | 流式中间块（未结束） |

---

### 4. `system` — 系统事件

```json
{
  "parentUuid": "...",
  "isSidechain": false,
  "type": "system",
  "subtype": "cache_warning",
  "level": "warning",
  "content": "Cache hit rate 52%, below 80% threshold",
  "timestamp": "...",
  "uuid": "...",
  "isMeta": false,
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "...",
  "sessionId": "...",
  "version": "2.8.3",
  "gitBranch": "main"
}
```

#### subtype 种类

| subtype | 次数 | 特有字段 | 说明 |
|---------|------|---------|------|
| `cache_warning` | 2 | `level: "warning"` | 缓存命中率低于阈值 |
| `turn_duration` | 2 | `durationMs`, `messageCount` | 一轮对话耗时统计 |
| `informational` | 1 | — | 信息提示（如 auto mode 说明） |
| `memory_saved` | 1 | `writtenPaths: [...]` | 记忆已保存到文件 |
| `away_summary` | 1 | — | 离开后返回时的上下文摘要 |

- `isMeta: false` — 本样本无 meta 消息（meta 消息不展示给用户）

---

### 5. `attribution-snapshot` — 归因快照

```json
{
  "type": "attribution-snapshot",
  "messageId": "887e91f3-...",
  "surface": "cli",
  "fileStates": {},
  "promptCount": 1,
  "promptCountAtLastCommit": 0,
  "permissionPromptCount": 0,
  "permissionPromptCountAtLastCommit": 0,
  "escapeCount": 0,
  "escapeCountAtLastCommit": 0
}
```

追踪会话的 prompt 计数、权限提示计数、ESC 按下计数，以及与上次 commit 的差值。`fileStates` 记录文件变更归因。

---

### 6. `file-history-snapshot` — 文件历史快照

```json
{
  "type": "file-history-snapshot",
  "messageId": "46ca8b85-...",
  "snapshot": {
    "messageId": "46ca8b85-...",
    "trackedFileBackups": {},
    "timestamp": "2026-07-11T05:07:41.611Z"
  },
  "isSnapshotUpdate": false
}
```

在用户消息前后拍摄文件状态快照，`trackedFileBackups` 记录被修改文件的备份路径，支持 undo/restore。本样本中 `trackedFileBackups` 为空（会话中未修改文件或未触发备份）。

---

### 7. `last-prompt` — 最后 prompt

```json
{
  "type": "last-prompt",
  "lastPrompt": "增加一个 init_hooks，让 cjson 可以使用 c3 的 mem 内存分配器",
  "sessionId": "2308e478-..."
}
```

会话末尾记录最后一条用户输入，用于会话恢复。

---

## 公共字段汇总

以下字段在 `user`/`assistant`/`system` 三类消息中通用：

| 字段 | 类型 | 说明 |
|------|------|------|
| `uuid` | string | 本条目唯一 ID |
| `parentUuid` | string\|null | 父消息 UUID，构成对话链 |
| `isSidechain` | bool | 是否为子 agent 侧链 |
| `timestamp` | string (ISO 8601) | 事件时间 |
| `sessionId` | string | 会话 ID |
| `userType` | string | 用户类型（`external`） |
| `entrypoint` | string | 入口（`cli`） |
| `cwd` | string | 工作目录 |
| `version` | string | Claude Code 版本 |
| `gitBranch` | string | 当前 Git 分支 |
| `slug` | string | 会话 slug（人类可读标识，如 `dreamy-kindling-planet`） |

---

## 对话流示例

```
[mode]              mode=normal
[attribution]       promptCount=1
[file-history]      snapshot (empty)
[user]              "cjson 模块，是否可以直接设置使用 c3 的内存分配器？"  (parentUuid=null)
[assistant]         thinking → tool_use(Agent)  (stop_reason=tool_use)
[user]              tool_result(Agent → error)  (parentUuid=assistant)
[assistant]         thinking → tool_use(Bash)   (stop_reason=tool_use)
[user]              tool_result(Bash → output)  (parentUuid=assistant)
[assistant]         thinking → tool_use(Read)
[user]              tool_result(Read → content)
...
[assistant]         text("分析结论...")  (stop_reason=end_turn)
[system]            turn_duration (durationMs=443491, messageCount=178)
[system]            memory_saved (writtenPaths=[...])
[system]            away_summary
[last-prompt]       "增加一个 init_hooks..."
```

---

## 对 mini_pi 的借鉴价值

当前 mini_pi 的 `context.c3` 管理 Context/Message/ToolCall 结构。Claude Code transcript 的设计有以下值得参考的点：

1. **`parentUuid` 链表结构** — 比 mini_pi 当前的线性数组更适合支持分支/侧链
2. **content 块数组** — 一条 assistant 消息可包含 thinking + text + 多个 tool_use，比单字段更灵活
3. **`toolUseResult` 冗余字段** — 在 user 消息上同时存原始工具输入和执行结果，便于审计回放
4. **usage 完整记录** — 包含 cache 读写、service_tier、speed 等，对成本分析有价值
5. **system 事件** — cache_warning / turn_duration / away_summary 等，是 mini_pi `log.c3` 可借鉴的维度
6. **attribution-snapshot** — prompt/permission 计数与 commit 差值，对操作审计有意义
