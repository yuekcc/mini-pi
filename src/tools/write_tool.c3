module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;

fn String? write(Allocator allocator, String file_path, String content)
{
    Path path_obj = path::new(tmem, file_path)!;
    file::save(path_obj.str_view(), content)!;
    return string::format(allocator, "(Saved to %s)", path_obj.str_view());
}

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
