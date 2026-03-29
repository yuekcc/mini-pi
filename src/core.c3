module core;

import std::io;
import std::io::path;
import std::collections::list;

import util;

/**
 * Agent 初始化选项结构体
 * @agent_name: Agent 名称
 * @init_message: 初始化消息（headless 模式使用）
 * @model_id: 模型标识符
 * @url: API 端点 URL
 * @api_key: API 密钥
 * @headless: 是否为无头模式（自动执行）
 */
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
    String id;
    String name;
    String arguments;
}

struct Message
{
    String id;
    String role;
    String content;
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
        return allocator::clone(allocator, message);
    }

    return null;
}

fn void Context.push_message(&self, Message* message)
{
    Message* result = allocator::new(self.allocator, Message);
    result.role = message.role.copy(self.allocator);
    result.content = message.content.copy(self.allocator);
    result.id = util::timestamp_id(self.allocator);
    if (message.tool_call != null)
    {
        result.tool_call = allocator::clone(self.allocator, *message.tool_call);
    }

    self.messages.push(*result);
}
