module http;

import std::io;
import std::collections::list;
import curl;

/** HTTP 错误故障 */
faultdef HTTP_ERROR;

/**
 * HTTP 响应结构体
 * @status_code: HTTP 状态码
 * @body: 响应体内容
 */
struct Response
{
	int status_code;
	String body;
}

/**
 * HttpClient 结构体，用于执行 HTTP 请求
 */
struct HttpClient
{
	Curl* curl;
	DString response_buffer;
	bool inited;
}

fn void HttpClient.init(&self)
{
	if (self.inited) return;
	self.curl = curl::easy_init();
	self.response_buffer = dstring::new(tmem);
	self.inited = true;
}

fn void HttpClient.free(&self)
{
	if (!self.inited) return;
	if (self.curl) curl::easy_cleanup(self.curl);
	self.response_buffer.free();
	self.inited = false;
}

fn usz write_callback(char* buffer, usz size, usz nitems, void* userdata)
{
	usz realsize = size * nitems;
	DString* buffer_ptr = (DString*)userdata;
	buffer_ptr.append_bytes((char[])buffer[:realsize]);
	return realsize;
}

/**
 * 发送 HTTP GET 请求
 * @self: HttpClient 指针
 * @url: 请求 URL
 * @return: HTTP 响应或错误
 */
fn Response? HttpClient.get(&self, String url)
{
	return self.request(url, "GET", null, "");
}

/**
 * 发送 HTTP POST 请求
 * @self: HttpClient 指针
 * @url: 请求 URL
 * @body: 请求体内容
 * @headers: 请求头列表（可选）
 * @return: HTTP 响应或错误
 */
fn Response? HttpClient.post(&self, String url, String body, List{String}* headers = null)
{
	return self.request(url, "POST", headers, body);
}

/**
 * 执行 HTTP 请求
 * @self: HttpClient 指针
 * @url: 请求 URL
 * @method: HTTP 方法
 * @headers: 请求头列表
 * @body: 请求体内容
 * @return: HTTP 响应或错误
 */
fn Response? HttpClient.request(&self, String url, String method, List{String}* headers, String body)
{
	if (!self.inited) self.init();

	// 清空响应缓冲区
	self.response_buffer.clear();

	// 重置 easy handle
	curl::easy_reset(self.curl);

	// 设置 URL (String 可以直接传给 C 函数作为 char*)
	curl::easy_setopt(self.curl, (curl::CurlOption)10002, url); // URL

	// 设置写回调
	curl::easy_setopt(self.curl, (curl::CurlOption)20011, &write_callback); // WRITEFUNCTION
	curl::easy_setopt(self.curl, (curl::CurlOption)10001, &self.response_buffer); // WRITEDATA

	// 设置 HTTP 头
	if (headers != null && headers.size > 0)
	{
		CurlSlist* header_list = null;
		foreach (String header : headers)
		{
			header_list = curl::slist_append(header_list, header);
		}
		curl::easy_setopt(self.curl, (curl::CurlOption)10023, header_list); // HTTPHEADER
	}

	// 设置请求方法
	switch (method)
	{
		case "POST":
			curl::easy_setopt(self.curl, (curl::CurlOption)47, 1); // POST
			curl::easy_setopt(self.curl, (curl::CurlOption)10015, body); // POSTFIELDS
		case "GET":
			curl::easy_setopt(self.curl, (curl::CurlOption)80, 1); // HTTPGET
		default:
			curl::easy_setopt(self.curl, (curl::CurlOption)10036, method); // CUSTOMREQUEST
	}

	// 执行请求
	CurlResult result = curl::easy_perform(self.curl);
	if ((int)result != 0) // 0 is CurlResult.OK
	{
		char* err = curl::easy_strerror(result);
		// 直接打印 char* 错误信息
		io::printf("Curl error code %d: %s\n", (int)result, err);
		return HTTP_ERROR~;
	}

	// 获取响应码
	int response_code = 0;
	curl::easy_getinfo(self.curl, (curl::CurlInfoType)2097154, &response_code); // RESPONSE_CODE

	// 构建响应
	Response response = {
		.status_code = response_code,
		.body = self.response_buffer.str_view().copy(tmem),
	};

	return response;
}
