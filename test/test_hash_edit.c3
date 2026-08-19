import std::io;
import std::io::file;
import std::collections::list;
import cjson;
import tool;
import util;

// 写入测试文件
fn void write_test_file(String path, String data)
{
	DString out = dstring::new(tmem);
	tool::write(tmem, &out, path, data)!!;
}

// 用计算出的锚点直接调用核心编辑逻辑
fn void run_edit(String path, tool::EditOp[] edits)
{
	DString out = dstring::new(tmem);
	tool::hash_edit(tmem, &out, path, edits)!!;
}

// 通过 JSON（模拟模型调用）执行 HashEditFile，返回工具输出
fn String run_edit_json(String path, String edits_json)
{
	DString out = dstring::new(tmem);
	CJsonItem* args = cjson::parse((ZString)edits_json);
	defer args.free();
	tool::HashEditFileTool t;
	ToolContext tctx = {};
	t.execute(&tctx, tmem, &out, args, null)!!;
	return out.str_view().copy(tmem);
}

fn void test_hash_edit_replace_single() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_replace.txt", data);

	String h2 = util::line_hash(tmem, "line two", 2);
	tool::EditOp op;
	op.line = 2;
	op.hash = h2.copy(tmem);
	op.content = "line TWO edited".copy(tmem);
	op.end_line = 0;
	op.end_hash = "".copy(tmem);
	op.insert_after = false;

	List{tool::EditOp} ops;
	ops.init(tmem);
	ops.push(op);
	run_edit("testdata/th_replace.txt", ops.to_array(tmem));

	String content = (String)file::load(tmem, "testdata/th_replace.txt")!!;
	io::printfn("replace -> \n%s", content);
	assert(content.count("line TWO edited") == 1);
	assert(content.count("line two") == 0);
	assert(content.count("line one") == 1);
	assert(content.count("line three") == 1);
}

fn void test_hash_edit_delete() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_delete.txt", data);

	String h2 = util::line_hash(tmem, "line two", 2);
	tool::EditOp op;
	op.line = 2;
	op.hash = h2.copy(tmem);
	op.content = "".copy(tmem); // 空 content = 删除
	op.end_line = 0;
	op.end_hash = "".copy(tmem);
	op.insert_after = false;

	List{tool::EditOp} ops;
	ops.init(tmem);
	ops.push(op);
	run_edit("testdata/th_delete.txt", ops.to_array(tmem));

	String content = (String)file::load(tmem, "testdata/th_delete.txt")!!;
	io::printfn("delete -> \n%s", content);
	assert(content.count("line two") == 0);
	assert(content.count("line one") == 1);
	assert(content.count("line three") == 1);
}

fn void test_hash_edit_insert_after() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_insert.txt", data);

	String h1 = util::line_hash(tmem, "line one", 1);
	tool::EditOp op;
	op.line = 1;
	op.hash = h1.copy(tmem);
	op.content = "inserted line".copy(tmem);
	op.end_line = 0;
	op.end_hash = "".copy(tmem);
	op.insert_after = true;

	List{tool::EditOp} ops;
	ops.init(tmem);
	ops.push(op);
	run_edit("testdata/th_insert.txt", ops.to_array(tmem));

	String content = (String)file::load(tmem, "testdata/th_insert.txt")!!;
	io::printfn("insert -> \n%s", content);
	assert(content.count("inserted line") == 1);
	assert(content.count("line one") == 1);
	// 插入行应位于 line one 之后（即 content 中 "line one\ninserted line"）
	assert(content.contains("line one\ninserted line"));
}

