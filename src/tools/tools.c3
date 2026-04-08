module tools;

import std::io;
import std::io::path;
import std::collections::list;

import c3x::object;
import cmd;
import util;
import context;

faultdef
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
    String[] allowed_tools = init_options.tools.split(tmem, ",");

    List{Tool} tools;
    tools.init(tmem);

    foreach (tool_name : allowed_tools)
    {
        switch (tool_name)
        {
            case "read": tools.push((Tool) alloc::new(allocator, ReadTool));
            case "bash": tools.push((Tool) alloc::new(allocator, BashTool));
            case "edit": tools.push((Tool) alloc::new(allocator, EditTool));
            case "write": tools.push((Tool) alloc::new(allocator, WriteTool));
            case "grep": tools.push((Tool) alloc::new(allocator, GrepTool));
            case "find": tools.push((Tool) alloc::new(allocator, FindTool));
            case "ls": tools.push((Tool) alloc::new(allocator, LsTool));
            default: unreachable(string::format(tmem, "UNKNOWN_TOOL: %s", tool_name));
        }
    }

    self.allocator = allocator;
    self.schema_cache = "";
    self.tools = tools.to_array(allocator);
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
    io::printfn(util::system_message("> Dispatch tool call. Use id = %s, name = %s, args = %s\n"), id, name, args);

    foreach (&tool: self.tools)
    {
        if (tool.name() == name)
        {
            return tool.execute(allocator, args);
        }
    }

    return UNKNOWN_TOOL~;
}

fn Message* ToolPool.dispatch(&self, Allocator allocator, String tool_call_id, ToolCall* tool_call)
{
    @pool()
    {
        Object* args = object::parse_string(tmem, tool_call.arguments)!!;
        Message* msg = alloc::new(allocator, Message);
        msg.tool_call_id = tool_call_id;
        msg.role = "tool";

        String? result = self.do_dispatch(tmem, tool_call_id, tool_call.name, args);
        if (catch excuse = result)
        {
            msg.content = string::format(allocator, "Execute %s tool failed, for %s. You should retry carefully", tool_call.name, excuse);
            msg.role = "tool";
        }
        else
        {
            msg.content = result.copy(allocator);
        }

        return msg;
    };
}
