import std::io;
import std::encoding::json;
import std::collections::object;
import std::collections::list;
import cmd;

const String SYSTEM_PROMPT = `You are an AI assistant with Napoleon Dynamite's personality.` 
    +++ `Say things like 'Gosh!', 'Sweet!', 'Idiot!', and be awkwardly enthusiastic. `
    +++ `Answer questions in Napoleon's quirky style. `
    +++ `User is on Windows 11. 尽量使用简体中文回答`;

struct HistoryRecord {
    String role;
    String content;
    Object* tool_calls;
    String id;
}

alias History = List{HistoryRecord};

faultdef
    EMPTY_RESPONSE, // 空白请求
    EXECUTE_COMMAND_ERROR; // 执行命令失败

macro String error_message(String $format)
{
    return Ansi.RED +++ $format +++ Ansi.RESET;
}

macro String system_message(String $format)
{
    return Ansi.BRIGHT_BLACK +++ $format +++ Ansi.RESET;
}


fn HistoryRecord? extract_response(Allocator allocator, String response)
{
    io::printfn(system_message("server response: %s"), response);

    Object* res = json::parse_string(allocator, response)!;
    Object* choices = res.get("choices")!;

    Object* last_choice = choices.get_at(0);
    if (try message = last_choice.get("message"))
    {
        String role = message.get_string("role") ?? "assistant";
        String content = message.get_string("content") ?? "";
        Object*? tool_calls = message.get("tool_calls");

        return {
            .role = role.copy(allocator),
            .content = content.copy(allocator),
            .tool_calls = null,
        };
    }

    return EMPTY_RESPONSE~;
}

fn void print_history(History history)
{
    foreach (&record : history)
    {
        io::printfn("# %s", record.role);
        io::printfn("%s\n", record.content.trim());
    }
}

fn Object* init_request(Allocator allocator, String modelId)
{
    Object* command_decl_obj = object::new_obj(allocator);
    command_decl_obj.set("type", "string");
    command_decl_obj.set("description", "The command to execute");

    Object* properties_obj = object::new_obj(allocator);
    properties_obj.set("command", command_decl_obj);
    Object* required_obj = object::new_obj(allocator);
    required_obj.push("command");
    Object* parameters_obj = object::new_obj(allocator);
    parameters_obj.set("type", "object");
    parameters_obj.set("properties", properties_obj);
    parameters_obj.set("required", required_obj);

    Object* function_obj = object::new_obj(allocator);
    function_obj.set("name", "execute_command");
    function_obj.set("description", "Run shell commands in the terminal, ensuring proper handling and security measures.Before using this tool, verify that the command is not one of the banned commands: rm, make. User is using BASH as shell. DO NOT need to try in other shell when get error.");
    function_obj.set("parameters", parameters_obj);

    Object* tools = object::new_obj(allocator);
    Object* tool = object::new_obj(allocator);
    tool.set("type", "function");
    tool.set("function", function_obj);
    tools.push(tool);

    Object* obj = object::new_obj(allocator);
    obj.set("tool_choice", "auto");
    obj.set("tools", tools);

    obj.set("model", modelId);

    io::printfn("%s", obj);
    return obj;
}

fn String escape(String s, Allocator allocator, bool strip_quotes = true) @local
{
    usz initial_capacity = s.len + s.len / 5 + 2;
    DString result = dstring::new_with_capacity(tmem, initial_capacity);

    if (!strip_quotes) result.append_char('"');

    foreach (char c : s)
    {
        switch (c)
        {
            case '"':  result.append(`\"`);
            case '\\': result.append(`\\`);
            case '\b': result.append(`\b`);
            case '\f': result.append(`\f`);
            case '\n': result.append(`\n`);
            case '\r': result.append(`\r`);
            case '\t': result.append(`\t`);
            case '\v': result.append(`\v`);
            case '\0': result.append(`\0`);
            default:
                result.append_char(c);
        }
    }

    if (!strip_quotes) result.append_char('"');
    return result.str_view().copy(allocator);
}

fn String? send_messages(Allocator allocator, History history)
{
    @pool()
    {
        Object* request = init_request(tmem, "LongCat-Flash-Chat");
        Object* messages = object::new_obj(tmem);

        foreach (i, &record : history)
        {
            Object* message = object::new_obj(tmem);
            message.set("role", record.role);
            message.set("content", escape(record.content, tmem));
            messages.push(message);
        }

        request.set("messages", messages);
        String filename = "req.json";
        file::save(filename, string::format(tmem, "%s", request))!;

        String[] final_cmd = {
            "xh",
            "post",
            "https://api.longcat.chat/openai/v1/chat/completions",
            "--stream",
            "--ignore-stdin",
            "Authorization:@apikey.txt",
            string::format(tmem, "@%s", filename),
        };

        io::printn(system_message("waiting for reply ..."));
        CommandResult xh_result = cmd::execute(tmem, final_cmd)!;
        if (xh_result.code == 0)
        {
            return xh_result.output.copy(allocator);
        }
        else
        {
            io::printfn(error_message("xh got failed. code = %d, message = %s"), xh_result.code, xh_result.output);
            return EMPTY_RESPONSE~;
        }
    };
}

