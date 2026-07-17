module log;

import std::io;
import std::io::file;
import std::io::path;
import std::time::datetime;

import global;

// 分级别日志。debug 受 global::debug() 开关控制；info/warn/error 始终输出。
//
// 控制台：info 走 stdout 作为常规运行信息，debug/warn/error 走 stderr；不带颜色
//         （颜色是 ui 层的职责，与 NO_COLOR 解耦）。
//
// 文件：全部级别追加写入 global::log_file() 指向的日志文件，每行格式为
//       "[YYYY-MM-DD HH:MM:SS] [LEVEL] 消息"。纯文本，无 ANSI 颜色码。
//
// 生命周期：main 启动时调用 log::init() 一次性打开文件；若未调用，首次写日志时
//           懒加载打开。init 失败时静默降级为仅控制台输出，绝不抛错。

tlocal File _log_file;
tlocal bool _log_open = false;
tlocal bool _init_done = false;

// 显式初始化日志文件句柄。在 main 启动早期调用一次。重复调用安全（幂等）。
// 任何失败（目录创建失败、文件打开失败）均静默降级，不影响程序运行。
fn void init()
{
	if (_init_done) return;
	_init_done = true;

	Path log_path = global::log_file();
	if (log_path == "") return;

	// 确保父目录存在（路径形如 <config_dir>/log/ses_xxx.log）
	if (try parent = log_path.parent())
	{
		if (!path::exists(parent))
		{
			if (catch path::mkdir(parent, true)) return;
		}
	}

	// 追加模式打开；失败则降级为仅控制台输出
	if (try f = file::open_path(log_path, "a"))
	{
		_log_file = f;
		_log_open = true;
	}
}

// 关闭日志文件句柄。进程退出前可选调用；不调用也无妨——每次写入后已 flush，
// 操作系统会在进程退出时回收文件描述符。
fn void close()
{
	if (_log_open)
	{
		(void)_log_file.close();
		_log_open = false;
	}
}

// 内部：将一条日志写入文件，格式 "[时间戳] [级别] 消息"。
// 若日志文件未就绪（init 未调用或失败），直接返回，不影响控制台输出。
// 任何写入错误静默忽略，避免日志系统拖垮主流程。
fn void _to_file(String level, String format, args...)
{
	if (!_log_open) return;

	String ts = datetime::now().to_local().format(tmem, DateTimeFormat.DATETIME);
	// 先把时间戳和级别拼到 format 头部，再一次性 fprintf，减少 IO 次数。
	// ts/level 均为受控内容（数字/固定字符串），不会引入额外的 % 占位符。
	String line_format = string::tformat("[%s] [%s] %s\n", ts, level, format);
	(void)io::fprintf(&_log_file, line_format, ...args);
	(void)_log_file.flush();
}

macro void debug(String $format, args...)
{
	if (global::debug())
	{
		io::eprintfn("[DEBUG] " +++ $format, ...args);
		_to_file("DEBUG", $format, ...args);
	}
}

macro void info(String $format, args...)
{
	io::printfn($format, ...args);
	_to_file("INFO", $format, ...args);
}

macro void warn(String $format, args...)
{
	io::eprintfn("[WARN] " +++ $format, ...args);
	_to_file("WARN", $format, ...args);
}

macro void error(String $format, args...)
{
	io::eprintfn("[ERROR] " +++ $format, ...args);
	_to_file("ERROR", $format, ...args);
}
