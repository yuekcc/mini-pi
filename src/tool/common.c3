module tool;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;

import global;

fn Path load_store_dir(Allocator allocator)
{
	Path store_dir;
	Path config_dir = global::config_dir();
	if (config_dir != "")
	{
		store_dir = config_dir.append(allocator, "task_store")!!;
	}
	else
	{
		Path user_home  = path::home_directory(allocator)!!;
		store_dir = user_home.append(allocator, ".config/mp/task_store")!!;
	}

	if (!path::exists(store_dir))
	{
		path::mkdir(store_dir, true)!!;
	}

	return store_dir;
}