fn void test_hash_edit_range() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_range.txt", data);

	String h1 = util::line_hash(tmem, "line one", 1);
	String h3 = util::line_hash(tmem, "line three", 3);
	tool::EditOp op;
	op.line = 1;
	op.hash = h1.copy(tmem);
	op.content = "REPLACED ALL".copy(tmem);
	op.end_line = 3;
	op.end_hash = h3.copy(tmem);
	op.insert_after = false;

	List{tool::EditOp} ops;
	ops.init(tmem);
	ops.push(op);
	run_edit("testdata/th_range.txt", ops.to_array(tmem));

	String content = (String)file::load(tmem, "testdata/th_range.txt")!!;
	io::printfn("range -> \n%s", content);
	assert(content.count("REPLACED ALL") == 1);
	assert(content.count("line one") == 0);
	assert(content.count("line two") == 0);
	assert(content.count("line three") == 0);
}

fn void test_hash_edit_batch() @test
{
	String data = "alpha\nbeta\ngamma\ndelta";
	write_test_file("testdata/th_batch.txt", data);

	String hb = util::line_hash(tmem, "beta", 2);
	String hg = util::line_hash(tmem, "gamma", 3);
	List{tool::EditOp} ops;
	ops.init(tmem);

	tool::EditOp o1;
	o1.line = 2; o1.hash = hb.copy(tmem); o1.content = "BETA".copy(tmem);
	o1.end_line = 0; o1.end_hash = "".copy(tmem); o1.insert_after = false;
	ops.push(o1);

	tool::EditOp o2;
	o2.line = 3; o2.hash = hg.copy(tmem); o2.content = "GAMMA".copy(tmem);
	o2.end_line = 0; o2.end_hash = "".copy(tmem); o2.insert_after = false;
	ops.push(o2);

	run_edit("testdata/th_batch.txt", ops.to_array(tmem));

	String content = (String)file::load(tmem, "testdata/th_batch.txt")!!;
	io::printfn("batch -> \n%s", content);
	assert(content.count("BETA") == 1);
	assert(content.count("GAMMA") == 1);
	assert(content.count("alpha") == 1);
	assert(content.count("delta") == 1);
}

fn void test_hash_edit_stale_rejected() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_stale.txt", data);

	// 故意使用错误哈希，模拟文件自读取后发生变化
	tool::EditOp op;
	op.line = 2;
	op.hash = "ZZ".copy(tmem); // 错误哈希
	op.content = "should not apply".copy(tmem);
	op.end_line = 0;
	op.end_hash = "".copy(tmem);
	op.insert_after = false;

	List{tool::EditOp} ops;
	ops.init(tmem);
	ops.push(op);

	DString out = dstring::new(tmem);
	tool::hash_edit(tmem, &out, "testdata/th_stale.txt", ops.to_array(tmem))!!;

	String msg = out.str_view().copy(tmem);
	io::printfn("stale -> %s", msg);
	assert(msg.contains("rejected"));

	// 文件内容不应被修改
	String content = (String)file::load(tmem, "testdata/th_stale.txt")!!;
	assert(content.count("line two") == 1);
	assert(content.count("should not apply") == 0);
}

fn void test_hash_edit_via_json() @test
{
	String data = "line one\nline two\nline three";
	write_test_file("testdata/th_json.txt", data);

	String h2 = util::line_hash(tmem, "line two", 2);
	DString json = dstring::new(tmem);
	json.appendf("{\"path\":\"testdata/th_json.txt\",\"edits\":[{\"line\":2,\"hash\":\"%s\",\"content\":\"JSON EDIT\"}]}", h2);

	String msg = run_edit_json("testdata/th_json.txt", json.str_view());
	io::printfn("json -> %s", msg);

	String content = (String)file::load(tmem, "testdata/th_json.txt")!!;
	assert(content.count("JSON EDIT") == 1);
	assert(content.count("line two") == 0);
}

