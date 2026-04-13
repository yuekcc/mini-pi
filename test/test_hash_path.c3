import std::io;
import std::io::path;
import util;

fn void test_hash_path() @test
{
	Path cwd = path::cwd(tmem)!!;
	String name = util::hash_path(cwd);

	io::printfn("name = %s", name);
}
