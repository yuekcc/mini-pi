module global;

import std::io::path;

struct GlobalStore
{
	Path config_dir;
	Path log_file;
	bool enable_debug;
	bool enable_transcript;
	String session_id;
	String active_request_id;
}

tlocal GlobalStore global_store;

fn void update(Path config_dir, Path log_file, bool enable_debug, bool enable_transcript)
{
	// 直接引用调用方分配的长生命周期字符串（main 的 tmem / ctx.allocator），
	// 不做 mem 拷贝：避免永久分配泄漏（c3c test 会检测），且调用方保证生命周期。
	global_store.config_dir = config_dir;
	global_store.log_file = log_file;
	global_store.enable_debug = enable_debug;
	global_store.enable_transcript = enable_transcript;
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

// transcript 是否启用（--no-transcript 关闭）。
fn bool transcript_enabled()
{
	return global_store.enable_transcript;
}

// 当前会话 ID（供 Task 工具注入 MP_PARENT_SESSION 使用）。
fn void set_session_id(String id)
{
	global_store.session_id = id;
}

fn String session_id()
{
	return global_store.session_id;
}

// 当前 API round-trip 的 request_id（供 Task 工具注入父 request 使用）。
fn void set_active_request_id(String id)
{
	global_store.active_request_id = id;
}

fn String active_request_id()
{
	return global_store.active_request_id;
}
