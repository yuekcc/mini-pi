module context;

import std::io;
import std::os;
import std::time::datetime;

import util;

const String PROVIDER_URL = "http://127.0.0.1:5678/chat/completions";
const String PROVIDER_API_KEY = "sk-1234";
const String DEFAULT_MODEL_ID = "minimax.com/MiniMax-M2.7";
const String DEFAULT_AGENT_NAME = "default";
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");

faultdef
	NO_MODE_ID, // 未提供 model id
	NO_TOOLS, // 未提供工具列表
	NO_AGENT_NAME, // 未提供 Agent 名称
	NO_INIT_MESSAGE; // 未提供初始消息

struct InitOptions (Printable)
{
	String agent_name;
	String init_message;
	String model_id;
	String url;
	String api_key;
	bool headless;
	bool print_help;
	bool print_version;
	bool enable_agents_md;
	String instructions; // AGENTS.md 内容
	String tools;
	String system_prompt;
}

fn sz? InitOptions.to_format(&self, Formatter* formatter) @dynamic
{
	sz count = 0;
	count += formatter.printf(util::system_message("Start mp with agent %s@%s, headless is %s\n"), self.agent_name, self.model_id, self.headless)!;
	count += formatter.printf(util::system_message("Load AGENTS.md: %s\n"), self.enable_agents_md)!;
	count += formatter.printf(util::system_message("Allowed tools: %s\n"), self.tools)!;

	return count;
}

fn void try_load_user_prompt(Allocator allocator, InitOptions* init_options) @local
{
	if (!init_options.init_message.starts_with("@"))
	{
		return;
	}

	String file_name = init_options.init_message.trim_left("@");
	if (try content = (String)file::load(tmem, file_name))
	{
		init_options.init_message = content.copy(allocator);
	}
}

fn void try_load_instructions(Allocator allocator, InitOptions* init_options) @local
{
	if (try content = (String)file::load(tmem, "AGENTS.md"))
	{
		init_options.instructions = content.copy(allocator);
		init_options.enable_agents_md = true;
	}
}

fn void try_load_system_prompt(Allocator allocator, InitOptions* init_options) @local
{
	DateTime now = datetime::now();
	String now_str = now.to_local().format(tmem, DateTimeFormat.DATEONLY);
	Path cwd = path::cwd(allocator)!!;

	String final_system_prompt = SYSTEM_PROMPT_TPL
		.replace(tmem, "{{cwd}}", cwd.str_view())
		.replace(tmem, "{{date}}", now_str)
		.replace(tmem, "{{os}}", "Windows 11 + Msys2 + GNU Bash 5.2 (x86_64-pc-msys)");

	init_options.system_prompt = final_system_prompt.copy(allocator);
}

fn InitOptions*? InitOptions.init(&self, Allocator allocator, String[] args)
{
	self.agent_name = DEFAULT_AGENT_NAME;
	self.model_id = DEFAULT_MODEL_ID;
	self.url = PROVIDER_URL;
	self.api_key = PROVIDER_API_KEY;
	self.headless = false;
	self.init_message = "";
	self.tools = "read,bash,edit,write,grep,find,ls";

	for (usz i = 1; i < args.len; i++)
	{
		String flag = args[i];
		if (flag == "--agent")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_AGENT_NAME~;
			self.agent_name = args[i];
			continue;
		}
		else if (flag == "--model")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_MODE_ID~;
			self.model_id = args[i];
			continue;
		}
		else if (flag == "--headless")
		{
			self.headless = true;
			continue;
		}
		else if (flag == "--init-message")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_INIT_MESSAGE~;
			self.init_message = args[i];
			continue;
		}
		else if (flag == "--version" || flag == "-v")
		{
			self.print_version = true;
			continue;
		}
		else if (flag == "--help" || flag == "-h")
		{
			self.print_help = true;
			continue;
		}
		else if (flag == "--tools")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_TOOLS~;
			self.tools = args[i];
			continue;
		}
	}

	try_load_system_prompt(allocator, self);

	try_load_instructions(allocator, self);

	try_load_user_prompt(allocator, self);

	return self;
}
