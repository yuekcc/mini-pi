module util::ctrl_c;

// Ctrl+C 捕获（arch-next-spec 决策 12 的信号基础）。
//
// handler 内只做一件事：atomic store（在信号 handler 中安全）。返回值表示已处理，
// 阻止默认终止。主循环观察到标志后按状态分流（L1 请求中断 / L3 会话中断）。
//
// 注意：Windows 的 SetConsoleCtrlHandler 回调运行在独立线程（非主线程）；
// POSIX 信号可能打断任意线程。因此 handler 只能触碰 atomic。
// 平台绑定无条件声明（未使用平台不引用，链接器不会解析；$if 只在函数体内使用，
// c3 0.8.3 不支持模块级 $if）。

import std::atomic;
import std::os::posix;

Atomic{bool} g_ctrl_c;

alias HandlerRoutine = fn int(uint ctrl_type);

// Windows：SetConsoleCtrlHandler（handler 返回 TRUE 阻止默认终止）
extern fn int set_console_ctrl_handler(HandlerRoutine handler, int add) @cname("SetConsoleCtrlHandler");

fn int ctrl_c_routine(uint ctrl_type)
{
	if (ctrl_type == 0 /* CTRL_C_EVENT */ || ctrl_type == 1 /* CTRL_BREAK_EVENT */)
	{
		g_ctrl_c.store(true);
		return 1;
	}
	return 0;
}

// POSIX：SIGINT handler
fn void ctrl_c_signal(int signal)
{
	g_ctrl_c.store(true);
}

// main 启动时调用一次（交互与 headless 均安装；headless 下用于优雅停机）。
fn void install()
{
	$if env::WIN32:
		(void)set_console_ctrl_handler(&ctrl_c_routine, 1);
	$else
		posix::install_signal_handler(2 /* SIGINT */, &ctrl_c_signal);
	$endif
}

// 主循环轮询：返回自上次调用以来是否按下过 Ctrl+C（读取后复位）。
fn bool pressed()
{
	if (!g_ctrl_c.load()) return false;
	g_ctrl_c.store(false);
	return true;
}
