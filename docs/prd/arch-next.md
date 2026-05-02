# mini_pi 架构优化方案（arch-next）

> 版本：v0.1.0  
> 日期：2026-05-01  
> 说明：基于现有架构分析，结合内存管理优化共识，制定本架构演进方案。

---

## 一、背景与目标

### 1.1 现状概述
mini_pi 是基于 C3 语言实现的 Coding Agent，当前采用单体循环架构，已完成核心功能（上下文管理、工具调用、LLM 交互、技能系统）。但随着功能迭代，逐渐暴露模块耦合高、内存管理混乱、扩展性不足等问题。

### 1.2 优化目标
- **内存安全**：统一内存分配规则，消除分配器混用问题
- **可扩展性**：工具、模型提供商等组件支持低侵入扩展
- **可维护性**：解耦模块依赖，降低单点修改成本
- **可测试性**：消除全局状态，支持模块级单元测试

---

## 二、当前架构核心问题

### 2.1 内存管理混乱（高优先级）
- 混合使用 `tmem`（临时分配器）、`ctx.allocator`、`mem`（系统分配器），职责边界模糊
- 临时数据与会话级数据分配器混用，存在悬垂指针、内存泄漏风险
- 工具执行结果在临时分配器与上下文分配器之间复制规则不统一

### 2.2 模块耦合过高
- HTTP 模块（`openai_completions.c3`）直接依赖 `context` 模块，无法独立复用
- Skill 系统使用全局可变状态（`_global_context`），不利于测试和多实例场景

### 2.3 扩展性不足
- 工具注册采用硬编码 `switch-case`，新增工具需修改 `tools.c3` 核心逻辑
- 配置加载逻辑分散，无统一配置层次（文件/环境变量/CLI）

---

## 三、核心优化方案

### 3.1 统一内存管理策略（基础改造）
明确三类分配器职责，**临时分配器统一使用 `tmem`，无需在结构体中额外存储 `temp` 字段**：

| 分配器角色 | 对应标识 | 生命周期 | 使用场景 |
|-----------|---------|---------|---------|
| 临时分配器 | `tmem` | 函数调用/`@pool` 作用域内 | 临时拼接、解析、中间计算，作用域结束自动释放 |
| 上下文分配器 | `ctx_alloc`/`allocators.ctx` | Agent 会话生命周期 | 会话级持久化数据（消息、配置、路径等） |
| 系统分配器 | `mem`/`allocators.system` | 进程生命周期 | 全局静态数据、配置默认值等 |

#### 3.1.1 分配器结构体定义
```c3
// util/memory.c3
module memory;

struct Allocators
{
    Allocator* ctx;     // 上下文分配器（会话级，需显式存储）
    Allocator* system;  // 系统分配器（进程级，可选存储）
}

fn Allocators Allocators.new(Allocator* ctx_alloc)
{
    return { .ctx = ctx_alloc, .system = mem };
}
```

#### 3.1.2 各模块内存使用规则
- **Context 模块**：所有会话级字段（`id`、`cwd`、`messages` 等）使用 `allocators.ctx` 分配，释放时统一用该分配器回收
- **工具执行**：工具内部临时计算用 `tmem`，执行结果需持久化时显式复制到 `ctx.alloc`
- **HTTP 请求**：请求构建、响应解析等中间过程用 `tmem`（配合 `@pool` 作用域），最终生成的 `Message` 用 `ctx.alloc` 分配
- **临时数据获取**：如 `last_message_temp` 类方法，直接用 `tmem` 分配，调用者无需长期持有

#### 3.1.3 改造示例：Context 结构体
```c3
// context/context.c3
struct Context
{
    Allocators allocators;      // 仅存储 ctx 和 system 分配器
    String id;                  // allocators.ctx 分配
    MessageList messages;       // allocators.ctx 分配
    // ... 其他字段
}

fn Context* Context.init(&self, Allocator* ctx_alloc, InitOptions* init_options)
{
    self.allocators = Allocators.new(ctx_alloc);
    
    // 会话级数据用 ctx 分配
    self.id = util::timestamp_id(self.allocators.ctx);
    self.messages.init(self.allocators.ctx);
    
    // 临时计算用 tmem，结果复制到 ctx
    self.cwd = path::cwd(tmem)!!.str_view().copy(self.allocators.ctx);
    return self;
}

fn void Context.free(&self)
{
    // 统一用 ctx 分配器释放会话级数据
    self.id.free(self.allocators.ctx);
    self.cwd.free(self.allocators.ctx);
    self.messages.free();
}
```

---

### 3.2 工具系统重构（去除硬编码）
采用 **注册表模式** 替代 `switch-case` 工具映射，支持动态注册：

