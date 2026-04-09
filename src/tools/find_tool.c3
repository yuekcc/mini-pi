module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;

fn String? find(Allocator allocator, String pattern, String file_path = "", int limit = 1000)
{
    List{String} final_command;
    final_command.init(tmem);

    final_command.push("fd");

    if (pattern != "" && pattern.contains("*"))
    {
        final_command.push("-g");
    }

    final_command.push(pattern);

    if (file_path != "")
    {
        final_command.push(pattern);
    }

    CommandResult result = cmd::execute(allocator, final_command.to_array(tmem))!;
    if (result.code == 0)
    {
        return result.output.copy(allocator);
    }

    return EXECUTE_FD_COMMAND_ERROR~;
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

fn String? FindTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String pattern = args.get_string("pattern") ?? "";
    String file_path = args.get_string("path") ?? "";
    return find(allocator, pattern, file_path);
}
