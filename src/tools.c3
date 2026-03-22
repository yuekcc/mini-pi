module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import cmd;

alias StringList = List{String};

fn String bash(Allocator allocator, String command, int timeout_s = -1)
{
    String[] final_command = {"sh", "-c", command}; 
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

fn String edit(Allocator allocator, String file_path, String old_text, String new_text)
{
    Path? path_obj = path::new(tmem, file_path);
    if (try path_obj)
    {
        if (try content = file::load_path(tmem, path_obj))
        {
            String updated = ((String)content).replace(tmem, old_text, new_text).copy(allocator);
            return write(allocator, file_path, updated);
        }
        else
        {
            return "READ FILE FAILED";
        }
    }
    else
    {
        return "INVALID_PATH";
    };
}

fn String find(Allocator allocator, String pattern, String file_path = "", int limit = 1000)
{
    String[] final_command = file_path != "" ? {"fd", pattern, file_path} : {"fd", pattern}; 
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

fn String grep(Allocator allocator, String pattern, String file_path = "", String glob = "", bool ignore_case = false, bool literal = false,  int context = 0, int limit = 100)
{
    StringList final_command;
    final_command.init(tmem);
    
    final_command.push("rg");
    final_command.push(pattern);
    if (file_path != "")
    {
        final_command.push(file_path);
    }
    if (glob != "")
    {
        final_command.push("--glob");
        final_command.push(glob);
    }
    if (ignore_case)
    {
        final_command.push("--ignore-case");
    }
    if (literal)
    {
        final_command.push("--fixed-strings");
    }
    if (context > 0)
    {
        final_command.push("-C");
        final_command.push(string::format(tmem, "%d", context));
    }

    CommandResult result = cmd::execute(allocator, final_command.to_array(tmem))!!;
    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

fn String ls(Allocator allocator, String file_path = "", int limit = 500)
{
    String[] final_command = file_path != "" ? {"ls", "-ahl", file_path} : {"ls", "-ahl"}; 
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

fn String read(Allocator allocator, String file_path, int offset = 1, int limit = -1)
{
    Path? path_obj = path::new(tmem, file_path);
    if (try path_obj)
    {
        if (try content = file::load_path(tmem, path_obj))
        {
            return ((String)content).copy(allocator);
        }
        else
        {
            return "READ FILE FAILED";
        }
    }
    else
    {
        return "INVALID_PATH";
    };
}

fn String write(Allocator allocator, String file_path, String content)
{
    if (try file::save(file_path, content))
    {
        return "(Success)";
    }
    else
    {
        return "WRITE FILE FAILED";
    }
}

fn String dispatch(Allocator allocator, String name, Object* args)
{
    io::printfn("> tool dispatch, name = %s, args = %s", name, args);

    switch (name)
    {
        case "bash":
            String command = args.get_string("command") ?? "";
            if (command != "")
            {
                return bash(allocator, command);
            }
            return "ARGUMENT INVALID, REQUIRE 'command'";
        case "edit":
            String file_path = args.get_string("path") ?? "";
            String old_text = args.get_string("oldText") ?? "";
            String new_text = args.get_string("newText") ?? "";
            if (file_path == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'path'";
            }
            if (old_text == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'oldText'";
            }
            if (new_text == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'newText'";
            }
            return edit(allocator, file_path, old_text, new_text);
        case "write":
            String file_path = args.get_string("path") ?? "";
            if (file_path == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'path'";
            }
            String content = args.get_string("content") ?? "";
            return write(allocator, file_path, content);
        case "find":
            String pattern = args.get_string("pattern") ?? "";
            if (pattern == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'pattern'";
            }
            String file_path = args.get_string("path") ?? "";
            return find(allocator, pattern, file_path);
        case "grep":
            String pattern = args.get_string("pattern") ?? "";
            if (pattern == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'pattern'";
            }
            String file_path = args.get_string("path") ?? "";
            String glob = args.get_string("glob") ?? "";
            bool ignore_case = args.get_bool("ignoreCase") ?? false;
            bool literal = args.get_bool("literal") ?? false;
            int context = args.get_int("context") ?? 0;
            return grep(allocator, pattern, file_path, glob, ignore_case, literal, context);
        case "ls":
            String file_path = args.get_string("path") ?? "";
            if (file_path == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'path'";
            }
            return ls(allocator, file_path);
        case "read":
            String file_path = args.get_string("path") ?? "";
            if (file_path == "")
            {
                return "ARGUMENT INVALID, REQUIRE 'path'";
            }
            int offset = args.get_int("offset") ?? -1;
            int limit = args.get_int("limit") ?? -1;
            return read(allocator, file_path, offset, limit);
        default:
            return string::format(allocator, "UNKNOWN TOOL '%s', RECHECK YOUR TOOL LIST", name);
    }
}