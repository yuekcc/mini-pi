# mp 2.0.0 架构重构开发规格

> 依据：[arch-next.md](arch-next.md)（方案定稿，OQ-1~OQ-7 全部决议）。本规格面向实施，是 arch-next.md 的可执行细化。
> 基线版本 1.0.0 → 目标版本 2.0.0（架构分水岭，对外行为保持兼容）。

## Problem Statement

v1 的 mp 是一个单线程命令行 coding agent。使用者（交互用户、headless 自动化、Task 子代理）遇到三类问题：

1. **无法中断**：`rat_loop` 中 API 请求直接阻塞在 libcurl 的 `easy_perform`，工具（Bash）执行同样阻塞。请求进行中按 Ctrl+C 只能杀死整个进程——transcript 留下半截 turn，工作上下文丢失，无法优雅停止。
2. **token 不可感知**：每次请求的 usage 被解析后只写入 transcript 的 `api_usage` 事件，没有会话级累计、没有预算、没有阈值告警。使用者无法感知上下文窗口逼近上限，未来 compaction 也没有数据基础。
3. **演进受阻**（开发者视角）：全局状态散落在五处（tlocal GlobalStore、Context、tlocal 日志文件、无状态 transcript 函数、skill 预留全局变量）；UI 渲染与 Agent 逻辑耦合在同一调用栈；API 层混杂 HTTP、transcript 副作用与 global 依赖。新增子系统无处安放，改造牵一发动全身。

## Solution

把 mp 改造为「一个 AppContext 管全局 + 三线程可中断」的架构：

- **统一 AppContext**：配置、会话状态、工具/技能 hub、token 账本、transcript、日志、取消信号统一挂载在一个对象上，一处初始化、一处持有、按所有权分区访问。删除 tlocal 全局单例。
- **三线程模型**：UI/UX 在主线程，Agent loop 独立线程，API 调用独立 worker 线程。核心收益是 **Ctrl+C 可中断**：进行中的 HTTP 请求被干净取消，长工具执行可杀子进程，进程保持存活回到输入提示。
- **Token 账本与预算**：会话级累计（prompt/completion/reasoning），可配置上下文窗口上限与软/硬阈值，超软阈值告警。
- **行为兼容**：CLI 参数、transcript 事件 schema（v1）、`--resume`、Task 子代理机制、hashline/HashEditFile 全部保持不变。

## User Stories

