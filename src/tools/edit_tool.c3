module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;

import cmd;


const String EDIT_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "edit",
    "label": "edit",
    "strict": true,
    "description": "Edit a file by replacing exact text. The oldText must match exactly (including whitespace). Use this for precise, surgical edits.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Path to the file to edit (relative or absolute)"
        },
        "oldText": {
          "type": "string",
          "description": "Exact text to find and replace (must match exactly)"
        },
        "newText": {
          "type": "string",
          "description": "New text to replace the old text with"
        }
      },
      "required": ["path", "oldText", "newText"],
      "additionalProperties": false
    }
  }
}`;

struct EditTool (Tool)
{
    bool _pad;
}

fn String EditTool.name(&self) @dynamic
{
    return "edit";
}

fn String EditTool.schema(&self) @dynamic
{
    return EDIT_SCHEMA;
}

fn String? EditTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    String old_text = args.get_string("oldText") ?? "";
    String new_text = args.get_string("newText") ?? "";
    return edit(allocator, file_path, old_text, new_text);
}
