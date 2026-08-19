module util;

import std::io::file;
import std::io::path;

// FNV-1a 32 位哈希参数
const uint FNV_OFFSET_32 = 0x811c9dc5; // 2166136261
const uint FNV_PRIME_32  = 0x01000193; // 16777619

// 锚点字母表（对齐 oh-my-pi）：最低字节拆成两个 4-bit nibble 后映射
const String HASH_ALPHABET = "ZPMQVRWSNKTXJBYH";

// hashline 输出格式（read() 产出、hash_edit() 消费的契约，单一来源）：
//   行号:哈希|内容
const String HASH_LINE_FORMAT = "%d:%s|%s\n";

// 锚点契约的基础管线：加载文件 → 归一化行尾 → 按 \n 切行。
// read() 与 hash_edit() 必须对同一文件得到字节一致的行数组，锚点才成立——
// 本函数是唯一入口，避免两处管线漂移（arch review 卡 4）。
fn String[]? load_lines(Allocator allocator, String file_path)
{
	Path path_obj = path::new(tmem, file_path)!;
	String content = (String)file::load_path(tmem, path_obj)!;
	String normalized_content = normalize_line_endings(tmem, content);
	return normalized_content.split(allocator, "\n");
}

// 判断一行是否含有字母或数字
fn bool has_alnum(String s)
{
	foreach (b : s)
	{
		if ((b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9'))
		{
			return true;
		}
	}
	return false;
}

// 计算单行的内容哈希锚点（2 字符）。
// 算法对齐 oh-my-pi 的 hashline：
//   1. 去掉行尾 \r 与行尾空白
//   2. 对归一化字节做 FNV-1a 32 位哈希
//   3. 取最低字节，拆成两个 4-bit nibble，映射到 HASH_ALPHABET
//   4. 无字母数字的行（空行、{、} 等）额外把 1-based 行号折叠进哈希状态，
//      保证不同位置的同构行得到不同锚点
// 注意：模型读取时看到的锚点由同一函数生成，因此只需本构建内自洽即可，
//       不要求跨平台/跨版本一致。
fn String line_hash(Allocator allocator, String line, usz line_num)
{
	// 去掉行尾 \r
	String trimmed = line;
	if (trimmed.len > 0 && trimmed[trimmed.len - 1] == '\r')
	{
		trimmed = trimmed[:trimmed.len - 1];
	}
	// 去掉行尾空白（空格、tab）
	while (trimmed.len > 0 &&
	       (trimmed[trimmed.len - 1] == ' ' || trimmed[trimmed.len - 1] == '\t'))
	{
		trimmed = trimmed[:trimmed.len - 1];
	}

	uint h = FNV_OFFSET_32;

	if (!has_alnum(trimmed))
	{
		// 把行号按字节折叠进哈希状态，使同构行在不同位置得到不同锚点
		usz n = line_num;
		while (n > 0)
		{
			h ^= (uint)(n & 0xff);
			h *= FNV_PRIME_32;
			n >>= 8;
		}
	}

	foreach (b : trimmed)
	{
		h ^= (uint)b;
		h *= FNV_PRIME_32;
	}

	char low = (char)(h & 0xff);
	usz hi = (usz)((low >> 4) & 0xf);
	usz lo = (usz)(low & 0xf);

	DString buf = dstring::new(allocator);
	buf.append(HASH_ALPHABET[hi]);
	buf.append(HASH_ALPHABET[lo]);
	return buf.copy_str(allocator);
}