1. 作为交互用户，我想在模型响应进行中按 Ctrl+C 中断请求，以便不必等待一个缓慢或跑偏的回复。
2. 作为交互用户，我想中断后进程保持存活并回到输入提示，以便立即提出新问题而不是重启会话。
3. 作为交互用户，我想被中断的请求在 transcript 中留下 `request_cancelled` 标记（含 request_id 与已消耗时长），以便事后审计知道哪里被打断。
4. 作为交互用户，我想长 Bash 命令执行时按 Ctrl+C 杀死子进程，以便停止失控的脚本。
5. 作为交互用户，我想中断后会话上下文不包含半截 turn（无半截 assistant 消息、无 tool_result），以便后续回复不受污染。
6. 作为交互用户，我想空闲时按 Ctrl+C 或 `/exit` 优雅退出，以便得到合法的 `session_end` 记录。
7. 作为交互用户，我想在会话中查看累计 token 用量，以便了解消耗。
8. 作为交互用户，我想在逼近上下文窗口上限时收到告警，以便及时 `/clear` 或新开会话。
9. 作为交互用户，我想多线程重构后终端输出仍完整、不交错，以便正常阅读模型回复与日志。
10. 作为交互用户，我想中断时 UI 给出明确的 `(interrupted)` 提示，以便知道请求是被取消而非模型自然结束。
11. 作为交互用户，我想模型回复的渲染方式与 v1 一致（一次性整段渲染），以便阅读体验不因重构改变。
12. 作为交互用户，我想 `/clear` 仍会收尾旧会话（`session_end(interrupted)`）并开启新 session，以便多线程下行为与 v1 一致。
13. 作为交互用户，我想工具执行的折叠预览等 UI 细节与 v1 一致，以便不感知重构。
14. 作为 headless 用户，我想按 Ctrl+C 时优雅停机（取消请求、写 `session_end(reason=interrupted)`、退出码非零），以便 CI 流水线能区分中断与正常完成。
15. 作为 headless 用户，我想 headless 下 API 错误仍按 v1 语义直接退出，以便自动化脚本行为不变。
16. 作为 Task 子代理，我想父会话关联（`MP_PARENT_SESSION`）机制不变，以便子代理树在 transcript 中完整还原。
17. 作为 Task 子代理，我想 headless 续跑（`--headless --resume <id> -t "继续"`）仍然工作，以便长任务链继续可用。
18. 作为 `--resume` 用户，我想 v1 的 transcript 文件仍可恢复（包括被中断的会话），以便跨版本续跑。
19. 作为 `--resume` 用户，我想恢复时丢弃未收尾 turn 的语义不变，以便中断后的 resume 行为一致。
20. 作为重度用户，我想用 `--max-tokens <n>` 配置预算上限，以便防止意外超限。
21. 作为 `--no-transcript` 用户，我想关闭落盘的行为不变，以便隐私场景继续可用。
22. 作为维护者，我想全局状态不再经 tlocal 单例访问，以便新增子系统有明确挂载点。
23. 作为维护者，我想 transcript 全部事件只在一个线程（Agent）写，以便无需锁且事件顺序确定。
24. 作为维护者，我想日志文件在多线程下每行完整、无交错字节，以便排查多线程问题。
25. 作为维护者，我想任何退出路径（`/exit`、headless 完成、Ctrl+C）都无 hang、无孤儿线程，以便进程干净结束。
26. 作为维护者，我想 API 请求体由 Agent 线程序列化快照后投递，worker 不读共享消息列表，以便杜绝锁竞争与指针失效。
27. 作为维护者，我想工具执行永远串行，以便行为确定、无并发编辑风险（永久承诺）。
28. 作为维护者，我想技能与工具 hub 初始化后只读访问、schema 预计算，以便无锁且启动开销一次付清。
29. 作为维护者，我想阶段 0 重构后 transcript 与 v1 逐字节一致（golden diff），以便行为兼容有回归护栏。
30. 作为维护者，我想每个实施阶段独立可编译、可测试、可发布，以便渐进迁移、不出现大爆炸式重构。
31. 作为维护者，我想取消延迟有上限（100ms 级），以便中断响应及时。
32. 作为维护者，我想 Agent 线程空闲时零 CPU 占用（阻塞在通道上而非忙等），以便后台等待时不浪费资源。

## Implementation Decisions

1. **版本与兼容承诺**：目标版本 2.0.0（线程模型是内部破坏性变化）。CLI 参数全集不变（仅新增可选的 `--max-tokens`）；transcript 事件 schema v1 不变（新增 subtype 为 additive）；`MP_PARENT_SESSION` 子代理协议不变；hashline/HashEditFile 算法不变；`--resume` 恢复语义不变（快照 system prompt + 丢尾部未收尾 turn）。

2. **AppContext 统一**（取代 tlocal GlobalStore 单例）。字段按所有权分为四区：
   - **配置区**（初始化后只读）：Flag 拷贝（不再传 `Flag*`）、allocator、cwd、config_dir；
   - **会话状态区**（仅 Agent 线程写）：session_id、messages、turns_total、started_at/updated_at、resumed 标记；
   - **资源区**（初始化后只读）：ToolHub/SkillHub 指针、system_prompt_snapshot、tools_schema_json（schema_cache 预计算产物）；
   - **子系统与信号区**：TokenLedger、TranscriptWriter、Logger、atomic cancel_flag、线程句柄。
   
   共享可变原语只有两处：`cancel_flag`（atomic）与 Logger 文件句柄（内部 mutex）。其余要么只读、要么单写者。tlocal 全局单例删除，启动引导改由 main 显式传参。

