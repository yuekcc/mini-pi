module ui;

import std::io;
import std::os::env;
import std::time::datetime;

import context;

// NO_COLOR 约定（https://no-color.org）：环境变量存在且非空时禁用颜色。
// init() 在 main 启动时调用一次，缓存结果。
tlocal bool _no_color = false;

fn void init()
{
	@pool()
	{
		if (try v = env::get_var(tmem, "NO_COLOR"))
		{
			_no_color = v.len > 0;
		}
	};
}

fn bool no_color() => _no_color;

// 私有：带颜色包裹的输出，NO_COLOR 时退化为纯文本。
macro void c_print(String $prefix, String $fmt, args...)
{
	if (no_color())
	{
		io::printf($fmt, ...args);
	}
	else
	{
		io::printf($prefix +++ $fmt +++ Ansi.RESET, ...args);
	}
}

macro void c_println(String $prefix, String $fmt, args...)
{
	if (no_color())
	{
		io::printfn($fmt, ...args);
	}
	else
	{
		io::printfn($prefix +++ $fmt +++ Ansi.RESET, ...args);
	}
}

// 工具结果折叠预览：只显示前 8 行（单行超长再截断），完整输出见 transcript。
// 折叠仅影响终端显示，消息 content 仍完整保留（发给模型、写入 transcript）。
const usz TOOL_PREVIEW_LINES = 8;
const usz TOOL_PREVIEW_LINE_LEN = 200;

fn void render_tool_preview(String content, String tool_name)
{
	String[] lines = content.split(tmem, "\n");

	// 行数统计：跳过末尾空行（trim 后一般不出现，稳妥起见）
	usz line_count = lines.len;
	while (line_count > 0 && lines[line_count - 1].len == 0) line_count--;

	if (tool_name.len > 0)
	{
		c_println(Ansi.BG_BRIGHT_BLACK +++ Ansi.WHITE, "\n%s · %d lines · %d chars:", tool_name, line_count, content.len);
	}
	else
	{
		c_println(Ansi.BG_BRIGHT_BLACK +++ Ansi.WHITE, "\n%d lines · %d chars:", line_count, content.len);
	}

	usz preview = line_count < TOOL_PREVIEW_LINES ? line_count : TOOL_PREVIEW_LINES;
	for (usz i = 0; i < preview; i++)
	{
		String line = lines[i];
		if (line.len > TOOL_PREVIEW_LINE_LEN)
		{
			String clipped = line[:TOOL_PREVIEW_LINE_LEN];
			line = string::tformat("%s...", clipped);
		}
		c_println(Ansi.BRIGHT_BLACK, "%s", line);
	}

	if (line_count > preview)
	{
		c_println(Ansi.BRIGHT_BLACK, "... %d more lines (full output in transcript)", line_count - preview);
	}
}

// 渲染一条会话消息。模式无关：headless 与交互模式均使用。
// tool_name 仅用于 tool 结果的折叠标题（rat_loop 传入工具名，其余调用不传）。
fn void render_message(Message* msg, String tool_name = "")
{
	if (!msg) return;

	defer io::print("\n");

	c_println(Ansi.BOLD, "%s %s:", msg.timestamp.to_local().format(tmem, DateTimeFormat.DATETIME), msg.role);

	String content = msg.content.trim().replace(tmem, "\t", "    ");
	String reasoning_content = msg.reasoning_content.trim().replace(tmem, "\t", "    ");

	if (msg.role == "tool" && content != "")
	{
		render_tool_preview(content, tool_name);
		return;
	}

	if (reasoning_content != "")
	{
		c_println(Ansi.BRIGHT_BLACK +++ Ansi.ITALIC, "\nThinking ... %s", reasoning_content);
	}

	if (content != "")
	{
		io::printfn("\n%s", content);
	}

	if (msg.role == "assistant" && msg.tool_calls.len() > 0)
	{
		io::print("\n");
		foreach (&tc : msg.tool_calls)
		{
			c_println(Ansi.BRIGHT_YELLOW, "(Call tool: %s with %s)", tc.name, tc.arguments);
		}
	}
}

// 启动横幅。仅交互模式调用，走 stderr。
fn void banner(String version, Path config_dir, Path log_file, bool debug_on)
{
	io::eprintfn("\n %s v%s", Ansi.BOLD +++ "mp" +++ Ansi.RESET, version);
	io::eprintfn(" Using config dir: %s", config_dir);
	io::eprintfn(" Using log file: %s", log_file);
	io::eprintfn(" Debug mode: %s", debug_on ? "on" : "off");
	io::eprintfn(" /exit exit ・ /clear clean history ・ /export export history");
	io::eprint("\n");
}

// 交互输入提示：打印 ">>> "（带颜色），读取一行，复位颜色。返回输入字符串。
fn String read_prompt(Allocator allocator)
{
	if (no_color())
	{
		io::print(">>> ");
	}
	else
	{
		io::print(Ansi.BOLD +++ Ansi.GREEN +++ ">>> ");
	}
	String input = io::readline(allocator)!!;
	if (!no_color()) io::print(Ansi.RESET);
	return input;
}

// 黄色括号状态提示，尾部带空行。用于 (Saved to ...)/(DONE)/(Bye ...) 等。
macro void notice(String $format, args...)
{
	if (no_color())
	{
		io::printfn("(" +++ $format +++ ")\n", ...args);
	}
	else
	{
		io::printfn(Ansi.BRIGHT_YELLOW +++ "(" +++ $format +++ ")" +++ Ansi.RESET +++ "\n", ...args);
	}
}
