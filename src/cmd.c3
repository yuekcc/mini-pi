module cmd;

import std::os::process;
import std::io;

/**
 * 命令执行结果结构体
 * @code: 进程退出码，0 表示成功
 * @output: 标准输出和标准错误的合并内容
 */
struct CommandResult
{
    int code;
    String output;
}

/**
 * 执行外部命令并捕获输出
 * @allocator: 内存分配器
 * @command_line: 命令及其参数列表
 * @return: 命令执行结果，失败时返回 null
 */
fn CommandResult? execute(Allocator allocator, String[] command_line) 
{
    process::SubProcess process = process::create(
        command_line,
        {
            .combined_stdout_stderr = true,  // 合并 stdout 和 stderr
            .inherit_environment = true,    // 继承环境变量
            .search_user_path = true,       // 在用户 PATH 中搜索命令
            .no_window = true,               // Windows 下不显示窗口
            .inherit_stdio = false,          // 不继承标准 IO
        }
    )!;

    @pool()
    {
        DString result = dstring::new(tmem);
        // 读取命令输出直到完毕
        while(true)
        {
            char[512] buf @noinit;
            usz len = process.read_stdout(&buf, buf.len)!;
            if (len == 0)
            {
                break;
            }

            result.write(buf[:len])!;
        }

        // 等待进程完全结束
        while (true)
        {
            if (!process.is_running()!) {
                process.destroy();
                break;
            }
        }

        return {
            .code = 0,
            .output = result.copy_str(allocator)
        };
    };
}

/**
 * 执行命令并直接返回输出字符串
 * @allocator: 内存分配器
 * @command_line: 命令及其参数列表
 * @return: 命令输出字符串
 */
fn String? execute_to_string(Allocator allocator, String[] command_line)
{
    CommandResult cmd_result = execute(allocator, command_line)!;
    return cmd_result.output;
}

