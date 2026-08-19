import util;

// timestamp_id 格式为 <timestamp>_<seq>_<pid>：同进程内快速连续调用必须
// 互不相同且字典序严格递增（seq 零填充定宽保证同秒内有序）。
fn void test_timestamp_id_unique_and_ordered() @test
{
	String first = util::timestamp_id(tmem);
	String prev = first;
	for (int i = 0; i < 100; i++)
	{
		String cur = util::timestamp_id(tmem);
		assert(cur.compare_to(prev) > 0, "timestamp_id strictly increasing");
		prev = cur;
	}
	assert(prev.compare_to(first) > 0, "last timestamp_id > first");
}
