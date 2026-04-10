module context;

import std::io;
import std::io::path;
import std::collections::list;
import util;

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
    Allocator allocator;

    String id;
    String topic;
    InitOptions* init_options;
    MessageList messages;
    Path cwd;
}

fn Context* Context.init(&self, Allocator allocator, InitOptions* init_options)
{
    self.allocator = allocator;
    self.id = util::timestamp_id(allocator);
    self.topic = "TBA";
    self.init_options = init_options;
    self.messages = {};
    self.messages.init(allocator);
    self.cwd = path::cwd(allocator)!!;

    self.reset();

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
    result.tool_call_id = message.tool_call_id.copy(self.allocator);
    if (message.tool_call != null)
    {
        result.tool_call = alloc::clone(self.allocator, *message.tool_call);
    }

    self.messages.push(*result);
}

fn void Context.reset(&self)
{
    Message system_msg = {
		.role = "system",
	};

	if (self.init_options.enable_agents_md)
	{
	    system_msg.content = string::format(self.allocator, "%s\n----\n%s", self.init_options.system_prompt, self.init_options.instructions);
	}
	else
	{
	    system_msg.content = self.init_options.system_prompt.copy(self.allocator);
	}

	self.push_message(&system_msg);
}
