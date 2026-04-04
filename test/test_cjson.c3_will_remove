import std::io;
import cjson;

const String TEST_DATA = `{
    "name": "Awesome 4K",
    "resolutions": [
        {
            "width": 1280,
            "height": 720
        },
        {
            "width": 1920,
            "height": 1080
        },
        {
            "width": 3840,
            "height": 2160
        }
    ]
}`;

fn void test_print_version() @test
{
    ZString version = cjson::version();
    io::printfn("cjson version is %s", version);
}

fn void test_parse() @test
{
    Json* result = cjson::parse(TEST_DATA);
    io::printfn(">>>\n%s", cjson::print(result));

    io::printfn(">>> name = %s", cjson::get_string_value(cjson::get_object_item(result, "name")));

    cjson::delete(result);
}
