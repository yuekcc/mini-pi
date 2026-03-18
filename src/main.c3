module mini_pi;
import std::io;
import std::io::path;
import std::time::datetime;
import std::collections::object;
import std::collections::list;

import cmd;

const String REQUEST_TPL = (String)$embed("request_template.json");
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

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

fn Object* Message.to_obj(&self, Allocator allocator)
{
	Object* result = object::new_obj(allocator);
	result.set("role", self.role.copy(allocator));
	result.set("content", self.content.copy(allocator));

	if (self.id != "")
	{
		result.set("id", self.id.copy(allocator));
	}

	return result;
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
	io::printfn("%s\n", record.content.trim());
	}
}

fn void user_input(Allocator allocator, History* history)
{
	io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	String? input = io::readline(tmem);
	io::print(Ansi.RESET);
	if (try input)
	{
		history.push({
			.role = "user",
			.content = input.copy(allocator),
		});
	}
}

fn void agent_loop(Allocator allocator, Path cwd, InitOption init_opt)
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
			// 调用工具，将结果放入 history
			print_last_message(&history);
		}
		else if (!init_opt.headless)
		{
			user_input(allocator, &history);
		}

		// send(history)
		// 处理响应
		break AGENT_LOOP;
	};
}


fn int main(String[] args)
{
	Path cwd = path::cwd(mem)!!;

	InitOption init_opt = {
		.agent_name = "default",
		.init_message = "",
		.model_id = "LongCat-Flash-Chat",
		.url = "https://api.longcat.chat/openai/v1/chat/completions",
		.api_key = "",
		.headless = false,
	};

	agent_loop(mem, cwd, init_opt);
	return 0;
}
