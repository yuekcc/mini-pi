module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
import cmd;
import core;

faultdef UNKNOWN_TOOL;

interface Tool
{
    fn String name();
    fn String schema();
    fn String execute(Allocator allocator, Object* args);
}

const String BASH_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "bash",
    "label": "bash",
    "strict": true,
    "description": "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last 2000 lines or 50KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds.",
    "parameters": {
      "type": "object",
      "properties": {
        "command": {
          "type": "string",
          "description": "Bash command to execute"
        },
        "timeout": {
          "type": "number",
          "description": "Timeout in seconds (optional, no default timeout)"
        }
      },
      "required": ["command"],
      "additionalProperties": false
    }
  }
}`;

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

fn String BashTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String command = args.get_string("command") ?? "";
    if (command == "") return "ARGUMENT INVALID, REQUIRE 'command'";
    return tools::bash(allocator, command);
}

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

fn String EditTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    String old_text = args.get_string("oldText") ?? "";
    String new_text = args.get_string("newText") ?? "";
    return tools::edit(allocator, file_path, old_text, new_text);
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

fn String WriteTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    String content = args.get_string("content") ?? "";
    return tools::write(allocator, file_path, content);
}

const String FIND_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "find",
    "label": "find",
    "strict": true,
    "description": "Search for files by glob pattern. Returns matching file paths relative to the search directory. Respects .gitignore. Output is truncated to 500 results or 50KB (whichever is hit first).",
    "parameters": {
      "type": "object",
      "properties": {
        "pattern": {
          "type": "string",
          "description": "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"
        },
        "path": {
          "type": "string",
          "description": "Directory to search in (default: current directory)"
        },
        "limit": {
          "type": "number",
          "description": "Maximum number of results (default: 1000)"
        }
      },
      "required": ["pattern"],
      "additionalProperties": false
    }
  }
}`;

struct FindTool (Tool)
{
    bool _pad;
}

fn String FindTool.name(&self) @dynamic
{
    return "find";
}

fn String FindTool.schema(&self) @dynamic
{
    return FIND_SCHEMA;
}

fn String FindTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String pattern = args.get_string("pattern") ?? "";
    String file_path = args.get_string("path") ?? "";
    return tools::find(allocator, pattern, file_path);
}

const String GREP_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "grep",
    "label": "grep",
    "strict": true,
    "description": "Search file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first). Long lines are truncated to 500 chars.",
    "parameters": {
      "type": "object",
      "properties": {
        "pattern": {
          "type": "string",
          "description": "Search pattern (regex or literal string)"
        },
        "path": {
          "type": "string",
          "description": "Directory or file to search (default: current directory)"
        },
        "glob": {
          "type": "string",
          "description": "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"
        },
        "ignoreCase": {
          "type": "boolean",
          "description": "Case-insensitive search (default: false)"
        },
        "literal": {
          "type": "boolean",
          "description": "Treat pattern as literal string instead of regex (default: false)"
        },
        "context": {
          "type": "number",
          "description": "Number of lines to show before and after each match (default: 0)"
        },
        "limit": {
          "type": "number",
          "description": "Maximum number of matches to return (default: 100)"
        }
      },
      "required": ["pattern"],
      "additionalProperties": false
    }
  }
}`;

struct GrepTool (Tool)
{
    bool _pad;
}

fn String GrepTool.name(&self) @dynamic
{
    return "grep";
}
fn String GrepTool.schema(&self) @dynamic
{
    return GREP_SCHEMA;
}

fn String GrepTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String pattern = args.get_string("pattern") ?? "";
    String file_path = args.get_string("path") ?? "";
    String glob = args.get_string("glob") ?? "";
    bool ignore_case = args.get_bool("ignoreCase") ?? false;
    bool literal = args.get_bool("literal") ?? false;
    int context = args.get_int("context") ?? 0;
    return tools::grep(allocator, pattern, file_path, glob, ignore_case, literal, context);
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

fn String LsTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? ".";
    return tools::ls(allocator, file_path);
}

const String READ_SCHEMA = `{
  "type": "function",
  "function": {
    "name": "read",
    "label": "read",
    "strict": true,
    "description": "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "Path to the file to read (relative or absolute)"
        },
        "offset": {
          "type": "number",
          "description": "Line number to start reading from (1-indexed)"
        },
        "limit": {
          "type": "number",
          "description": "Maximum number of lines to read"
        }
      },
      "required": ["path"],
      "additionalProperties": false
    }
  }
}`;

struct ReadTool (Tool)
{
    bool _pad;
}

fn String ReadTool.name(&self) @dynamic
{
    return "read";
}
fn String ReadTool.schema(&self) @dynamic
{
    return READ_SCHEMA;
}

fn String ReadTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    int offset = args.get_int("offset") ?? -1;
    int limit = args.get_int("limit") ?? -1;
    return tools::read(allocator, file_path, offset, limit);
}

struct ToolPool
{
    Allocator allocator;
    String schema_cache;
    Tool[] tools;
}

fn ToolPool* ToolPool.init(&self, Allocator allocator, InitOptions* init_options)
{
    Tool[*] tmp_tools = {
        (Tool) allocator::new(allocator, BashTool),
        (Tool) allocator::new(allocator, EditTool),
        (Tool) allocator::new(allocator, WriteTool),
        (Tool) allocator::new(allocator, GrepTool),
        (Tool) allocator::new(allocator, LsTool),
        (Tool) allocator::new(allocator, ReadTool),
    };

    self.allocator = allocator;
    self.tools = allocator::clone_slice(allocator, tmp_tools);
    self.schema_cache = "";

    return self;
}

fn void ToolPool.free(&self)
{
}

fn String ToolPool.schema(&self, Allocator allocator)
{
    if (self.schema_cache != "")
    {
        return self.schema_cache.copy(allocator);
    }

    DString buf = dstring::new(tmem);
    bool tool_added = false;
    buf.append("[");
    foreach (tool: self.tools)
    {
        if (tool_added)
        {
            buf.append(",");
        }
        buf.append(tool.schema());
        tool_added = true;
    }
    buf.append("]");

    self.schema_cache = buf.str_view().copy(self.allocator);
    return self.schema_cache.copy(allocator);
}

fn String? ToolPool.do_dispatch(&self, Allocator allocator, String name, Object* args)
{
    io::printfn("> tool dispatch, name = %s, args = %s", name, args);

    foreach (&tool: self.tools)
    {
        if (tool.name() == name)
        {
            return tool.execute(allocator, args);
        }
    }

    return UNKNOWN_TOOL~;
}

fn Message* ToolPool.dispatch(&self, Allocator allocator, ToolCall* tool_call)
{
    @pool()
    {
        Object* args = json::parse_string(tmem, tool_call.arguments)!!;
        Message* msg = allocator::new(allocator, Message);
        msg.id = tool_call.id.copy(allocator);
        msg.role = "tool";

        if (try result = self.do_dispatch(tmem, tool_call.name, args))
        {
            msg.content = result.copy(allocator);
        }
        else
        {
            msg.content = "UNKNOWN_TOOL";
        }

        return msg;
    };
}
