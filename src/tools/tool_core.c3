module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
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
            String normalized_content = ((String)content).treplace("\r\n", "\n");
            String normalized_old = old_text.treplace("\r\n", "\n");
            String normalized_new = new_text.treplace("\r\n", "\n");

            String updated = normalized_content.replace(tmem, normalized_old, normalized_new).copy(allocator);
            return tools::write_file(allocator, file_path, updated);
        }
        return "READ FILE FAILED";
    }
    return "INVALID_PATH";
}

fn String find(Allocator allocator, String pattern, String file_path = "", int limit = 1000)
{
    String[] final_command = file_path != "" ? {"fd", pattern, file_path} : {"fd", pattern};
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

fn String grep(Allocator allocator, String pattern, String file_path = "", String glob = "", bool ignore_case = false, bool literal = false, int context = 0, int limit = 100)
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
        return "READ FILE FAILED";
    }
    return "INVALID_PATH";
}

fn String write(Allocator allocator, String file_path, String content)
{
    return tools::write_file(allocator, file_path, content);
}

fn String write_file(Allocator allocator, String file_path, String content)
{
    if (try file::save(file_path, content))
    {
        return "(Success)";
    }
    return "WRITE FILE FAILED";
}
