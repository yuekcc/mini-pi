module cli;

const String HELP = `mp - a pi coding agent clone, my own coding agent.

flags:
	--agent         指定智能体角色，默认为 default
	--model         指定使用的模型 ID
	--tools         允许使用的工具列表，默认值是 read,bash,edit,write,grep,find,ls
	--headless      设置为非交互模式，未设置 --headless 时默认进入交互模式
	--task, -t      指定默认任务
	--file, -f      从指定文件中读出内容，并设置为默认任务
	--help          显示帮助信息
	--version       查看版本号
	--debug         启动 DEBUG 模式
	--output-file   将最后一次 LLM 回复输出到指定文件

tools:
	- 'read'
	- 'bash'
	- 'edit'
	- 'write'
	- 'grep'
	- 'find'
	- 'ls'
`;

const String DEFAULT_AGENT_NAME = "default";
const String DEFAULT_MODEL_ID = "minimax.com/MiniMax-M2.7";
const String DEFAULT_TOOLS = "read,bash,edit,write,grep,find,ls,task";

faultdef
	NO_OUTPUT_FILE,
	NO_MODE_ID, // 未提供 model id
	NO_TOOLS, // 未提供工具列表
	NO_AGENT_NAME, // 未提供 Agent 名称
	NO_INIT_MESSAGE; // 未提供初始消息


struct CliOptions
{
	String agent;
	String model;
	String tools;
	bool headless;
	String task;
	String file;
	bool help;
	bool version;
	bool debug;
	String output_file;
}

fn CliOptions*? CliOptions.init(&self, String[] args)
{
	self.agent = DEFAULT_AGENT_NAME;
	self.model = DEFAULT_MODEL_ID;
	self.tools = DEFAULT_TOOLS;

	for (usz i = 1; i < args.len; i++)
	{
		String flag = args[i];
		if (flag == "--agent")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_AGENT_NAME~;
			self.agent = args[i];
			continue;
		}
		else if (flag == "--model")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_MODE_ID~;
			self.model = args[i];
			continue;
		}
		else if (flag == "--headless")
		{
			self.headless = true;
			continue;
		}
		else if (flag == "--task" || flag == "-t")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_INIT_MESSAGE~;
			self.task = args[i];
			continue;
		}
		else if (flag == "--file" || flag == "-f")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_INIT_MESSAGE~;
			self.file = args[i];
			continue;
		}
		else if (flag == "--version" || flag == "-v")
		{
			self.version = true;
			continue;
		}
		else if (flag == "--debug")
		{
			self.debug = true;
			continue;
		}
		else if (flag == "--help" || flag == "-h")
		{
			self.help = true;
			continue;
		}
		else if (flag == "--tools")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_TOOLS~;
			self.tools = args[i];
			continue;
		}
		else if (flag == "--output-file")
		{
			i += 1;
			if (i >= args.len || args[i] == "") return NO_OUTPUT_FILE~;
			self.output_file = args[i];
			continue;
		}
	}

	return self;
}
