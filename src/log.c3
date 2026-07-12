module log;

import std::io;
import global;

// 分级别日志。debug 受 global::debug() 开关控制；info/warn/error 始终输出。
// 全部走 stderr（info 除外，info 走 stdout 作为常规运行信息），不带颜色，
// 颜色是 ui 层的职责，与 NO_COLOR 解耦。

macro void debug(String $format, args...)
{
	if (global::debug())
	{
		io::eprintfn("[DEBUG] " +++ $format, ...args);
	}
}

macro void info(String $format, args...)
{
	io::printfn($format, ...args);
}

macro void warn(String $format, args...)
{
	io::eprintfn("[WARN] " +++ $format, ...args);
}

macro void error(String $format, args...)
{
	io::eprintfn("[ERROR] " +++ $format, ...args);
}
