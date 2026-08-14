module tool;

import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;

// 工具中间产物目录：<config_dir>/task_store（config_dir 空时回退 ~/.config/mp/task_store）。
fn Path load_store_dir(Allocator allocator, Path config_dir = (Path)"")
{
	Path store_dir;
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
