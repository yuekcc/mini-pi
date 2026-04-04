module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;

fn String pad_line_numbers(Allocator allocator, String content)
{
    String[] lines = content.split(tmem, "\n");
    usz width = (usz)string::format(tmem, "%d", lines.len).len;

    DString buf = dstring::new(tmem);
    foreach (i, &line : lines)
    {
        String line_num = string::format(tmem, "%d", i+1);
        buf.appendf("%s%s: %s\n", util::pad_start(tmem, width - line_num.len, "0"), line_num, *line);
    }

    buf.appendf("\n(End of file, total %d lines)", lines.len);
    return buf.copy_str(allocator);
}


fn String? read(Allocator allocator, String file_path, int offset = 1, int limit = -1)
{
    Path? path_obj = path::new(tmem, file_path);
    if (try path_obj)
    {
        if (try content = (String)file::load_path(tmem, path_obj))
        {
            String normalized_content = content.replace(tmem, "\r\n", "\n");
            return pad_line_numbers(allocator, normalized_content);
        }
        return READ_FILE_ERROR~;
    }
    return INVALIDE_FILE_PATH~;
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

fn String? ReadTool.execute(&self, Allocator allocator, Object* args) @dynamic
{
    String file_path = args.get_string("path") ?? "";
    int offset = args.get_int("offset") ?? -1;
    int limit = args.get_int("limit") ?? -1;
    return read(allocator, file_path, offset, limit);
}
