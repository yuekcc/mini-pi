module util::input;

// 非阻塞 stdin 就绪检查（UI 主循环轮询用，arch-next-spec 决策 8 的输入轮询方案）。
// Windows：GetNumberOfConsoleInputEvents；POSIX：poll(fd 0, timeout 0)。
// 非控制台 stdin（管道/文件重定向）：恒返回 true，UI 主循环回退到阻塞 readline
// （与 v1 语义一致；此时渲染事件在输入等待期间排队）。
// 平台 extern 声明均为模块级（未使用平台不引用，链接器不会解析）。

// Windows 控制台（仅 $if env::WIN32 分支引用）
extern fn void* get_std_handle(uint handle) @cname("GetStdHandle");
extern fn int get_number_of_console_input_events(void* handle, uint* count) @cname("GetNumberOfConsoleInputEvents");
extern fn uint get_file_type(void* handle) @cname("GetFileType");

// POSIX poll / isatty（仅 !WIN32 分支引用）
struct PollFd
{
	int fd;
	short events;
	short revents;
}
extern fn int poll(PollFd* fds, ulong nfds, int timeout) @cname("poll");
extern fn int isatty(int fd) @cname("isatty");

fn bool stdin_has_data()
{
	$if env::WIN32:
		void* h = get_std_handle((uint)-10); // STD_INPUT_HANDLE
		if (h == null) return true; // 无控制台句柄：回退阻塞读
		if (get_file_type(h) != 0x0002 /* FILE_TYPE_CHAR */) return true; // 管道/文件：回退阻塞读
		uint count = 0;
		return get_number_of_console_input_events(h, &count) != 0 && count > 0;
	$else
		if (isatty(0) == 0) return true; // 管道/文件：回退阻塞读
		PollFd pfd = { .fd = 0, .events = 0x0001 /* POLLIN */, .revents = 0 };
		return poll(&pfd, 1, 0) > 0;
	$endif
}
