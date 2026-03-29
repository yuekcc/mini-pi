import std::io;
import curl;

fn void print_curl_verion() @test
{
    ZString version = curl::version();
    io::printfn("Curl version  = %s", version);
}
