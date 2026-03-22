module tools;

import std::io;
import std::io::path;
import std::collections::list;
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