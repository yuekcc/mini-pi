module getopts;

import std::io;
import std::os;

import context;

const String PROVIDER_URL = "http://127.0.0.1:5678/chat/completions";
const String PROVIDER_API_KEY = "sk-1234";
const String DEFAULT_MODEL_ID = "minimax.com/MiniMax-M2.7";
const String DEFAULT_AGENT_NAME = "default";

faultdef
    NO_MODE_ID, // 未提供 model id
    NO_AGENT_NAME, // 未提供 Agent 名称
    NO_INIT_MESSAGE; // 未提供初始消息

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
    }
    // io::printfn("init_message = %s", init_options.init_message);
    // io::printfn("headless = %s", init_options.headless);
	return init_options;
}
