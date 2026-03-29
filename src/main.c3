module mini_pi;
import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::object;
import std::collections::list;
import std::encoding::json;

import cmd;
import util;
import tools;

/** 故障定义：命令执行错误、空响应 */
faultdef
	EXECUTE_COMMAND_ERROR,
	EMPTY_RESPONSE;

/** 嵌入的模板文件内容 */
const String REQUEST_TPL = (String)$embed("request_template.json");
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");
const String TOOLS_SCHEMA = (String)$embed("tools_schema.json");

/**
 * Agent 初始化选项结构体
 * @agent_name: Agent 名称
 * @init_message: 初始化消息（headless 模式使用）
 * @model_id: 模型标识符
 * @url: API 端点 URL
 * @api_key: API 密钥
 * @headless: 是否为无头模式（自动执行）
 */
struct InitOption
{
	String agent_name;
	String init_message;
	String model_id;
	String url;
	String api_key;
	bool headless;
}

/**
 * 消息结构体
 * @role: 角色（user/assistant/system）
 * @content: 消息内容
 * @id: 消息 ID
 */
struct Message
{
	String role;
	String content;
	String id;
}

/**
 * 历史记录结构体
 * @role: 角色
 * @content: 内容
 * @tool_calls: 工具调用列表（可选）
 * @id: 记录 ID
 */
struct HistoryRecord
{
    String role;
    String content;
    Object* tool_calls;
    String id;
}

/** 历史记录列表类型别名 */
alias History = List{HistoryRecord};

/**
 * 打印完整的对话历史
 * @history: 历史记录指针
 */
fn void print_history(History* history)
{
    foreach (&record : history)
    {
        io::printfn("# %s", record.role);
        io::printfn("%s\n", record.content.trim());
    }
}

/**
 * 打印最近一条消息
 * @history: 历史记录指针
 */
fn void print_last_message(History* history)
{
	if (try record = history.last())
	{
		io::printfn("# %s", record.role);
		io::printfn("%s\n\n", record.content.trim());
	}
}

/**
 * 读取用户输入
 * @allocator: 内存分配器
 * @return: 用户输入构建的 HistoryRecord
 */
fn HistoryRecord* read_input(Allocator allocator)
{
	io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	String input = io::readline(tmem)!!;
	io::print(Ansi.RESET);

	HistoryRecord* result = allocator::new(allocator, HistoryRecord);
	result.role = "user";
	result.content = input.copy(allocator);
	return result;
}

/**
 * 解析 API 响应 JSON 为 HistoryRecord
 * @allocator: 内存分配器
 * @json_doc: API 返回的 JSON 文档
 * @return: 解析出的 HistoryRecord，解析失败返回 null
 */
fn HistoryRecord? read_to_history_record(Allocator allocator, String json_doc)
{
	Object* res = json::parse_string(tmem, json_doc)!;
	Object* choices = res.get("choices")!;
	Object* last_choice = choices.get_at(0);

	if (try Object* message = last_choice.get("message"))
	{
		String role = message.get_string("role") ?? "assistant";
		String content = message.get_string("content") ?? "";
		String finish_reason = message.get_string("finish_reason") ?? "";
		HistoryRecord result = {
			.role = role.copy(allocator),
			.content = content.copy(allocator),
		};
		if (try Object* tool_calls = message.get("tool_calls"))
		{
			result.tool_calls = allocator::clone(allocator, *tool_calls);
		}

		return result;
	}

	return EMPTY_RESPONSE~;
}

/**
 * 发送消息到 API 并获取响应
 * @allocator: 内存分配器
 * @history: 对话历史
 * @init_opt: 初始化选项
 * @return: API 响应转换的 HistoryRecord
 */
