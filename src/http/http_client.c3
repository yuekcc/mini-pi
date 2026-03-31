module http;

import std::io;
import std::collections::list;
import curl;

faultdef HTTP_ERROR;

struct Response
{
	int status_code;
	String body;
}

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

fn Response? HttpClient.get(&self, String url)
{
	return self.request(url, "GET", null, "");
}

fn Response? HttpClient.post(&self, String url, String body, List{String}* headers = null)
{
	return self.request(url, "POST", headers, body);
}

fn Response? HttpClient.request(&self, String url, String method, List{String}* headers, String body)
{
	if (!self.inited) self.init();

	self.response_buffer.clear();

	curl::easy_reset(self.curl);

	curl::easy_setopt(self.curl, (curl::CurlOption)10002, url); // URL
	curl::easy_setopt(self.curl, (curl::CurlOption)20011, &write_callback); // WRITEFUNCTION
	curl::easy_setopt(self.curl, (curl::CurlOption)10001, &self.response_buffer); // WRITEDATA

	if (headers != null && headers.size > 0)
	{
		CurlSlist* header_list = null;
		foreach (String header : headers)
		{
			header_list = curl::slist_append(header_list, header);
		}
		curl::easy_setopt(self.curl, (curl::CurlOption)10023, header_list); // HTTPHEADER
	}

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

	CurlResult result = curl::easy_perform(self.curl);
	if ((int)result != 0) // 0 is CurlResult.OK
	{
		char* err = curl::easy_strerror(result);
		io::printf("Curl error code %d: %s\n", (int)result, err);
		return HTTP_ERROR~;
	}

	int response_code = 0;
	curl::easy_getinfo(self.curl, (curl::CurlInfoType)2097154, &response_code); // RESPONSE_CODE

	Response response = {
		.status_code = response_code,
		.body = self.response_buffer.str_view().copy(tmem),
	};

	return response;
}
