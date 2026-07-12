module global;

import std::io::path;

struct GlobalStore
{
	Path config_dir;
	Path log_file;
	bool enable_debug;
}

tlocal GlobalStore global_store;

fn void update(Path config_dir, Path log_file, bool enable_debug)
{
	global_store.config_dir = config_dir.copy(mem);
	global_store.log_file = log_file.copy(mem);
	global_store.enable_debug = enable_debug;
}

fn Path config_dir()
{
	return global_store.config_dir;
}

fn Path log_file()
{
	return global_store.log_file;
}

fn bool debug()
{
	return global_store.enable_debug;
}
