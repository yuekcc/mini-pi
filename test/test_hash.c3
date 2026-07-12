import std::io;
import util;

fn void test_line_hash_deterministic() @test
{
	String a = util::line_hash(tmem, "fn main() {}", 1);
	String b = util::line_hash(tmem, "fn main() {}", 1);
	assert(a == b);
	assert(a.len == 2);
}

fn void test_line_hash_blank_lines_differ_by_position() @test
{
	// 空行无字母数字，应混入行号 → 不同位置得到不同哈希
	String l1 = util::line_hash(tmem, "", 1);
	String l2 = util::line_hash(tmem, "", 2);
	io::printfn("blank hash: l1=%s l2=%s", l1, l2);
	assert(l1 != l2);
}

fn void test_line_hash_structural_lines_differ() @test
{
	// { 和 } 这类无字母数字的行，不同位置也应不同
	String a = util::line_hash(tmem, "{", 4);
	String b = util::line_hash(tmem, "{", 9);
	assert(a != b);
}

fn void test_line_hash_alnum_position_independent() @test
{
	// 有字母数字且内容相同的两行，哈希应相同（去重靠 line:hash 中的行号）
	String l1 = util::line_hash(tmem, "    return 0;", 3);
	String l2 = util::line_hash(tmem, "    return 0;", 7);
	assert(l1 == l2);
}

fn void test_line_hash_trims_trailing_ws() @test
{
	// 行尾空白与 \r 不应影响哈希（对齐读取端的处理）
	String a = util::line_hash(tmem, "x = 1   ", 1);
	String b = util::line_hash(tmem, "x = 1", 1);
	String c = util::line_hash(tmem, "x = 1\r", 1);
	assert(a == b);
	assert(b == c);
}
