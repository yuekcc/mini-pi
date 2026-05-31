module cli;

import std::io;
import std::io::path;
import version;

const String DEFAULT_AGENT = "default";
const String DEFAULT_MODEL = "Local/Any"; // "minimax.com/MiniMax-M2.7";
const String DEFAULT_BASE_URL = "http://127.0.0.1:8001";
const String DEFAULT_API_KEY = "sk-1234";
const String DEFAULT_TOOLS = "read,bash,edit,write,grep,find,ls,task";

const String HELP_MESSAGE = `mp - a coding agent, my own coding agent.

flags:
	--config, -c    指定配置目录
    --agent    指定智能体角色，默认为 default
    --tools    允许使用的工具列表，默认值是 read,bash,edit,write,grep,find,ls
    --task, -t    指定默认任务
    --task-file, -f    从指定文件中读出内容，并设置为默认任务
    --output-file, -o    将最后一次 LLM 回复输出到指定文件
    --headless    设置为非交互模式，一轮对话后会自动退出

    --model    指定使用的模型 ID
    --base-url    指定 OpenAI-compatible API base URL，默认 'http://127.0.0.1:8001'
    --api-key    指定 Completions API key， 默认 'sk-1234'

    --list-skills    列出全部可用 skill

    --help    显示帮助信息
    --version    查看版本号
    --debug    启动 DEBUG 模式

tools:
    - 'read'
    - 'bash'
    - 'edit'
    - 'write'
    - 'grep'
    - 'find'
    - 'ls'
    - 'task'
`;

struct Flag
{
	String agent;
	String model;
	String baseUrl;
	String apiKey;
	String tools;
	String task;
	String task_file;
	Path output_file;
	Path config_dir;
	Path cwd;
	bool enable_headless;
	bool enable_debug;
	bool show_help;
	bool show_version;
	bool show_skills;
}

faultdef
	NO_AGENT, NO_MODEL, NO_BASE_URL, NO_API_KEY, NO_TOOLS, NO_INIT_TASK, NO_OUTPUT_FILE, NO_CONFIG_DIR,
;

fn void? Flag.init(&self, Allocator allocator, String[] args)
{
	self.agent = DEFAULT_AGENT;
	self.model = DEFAULT_MODEL;
	self.apiKey = DEFAULT_API_KEY;
	self.baseUrl = DEFAULT_BASE_URL;

	self.tools = DEFAULT_TOOLS;
	self.cwd = path::cwd(allocator)!;

	Path home_dir = path::home_directory(tmem)!!;
	self.config_dir = home_dir.append(allocator, ".config/mp")!;

	for (sz i = 1; i < args.len; i++)
	{
		String flag = args[i];

		if (flag == "--config" || flag == "-c")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_CONFIG_DIR~;
			self.config_dir = path::new(allocator, args[i])!;
			continue;
		}
		else if (flag == "--agent")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_AGENT~;
			self.agent = args[i];
			continue;
		}
		else if (flag == "--model")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_MODEL~;
			self.model = args[i];
			continue;
		}
		else if (flag == "--base-url")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_BASE_URL~;
			self.baseUrl = args[i];
			continue;
		}
		else if (flag == "--api-key")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_BASE_URL~;
			self.apiKey = args[i];
			continue;
		}
		else if (flag == "--tools")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_TOOLS~;
			self.tools = args[i];
			continue;
		}
		else if (flag == "--task" || flag == "-t")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_INIT_TASK~;
			self.task = args[i];
			continue;
		}
		else if (flag == "--task-file" || flag == "-f")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_INIT_TASK~;
			self.task_file = args[i];
			continue;
		}
		else if (flag == "--output-file" || flag == "-o")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_OUTPUT_FILE~;
			self.output_file = path::new(allocator, args[i])!;
			continue;
		}
		else if (flag == "--version" || flag == "-v")
		{
			self.show_version = true;
			continue;
		}
		else if (flag == "--help" || flag == "-h")
		{
			self.show_help = true;
			continue;
		}
		else if (flag == "--list-skills")
		{
			self.show_skills = true;
			continue;
		}
		else if (flag == "--debug")
		{
			self.enable_debug = true;
			continue;
		}
		else if (flag == "--headless")
		{
			self.enable_headless = true;
			continue;
		}
	}
}

fn void Flag.print_help(&self)
{
	io::printn(HELP_MESSAGE);
}

fn void Flag.print_version(&self)
{
	io::printn(version::VERSION);
}
