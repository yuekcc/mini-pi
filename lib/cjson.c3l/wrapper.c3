module cjson;

import std::io;
import std::core::mem;
import std::core::string;


faultdef MALFORMED_STRING, MALFORMED_BOOL;

// --- c3 mem allocator bridge -------------------------------------------------
// cJSON 默认用 malloc/free；显式挂钩（main 启动时 init_mem_hooks 调用一次）保证
// 分配与释放走同一实现。直接转发 libc。
import libc;

fn void* cjson_mem_alloc(usz size) @export => libc::malloc(size);
fn void cjson_mem_free(void* ptr) @export => libc::free(ptr);

macro init_mem_hooks()
{
    Hook hook = {
        .malloc_fn = &cjson_mem_alloc,
        .free_fn = &cjson_mem_free,
    };
    init_hooks(&hook);
}

fn void reset_hooks() @inline => init_hooks(null);


fn void CJsonItem.free(&self) => delete(self);

fn sz? CJsonItem.to_format(&self, Formatter* formatter) @dynamic
{
	ZString zstr = print_unformatted(self);
	return formatter.printf("%s", zstr)!;
}

fn CJsonItem* new_null(Allocator allocator) @inline => create_null();

fn bool CJsonItem.is_null(&self)      @inline => is_null(self);
fn bool CJsonItem.is_bool(&self)      @inline => is_bool(self);
fn bool CJsonItem.is_number(&self)    @inline => is_number(self);
fn bool CJsonItem.is_string(&self)    @inline => is_string(self);
fn bool CJsonItem.is_array(&self)     @inline => is_array(self);
fn bool CJsonItem.is_list(&self)      @inline => is_array(self);
fn bool CJsonItem.is_object(&self)    @inline => is_object(self);
fn bool CJsonItem.is_map(&self)       @inline => is_object(self);
fn bool CJsonItem.is_raw(&self)       @inline => is_raw(self);
fn bool CJsonItem.is_invalid(&self)   @inline => is_invalid(self);
fn bool CJsonItem.is_false(&self)     @inline => is_false(self);
fn bool CJsonItem.is_true(&self)      @inline => is_true(self);
fn bool CJsonItem.is_empty(&self)     @inline => is_null(self);

// --- setter -----------------------------------------------------------------

macro CJsonItem* CJsonItem.set(&self, String key, value)
{
	$switch:
		$case $Typeof(value) == String:
			return add_string_to_object(self, (ZString)key, (ZString)value);
		$case types::is_int($Typeof(value)):
			return add_number_to_object(self, (ZString)key, (double)value);
		$case $Typeof(value) == bool:
			return add_bool_to_object(self, (ZString)key, value);
		$case types::is_float($Typeof(value)):
			return add_number_to_object(self, (ZString)key, value);
		$case $Typeof(value) == CJsonItem*:
		{
			add_item_to_object(self, (ZString)key, value);
			return value;
		}
		$default:
			$error "Unsupported cjson set type '" +++ $Typeof(value)::name +++ "'";
	$endswitch
}

fn CJsonItem* CJsonItem.set_item(&self, String key, CJsonItem* value) @inline
{
	add_item_to_object(self, (ZString)key, value);
	return value;
}

macro CJsonItem* CJsonItem.set_at(&self, sz index, value)
{
	$switch:
		$case $Typeof(value) == String:
		{
			CJsonItem* item = create_string((ZString)value);
			return insert_item_in_array(self, (int)index, item) ? item : null;
		}
		$case types::is_int($Typeof(value)):
		{
			CJsonItem* item = create_number((double)value);
			return insert_item_in_array(self, (int)index, item) ? item : null;
		}
		$case $Typeof(value) == bool:
		{
			CJsonItem* item = create_bool(value);
			return insert_item_in_array(self, (int)index, item) ? item : null;
		}
		$case types::is_float($Typeof(value)):
		{
			CJsonItem* item = create_number(value);
			return insert_item_in_array(self, (int)index, item) ? item : null;
		}
		$case $Typeof(value) == CJsonItem*:
			return insert_item_in_array(self, (int)index, value) ? value : null;
		$default:
			$error "Unsupported cjson set_at type '" +++ $Typeof(value)::name +++ "'";
	$endswitch
}