3. **TokenLedger**（新增子系统）。类型形状（来自设计定稿，决策富集部分）：
   ```
   TokenUsage { prompt_tokens; completion_tokens; reasoning_tokens }
   TokenLedger { session_total; turn_total; last_request; history;
                 context_window_limit; soft_ratio(默认 0.8); hard_ratio(默认 0.95) }
   ```
   接口语义：`record()` 累计会话/本轮/最近一次请求并留最近 N 条明细；`check_budget()` 返回三态判定 OK / WARN / EXCEEDED。WARN → 写 `system_event(token_warning)` + UI 状态行提示；EXCEEDED → 拒绝继续请求并提示（v1 范围只实现到 WARN 的落盘与展示，compaction 预留）。数据来源不变：API worker 回报 usage，Agent 记账并写 `api_usage` 事件。新增 CLI `--max-tokens <n>`（0 = 不启用）。

4. **TranscriptWriter 对象化**：持有 allocator / session_id / enabled 标志；方法签名不再散传 session_id；全部事件写入**只在 Agent 线程发生**（UI 线程把输入/命令事件转发给 Agent 后由 Agent 落盘），写点线程唯一、无需锁。`--no-transcript` 时内部全 no-op。事件 schema v1 不变；新增 `system_event` subtype：`request_cancelled`（detail 含 request_id、已消耗 latency、是否有部分内容）与 `tool_cancelled`，均为 additive，兼容旧 resume。

5. **Logger 对象化**：文件 sink + mutex + 级别过滤 + 控制台 sink。两级设计：**文件 sink 任意线程可写**（mutex 保护，单次写入 + flush，保证行完整）；**控制台 sink 只走主线程**——非 UI 线程的日志转成 LogEvent 投递 UI 通道，由主线程统一打印，保证不交错。日志格式（`[时间戳] [级别] 消息`）与级别→流映射（info→stdout，其余→stderr）保持不变。

6. **PromptAssembly 抽取**：系统提示词装配从 `Context.reset()` 抽出为可重入函数——模板渲染（`{{cwd}}/{{date}}/{{os}}`）+ behavioral guideline + tools 列表 + tools_memo + AGENTS.md（`<project_instructions>`）+ 已安装 skill 列表。产物存入 `system_prompt_snapshot`，`session_start` 事件直接引用；`/clear` 时重新装配；`--resume` 时用快照不重装。Context 结构本身并入 AppContext（Message/ToolCall 类型保留）。

7. **ToolHub / SkillHub 只读化**：init 时预计算 schema_cache 与工具名列表（写入 AppContext，避免惰性写）；`do_dispatch` 仍在 Agent 线程内串行执行（永久串行）；Task 工具的父 request_id 从 AppContext 读取（不再依赖 tlocal）；skill 模块预留的全局变量删除。不做运行时热插拔。

8. **三线程模型与职责**：
   - **主线程（UI）**：AppContext 初始化与所有权；交互模式读 stdin；事件循环（RenderEvent 渲染、LogEvent 打印、StatusEvent 状态行）；Ctrl+C 捕获置 cancel_flag；shutdown 协调与 join。禁止直接读写 messages/token/transcript、禁止直接调 API。
   - **Agent 线程**：turn 管理、工具游标调度、消息装配、请求体快照构造、transcript 全部事件写入、token 记账、`/clear` `/export` 处理。
   - **API worker 线程**：收 ApiRequest → curl multi 事件循环执行 HTTP → SSE 解析为 Message → 回传 ApiResponse；轮询 cancel_flag 支持取消。
   - headless 与交互共用同一线程拓扑（OQ-4：不做单线程快路径）；headless 下主线程只做「投递初始任务 + 等待 Shutdown + join」，UI 渲染仍走事件。