// 重叠：区间 [1..3] 与 line 2 单行编辑冲突 → 整批拒绝，文件不变
fn void test_hash_edit_overlap_rejected() @test
{
	String data = "a\nb\nc\nd\ne";
	write_test_file("testdata/th_overlap.txt", data);

	String h1 = util::line_hash(tmem, "a", 1);
	String h2 = util::line_hash(tmem, "b", 2);
	String h3 = util::line_hash(tmem, "c", 3);

	List{tool::EditOp} ops;
	ops.init(tmem);

	tool::EditOp o1;
	o1.line = 1; o1.hash = h1.copy(tmem); o1.content = "X".copy(tmem);
	o1.end_line = 3; o1.end_hash = h3.copy(tmem); o1.insert_after = false;
	ops.push(o1);

	tool::EditOp o2;
	o2.line = 2; o2.hash = h2.copy(tmem); o2.content = "Y".copy(tmem);
	o2.end_line = 0; o2.end_hash = "".copy(tmem); o2.insert_after = false;
	ops.push(o2);

	DString out = dstring::new(tmem);
	tool::hash_edit(tmem, &out, "testdata/th_overlap.txt", ops.to_array(tmem))!!;

	String msg = out.str_view().copy(tmem);
	io::printfn("overlap -> %s", msg);
	assert(msg.contains("rejected"));
	assert(msg.contains("overlaps"));

	// 文件未被修改
	String content = (String)file::load(tmem, "testdata/th_overlap.txt")!!;
	assert(content.count("a") == 1);
	assert(content.count("X") == 0);
	assert(content.count("Y") == 0);
}

// 重复锚点：两个 edit 都指向 line 2 → 整批拒绝
fn void test_hash_edit_duplicate_anchor_rejected() @test
{
	String data = "a\nb\nc";
	write_test_file("testdata/th_dup.txt", data);

	String h2 = util::line_hash(tmem, "b", 2);

	List{tool::EditOp} ops;
	ops.init(tmem);

	tool::EditOp o1;
	o1.line = 2; o1.hash = h2.copy(tmem); o1.content = "B1".copy(tmem);
	o1.end_line = 0; o1.end_hash = "".copy(tmem); o1.insert_after = false;
	ops.push(o1);

	tool::EditOp o2;
	o2.line = 2; o2.hash = h2.copy(tmem); o2.content = "B2".copy(tmem);
	o2.end_line = 0; o2.end_hash = "".copy(tmem); o2.insert_after = false;
	ops.push(o2);

	DString out = dstring::new(tmem);
	tool::hash_edit(tmem, &out, "testdata/th_dup.txt", ops.to_array(tmem))!!;

	String msg = out.str_view().copy(tmem);
	io::printfn("dup -> %s", msg);
	assert(msg.contains("rejected"));
	assert(msg.contains("overlaps"));

	String content = (String)file::load(tmem, "testdata/th_dup.txt")!!;
	assert(content.count("b") == 1);
	assert(content.count("B1") == 0);
	assert(content.count("B2") == 0);
}

// insertAfter + endLine 互斥 → 整批拒绝
fn void test_hash_edit_insert_after_with_endline_rejected() @test
{
	String data = "a\nb\nc";
	write_test_file("testdata/th_combo.txt", data);

	String h1 = util::line_hash(tmem, "a", 1);
	String h3 = util::line_hash(tmem, "c", 3);

	List{tool::EditOp} ops;
	ops.init(tmem);

	tool::EditOp op;
	op.line = 1; op.hash = h1.copy(tmem); op.content = "NEW".copy(tmem);
	op.end_line = 3; op.end_hash = h3.copy(tmem); op.insert_after = true;
	ops.push(op);

	DString out = dstring::new(tmem);
	tool::hash_edit(tmem, &out, "testdata/th_combo.txt", ops.to_array(tmem))!!;

	String msg = out.str_view().copy(tmem);
	io::printfn("combo -> %s", msg);
	assert(msg.contains("rejected"));
	assert(msg.contains("insertAfter and endLine cannot be combined"));

	String content = (String)file::load(tmem, "testdata/th_combo.txt")!!;
	assert(content.count("a") == 1);
	assert(content.count("NEW") == 0);
}

