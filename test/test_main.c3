import mini_pi;

import std::io;
import std::collections::object;
import std::encoding::json;

fn void dispatch_tool_calls(Allocator allocator, Object* tool_calls)
{
	Object* tool_call = tool_calls.get_at(0); // {"type":"function","function":{"name":"bash","arguments":{"command":"which python && python --version"}},"id":"NbWr7IEREHyuKkrZ7OWGGNwvdN9xfhCX"}]}}
	String id = tool_call.get_string("id")!!;

	Object* function = tool_call.get("function")!!;
	String function_name = function.get_string("name")!!;
	Object* arguments = function.get("arguments")!!;
	if (arguments.is_string())
	{
		arguments = json::parse_string(tmem, function.get_string("arguments")!!)!!;
	}

    io::printfn("parsed function_name is %s", function_name);
    io::printfn("parsed arguments is %s", arguments);
	// String call_tool_result = tools::dispatch(tmem, function_name, arguments);

	// HistoryRecord* result = allocator::new(allocator, HistoryRecord);
	// result.id = id.copy(allocator);
	// result.role = "tool";
	// result.content = call_tool_result.copy(allocator);
	// return result;
}

fn void test_read_to_history_record() @test
{
    String content = (String)file::load(tmem, "response_test_data.json")!!;
    // io::printfn("content -> %s", content);

    HistoryRecord record =  mini_pi::read_to_history_record(tmem, content)!!;
    io::printfn("record role = %s", record.role);
    io::printfn("record content = %s", record.content);
    io::printfn("record tool_calls = %s", record.tool_calls);
    dispatch_tool_calls(tmem, record.tool_calls);
}