9. **通道拓扑与事件类型**（类型形状来自设计定稿）：
   - ui→agent（unbounded）：`UiEvent { type, text }`，type ∈ USER_INPUT / COMMAND_CLEAR / COMMAND_EXIT / CANCEL_REQUEST / CANCEL_TOOL；
   - agent→ui（unbounded）：`RenderEvent`（消息渲染/工具折叠预览）、`StatusEvent`（状态行）、`LogEvent`（非 UI 线程日志转发）；
   - agent→api（buffered，容量 1）：`ApiRequest { request_id, body_json, url, headers }`——Agent 一次只投一个请求，天然背压；
   - api→agent（unbounded）：`ApiResponse { request_id, message, meta, error, cancelled }`。
   
   选型理由：UI 事件与 API 响应生产速率不可控用 unbounded，避免背压死锁；请求通道容量 1 即背压。`close()` 作为 shutdown 信号：阻塞 `pop()` 先排空队列剩余元素，随后返回 `CHANNEL_CLOSED` fault（非 null），接收循环据此退出。

10. **Agent 状态机**（决策富集部分，来自设计定稿——显式 enum 取代 v1 的隐式游标状态，支撑中断正确性）：
    ```
    AgentState: IDLE | AWAITING_API | EXECUTING_TOOLS | CANCELLING | SHUTDOWN
    ```
    线程函数内部为状态机驱动的 while 循环；两个阻塞点都在通道 `pop()` 上（等 UI 输入 / 等 API 响应），空闲零 CPU。turn 状态（turn_id / tool_call_cursor / pending_assistant_idx）留在状态机局部变量，这也是「messages/token/transcript 由 Agent 单写、无需锁」的前提。状态迁移表：
    | 状态 | 事件 | 下一状态 | 动作 |
    | --- | --- | --- | --- |
    | IDLE | UserInput | AWAITING_API | start_user_turn + 构造请求体快照 + 投递 |
    | IDLE | `/clear` 命令 | IDLE | 旧会话收尾(interrupted) + 新 session + 重装配 prompt |
    | IDLE | `/exit` 命令 / 通道关闭 | SHUTDOWN | 写 session_end |
    | AWAITING_API | 响应无 tool_calls | IDLE | 终答渲染 |
    | AWAITING_API | 响应有 tool_calls | EXECUTING_TOOLS | 记游标 |
    | AWAITING_API | cancelled（L1） | CANCELLING | 写 system_event(request_cancelled) |
    | AWAITING_API | API 错误 | IDLE（交互）/ SHUTDOWN（headless） | 同 v1 语义 |
    | EXECUTING_TOOLS | 还有未执行 tool_call | EXECUTING_TOOLS | 串行 do_dispatch 下一个 |
    | EXECUTING_TOOLS | 全部执行完 | AWAITING_API | 再请求 |
    | EXECUTING_TOOLS | 工具中断（L2） | CANCELLING | 杀子进程 + system_event(tool_cancelled) |
    | CANCELLING | 清理完成 | IDLE | 丢弃半成品 turn |

11. **curl multi 取消协议**：worker 每请求独立 easy handle + multi 事件循环（`multi_poll` 100ms 超时 + `multi_perform` + `multi_info_read` 收 `CURLMSG_DONE`，`easy_getinfo` 取状态码）；循环每轮检查 cancel_flag，取消延迟上限 100ms（可选 `multi_wakeup` 立即唤醒）。`curl_global_init` 必须在创建任何线程前、在 main 显式调用一次（多线程下 libcurl 的硬要求）。SSE 解析逻辑原样迁移进 worker，不改行为。