macro CJsonItem* CJsonItem.push_back(&self, value)
{
	$switch:
		$case $Typeof(value) == String:
		{
			CJsonItem* item = create_string((ZString)value);
			return add_item_to_array(self, item) ? item : null;
		}
		$case types::is_int($Typeof(value)):
		{
			CJsonItem* item = create_number((double)value);
			return add_item_to_array(self, item) ? item : null;
		}
		$case $Typeof(value) == bool:
		{
			CJsonItem* item = create_bool(value);
			return add_item_to_array(self, item) ? item : null;
		}
		$case types::is_float($Typeof(value)):
		{
			CJsonItem* item = create_number(value);
			return add_item_to_array(self, item) ? item : null;
		}
		$case $Typeof(value) == CJsonItem*:
			return add_item_to_array(self, value) ? value : null;
		$default:
			$error "Unsupported cjson push_back type '" +++ $Typeof(value)::name +++ "'";
	$endswitch
}

// --- child access -----------------------------------------------------------

fn CJsonItem* CJsonItem.get_key(&self, String key) @inline => get_object_item(self, (ZString)key);
fn CJsonItem* CJsonItem.get_at(&self, sz index) @inline => get_array_item(self, (int)index);
fn bool CJsonItem.has_key(&self, String key) @inline => has_object_item(self, (ZString)key);
fn bool CJsonItem.contains(&self, String key) @inline => has_object_item(self, (ZString)key);

macro void CJsonItem.@each_entry(&self; @body(String key, CJsonItem* value))
{
	CJsonItem* item = self.child;
	while (item)
	{
		CJsonItem* next = item.next;
		@body((String)item.string, item);
		item = next;
	}
}

fn String[] CJsonItem.keys(&self, Allocator allocator)
{
	sz count = 0;
	for (CJsonItem* item = self.child; item; item = item.next) count++;
	if (!count) return {};
	String[] result = alloc::alloc_array(allocator, String, count);
	CJsonItem* item = self.child;
	for (sz i = 0; i < count; i++)
	{
		result[i] = string::format(allocator, "%s", (ZString)item.string);
		item = item.next;
	}
	return result;
}

// --- self-extract typed getters ---------------------------------------------

fn String CJsonItem.get_string(&self, Allocator allocator)
{
	return string::format(allocator, "%s", get_string_value(self));
}

fn int128? CJsonItem.get_int(&self)
{
	if (!self.is_number()) return string::MALFORMED_INTEGER~;
	return (int128)get_number_value(self);
}

fn bool? CJsonItem.get_bool(&self)
{
	if (self.is_true()) return true;
	if (self.is_false()) return false;
	return MALFORMED_BOOL~;
}

// --- deletion ---------------------------------------------------------------

// --- key-based typed getters (convenience) ---------------------------------

	fn String? CJsonItem.get_key_string(&self, String key, Allocator allocator)
	{
		CJsonItem* item = self.get_key(key);
		if (!item || !item.is_string()) return MALFORMED_STRING~;
		return item.get_string(allocator);
	}

	fn int? CJsonItem.get_key_int(&self, String key)
	{
		CJsonItem* item = self.get_key(key);
		if (!item) return string::MALFORMED_INTEGER~;
		int128? val = item.get_int();
		if (catch exc = val) return string::MALFORMED_INTEGER~;
		return (int)val;
	}

	fn bool? CJsonItem.get_key_bool(&self, String key)
	{
		CJsonItem* item = self.get_key(key);
		if (!item) return MALFORMED_BOOL~;
		return item.get_bool();
	}

// --- deletion ---------------------------------------------------------------

	fn void CJsonItem.delete_key(&self, String key) @inline => delete_item_from_object(self, (ZString)key);
	fn void CJsonItem.delete_at(&self, sz index) @inline => delete_item_from_array(self, (int)index);

// --- length -----------------------------------------------------------------

fn usz CJsonItem.get_len(&self) @inline => (usz)get_array_size(self);

// --- construction helpers ---------------------------------------------------

fn CJsonItem* new_object(Allocator allocator) @inline => create_object();
fn CJsonItem* new_array(Allocator allocator) @inline => create_array();

// --- generic value extraction -----------------------------------------------

macro CJsonItem* CJsonItem.to_value(&self, $Type)
{
	$switch:
		$case types::is_int($Type):
			if (!self.is_number()) return string::MALFORMED_INTEGER~;
			return ($Type)(int128)get_number_value(self);
		$case types::is_float($Type):
			if (!self.is_number()) return string::MALFORMED_FLOAT~;
			return ($Type)get_number_value(self);
		$case $Type == String:
			if (!self.is_string()) return MALFORMED_STRING~;
			return (String)self.get_string(tmem);
		$case $Type == bool:
			if (self.is_true()) return true;
			if (self.is_false()) return false;
			return MALFORMED_BOOL~;
		$default:
			$error "Unsupported object type '" +++ $Type::name +++ "'";
	$endswitch
}
