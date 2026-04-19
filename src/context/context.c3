module context;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;
import std::os::env;
import util;
import c3x::object;

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


fn Object* Message.to_object(&self, Allocator allocator)
{
	Object* message = object::new_obj(allocator);

	message.set("role", self.role.copy(allocator));
	message.set("content", self.content.copy(allocator));

	if (self.tool_call_id != "")
	{
		message.set("tool_call_id", self.tool_call_id.copy(allocator));

		if (self.tool_call != null)
		{
			Object* tool_calls = object::new_obj(allocator);
			message.set("tool_calls", tool_calls);

			Object* tool_call = object::new_obj(allocator);
			tool_calls.push(tool_call);

			tool_call.set("id",  self.tool_call_id.copy(allocator));
			tool_call.set("index",  0);
			Object* function = object::new_obj(allocator);
			tool_call.set("function",  function);

			function.set("name", self.tool_call.name.copy(allocator));
			function.set("arguments", self.tool_call.arguments.copy(allocator));
		}
	}

	return message;
}

alias MessageList = List{Message};

struct Context
{
	Allocator allocator;

	String id;
	String topic;
	InitOptions* init_options;
	MessageList messages;
	String cwd;
	String log_file_path;
	// File log_file;
}

fn bool Context.debug(&self)
{
	return self.init_options.debug;
}

fn Context* Context.init(&self, Allocator allocator, InitOptions* init_options)
{
	self.allocator = allocator;
	self.id = util::timestamp_id(allocator);
	self.topic = "TBA";
	self.init_options = init_options;
	self.messages = {};
	self.messages.init(allocator);
	self.cwd = path::cwd(tmem)!!.str_view().copy(allocator);

	// 顺序有关
	self.init_log_file();
	self.reset();
	

	return self;
}

fn void Context.free(&self)
{
	self.messages.free();
	// @catch(self.log_file.close());
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
	@ok(self.log_message(result));
}

fn String Context.get_workspace(&self)
{
	Path mp_home = util::get_agent_home();
	Path workspace = mp_home.append(tmem, string::format(tmem, ".config/mp/workspace/%s", util::hash_path(path::new(tmem, self.cwd))))!!;
	return workspace.str_view();
}

fn void Context.init_log_file(&self)
{
	Path mp_home = util::get_agent_home();
	Path log_file = mp_home.append(tmem, 
		string::format(tmem, ".config/mp/workspace/%s/%s.jsonl", util::hash_path(path::new(tmem, self.cwd)), self.id))!!;

	Path log_file_store_dir = log_file.parent()!!;
	if (!path::exists(log_file_store_dir))
	{
		path::mkdir(log_file_store_dir, true)!!;
	}

	self.log_file_path = log_file.str_view().copy(self.allocator);
}

fn void? Context.log_message(&self, Message* message)
{
	File log_file = file::open(self.log_file_path, "a+")!;
	defer log_file.close()!!;

	String data = message.to_object(tmem).to_json(tmem);
	io::fprintfn(&log_file, data);
	log_file.flush()!;
}

fn void Context.reset(&self)
{
	Message system_msg = {
		.role = "system",
	};

	if (self.init_options.enable_agents_md)
	{
		system_msg.content = string::format(self.allocator,
			"%s\n----\n%s", self.init_options.system_prompt, self.init_options.instructions);
	}
	else
	{
		system_msg.content = self.init_options.system_prompt.copy(self.allocator);
	}

	self.push_message(&system_msg);
}
