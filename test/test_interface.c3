import std::io;
import std::collections::object;

interface Tool
{
    fn String name();
    fn String schema();
    fn String execute(Allocator allocator, Object* args);
}

struct AStruct
{
    bool _pad;
}

fn String AStruct.name(&self) @dynamic
{
    return "call name";
}

fn String AStruct.schema(&self) @dynamic
{
    return "call schema";
}

fn String AStruct.execute(&self, Allocator allocator, Object* args) @dynamic
{
    return "call execute";
}

fn void test_interface() @test
{
    Tool[] tools = {
        (Tool)allocator::new(tmem, AStruct),
        (Tool)allocator::new(tmem, AStruct)
    };

    foreach(i, tool: tools)
    {
        io::printfn("%d %s", i, tool.name());
        io::printfn("%d %s", i, tool.schema());
        io::printfn("%d %s", i, tool.execute(tmem, null));
    }
}
