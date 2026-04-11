import std::io;
import std::collections::list;
import curl;
import http;

fn void print_curl_version() @test
{
	ZString version = curl::version();
	io::printfn("Curl version = %s", version);
}

fn void test_http_get() @test
{
	HttpClient client;
	client.init();
	defer client.free();

	// 测试 GET 请求
	if (try Response response = client.get("https://httpbin.org/get"))
	{
		io::printfn("GET Response status: %d", response.status_code);
		io::printfn("GET Response body length: %d", response.body.len);
		assert(response.status_code == 200, "GET should return 200");
	}
}

fn void test_http_post() @test
{
	HttpClient client;
	client.init();
	defer client.free();

	// 测试 POST 请求
	if (try Response response = client.post("https://httpbin.org/post", `{"test": "data"}`, null))
	{
		io::printfn("POST Response status: %d", response.status_code);
		io::printfn("POST Response body length: %d", response.body.len);
		assert(response.status_code == 200, "POST should return 200");
	}
}

fn void test_http_post_with_headers() @test
{
	HttpClient client;
	client.init();
	defer client.free();

	// 测试带自定义头的 POST 请求
	List{String} headers;
	headers.init(tmem);
	defer headers.free();
	headers.push("X-Custom-Header: test-value");

	if (try Response response = client.post("https://httpbin.org/post", `{"test": "data"}`, &headers))
	{
		io::printfn("POST with headers status: %d", response.status_code);
		assert(response.status_code == 200, "POST with headers should return 200");
	}
}

fn void test_http_client_reuse() @test
{
	HttpClient client;
	client.init();
	defer client.free();

	// 测试客户端重用（连续发送多个请求）
	if (try Response response1 = client.get("https://httpbin.org/get"))
	{
		assert(response1.status_code == 200, "First GET should return 200");
	}

	if (try Response response2 = client.post("https://httpbin.org/post", `{"test": "reuse"}`, null))
	{
		assert(response2.status_code == 200, "POST after GET should return 200");
	}

	if (try Response response3 = client.get("https://httpbin.org/get"))
	{
		assert(response3.status_code == 200, "Second GET should return 200");
	}
}
