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

faultdef
	EXECUTE_COMMAND_ERROR,
	EMPTY_RESPONSE;

const String REQUEST_TPL = (String)$embed("request_template.json");
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");
const String TOOLS_SCHEMA = (String)$embed("tools_schema.json");

struct InitOption
{
	String agent_name;
	String init_message;
	String model_id;
	String url;
	String api_key;
	bool headless;
}

struct Message
{
	String role;
	String content;
	String id;
}

struct HistoryRecord
{
    String role;
    String content;
    Object* tool_calls;
    String id;
}

alias History = List{HistoryRecord};

fn void print_history(History* history)
{
    foreach (&record : history)
    {
        io::printfn("# %s", record.role);
        io::printfn("%s\n", record.content.trim());
    }
}

fn void print_last_message(History* history)
{
	if (try record = history.last())
	{
		io::printfn("# %s", record.role);
		io::printfn("%s\n\n", record.content.trim());
		// if (record.tool_calls != null)
		// {
		// 	io::printfn("执行工具：%s", record.tool_calls);
		// }
	}
}

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
			// if (record.tool_calls != null)
			// {
			// 	message.set("tool_calls", string::format(tmem, "%s", *record.tool_calls));
			// }
            messages.push(message);
		}

		String request_body = REQUEST_TPL.replace(tmem, "{{tools}}", TOOLS_SCHEMA)
		.replace(tmem, "{{model_id}}", util::escape(tmem, init_opt.model_id, false))
		.replace(tmem, "{{messages}}", string::format(tmem, "%s", messages));

		DateTime now = datetime::now();
		String filename = string::format(tmem,"req_%s.json", util::timestamp(tmem, now.to_local()));
		file::save(filename, request_body)!;

		String[] cmd = {
			"curl",
			"-s", // 不显示进度
			"-X", "POST", // POST 方法调用
			"-H", string::format(tmem, "Authorization: %s", init_opt.api_key), // APP KEY
			"-H", "Content-Type: application/json",
			"--data-binary", string::format(tmem, "@%s", filename), // 通过临时文件传入请求体
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

fn HistoryRecord* dispatch_tool_calls(Allocator allocator, Object* tool_calls)
{
	Object* tool_call = tool_calls.get_at(0); // {"type":"function","function":{"name":"bash","arguments":{"command":"which python && python --version"}},"id":"NbWr7IEREHyuKkrZ7OWGGNwvdN9xfhCX"}]}}
	if (tool_call == null) return null;
	String id = tool_call.get_string("id")!!;

	Object* function = tool_call.get("function")!!;
	String function_name = function.get_string("name")!!;
	Object* arguments = function.get("arguments")!!;
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

fn void agent_loop(Allocator allocator, Path cwd, InitOption* init_opt)
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);

	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", cwd.str_view())
		.replace(tmem, "{{date}}", now_str);

	History history;
	history.init(allocator);

	history.push({
		.role = "system",
		.content = final_system_prompt,
	});
	print_last_message(&history);
	
	// 等待用户录入第一条消息
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
			HistoryRecord* user_input = read_input(allocator);
			history.push(*user_input);
		}

		if (try message = send_messages(allocator, &history, init_opt))
		{
			history.push(message);
			print_last_message(&history);
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
