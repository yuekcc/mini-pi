module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;


fn String? ls(Allocator allocator, String file_path = "", int limit = 500)
{
	String[] final_command = file_path != "" ? {"ls", "-ahl", file_path} : {"ls", "-ahl"};
	CommandResult result = cmd::execute(allocator, final_command)!;
	if (result.code == 0)
	{
		return result.output.copy(allocator);
	}

	return EXECUTE_LS_COMMAND_ERROR~;
}

const String LS_SCHEMA = `{
  "type": "function",
  "function": {
	"name": "ls",
	"label": "ls",
	"strict": true,
	"description": "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit first).",
	"parameters": {
	  "type": "object",
	  "properties": {
		"path": {
		  "type": "string",
		  "description": "Directory to list (default: current directory)"
		},
		"limit": {
		  "type": "number",
		  "description": "Maximum number of entries to return (default: 500)"
		}
	  },
	  "required": [],
	  "additionalProperties": false
	}
  }
}`;

struct LsTool (Tool)
{
	bool _pad;
}

fn String LsTool.name(&self) @dynamic
{
	return "ls";
}

fn String LsTool.schema(&self) @dynamic
{
	return LS_SCHEMA;
}

fn String? LsTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
	String file_path = args.get_string("path") ?? ".";
	return ls(allocator, file_path);
}
