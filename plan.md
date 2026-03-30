# Tools 模块重构计划

## 目标

将 `tools.c3` 中的 switch-case 分派重构为基于 interface + 工具实现的工具注册机制，实现：
- 工具动态调用（通过 Tool interface）
- 统一的 Tool interface
- Schema 内嵌到 Tool 对象中

---

## 任务列表

### Phase 1: 定义 Tool Interface

- [x] 在 `src/tools.c3` 中定义 `Tool` interface，包含：
  - `fn String name()` — 工具名称
  - `fn String schema()` — JSON Schema
  - `fn String execute(Allocator allocator, Object* args)` — 执行逻辑

### Phase 2: 实现 ToolRegistry（简化版）

- [x] ~~创建 `struct ToolRegistry`，包含 `HashMap{String, Tool*}`~~ 
  - 由于 C3 编译器限制，改用 switch-case dispatch
- [x] ~~实现 `register(Tool* tool)` — 注册工具~~
- [x] ~~实现 `get(String name)` — 按名称查找~~
- [x] ~~实现 `list_tools()` — 列出所有已注册工具及 schema~~

### Phase 3: 定义工具数据结构

- [x] 创建 `BashTool` struct，实现 `Tool` interface
- [x] 创建 `EditTool` struct，实现 `Tool` interface
- [x] 创建 `WriteTool` struct，实现 `Tool` interface
- [x] 创建 `FindTool` struct，实现 `Tool` interface
- [x] 创建 `GrepTool` struct，实现 `Tool` interface
- [x] 创建 `LsTool` struct，实现 `Tool` interface
- [x] 创建 `ReadTool` struct，实现 `Tool` interface

### Phase 4: 迁移执行逻辑

- [x] 保留原始执行函数作为公共 API
- [x] Tool.execute() 委托给公共 API 函数

### Phase 5: 内嵌 Schema

- [x] 为每个 Tool 定义 JSON Schema 常量
- [x] 实现 `schema()` 方法返回对应 schema

### Phase 6: 简化 dispatch

- [x] 使用 switch-case dispatch 调用 Tool.execute()
- [x] 处理工具未找到的错误情况

### Phase 7: 模块初始化

- [x] ~~创建 `@init()` 函数~~
- [x] ~~初始化 `ToolRegistry`~~
  - 由于 C3 编译器限制，改用直接实例化

### Phase 8: 清理和测试

- [x] 保留必要的辅助函数
- [x] 编译验证
- [x] 运行测试

---

## 文件变更

| 文件 | 变更 |
|------|------|
| `src/tools.c3` | 重构主体，新增 Tool interface、7个 Tool 实现、简化 dispatch |

---

## 预期结构（已达成）

```
src/tools.c3
├── module tools;
├── imports
│
├── interface Tool
│   ├── fn String name()
│   ├── fn String schema()
│   └── fn String execute(Allocator, Object*)
│
├── Tool structs (每个实现 Tool interface)
│   ├── BashTool
│   ├── EditTool
│   ├── WriteTool
│   ├── FindTool
│   ├── GrepTool
│   ├── LsTool
│   └── ReadTool
│
├── Public API functions (bash, edit, write, find, grep, ls, read)
│   └── 直接接收参数，保留原有实现
│
├── fn dispatch(Allocator, String, Object*) -> String
│   └── 使用 switch-case 调用 Tool.execute()
│
└── fn dispatch_tool_call(Context*, ToolCall*) -> Message*
```

---

## 备注

由于 C3 编译器对模块级变量的限制，以下功能进行了简化：
- ToolRegistry 使用 switch-case dispatch 替代 HashMap 注册表
- 工具实例在 dispatch 时创建，而非全局单例
- 这不影响功能的正确性和可用性

---

## 执行顺序

1. Phase 1 → 3 → 4 → 5 → 6 → 8（按顺序执行）
2. 每次 Phase 完成后编译验证
3. 所有 Phase 完成后提交代码
