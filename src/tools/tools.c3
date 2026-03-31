module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;
import cmd;
import core;

faultdef UNKNOWN_TOOL;





// ============================================================================
// Phase 1: Tool Interface
// ============================================================================

/**
 * 工具接口
 * 所有工具必须实现此接口
 */
interface Tool
{
    /** 获取工具名称 */
    fn String name();

    /** 获取工具的 JSON Schema */
    fn String schema();

    /** 执行工具
     * @allocator: 内存分配器
     * @args: 工具参数对象
     * @return: 工具执行结果字符串
     */
    fn String execute(Allocator allocator, Object* args);
}

// ============================================================================
// Phase 3 & 5: Tool Implementations with Schema
// ============================================================================

// --- BashTool ---

const String BASH_SCHEMA = `{
    "name": "bash",
    "description": "Execute a bash command",
    "parameters": {
        "type": "object",
        "properties": {
            "command": {
                "type": "string",
                "description": "The shell command to execute"
            }
        },
        "required": ["command"]
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

// --- EditTool ---

const String EDIT_SCHEMA = `{
    "name": "edit",
    "description": "Edit file content by replacing text",
    "parameters": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "The file path to edit"
            },
            "oldText": {
                "type": "string",
                "description": "The text to replace"
            },
            "newText": {
                "type": "string",
                "description": "The replacement text"
            }
        },
        "required": ["path", "oldText", "newText"]
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

// --- WriteTool ---

const String WRITE_SCHEMA = `{
    "name": "write",
    "description": "Write content to a file",
    "parameters": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "The target file path"
            },
            "content": {
                "type": "string",
                "description": "The content to write"
            }
        },
        "required": ["path", "content"]
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

// --- FindTool ---

const String FIND_SCHEMA = `{
    "name": "find",
    "description": "Find files using fd pattern matching",
    "parameters": {
        "type": "object",
        "properties": {
            "pattern": {
                "type": "string",
                "description": "File name pattern to match"
            },
            "path": {
                "type": "string",
                "description": "Starting directory for search (optional)"
            },
            "limit": {
                "type": "integer",
                "description": "Maximum number of results",
                "default": 1000
            }
        },
        "required": ["pattern"]
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

// --- GrepTool ---

const String GREP_SCHEMA = `{
    "name": "grep",
    "description": "Search file contents using ripgrep",
    "parameters": {
        "type": "object",
        "properties": {
            "pattern": {
                "type": "string",
                "description": "Search pattern (regex)"
            },
            "path": {
                "type": "string",
                "description": "File or directory to search in (optional)"
            },
            "glob": {
                "type": "string",
                "description": "File name filter glob pattern (optional)"
            },
            "ignoreCase": {
                "type": "boolean",
                "description": "Ignore case sensitivity",
                "default": false
            },
            "literal": {
                "type": "boolean",
                "description": "Treat pattern as literal string (not regex)",
                "default": false
            },
            "context": {
                "type": "integer",
                "description": "Lines of context before and after match",
                "default": 0
            },
            "limit": {
                "type": "integer",
                "description": "Maximum number of results",
                "default": 100
            }
        },
        "required": ["pattern"]
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

// --- LsTool ---

const String LS_SCHEMA = `{
    "name": "ls",
    "description": "List directory contents",
    "parameters": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "Directory path to list",
                "default": "."
            },
            "limit": {
                "type": "integer",
                "description": "Maximum number of entries",
                "default": 500
            }
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

// --- ReadTool ---

const String READ_SCHEMA = `{
    "name": "read",
    "description": "Read file content",
    "parameters": {
        "type": "object",
        "properties": {
            "path": {
                "type": "string",
                "description": "File path to read"
            },
            "offset": {
                "type": "integer",
                "description": "Starting line number (1-indexed)",
                "default": 1
            },
            "limit": {
                "type": "integer",
                "description": "Maximum number of lines (-1 for all)",
                "default": -1
            }
        },
        "required": ["path"]
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

// ============================================================================
// Phase 6: Simplified Dispatch (using Tool interface)
// ============================================================================


struct ToolPool
{
    Allocator allocator;
    String schema_cache;
    Tool[] tools;
}

fn ToolPool* ToolPool.init(&self, Allocator allocator, InitOptions* init_options)
{
    self.allocator = allocator;
    self.tools = {
        (Tool) allocator::new(allocator, BashTool),
        (Tool) allocator::new(allocator, EditTool),
        (Tool) allocator::new(allocator, WriteTool),
        (Tool) allocator::new(allocator, GrepTool),
        (Tool) allocator::new(allocator, LsTool),
        (Tool) allocator::new(allocator, ReadTool),
    };
    self.schema_cache = "";

    return self;
}

fn void ToolPool.free(&self)
{
    // TODO 清理内存
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
    foreach (Tool tool: self.tools)
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

    foreach (Tool tool: self.tools)
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