12. **中断语义分级**：
    - **L1 请求中断**（Ctrl+C 且 Agent 处于等 API 响应）：取消 HTTP → 丢弃半成品 turn（不 add assistant 消息、不写 tool_result）→ 写 `system_event(request_cancelled)` → 回输入态，UI 显示 `(interrupted)` notice；
    - **L2 工具中断**（Ctrl+C 且 Agent 正在执行 Bash/Task 等长工具）：杀子进程（Windows `TerminateProcess`；POSIX kill 进程组）→ 丢弃半成品 turn（OQ-3：不写 tool_result）→ 写 `system_event(tool_cancelled)`；
    - **L3 会话中断**（交互模式空闲时 Ctrl+C 或 `/exit`）：等价 `/exit`，写 `session_end(exit)`；
    - **headless 中断**：Ctrl+C = 优雅停机——取消请求、写 `session_end(reason=interrupted)`、exit 非零。
    
    被中断的 turn 不留半截 assistant 消息/tool_result，与「未收尾 turn」语义一致——现有 resume 尾部丢弃逻辑天然兼容，无需改 schema。

13. **跨线程内存规则**：AppContext 的 messages 及其中全部字符串用 LIBC_ALLOCATOR 堆分配（项目需开 `LIBC` feature）；跨线程通道负载一律堆分配、接收方处理完显式释放；`tmem` 仅限线程内短生命周期临时值、绝不放入消息/通道负载/AppContext，**新线程必须 `@pool_init` 包裹**（否则 panic）；cjson 实例不跨线程（SSE 解析在 worker 自己的树、工具参数解析在 Agent 自己的树），`init_mem_hooks` 在 main 调用一次；传给 C 函数（curl 等）的字符串必须 NUL 结尾（用 `string::format` 或 zstr_copy，`tformat` 返回值不保证 NUL 结尾）。

14. **shutdown 协议**（退出路径唯一）：`/exit`、headless 完成、Ctrl+C 全部汇聚到 SHUTDOWN——停止 Agent → close 输入通道 → close 请求通道 + 置 cancel_flag → join 两线程 → logger.close() → 返回退出码。三种退出路径均无 hang、无孤儿线程。

15. **实施分四阶段**（每阶段 `c3c build` + `c3c test` + headless 集成测试全绿，可独立发布）：
    - **阶段 0（单线程，风险低）**：AppContext 统一；TokenLedger 新增；TranscriptWriter/Logger 对象化（暂不加锁）；global 单例删除；PromptAssembly 抽取；skill 全局清理。注意：阶段 0 不引入 `@pool_init`/通道等线程机制；
    - **阶段 1（风险低-中）**：线程骨架——通道与事件类型、Agent 线程承载 rat_loop、API worker 先用原 blocking easy_perform（取消暂不支持）、UI 事件循环、shutdown 协议、curl_global_init 显式化、Logger 加 mutex；
    - **阶段 2（风险中）**：API worker 换 curl multi 事件循环 + cancel_flag + `request_cancelled` 事件；HTTP 错误码（429/500）在 multi 下的回归补齐；
    - **阶段 3（风险中）**：SetConsoleCtrlHandler / signal handler、L1/L3 中断语义、headless 停机语义；
    - **阶段 4（风险高）**：L2 工具中断（杀子进程跨平台）、token 阈值 UI 展示完善、compaction 预留接口。

## Testing Decisions

**测试缝（三层，已与用户确认）**——优先使用现有缝，仅中断场景新增一层：

