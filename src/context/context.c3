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