// 成功输出应包含每条 edit 的逐条结果（含多行替换的行数）
fn void test_hash_edit_success_report() @test
{
	String data = "alpha\nbeta\ngamma\ndelta";
	write_test_file("testdata/th_report.txt", data);

	String hb = util::line_hash(tmem, "beta", 2);
	String hg = util::line_hash(tmem, "gamma", 3);

	DString json = dstring::new(tmem);
	json.appendf("{\"path\":\"testdata/th_report.txt\",\"edits\":[{\"line\":2,\"hash\":\"%s\",\"content\":\"BETA\"},{\"line\":3,\"hash\":\"%s\",\"content\":\"GAMMA\\nGAMMA2\"}]}", hb, hg);

	String msg = run_edit_json("testdata/th_report.txt", json.str_view());
	io::printfn("report -> %s", msg);

	assert(msg.contains("Success"));
	assert(msg.contains("2 edit(s) applied"));
	assert(msg.contains("line 2: replaced"));
	assert(msg.contains("line 3: replaced with 2 line(s)"));

	String content = (String)file::load(tmem, "testdata/th_report.txt")!!;
	assert(content.count("BETA") == 1);
	assert(content.count("GAMMA2") == 1);
}

// 锚点契约回归（arch review 卡 4）：read() 产出的 hashline 必须能被 hash_edit()
// 原样接受；文件变更后旧锚点必须被整体拒绝。两工具共用的行管线由
// util::load_lines 单一入口保证字节一致。
fn void test_anchor_lockstep_read_to_edit() @test
{
	// 刁钻内容：结构相同的行（位置折叠）、空行、纯符号行、行尾空白、CRLF
	String data = "{\n\n}\nplain\ndup\ndup  \nlast\r\n";
	write_test_file("testdata/th_lockstep.txt", data);

	// 1) read() 产出 hashline 输出
	DString out = dstring::new(tmem);
	tool::read(tmem, &out, "testdata/th_lockstep.txt")!!;

	// 2) 解析 `line:hash|content`，收集 (line, hash) 作为编辑锚点
	List{tool::EditOp} ops;
	ops.init(tmem);
	foreach (l : out.str_view().split(tmem, "\n"))
	{
		sz colon = l.index_of_char(':') ?? 0;
		sz bar = l.index_of_char('|') ?? 0;
		if (colon == 0 || bar <= colon) continue; // 跳过页脚等非 hashline
		// c3 切片：s[a..b] 为含端区间 [a,b]；s[i:n] 为从 i 起长度 n（见 c3 MANUAL §range）
		int ln = (int)(l[0..colon - 1].to_long() ?? 0);
		if (ln < 1) continue;
		tool::EditOp op;
		op.line = ln;
		op.hash = l[colon + 1..bar - 1].copy(tmem);
		op.content = "replaced".copy(tmem);
		op.end_line = 0;
		op.end_hash = "".copy(tmem);
		op.insert_after = false;
		ops.push(op);
	}
	assert(ops.len() >= 4, "hashline output parsed");

	// 3) hash_edit 接受这批锚点（全部替换，无 stale）
	DString out2 = dstring::new(tmem);
	tool::hash_edit(tmem, &out2, "testdata/th_lockstep.txt", ops.to_array(tmem))!!;
	String edited = (String)file::load(tmem, "testdata/th_lockstep.txt")!!;
	assert(edited.count("replaced") == ops.len(), "all edits applied");

	// 4) 原锚点已 stale → 再次 hash_edit 必须整体拒绝（不写文件）
	DString out3 = dstring::new(tmem);
	bool rejected = false;
	if (catch ex = tool::hash_edit(tmem, &out3, "testdata/th_lockstep.txt", ops.to_array(tmem)))
	{
		(void)ex;
		rejected = true;
	}
	else
	{
		rejected = out3.str_view().contains("HashEdit rejected");
	}
	assert(rejected, "stale anchors rejected");
}