```c3
// tools/registry.c3
module tools;

type ToolFactory = fn void* (Allocator*) @dynamic;

struct ToolRegistry
{
    HashMap{String, ToolFactory} factories;
    Allocator* alloc;
}

fn void ToolRegistry.register(&self, String name, ToolFactory factory)
{
    self.factories.set(name.copy(self.alloc), factory);
}

fn Tool? ToolRegistry.create(&self, String name, Allocator* alloc)
{
    if (factory = self.factories.get(name))
    {
        return (Tool)factory(alloc);
    }
    return null;
}
```

新增工具只需注册工厂，无需修改核心逻辑：
```c3
// 内置工具注册
fn void register_builtin_tools(ToolRegistry* reg)
{
    reg.register("read", fn void*(Allocator* a) { return (Tool)alloc::new(a, ReadTool); });
    reg.register("bash", fn void*(Allocator* a) { return (Tool)alloc::new(a, BashTool); });
    // ... 其他内置工具
}
```

---

### 3.3 HTTP 模块解耦
提取 `CompletionsClient` 接口，使 HTTP 模块不依赖 `context` 模块：

```c3
// http/client.c3
module http;

interface CompletionsClient
{
    fn Message? chat(Message[] messages, String tools_schema, Allocator* result_alloc);
}

struct OpenAIClient (CompletionsClient)
{
    HttpClient http;
    String base_url;
    String api_key;
    String model_id;
}

fn Message? OpenAIClient.chat(&self, Message[] messages, String tools_schema, Allocator* result_alloc)
{
    @pool() // 临时计算用 tmem
    {
        // 构建请求、发送、解析响应，最终 Message 用 result_alloc 分配
        // ...
    }
}
```

---

### 3.4 配置管理重构
统一配置层次，优先级从低到高：**默认配置 < 配置文件 < 环境变量 < CLI 参数**

```c3
// config/config.c3
module config;

interface ConfigProvider
{
    fn String? get(String key) @dynamic;
}

struct LayeredConfig (ConfigProvider)
{
    ConfigProvider[] providers;
}

fn String? LayeredConfig.get(&self, String key)
{
    // 从高优先级到低优先级查找
    foreach (provider : self.providers)
    {
        if (try value = provider.get(key)) return value;
    }
    return null;
}
```

---

### 3.5 核心 Agent 类封装
将 `agent_loop` 逻辑封装为 `Agent` 结构体，降低 `main.c3` 复杂度：

```c3
// agent/agent.c3
module agent;

struct Agent
{
    Context* ctx;
    ToolRegistry* tools;
    CompletionsClient* client;
}

fn void Agent.run(&self)
{
    while (true)
    {
        @pool() // 单次循环临时数据用 tmem
        {
            // 工具调用检查、用户输入、LLM 请求等逻辑
            // ...
        }
    }
}
```

---

### 3.6 Skill 系统去全局化
消除全局状态，改为依赖注入：

```c3
// skill/loader.c3
module skill;

struct SkillLoader
{
    Path[] search_paths;
    Allocator* alloc;
}

fn SkillHub? SkillLoader.load_all(&self)
{
    // 从 search_paths 加载技能，返回 SkillHub 实例
    // ...
}
```

---

## 四、重构路线图

分阶段实施，降低风险：

| 阶段 | 任务 | 优先级 | 说明 |
|------|------|--------|------|
| Phase 1 | 统一内存管理策略落地 | 高 | 改造 Context、工具、HTTP 模块的内存分配规则 |
| Phase 1 | 工具注册表模式实现 | 高 | 去除硬编码 switch，支持动态注册 |
| Phase 2 | HTTP 模块解耦 | 中 | 提取 CompletionsClient 接口，移除对 context 的依赖 |
| Phase 2 | 配置管理重构 | 中 | 统一配置层次，支持多来源配置 |
| Phase 3 | Agent 核心类封装 | 低 | 重构 main.c3，将逻辑迁移到 Agent 类 |
| Phase 3 | Skill 系统去全局化 | 低 | 消除全局状态，改为注入式加载 |
| Phase 4 | 单元测试补全 | 中 | 为各模块添加 mock 测试，覆盖核心逻辑 |

---

## 五、风险与应对

1. **内存泄漏风险**：重构过程中需配合 `@pool` 作用域验证，使用 C3 的内存调试工具
2. **功能回归风险**：每阶段重构后执行全量单元测试，确保现有功能正常
3. **接口变更风险**：优先采用兼容式改造，避免一次性大范围修改接口

---

## 六、参考文档
- [C3 语言内存管理指南](docs/c3_intro.md)
- [现有架构分析记录](../../../src)（基于 2026-05-01 源码分析）
