module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;

import cmd;
import util;
import core;

faultdef
    INVALID_ARGUMENT,
    WRITE_FILE_ERROR,
    READ_FILE_ERROR,
    INVALIDE_FILE_PATH,
    EXECUTE_LS_COMMAND_ERROR,
    EXECUTE_RIPGREP_COMMAND_ERROR,
    EXECUTE_FD_COMMAND_ERROR,
    EXECUTE_BASH_COMMAND_ERROR,
    UNKNOWN_TOOL;

alias StringList = List{String};

interface Tool
{
    fn String name();
    fn String schema();
    fn String? execute(Allocator allocator, Object* args);
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
        (Tool) alloc::new(allocator, BashTool),
        (Tool) alloc::new(allocator, EditTool),
        (Tool) alloc::new(allocator, WriteTool),
        (Tool) alloc::new(allocator, GrepTool),
        (Tool) alloc::new(allocator, LsTool),
        (Tool) alloc::new(allocator, ReadTool),
    };

    self.allocator = allocator;
    self.tools = alloc::clone_slice(allocator, tmp_tools);
    self.schema_cache = "";

    return self;
}

fn void ToolPool.free(&self)
{
    foreach (&tool: self.tools)
    {
        alloc::free(self.allocator, tool);
    }
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

fn String? ToolPool.do_dispatch(&self, Allocator allocator, String id, String name, Object* args)
{
    io::printfn(util::system_message("> tool dispatch, id = %s, name = %s, args = %s"), id, name, args);

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
        Message* msg = alloc::new(allocator, Message);
        msg.tool_call_id = tool_call.id.copy(allocator);
        msg.role = "tool";

        String? result = self.do_dispatch(tmem, tool_call.id, tool_call.name, args);
        if (catch excuse = result)
        {
            msg.content = string::format(allocator, "Execute %s tool failed, %s. You should retry carefully", tool_call.name, excuse);
            msg.role = "system";
        }
        else
        {
            msg.content = result.copy(allocator);
        }

        return msg;
    };
}