fn HistoryRecord? execute_command(Allocator allocator, Object* tool_calls)
{
    @pool()
    {
        Object* function_call = tool_calls.get_at(0);
        io::printfn(system_message("find function_call declares: %s"), function_call);

        if (function_call)
        {
            Object* function_call_details = function_call.get("function")!;

            String function_name = function_call_details.get_string("name")!;
            String arguments = function_call_details.get_string("arguments")!;
            String id = function_call.get_string("id")!;

            io::printfn(system_message("get name = %s, arguments = %s, id = %s"), function_name, arguments, id);

            Object* res = json::parse_string(tmem, arguments)!;
            if (try String command = res.get_string("command"))
            {
                io::printfn(system_message("Execute command: %s"), command);

                $if env::WIN32:
                    String[] cmd = { "sh", "-c", command };
                $else
                    String[] cmd = { "sh", "-c", command };
                $endif

                CommandResult cmd_result = cmd::execute(tmem, cmd)!;
                io::printfn(system_message("Command output:\n%s"), cmd_result.output);

                String message;
                if (cmd_result.code == 0)
                {
                    message = cmd_result.output;
                }
                else
                {
                    message = string::format(
                        tmem, 
                        "Execute command failed.\nMaybe your should try in another way command.\nExecute command line: %s.\nReturn code is %d\nand feedback: %s", 
                        command,
                        cmd_result.code, 
                        cmd_result.output);
                }

                return {
                    .role = "tool",
                    .content = message.copy(allocator),
                    .id = id.copy(allocator),
                };
            }
        }

        return EXECUTE_COMMAND_ERROR~;
    };
}

fn void __main()
{
    History message_list;
    message_list.init(mem);

    message_list.push({
        .role = "system",
        .content = SYSTEM_PROMPT,
    });

    bool calling_tools = false;

    int retry_on_error = 0;
    while LOOP: (true)
    {    
        @pool()
        {            
            if (!calling_tools)
            {
                io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
                String? input = io::treadline();
                io::print(Ansi.RESET);
                if (try input)
                {
                    message_list.push({
                        .role = "user",
                        .content = input.copy(mem),
                    });
                }
            }

            Object* tool_calls_for_execute = null;
            HistoryRecord assistant_message;
            bool has_message = false;

            if (try String reply = send_messages(tmem, message_list))
            {
                io::printfn(system_message("Reply: %s\n"), reply);

                if (try Object* res = json::parse_string(tmem, reply))
                {
                    if (try Object* choices = res.get("choices"))
                    {
                        Object* last_choice = choices.get_at(0);
                        
                        if (try message_obj = last_choice.get("message"))
                        {
                            String role = message_obj.get_string("role") ?? "assistant";
                            String content = message_obj.get_string("content") ?? "";
                            Object*? tool_calls = message_obj.get("tool_calls");

                            assistant_message = {
                                .role = role.copy(mem),
                                .content = content.copy(mem),
                                .tool_calls = null,
                            };
                            has_message = true;
                            if (try Object* tc = tool_calls)
                            {
                                tool_calls_for_execute = tc;
                            }

                            io::printfn("%s", content);
                        }
                    }
                }
            }

            if (has_message)
            {
                if (tool_calls_for_execute != null)
                {
                    HistoryRecord? tool_response = execute_command(mem, tool_calls_for_execute);
                    if (catch err = tool_response)
                    {
                        io::printfn(error_message("Execute command failed, %s"), err);
                        message_list.push({
                            .role= "tool",
                            .content = string::format(mem, "execute command with cmd /c failed, for %s", err)
                        });
                        calling_tools = true;
                    }
                    else
                    {
                        message_list.push(tool_response);
                        calling_tools = true;
                    }
                }
                else
                {
                    calling_tools = false;
                    message_list.push(assistant_message);
                }

                io::print("\n");
                retry_on_error = 0;
                continue LOOP;
            }

            io::printn(error_message("BAD RESPONSE"));
            retry_on_error += 1;

            if (retry_on_error > 5)
            {
                io::printn(error_message("retry more than 5 times, force exit"));
                print_history(message_list);
                break LOOP;
            }
        };
    }
}