1. **主缝：进程级 headless 集成**（复用现有 test_transcript.c3 模式）：构建 mp 二进制 → 启动 Python mock OpenAI server（testdata/mock_openai_server.py，端口 + ready-file 握手）→ `--headless --config <tmpcfg> --base-url http://127.0.0.1:<port> -t <task>` 跑完整会话 → cjson 解析 transcript JSONL 断言事件结构与顺序 → `--resume` roundtrip（消息数回显证明历史重建）。**重构后此缝原样存活**，是「对外行为兼容」的主回归护栏。阶段 0 起升级为**逐字节 golden diff**（NFR-3 确定性要求），覆盖 `--no-transcript` 之外的完整事件流。
2. **辅缝：纯函数单测**（复用现有 test_api_parse / test_hash_edit 模式）：api 的 SSE 解析与请求体构造、hashline/hash_edit、**TokenLedger**（累计正确性 + OK/WARN/EXCEEDED 判定）、**PromptAssembly**（模板渲染 + 注入物齐全）、**TranscriptWriter**（事件字段 + no-op 语义）。
3. **中断缝：进程内 TCP mock + curl multi**（复用现有 test_curl_multi.c3 模式，hermetic：std::net::tcp mock server 线程 + 每连接 handler 线程）：慢请求 + cancel_flag → 断言取消延迟上限与资源清理。此缝向上扩展到 L1/L2 中断的进程级测试（信号注入 + headless 停机语义断言 session_end 与退出码）。

**好测试的定义**：只测外部行为——transcript 事件序列（golden）、退出码、resume 往返、取消延迟上限；不测线程内部调度顺序、不测实现细节。集成测试必须在无真实网络依赖的 mock server 上运行（test_http/test_main 等 live-network 测试保持现状，不新增此类）。

**测试模块矩阵**：TokenLedger（单测）、PromptAssembly（单测）、TranscriptWriter（单测 + 集成）、API worker（200/错误码/取消三路径，中断缝）、Agent 状态机（经 headless 集成间接断言，不直接单测内部状态）。

**Prior art**：test_transcript.c3（进程级集成 + 结构断言 + resume roundtrip）、test_curl_multi.c3（hermetic mock + 取消）、test_api_parse.c3（纯函数）、test_hash_edit.c3（纯函数 + testdata）。新增测试应沿用这些文件的既有夹具风格（tmp 配置目录、testdata 资源、cjson 断言）。

## Out of Scope

- 工具并行执行（多 tool_call 并行 dispatch、线程池）——**永久不做**（OQ-2）；
- 流式打字机渲染——保持一次性渲染（OQ-1），中断时 UI 不显示半截输出，仅提示 `(interrupted)`；
- transcript compaction 实现——仅预留接口与 `compact_boundary` 事件占位；
- `config.json` 配置文件读取——单独立项，`--max-tokens` 先走命令行（OQ-5）；
- TUI 框架——保持行式输出；
- 技能/工具运行时热插拔——hub 初始化后只读；
- 多 agent 差异化配置（v1 已有取舍，`--agent` 已解析但未实现差异化）。

## Further Notes

- **已验证的底层事实**（arch-next.md §13 实验记录）：新线程直接用 tmem 会 panic，必须 `@pool_init` 包裹；堆分配器是 `std::core::mem::allocators::LIBC_ALLOCATOR`（需 project.json 开 `LIBC` feature）；通道 `close()` 后阻塞 `pop()` 返回 `CHANNEL_CLOSED` fault；curl multi 取消延迟实测约 30ms（远小于 100ms 轮询窗口）；cjson 独立树三线程并发 parse/serialize 安全；`string::tformat` 返回值不保证 NUL 结尾（实验中导致 curl 414）。
- **未验证风险**（阶段 3 前需实验）：Windows 下主线程阻塞在 `io::readline` 时 Ctrl+C 的处理与 stdin 状态（必要时换非阻塞输入轮询）；退出死锁（用固定 shutdown 顺序 + join 前 close 全部通道缓解）；渲染顺序与 v1 单线程的视觉差异（事件通道 FIFO 保证，文档注明可接受）。
- **实验草稿**：系统临时目录 `mp_verify`（EXP1 线程/通道、EXP2 cjson、EXP3 curl multi，含 slow_server.py），可删可留。
- **阶段 0 红线**：阶段 1 才动线程，阶段 0 不要引入 `@pool_init`/通道等线程机制。
- **变更纪律**：大方向变更需先改 `arch-next.md` 再改本规格（先方案后实施）。
