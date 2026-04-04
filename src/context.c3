module core;

import std::io;
import std::io::path;
import std::collections::list;

import util;

struct InitOptions
{
	String agent_name;
	String init_message;
	String model_id;
	String url;
	String api_key;
	bool headless;
}

struct ToolCall
{
    String name;
    String arguments;
}

struct Message
{
    String id;
    String role;
    String content;
    String tool_call_id;
    ToolCall* tool_call;
}

alias MessageList = List{Message};

struct Context
{
    String id;
    String topic;
    Allocator allocator;
    InitOptions init_options;
    MessageList messages;
    Path cwd;
}

fn Context* Context.init(&self, Allocator allocator, InitOptions init_options)
{
    self.allocator = allocator;
    self.id = util::timestamp_id(allocator);
    self.topic = "TBA";
    self.init_options = init_options;
    self.messages = {};
    self.messages.init(allocator);
    self.cwd = path::cwd(allocator)!!;

    return self;
}

fn void Context.free(&self)
{
    self.messages.free();
}

fn Message* Context.last_message(&self, Allocator allocator)
{
    if (try Message message = self.messages.last())
    {
        return alloc::clone(allocator, message);
    }

    return null;
}

fn void Context.push_message(&self, Message* message)
{
    Message* result = alloc::new(self.allocator, Message);
    result.id = util::timestamp_id(self.allocator);
    result.role = message.role.copy(self.allocator);
    result.content = message.content.copy(self.allocator);
    // result.tool_call_raw = message.tool_call_raw.copy(self.allocator);
    result.tool_call_id = message.tool_call_id.copy(self.allocator);
    if (message.tool_call != null)
    {
        result.tool_call = alloc::clone(self.allocator, *message.tool_call);
    }

    self.messages.push(*result);
}
