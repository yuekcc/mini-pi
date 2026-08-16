module message;

// 会话消息类型（Message/ToolCall）与生命周期函数——独立叶子模块。
//
// 历史：类型曾位于 context 模块（与 PromptAssembly 同住）。v2 中 AppContext 持有
// messages 列表，但类型若搬进 app 模块会与 transcript 形成循环 import（app import
// transcript，transcript 需要 Message.init），故独立成无依赖的叶子模块，任何人可 import。
// 模块内只依赖 std，不 import 任何项目模块。

import std::collections::list;
import std::time::datetime;

struct ToolCall
{
	String id; // 模型返回的 tool_call id，例如 "call_xxx"
	usz index; // 模型返回的工具调用序号，从 0 递增
	String name;
	String arguments;
}

struct Message
{
	String id;
	String role;
	String content;
	String reasoning_content;
	String tool_call_id; // 仅 role=tool 消息使用，指向其回应的 tool_call id
	List{ToolCall} tool_calls; // 仅 role=assistant 消息使用，支持单次回复中的多个工具调用
	DateTime timestamp;
}

// 初始化一个 Message，role 拷贝进 allocator，tool_calls 列表也用同一 allocator 建立。
// 其余字段留空，调用方按需填充。
fn void Message.init(Message* m, Allocator allocator, String role)
{
	m.id = "";
	m.role = role.copy(allocator);
	m.content = "";
	m.reasoning_content = "";
	m.tool_call_id = "";
	m.tool_calls.init(allocator);
	m.timestamp = datetime::now().to_local();
}

// 深拷贝一个 Message 到 allocator（跨线程通道负载用；调用方负责最终释放）。
// 空串不拷贝（保持静态 ""，不占堆），与释放端 len 守卫配对——堆上只存在非空字符串。
fn Message* Message.clone(Message* src, Allocator allocator)
{
	Message* m = alloc::new(allocator, Message);
	m.id = src.id.len > 0 ? src.id.copy(allocator) : "";
	m.role = src.role.len > 0 ? src.role.copy(allocator) : "";
	m.content = src.content.len > 0 ? src.content.copy(allocator) : "";
	m.reasoning_content = src.reasoning_content.len > 0 ? src.reasoning_content.copy(allocator) : "";
	m.tool_call_id = src.tool_call_id.len > 0 ? src.tool_call_id.copy(allocator) : "";
	m.timestamp = src.timestamp;
	m.tool_calls.init(allocator);
	foreach (&tc : src.tool_calls)
	{
		m.tool_calls.push(
			{
				.id = tc.id.len > 0 ? tc.id.copy(allocator) : "",
				.index = tc.index,
				.name = tc.name.len > 0 ? tc.name.copy(allocator) : "",
				.arguments = tc.arguments.len > 0 ? tc.arguments.copy(allocator) : "",
			}
		);
	}
	return m;
}

// 释放 clone 产物（所有字符串均为 allocator 堆分配；静态 "" 由 len 守卫跳过）。
fn void Message.free(Message* m, Allocator allocator)
{
	m.free_strings(allocator);
	alloc::free(allocator, m);
}

// 只释放 Message 的字符串负载（列表内嵌的结构体由 List 持有，不能整体 free）。
// 用于 L2 丢弃半成品 turn 等「弹出列表元素」的场景。
fn void Message.free_strings(Message* m, Allocator allocator)
{
	if (m.id.len > 0) m.id.free(allocator);
	if (m.role.len > 0) m.role.free(allocator);
	if (m.content.len > 0) m.content.free(allocator);
	if (m.reasoning_content.len > 0) m.reasoning_content.free(allocator);
	if (m.tool_call_id.len > 0) m.tool_call_id.free(allocator);
	foreach (&tc : m.tool_calls)
	{
		if (tc.id.len > 0) tc.id.free(allocator);
		if (tc.name.len > 0) tc.name.free(allocator);
		if (tc.arguments.len > 0) tc.arguments.free(allocator);
	}
	m.tool_calls.free();
}
