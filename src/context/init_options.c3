module context;

import std::io;
import std::os;
import std::time::datetime;

import c3x::object;
import cli;
import util;

const String PROVIDER_URL = "http://127.0.0.1:1234";
const String PROVIDER_API_KEY = "sk-1234";
const String DEFAULT_MODEL_ID = "minimax.com/MiniMax-M2.7";
const String DEFAULT_AGENT_NAME = "default";
const String SYSTEM_PROMPT_TPL = (String)$embed("system_prompt_template.md");
const String DEFAULT_TOOLS = "read,bash,edit,write,grep,find,ls,task";

faultdef
	NO_OUTPUT_FILE, // 未指定输出文件
	NO_MODE_ID, // 未提供 model id
	NO_TOOLS, // 未提供工具列表
	NO_AGENT_NAME, // 未提供 Agent 名称
	NO_INIT_MESSAGE, // 未提供初始消息
;

struct SystemConfig
{
	String api_key;
	String base_url;
	String model_id;
}

fn SystemConfig* SystemConfig.init_from_json(&self, Allocator allocator, String json)
{
	Object*? config = object::parse(tmem, json);
	if (catch err = config)
	{
		io::printfn(util::error_message("Local config file failed, for %s"), err);
		os::exit(1);
	}

	if (config.has_key("api_key"))
	{
		self.api_key = config.get_string("api_key")!!.copy(allocator);
	}

	if (config.has_key("base_url"))
	{
		self.base_url = config.get_string("base_url")!!.copy(allocator);
	}

	if (config.has_key("model_id"))
	{
		self.model_id = config.get_string("model_id")!!.copy(allocator);
	}

	return self;
}


struct InitOptions (Printable)
{
	String agent_name;
	String init_message;
	String model_id;
	String base_url;
	String api_key;
	bool headless;
	bool print_help;
	bool print_version;
	bool debug;
	bool enable_agents_md;
	String instructions; // AGENTS.md 内容
	String tools;
	String system_prompt;
	String output_file;
}

fn sz? InitOptions.to_format(&self, Formatter* formatter) @dynamic
{
	sz count = 0;
	count += formatter.printf(util::system_message("\nStart mp@%s\n\n"), self.agent_name)!;
	count += formatter.printf(util::system_message("Enable tools: %s\n"), self.tools)!;
	count += formatter.printf(util::system_message("Enable headless mode：%s\n"), self.headless)!;
	count += formatter.printf(util::system_message("Enable AGENTS.md: %s\n"), self.enable_agents_md)!;
	count += formatter.printf(util::system_message("\nModel: %s@%s\n"), self.model_id, self.base_url)!;

	return count;
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

	String final_system_prompt = SYSTEM_PROMPT_TPL.replace(tmem, "{{cwd}}", cwd.str_view())
		.replace(tmem, "{{date}}", now_str)
		.replace(tmem, "{{os}}", "Windows 11 + Msys2 + GNU Bash 5.2 (x86_64-pc-msys)");

	init_options.system_prompt = final_system_prompt.copy(allocator);
}

fn void try_load_config_file(Allocator allocator, InitOptions* init_options)
{
	String file_path = util::get_config_file(tmem);
	if (!file::exists(file_path))
	{
		return;
	}

	if (try json = file::load(tmem, file_path))
	{
		SystemConfig config;
		config.init_from_json(tmem, (String)json);

		if (config.base_url != "")
		{
			init_options.base_url = config.base_url.copy(allocator);
		}

		if (config.api_key != "")
		{
			init_options.api_key = config.api_key.copy(allocator);
		}

		if (config.model_id != "")
		{
			init_options.model_id = config.model_id.copy(allocator);
		}
	}
}

fn void try_load_from_cli(Allocator allocator, InitOptions* init_options, String[] args)
{
	CliOptions cli_opts;
	bool read_cli_ok = @ok(cli_opts.init(args));
	if (!read_cli_ok)
	{
		return;
	}

	init_options.agent_name = cli_opts.agent.copy(allocator);
	init_options.model_id = cli_opts.model.copy(allocator);
	init_options.tools = cli_opts.tools.copy(allocator);
	init_options.headless = cli_opts.headless;
	init_options.init_message = cli_opts.task.copy(allocator);
	init_options.print_help = cli_opts.help;
	init_options.print_version = cli_opts.version;
	init_options.debug = cli_opts.debug;
	init_options.output_file = cli_opts.output_file.copy(allocator);

	if (cli_opts.task == "" && cli_opts.file != "")
	{
		if (try content = (String)file::load(tmem, cli_opts.file))
		{
			init_options.init_message = content.copy(allocator);
		}
	}
}

fn InitOptions*? InitOptions.init(&self, Allocator allocator, String[] args)
{
	self.agent_name = DEFAULT_AGENT_NAME;
	self.model_id = DEFAULT_MODEL_ID;
	self.base_url = PROVIDER_URL;
	self.api_key = PROVIDER_API_KEY;
	self.headless = false;
	self.init_message = "";

	try_load_config_file(allocator, self);

	try_load_from_cli(allocator, self, args);

	try_load_system_prompt(allocator, self);

	try_load_instructions(allocator, self);

	return self;
}