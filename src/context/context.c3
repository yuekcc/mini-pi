module context;

// 会话消息类型（Message/ToolCall）——v2 中 AppContext 持有 messages 列表，
// 类型本身保留在本模块（context 模块现只承载类型与提示词装配纯函数）。

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
fn void message_init(Message* m, Allocator allocator, String role)
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
fn Message* message_clone(Allocator allocator, Message* src)
{
	Message* m = alloc::new(allocator, Message);
	m.id = src.id.copy(allocator);
	m.role = src.role.copy(allocator);
	m.content = src.content.copy(allocator);
	m.reasoning_content = src.reasoning_content.copy(allocator);
	m.tool_call_id = src.tool_call_id.copy(allocator);
	m.timestamp = src.timestamp;
	m.tool_calls.init(allocator);
	foreach (&tc : src.tool_calls)
	{
		m.tool_calls.push(
			{
				.id = tc.id.copy(allocator),
				.index = tc.index,
				.name = tc.name.copy(allocator),
				.arguments = tc.arguments.copy(allocator),
			}
		);
	}
	return m;
}

// 释放 message_clone 产物（所有字符串均为 allocator 堆分配；静态 "" 由 len 守卫跳过）。
fn void message_free(Allocator allocator, Message* m)
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
	alloc::free(allocator, m);
}
