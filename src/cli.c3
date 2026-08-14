module cli;

import std::io;
import std::io::path;
import version;

const String DEFAULT_AGENT = "default";
const String DEFAULT_MODEL = "Any"; // "minimax.com/MiniMax-M2.7";
const String DEFAULT_BASE_URL = "http://127.0.0.1:5678";
const String DEFAULT_API_KEY = "sk-1234";
const String DEFAULT_TOOLS = "ReadFile,Bash,HashEditFile,WriteFile,Grep,Glob,ListDir,Task";

const String HELP_MESSAGE = `mp - a coding agent, my own coding agent.

flags:
    --config, -c         指定配置目录
    --agent              指定智能体角色，默认为 default
    --tools              允许使用的工具列表，默认值是 ReadFile,Grep,Glob,ListDir,Bash,HashEditFile,WriteFile,Task
    --task, -t           指定默认任务
    --task-file, -f      从指定文件中读出内容，并设置为默认任务
    --output-file, -o    将最后一次 LLM 回复输出到指定文件
    --headless           设置为非交互模式，一轮对话后会自动退出
    --resume             从指定 session_id 的 transcript 恢复会话（headless 下可与 -t 组合续跑）
    --no-transcript      关闭本会话的 transcript 写入

    --model              指定使用的模型 ID，默认 'Any'
    --base-url           指定 Chat Completions API 的 base URL，默认 'http://127.0.0.1:5678'
    --api-key            指定 API key， 默认 'sk-1234'
    --max-tokens         指定上下文窗口 token 预算上限（0 = 不启用，默认 0）

    --list-skills        列出全部可用 skill

    --help               显示帮助信息
    --version            查看版本号
    --debug              启动 DEBUG 模式

tools:
    - 'ReadFile'
    - 'Grep'
    - 'Glob'
    - 'ListDir'
    - 'Bash'
    - 'HashEditFile'
    - 'WriteFile'
    - 'Task'`;

struct Flag
{
	String agent;
	String model;
	String baseUrl;
	String apiKey;
	String tools;
	String task;
	String task_file;
	String resume_session;
	Path output_file;
	Path config_dir;
	Path cwd;
	bool enable_headless;
	bool enable_transcript;
	bool enable_debug;
	bool show_help;
	bool show_version;
	bool show_skills;
	long max_tokens;
}

faultdef
	NO_AGENT, NO_MODEL, NO_BASE_URL, NO_API_KEY, NO_TOOLS, NO_INIT_TASK, NO_OUTPUT_FILE, NO_CONFIG_DIR, NO_SESSION,
	NO_MAX_TOKENS,
;

fn void? Flag.init(&self, Allocator allocator, String[] args)
{
	self.agent = DEFAULT_AGENT;
	self.model = DEFAULT_MODEL;
	self.apiKey = DEFAULT_API_KEY;
	self.baseUrl = DEFAULT_BASE_URL;

	self.tools = DEFAULT_TOOLS;
	self.cwd = path::cwd(allocator)!;
	self.enable_transcript = true;

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
		else if (flag == "--max-tokens")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_MAX_TOKENS~;
			long? parsed = args[i].to_long();
			if (try val = parsed)
			{
				self.max_tokens = val;
			}
			else
			{
				return NO_MAX_TOKENS~;
			}
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
		else if (flag == "--resume")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_SESSION~;
			self.resume_session = args[i];
			continue;
		}
		else if (flag == "--no-transcript")
		{
			self.enable_transcript = false;
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
