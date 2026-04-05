module getopts;

import std::io;
import std::os;

import context;

const String PROVIDER_URL = "http://127.0.0.1:5678/chat/completions";
const String PROVIDER_API_KEY = "sk-1234";
const String DEFAULT_MODEL_ID = "minimax.com/MiniMax-M2.7";
const String DEFAULT_AGENT_NAME = "default";

const String HELP = `mp - a pi coding agent clone, my own coding agent.

flags:
    --agent         指定智能体角色，默认为 default
    --model         指定使用的模型 ID
    --headless      设置为非交互模式，未设置 --headless 时默认进入交互模式
    --init-message  指定默认输入的消息（需要同时设置 --headless）
    --help          显示帮助信息
    --version       查看版本号
`;

faultdef
    NO_MODE_ID, // 未提供 model id
    NO_AGENT_NAME, // 未提供 Agent 名称
    NO_INIT_MESSAGE; // 未提供初始消息

fn void print_help()
{
    io::printfn("%s", HELP);
}

fn void print_version()
{
    io::printfn("mp %s", "0.0.1");
}

fn InitOptions*? parse(Allocator allocator, String[] args)
{
    InitOptions* init_options = alloc::new(allocator, InitOptions);
    init_options.agent_name = DEFAULT_AGENT_NAME;
    init_options.model_id = DEFAULT_MODEL_ID;
    init_options.url = PROVIDER_URL;
    init_options.api_key = PROVIDER_API_KEY;
    init_options.headless = false;
    init_options.init_message = "";

    for (usz i = 1; i < args.len; i++)
    {
        String flag = args[i];
        if (flag == "--agent")
        {
            i += 1;
            if (i >= args.len || args[i] == "") return NO_AGENT_NAME~;
            init_options.agent_name = args[i];
            continue;
        }
        else if (flag == "--model")
        {
            i += 1;
            if (i >= args.len || args[i] == "") return NO_MODE_ID~;
            init_options.model_id = args[i];
            continue;
        }
        else if (flag == "--headless")
        {
            init_options.headless = true;
            continue;
        }
        else if (flag == "--init-message")
        {
            i += 1;
            if (i >= args.len || args[i] == "") return NO_INIT_MESSAGE~;
            init_options.init_message = args[i];
            continue;
        }
        else if (flag == "--version" || flag == "-v")
        {
            init_options.print_version = true;
            continue;
        }
        else if (flag == "--help" || flag == "-h")
        {
            init_options.print_help = true;
            continue;
        }
    }

	return init_options;
}
