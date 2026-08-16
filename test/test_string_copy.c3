import std::io;

// 验证 String.copy 对空串的实际行为。
// 标准库实现（std/core/string.c3:759）：
//   fn String String.copy(self, Allocator allocator) {
//       sz len = self.len;
//       char* str = alloc::malloc(allocator, len + 1);  // len=0 仍 malloc(1)
//       mem::copy(str, self.ptr, len);
//       str[len] = 0;
//       return (String)str[:len];
//   }
// 结论：空串不会被忽略，每次 copy 都分配一个 1 字节堆块。
// 项目里高频模式 `(get_key_string(...) ?? "").copy(allocator)` 在字段缺失时
// 也会走这条路径 —— 每个空字段一个堆块，需配套 free。

fn void test_empty_copy_allocates_new_block() @test
{
	String empty = "";
	String c = empty.copy(&allocators::LIBC_ALLOCATOR);
	defer c.free(&allocators::LIBC_ALLOCATOR);

	// 内容语义：仍为空
	assert(c.len == 0, "copied empty len must be 0");
	assert(c == "", "copied empty must equal empty literal");

	// 内存语义：copy 分配了新堆块，与静态字面量不同址
	assert(empty.ptr != null, "empty literal ptr is non-null");
	assert(c.ptr != null, "copied empty ptr is non-null");
	assert(c.ptr != empty.ptr, "copy must allocate a new block, not reuse the literal");

	io::printfn("[empty] literal ptr=%p  copied ptr=%p  (diff confirms new alloc)",
	            (void*)empty.ptr, (void*)c.ptr);
}

fn void test_empty_copy_each_call_independent() @test
{
	String empty = "";
	String a = empty.copy(&allocators::LIBC_ALLOCATOR);
	String b = empty.copy(&allocators::LIBC_ALLOCATOR);

	assert(a.ptr != b.ptr, "each copy must be a distinct heap allocation");
	assert(a == b, "content equal");
	assert(a == "" && b == "");

	// 打印须在 free 之前：free 后再读 ptr 属 use-after-free（读），
	// O2 下会被优化成误导性输出（曾观察到两者都退化成静态段同一地址）。
	io::printfn("[empty] two copies ptr a=%p b=%p (distinct)", (void*)a.ptr, (void*)b.ptr);

	a.free(&allocators::LIBC_ALLOCATOR);
	b.free(&allocators::LIBC_ALLOCATOR);
}

// 验证 free 对 copy 出来的空串安全（1 字节堆块可正常释放）
fn void test_empty_copy_free_is_safe() @test
{
	String empty = "";
	for (int i = 0; i < 100; i++)
	{
		String s = empty.copy(&allocators::LIBC_ALLOCATOR);
		s.free(&allocators::LIBC_ALLOCATOR);
	}
	// 走到这里说明 free 不崩溃
	assert(true);
	io::printfn("[empty] 100x copy+free on empty: no crash");
}

// 对比：非空串 copy 行为（确保断言逻辑正确，非误报）
fn void test_nonempty_copy_normal() @test
{
	String src = "abc";
	String c = src.copy(&allocators::LIBC_ALLOCATOR);
	defer c.free(&allocators::LIBC_ALLOCATOR);

	assert(c.len == 3);
	assert(c == "abc");
	assert(c.ptr != src.ptr, "copy must not reuse source ptr");
	io::printfn("[nonempty] src ptr=%p  copied ptr=%p", (void*)src.ptr, (void*)c.ptr);
}
