module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
import cmd;

/** String 列表类型别名 */
alias StringList = List{String};

/**
 * 执行 Bash 命令
 * @allocator: 内存分配器
 * @command: 要执行的 shell 命令
 * @timeout_s: 超时时间（秒），-1 表示无超时限制
 * @return: 包含退出码和命令输出的字符串
 */
fn String bash(Allocator allocator, String command, int timeout_s = -1)
{
    String[] final_command = {"sh", "-c", command};
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

/**
 * 编辑文件内容（替换指定文本）
 * @allocator: 内存分配器
 * @file_path: 文件路径
 * @old_text: 要替换的原始文本
 * @new_text: 替换后的新文本
 * @return: 操作结果状态消息
 */
fn String edit(Allocator allocator, String file_path, String old_text, String new_text)
{
    Path? path_obj = path::new(tmem, file_path);
    if (try path_obj)
    {
        if (try content = file::load_path(tmem, path_obj))
        {
            // 规范化行尾符（处理 CRLF/LF 不一致问题）
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

/**
 * 使用 fd 命令查找文件
 * @allocator: 内存分配器
 * @pattern: 文件名匹配模式
 * @file_path: 搜索起始路径（可选）
 * @limit: 最大结果数量
 * @return: 查找结果
 */
fn String find(Allocator allocator, String pattern, String file_path = "", int limit = 1000)
{
    String[] final_command = file_path != "" ? {"fd", pattern, file_path} : {"fd", pattern};
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

/**
 * 使用 ripgrep (rg) 命令搜索文件内容
 * @allocator: 内存分配器
 * @pattern: 搜索模式（正则表达式）
 * @file_path: 搜索文件路径（可选）
 * @glob: 文件名过滤 glob 模式（可选）
 * @ignore_case: 是否忽略大小写
 * @literal: 是否按字面量匹配（非正则）
 * @context: 显示匹配行前后的上下文行数
 * @limit: 最大结果数量
 * @return: 搜索结果
 */
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

/**
 * 列出目录内容
 * @allocator: 内存分配器
 * @file_path: 要列出的目录路径（默认为当前目录）
 * @limit: 最大显示数量
 * @return: 目录列表结果
 */
fn String ls(Allocator allocator, String file_path = "", int limit = 500)
{
    String[] final_command = file_path != "" ? {"ls", "-ahl", file_path} : {"ls", "-ahl"};
    CommandResult result = cmd::execute(allocator, final_command)!!;

    DString output = dstring::new(tmem);
    output.appendf("Command exited with code %s\n\n%s", result.code, result.output);
    return output.copy_str(allocator);
}

/**
 * 读取文件内容
 * @allocator: 内存分配器
 * @file_path: 要读取的文件路径
 * @offset: 起始行号（1-indexed，可选）
 * @limit: 最大读取行数，-1 表示读取全部（可选）
 * @return: 文件内容字符串
 */
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

/**
 * 写入内容到文件
 * @allocator: 内存分配器
 * @file_path: 目标文件路径
 * @content: 要写入的内容
 * @return: 操作结果状态消息
 */
fn String write(Allocator allocator, String file_path, String content)
{
    return tools::write_file(allocator, file_path, content);
}

/**
 * 内部写入文件函数
 */
fn String write_file(Allocator allocator, String file_path, String content)
{
    if (try file::save(file_path, content))
    {
        return "(Success)";
    }
    return "WRITE FILE FAILED";
}