fn HistoryRecord? send_messages(Allocator allocator, History* history, InitOption* init_opt)
{
	@pool()
	{
		Object* messages = object::new_obj(tmem);
		foreach (&record : history)
		{
            Object* message = object::new_obj(tmem);
            message.set("role", record.role);
            message.set("content", util::escape(tmem, record.content, true));
            messages.push(message);
		}

		// 构建请求体，替换模板中的占位符
		String request_body = REQUEST_TPL.replace(tmem, "{{tools}}", TOOLS_SCHEMA)
		.replace(tmem, "{{model_id}}", util::escape(tmem, init_opt.model_id, false))
		.replace(tmem, "{{messages}}", string::format(tmem, "%s", messages));

		// 保存请求体到临时文件
		DateTime now = datetime::now();
		String filename = string::format(tmem,"logs/req_%s.json", util::timestamp(tmem, now.to_local()));
		file::save(filename, request_body)!;

		// 构建 curl 命令
		String[] cmd = {
			"curl",
			"-s",                      // 不显示进度
			"-X", "POST",              // POST 方法
			"-H", string::format(tmem, "Authorization: %s", init_opt.api_key), // 认证头
			"-H", "Content-Type: application/json",
			"--data-binary", string::format(tmem, "@%s", filename), // 通过文件传入请求体
			init_opt.url,
		};

		CommandResult curl_result = cmd::execute(tmem, cmd)!;
		io::printfn("Execute curl\ncode = %d\nresult =%s \n\n", curl_result.code, curl_result.output);

		if (curl_result.code != 0)
		{
			io::printfn("Failed to run curl. Code = %d, message = %s", curl_result.code, curl_result.output);
			return EXECUTE_COMMAND_ERROR~;
		}

		return read_to_history_record(allocator, curl_result.output);
	};
}

/**
 * 执行工具调用
 * @allocator: 内存分配器
 * @tool_calls: 工具调用对象
 * @return: 工具执行结果构建的 HistoryRecord
 */
fn HistoryRecord* dispatch_tool_calls(Allocator allocator, Object* tool_calls)
{
	Object* tool_call = tool_calls.get_at(0);
	if (tool_call == null) return null;
	String id = tool_call.get_string("id")!!;

	Object* function = tool_call.get("function")!!;
	String function_name = function.get_string("name")!!;
	Object* arguments = function.get("arguments")!!;
	// 如果参数是字符串则先解析为 JSON 对象
	if (arguments.is_string())
	{
		arguments = json::parse_string(tmem, function.get_string("arguments")!!)!!;
	}
	String call_tool_result = tools::dispatch(tmem, function_name, arguments);

	HistoryRecord* result = allocator::new(allocator, HistoryRecord);
	result.id = id.copy(allocator);
	result.role = "tool";
	result.content = call_tool_result.copy(allocator);
	return result;
}

/**
 * Agent 主循环：处理用户输入、调用 API、执行工具
 * @allocator: 内存分配器
 * @cwd: 当前工作目录
 * @init_opt: 初始化选项
 */
fn void agent_loop(Allocator allocator, Path cwd, InitOption* init_opt)
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);

	// 填充系统提示模板
	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", cwd.str_view())
		.replace(tmem, "{{date}}", now_str);

	History history;
	history.init(allocator);
	defer history.free();

	// 添加系统消息
	history.push({
		.role = "system",
		.content = final_system_prompt,
	});
	print_last_message(&history);

	// Headless 模式：使用初始化消息作为第一条用户消息
	if (init_opt.headless)
	{
		history.push({
			.role = "user",
			.content = init_opt.init_message.copy(allocator),
		});
		print_last_message(&history);
	}

	bool calling_tools = false;

	while AGENT_LOOP: (true) @pool()
	{
		if (calling_tools)
		{
			// 执行工具调用
			HistoryRecord* tool_call_result = dispatch_tool_calls(allocator, history.last()!!.tool_calls);
			if (tool_call_result == null)
			{
				calling_tools = false;
				continue AGENT_LOOP;
			}
			history.push(*tool_call_result);
			print_last_message(&history);
		}
		else if (!init_opt.headless)
		{
			// 读取用户输入
			HistoryRecord* user_input = read_input(allocator);
			history.push(*user_input);
		}

		// 发送消息并获取响应
		if (try message = send_messages(allocator, &history, init_opt))
		{
			history.push(message);
			print_last_message(&history);
			// 检查是否需要继续调用工具
			if (message.tool_calls != null)
			{
				calling_tools = true;
			}
			else
			{
				calling_tools = false;
			}
		}

		continue AGENT_LOOP;
	};
}


/**
 * 程序入口点
 * @args: 命令行参数
 * @return: 退出码
 */
fn int main(String[] args)
{
	Path cwd = path::cwd(mem)!!;

	InitOption init_opt = {
		.agent_name = "default",
		.init_message = "",
		.model_id = "LongCat-Flash-Thinking",
		.url = "http://127.0.0.1:5678/chat/completions",
		.api_key = "sk-1234",
		.headless = false,
	};

	agent_loop(mem, cwd, &init_opt);
	return 0;
}
