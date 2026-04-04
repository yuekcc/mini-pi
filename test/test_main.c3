import std::io;
import std::collections::object;
import std::collections::list;
import std::encoding::json;
import http;
import context;

fn void test_http_request() @test
{
    HttpClient client;
    client.init();
    defer client.free();

    // 构建 HTTP 请求头
    List{String} headers;
    headers.init(tmem);
    defer headers.free();
    headers.push("Authorization: Bearer test-api-key");
    headers.push("Content-Type: application/json");

    String body = `{"messages":[{"role":"user","content":"Hello"}]}`;

    if (try Response response = client.post("https://httpbin.org/post", body, &headers))
    {
        io::printfn("Response status: %d", response.status_code);
        io::printfn("Response body length: %d", response.body.len);
        assert(response.status_code == 200, "Response should be 200");
    }
}
