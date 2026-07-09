module cjson;

fn void CJsonItem.free(&self)
{
	delete(self);
}

fn String CJsonItem.to_string(&self, Allocator allocator)
{
	ZString result = print_unformatted(self);
	return (String)result.copy(allocator);
}

fn String CJsonItem.get_string(&self, Allocator allocator)
{
	ZString result = get_string_value(self);
	return (String)result.copy(allocator);
}

fn CJsonItem* CJsonItem.get_key(&self, String key)
{
	return get_object_item(self, (ZString)key);
}

fn bool CJsonItem.is_invalid(&self)
{
	return is_invalid(self);
}
fn bool CJsonItem.is_false(&self)
{
	return is_false(self);
}
fn bool CJsonItem.is_true(&self)
{
	return is_true(self);
}
fn bool CJsonItem.is_bool(&self)
{
	return is_bool(self);
}
fn bool CJsonItem.is_null(&self)
{
	return is_null(self);
}
fn bool CJsonItem.is_number(&self)
{
	return is_number(self);
}
fn bool CJsonItem.is_string(&self)
{
	return is_string(self);
}
fn bool CJsonItem.is_array(&self)
{
	return is_array(self);
}
fn bool CJsonItem.is_object(&self)
{
	return is_object(self);
}
fn bool CJsonItem.is_raw(&self)
{
	return is_raw(self);
}

fn bool CJsonItem.add_array_item(&self, CJsonItem* item)
{
	return add_item_to_array(self, item);
}
