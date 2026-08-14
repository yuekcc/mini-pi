module log;

import std::io;
import std::io::file;
import std::io::path;
import std::time::datetime;
import std::thread;

// 分级别日志（Logger 对象化，arch-next-spec 决策 5）。
//
// 两级 sink：
// - 文件 sink：任意线程可写，内部 mutex 保护（单次 fprintf + flush，保证行完整、
//   无交错字节）。
// - 控制台 sink：只走主线程。info 走 stdout 作为常规运行信息，debug/warn/error 走
//   stderr；不带颜色（颜色是 ui 层的职责，与 NO_COLOR 解耦）。非 UI 线程的日志经
//   console_sink 回调转发（main 启动时注册，实现为向 UI 事件通道投递 LogEvent），
//   由主线程统一打印，保证不交错。
//
// 文件格式："[YYYY-MM-DD HH:MM:SS] [LEVEL] 消息"，纯文本，无 ANSI 颜色码。
//
// g_default：main 启动早期用 set_default() 登记的默认实例指针——只写一次（先于任何
// 线程创建），此后各线程只读，供 tool/api 等无 AppContext 引用的模块使用
// log::info/warn/error/debug 宏。AppContext.logger 指向同一实例。

enum LogLevel
{
	INFO,  // stdout
	WARN,  // stderr
	ERROR, // stderr
	DEBUG, // stderr
}

// 非主线程日志的控制台转发负载：text 已格式化完整行（含级别前缀），所有权移交 sink。
struct LogLine
{
	String text;      // heap（sink 负责释放）
	bool to_stderr;
}

alias ConsoleSinkFn = fn void(void* ctx, LogLine line);

struct Logger
{
	File log_file;      // 文件 sink（追加模式；file_open=false 表示未就绪）
	bool file_open;
	bool debug_enabled; // debug 级别过滤开关（受 --debug 控制）
	Mutex mu;           // 文件 sink 互斥（任意线程写）
	Thread main_thread; // 主线程 ID（控制台直接打印判定）
	ConsoleSinkFn console_sink; // 非主线程控制台转发（null = 直接打印兜底）
	void* console_sink_ctx;
}

Logger* g_default = null;

// main 启动早期显式登记默认 logger 实例（只写一次，先于任何线程创建；此后只读）。
// 测试中不调用：g_default 保持 null，日志宏的文件 sink 静默 no-op。
fn void set_default(Logger* logger)
{
	g_default = logger;
}

// 打开日志文件句柄（追加模式）。任何失败（目录创建失败、文件打开失败）均静默
// 降级为仅控制台输出，不影响程序运行。
fn void Logger.init(&self, Path log_file, bool enable_debug)
{
	self.file_open = false;
	self.debug_enabled = enable_debug;
	self.main_thread = thread::current();
	self.console_sink = null;
	self.console_sink_ctx = null;

	if (catch self.mu.init()) return;

	if (log_file == "") return;

	// 确保父目录存在（路径形如 <config_dir>/log/ses_xxx.log）
	if (try parent = log_file.parent())
	{
		if (!path::exists(parent))
		{
			if (catch path::mkdir(parent, true)) return;
		}
	}

	if (try f = file::open_path(log_file, "a"))
	{
		self.log_file = f;
		self.file_open = true;
	}
}

// 注册非主线程控制台日志转发（main 在 UI 事件循环启动前调用一次）。
fn void Logger.set_console_sink(&self, ConsoleSinkFn sink, void* ctx)
{
	self.console_sink = sink;
	self.console_sink_ctx = ctx;
}

// 关闭日志文件句柄。进程退出前调用；不调用也无妨——每次写入后已 flush，
// 操作系统会在进程退出时回收文件描述符。
fn void Logger.close(&self)
{
	if (self.file_open)
	{
		(void)self.log_file.close();
		self.file_open = false;
	}
}

// 将一条日志写入文件，格式 "[时间戳] [级别] 消息"。文件 sink 未就绪时静默返回。
// 任何写入错误静默忽略，避免日志系统拖垮主流程。
fn void Logger.to_file(&self, String level, String format, args...)
{
	if (!self.file_open) return;

	String ts = datetime::now().to_local().format(tmem, DateTimeFormat.DATETIME);
	// 先把时间戳和级别拼到 format 头部，再一次性 fprintf，减少 IO 次数。
	// ts/level 均为受控内容（数字/固定字符串），不会引入额外的 % 占位符。
	String line_format = string::tformat("[%s] [%s] %s\n", ts, level, format);

	(void)self.mu.lock();
	(void)io::fprintf(&self.log_file, line_format, ...args);
	(void)self.log_file.flush();
	self.mu.unlock();
}

// 控制台 sink：主线程直接打印；非主线程格式化后经 console_sink 转发（未注册时
// 直接打印兜底，覆盖测试与启动早期）。文本分配在调用线程的 tmem（临时值，
// 直接打印安全；转发路径由 sink 负责拷贝到堆）。
fn void Logger.console(&self, LogLevel level, String format, args...)
{
	String tag = "";
	bool to_stderr = false;
	switch (level)
	{
		case INFO: break;
		case WARN:
			tag = "[WARN] ";
			to_stderr = true;
		case ERROR:
			tag = "[ERROR] ";
			to_stderr = true;
		case DEBUG:
			tag = "[DEBUG] ";
			to_stderr = true;
	}

	String line = string::tformat("%s%s", tag, string::tformat(format, ...args));

	if (thread::current() == self.main_thread || self.console_sink == null)
	{
		if (to_stderr)
		{
			io::eprintfn("%s", line);
		}
		else
		{
			io::printfn("%s", line);
		}
		return;
	}

	LogLine payload = { .text = line, .to_stderr = to_stderr };
	self.console_sink(self.console_sink_ctx, payload);
}

// 控制台 sink 的默认实现：把 LogLine 投递到 UI 事件通道（见 main.c3 注册）。
// text 拷贝到堆，UI 线程处理后释放。

macro void debug(String $format, args...)
{
	if (g_default != null && g_default.debug_enabled)
	{
		g_default.console(LogLevel.DEBUG, $format, ...args);
	}
	if (g_default != null) g_default.to_file("DEBUG", $format, ...args);
}

macro void info(String $format, args...)
{
	if (g_default != null)
	{
		g_default.console(LogLevel.INFO, $format, ...args);
		g_default.to_file("INFO", $format, ...args);
	}
	else
	{
		io::printfn($format, ...args);
	}
}

macro void warn(String $format, args...)
{
	if (g_default != null)
	{
		g_default.console(LogLevel.WARN, $format, ...args);
		g_default.to_file("WARN", $format, ...args);
	}
	else
	{
		io::eprintfn("[WARN] " +++ $format, ...args);
	}
}

macro void error(String $format, args...)
{
	if (g_default != null)
	{
		g_default.console(LogLevel.ERROR, $format, ...args);
		g_default.to_file("ERROR", $format, ...args);
	}
	else
	{
		io::eprintfn("[ERROR] " +++ $format, ...args);
	}
}
