module app;

// 事件类型与通道负载（arch-next-spec 决策 9）。
//
// 内存规则：跨线程通道负载一律 LIBC 堆分配，接收方处理完显式释放
// （UiEvent.text / UiOutEvent.text / UiOutEvent.msg / ApiRequest.* / ApiResponse.*）。
// tmem 绝不放入通道负载。

import std::collections::list;

import context;
import transcript;

// ---- ui → agent ------------------------------------------------------------

enum UiEventType
{
	USER_INPUT,     // text = 用户输入内容
	COMMAND_CLEAR,  // /clear
	COMMAND_EXPORT, // /export
	COMMAND_EXIT,   // /exit / /e
	CANCEL_REQUEST, // Ctrl+C：取消进行中的 API 请求（阶段 3 起产生）
	CANCEL_TOOL,    // Ctrl+C：中断进行中的工具执行（阶段 4 起产生）
}

struct UiEvent
{
	UiEventType type;
	String text; // heap（Agent 处理完释放）
}

// ---- agent → ui ------------------------------------------------------------

enum UiOutKind
{
	RENDER_MESSAGE, // msg（+ 可选 tool_name）：渲染消息/工具折叠预览
	NOTICE,         // text：黄色括号提示（(DONE)/(Bye ...) 等）
	LOG_LINE,       // text + to_stderr：非主线程日志转发
	READY,          // Agent 回到 IDLE（交互模式：UI 打印输入提示）
	SHUTDOWN,       // Agent 已收尾：UI 退出事件循环（exit_code = 进程退出码）
}

struct UiOutEvent
{
	UiOutKind kind;
	Message* msg;     // RENDER_MESSAGE（heap，UI 渲染后释放）
	String tool_name; // RENDER_MESSAGE：tool 折叠预览标题（可空）
	String text;      // NOTICE / LOG_LINE（heap，UI 处理后释放）
	bool to_stderr;   // LOG_LINE：true → stderr，false → stdout
	int exit_code;    // SHUTDOWN
}

// ---- agent → api / api → agent ---------------------------------------------

struct ApiRequest
{
	String request_id;  // heap
	String body_json;   // heap（Agent 序列化快照，worker 不读共享 messages）
	String url;         // heap（NUL 结尾，供 curl）
	List{String} headers; // heap 列表，元素 heap（NUL 结尾）
}

struct ApiResponse
{
	String request_id;        // heap
	Message* message;         // heap；error/cancelled 时为 null
	transcript::Usage usage;  // message 成功时的 usage 回报
	bool has_usage;
	String finish_reason;     // heap
	String error_detail;      // heap；非空表示请求失败
	bool cancelled;           // 阶段 2 起：请求被取消
}
