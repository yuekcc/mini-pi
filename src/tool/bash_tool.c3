module tool;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;

import c3x::object;
import util::cmd;
import util;

const LINE_LIMIT = 2000;

fn void? bash(Allocator allocator, DString out, String command)
{
	String task_id =  util::timestamp_id(tmem);
	Path store_dir = load_store_dir(tmem);

	String[] final_command = { "sh", "-c", command };
	CommandResult result = cmd::execute(allocator, final_command)!;

	String command_output = result.output.trim();

	Path output_file = store_dir.append(tmem, string::tformat("%s_output.txt", task_id))!!;
	file::save(output_file, command_output)!!;

	String[] all_lines = command_output.split(tmem, "\n");
	bool should_truncated = all_lines.len > LINE_LIMIT;

	// 回显执行的命令
	out.appendf("$ %s\n\n", command);

	// 截断命令行输出，保留最后的 2000 行
	usz start_idx = should_truncated ? (all_lines.len - LINE_LIMIT) : 0;
	for (usz i = start_idx; i < LINE_LIMIT && i < all_lines.len; i++)
	{
		out.appendf("%s\n", all_lines[i]);	
	}

	// 截断了就增加提示
	if (should_truncated)
	{
		out.appendf("... (truncated, full output stored at %s)\n", output_file);
	}

	// 非 0 结束增加提示
	if (result.code != 0)
	{
		out.appendf("\n\nCommand exited with code %d", result.code);
	}
}

const String BASH_SCHEMA = (String)$embed("bash_tool_schema.json");

struct BashTool (Tool)
{
	bool _pad;
}

fn String BashTool.name(&self) @dynamic
{
	return "bash";
}

fn String BashTool.schema(&self) @dynamic
{
	return BASH_SCHEMA;
}

fn void? BashTool.execute(&self, Allocator allocator, DString out, Object* args) @dynamic
{
	String command = args.get_string("command") ?? "";
	if (command == "") return INVALID_COMMAND_PARAM~;
	bash(allocator, out, command)!;
}
