module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;

import cmd;

const String WRITE_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "write",
    "label": "write",
    "strict": true,
    "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Path to the file to write (relative or absolute)"
        },
        "content": {
          "type": "string",
          "description": "Content to write to the file"
        }
      },
      "required": ["path", "content"],
      "additionalProperties": false
    }
  }
}`;

struct WriteTool (Tool)
{
    bool _pad;
}

fn String WriteTool.name(&self) @dynamic
{
    return "write";
}

fn String WriteTool.schema(&self) @dynamic
{
    return WRITE_SCHEMA;
}

fn String? WriteTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    String content = args.get_string("content") ?? "";
    return write(allocator, file_path, content);
}
