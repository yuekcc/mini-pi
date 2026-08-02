# C3 语言简介

本文档是面向智能体的 **C3 语法参考**，覆盖编写、调试、解释 C3 代码时最常用的语法、类型系统、错误处理、内存模型与编译期特性。C3 是 C 的演进版本，保持 C ABI 兼容与底层控制力，同时加入模块、可选类型、接口、卫生宏等现代特性。

---

## 1. 基础语法

### 1.1 变量

```c3
int  a = 10;            // 显式类型
var  b = 20;            // 局部类型推断
const MAX = 100;        // 编译期常量
int  c @noinit;         // 跳过零初始化
```

- 所有变量默认**零初始化**；`@noinit` 退出此行为（常用于确定会立即写满的 I/O 缓冲）。
- 命名规则（编译器强制）：类型 `PascalCase`、常量 `SCREAMING_SNAKE_CASE`、其余 `snake_case`。

### 1.2 函数

```c3
fn int add(int x, int y) { return x + y; }
fn int square(int x) => x * x;                 // 单行简写
fn void greet(String name) { io::printn("Hello " + name); }
```

- 返回可选类型且函数未标 `@maydiscard` 时，调用方**必须用 `(void)` 显式忽略返回值**，否则编译报错：
  ```c3
  (void)file.close();
  defer (void)process.destroy();
  ```

### 1.3 控制流

```c3
if (x > 0) { ... } else { ... }

for (int i = 0; i < 10; i++) { ... }
while (cond) { ... }
do { ... } while (cond);

switch (x) {
    case 1:  ...;            // 隐式 break
    case 2:  ...; nextcase;  // 落入下一 case
    default: unreachable("unexpected");
}
```

- `foreach (v : list)` 遍历；`foreach (&v : list)` 取引用。
- 可给循环加标签：`while LOOP: (true) { ... continue LOOP; }`。
- `defer expr` 在函数退出前执行；`defer (void)resource.free();`。

### 1.4 数组与切片

```c3
int[4] arr = {1, 2, 3, 4};   // 定长数组（值类型）
int[]  slice = &arr;         // 切片视图
int[*] inferred = {1, 2, 3}; // 长度推断：int[3]
int[]  sub = arr[1..3];      // 子切片（半开区间）
```

- 切片有 `.ptr` 与 `.len`；数组可下标 `buf[:len]` 取子切片。
- 常用整数类型：`usz`（无符号 size）、`sz`（有符号）、`iptr`（指针宽整数）。

### 1.5 字符串

`String` 是 `char[]` 的别名，方法丰富：

```c3
String s = "Hello";
String up = s.replace(allocator, "l", "L");  // 返回新串（需分配器）
String[] parts = s.split(allocator, " ");
String t = s.trim();
usz n = s.len;
```

拼接运算符 `++`（可链式 `a ++ b ++ c`）：

```c3
String greeting = "Hello " ++ name;
```

---

## 2. 模块与导入

- 每个文件声明一个 `module`；**目录 = 子模块**：`src/foo/bar.c3` 声明 `module foo::bar;`。
- 同模块可跨多文件：`a.c3` 与 `b.c3` 都写 `module util;` 会合并为一个模块。
- 导入：`import std::io;`，多个用逗号 `import std::io, std::math;`。导入是递归的。
- 可见性：`@public`（默认）、`@private`（模块内）、`@local`（文件内）。
- 模块级变量默认私有，无需 `static`；`tlocal` 声明线程局部存储：
  ```c3
  tlocal GlobalState state;
  ```
- 类型可不加前缀使用；函数/变量需带最后一段前缀（`io::printfn`）。

---

## 3. 错误处理

C3 用 **可选类型**（`T?`）表达“值或错误（fault）”。

### 3.1 定义 fault

```c3
faultdef
    NOT_FOUND, PERMISSION_DENIED, IO_ERROR,
;
```

### 3.2 返回可选类型

```c3
fn int? read_int(String s) {
    if (s.len == 0) return NOT_FOUND~;   // ~ 把 fault 包成可选类型
    return s.to_int()!;                   // ! 解包或向上传播 fault
}
```

### 3.3 处理可选类型

- `if (try v = expr)`：成功分支，`v` 已解包
- `if (catch err = expr)`：失败分支，`err` 是 fault
- `expr ?? default`：为空时给默认值
- `expr!`：解包，失败则本函数返回该 fault
- `expr!!`：解包，失败则直接 panic（初始化等“失败即致命”处使用）

```c3
if (catch err = read_int("123")) {
    io::printfn("error: %s", err);
} else {
    int x = read_int("123");   // 已检查，安全解包
}
```

---

## 4. 内存管理

### 4.1 临时分配器 `tmem` + `@pool`

`tmem` 上的内存在退出 `@pool()` 块或函数返回时自动回收。**绝不要把 `tmem` 分配的内存返回出其作用域**。

```c3
@pool()
{
    DString result = dstring::new(tmem);
    result.append("hello");
    return result.copy_str(allocator);   // 复制出池外
};
```

带标签的池化循环：

```c3
while LOOP: (true) @pool()
{
    ...
    continue LOOP;   // @pool 作用域重新开始
}
```

### 4.2 堆分配 `mem` / `alloc`

需要跨函数长期持有（存入结构体、全局）的数据用显式分配器：

```c3
MyStruct* p = alloc::new(allocator, MyStruct);
alloc::free(allocator, p);
```

`Allocator` 主要有 `tmem`（临时）与 `mem`（堆全局）。

### 4.3 字符串构建用 `DString`

```c3
DString buf = dstring::new(tmem);
buf.append("line\n");
buf.appendf("- %s: %s", name, desc);
String out  = buf.copy_str(allocator);   // 落到指定分配器
String view = buf.str_view();            // 仅视图（生命周期同 buf）
```

### 4.4 容器 `List{Type}`

```c3
List{int} list;
list.init(tmem);                    // 默认 tmem
list.push(1);
usz n = list.len();                 // 元素个数（也可访问 .size 字段）
int[] arr = list.to_array(allocator);  // 转定长数组
list.free();                        // 手动释放（默认 tmem 时也可靠 @pool 自动）
```

> 坑：容器默认 `tmem`，若要在 `@pool()` 之外长期存活，必须 `init(mem)` 或把元素 `copy(mem)`。

---

## 5. 时间与日期

`datetime::now()` 返回 **UTC** 的 `DateTime`。取本地时间必须显式 `.to_local()`（幂等：已是 LOCAL 则原样返回）。直接读 `.year/.hour` 等分量会得到 UTC 值。

```c3
DateTime now = datetime::now().to_local();           // 统一转本地
String ts = now.format(allocator, DateTimeFormat.DATETIME);
```

`DateTime.to_local()` 既是静态方法 `DateTime.to_local(DateTime)` 也可作实例方法 `dt.to_local()` 使用。

---

## 6. 文件与 I/O

### 6.1 打开/读写

```c3
char[]? content = file::load(allocator, "data.txt");   // 一次性读，返回 char[]?
if (try c = content) { ... }

file::save(path, content)!!;                            // 保存
File f = file::open(path, "r")!;                       // 打开（返回 File，非可选）
defer f.close()!!;
```

**坑：`File?`（可选）不能用 `= null` 赋空**——`null` 在此语境被当作 `void*`。管理“可关闭资源”的惯用法是 `File` + `bool` 标志位。

### 6.2 写入流：必须传指针

`io::fprintf(OutStream out, ...)` 等接收流接口的参数**必须传指针** `&file`。`File` 实现了 `OutStream`/`InStream` 接口，传 `&file` 可隐式转换：

```c3
io::fprintf(&file, "x=%d\n", x);
file.flush();
```

### 6.3 路径 `Path`

```c3
import std::io::path;

Path cwd  = path::cwd(allocator)!;
Path home = path::home_directory(tmem)!!;
Path cfg  = home.append(allocator, ".config/app")!;
if (try parent = cfg.parent()) { if (!path::exists(parent)) path::mkdir(parent, true); }
Path base = cfg.basename();
```

---

## 7. 格式化与打印

```c3
io::printn("hello");                  // 换行
io::printfn("x=%d", x);               // 格式化 + 换行
io::eprintfn("[WARN] %s", msg);      // 走 stderr

String a = string::format(allocator, "id_%s", id);   // 落到指定分配器
String b = string::tformat("tmp_%s", id);             // tmem 临时版
String c = string::tcopy(tmem, src);                  // 复制一份
```

传给需要以 `\0` 结尾字符串的 C 接口时转 `ZString`：

```c3
ZString z = (ZString)buf.str_view();
```

---

## 8. 宏与编译期特性

### 8.1 变参宏

```c3
macro void log_error(String $format, args...) {
    io::eprintfn("[ERROR] " ++ $format, ...args);   // ...args 展开变参
}
```

- 变参声明 `args...`；函数体内是 `any[]`；调用其他变参函数时用 `...args` 展开。
- `$format` 用 `$` 前缀在编译期捕获格式串字面量。

### 8.2 条件编译

```c3
$if env::WIN32:
    // Windows 专属代码
$endif
```

### 8.3 编译期变量与反射

```c3
$foreach f : $Type.membersof:
    io::printfn("%s @ offset %d", f.nameof, f.offsetof);
$endforeach
```

### 8.4 嵌入资源 `$embed`

把文本/二进制文件编译进二进制，避免运行时路径依赖：

```c3
const String TEMPLATE = (String)$embed("template.md");
```

---

## 9. 接口与动态分派

```c3
interface Animal {
    fn String name();
    fn void speak();
}

struct Dog (Animal) {
    bool _pad;     // 占位，保证与接口布局匹配
}

fn String Dog.name(&self) @dynamic { return "Dog"; }
fn void Dog.speak(&self) @dynamic { io::printn("Woof"); }
```

调用侧把具体类型转成接口，通过接口调用动态方法：

```c3
Animal a = (Animal)alloc::new(allocator, Dog);
io::printn(a.name());     // 走 @dynamic 分派
```

---

## 10. 泛型

```c3
module stack <Type>;

struct Stack {
    usz capacity;
    usz size;
    Type* elems;
}

fn void Stack.push(&self, Type elem) { ... }
fn Type Stack.pop(&self) { ... }

// 使用
module main;
import stack;
alias IntStack = Stack{int};
```

---

## 11. 常用标准库模块

| 模块 | 用途 |
| --- | --- |
| `std::io` | 打印、`File`、流 |
| `std::io::file` | `file::load`/`save`/`open` |
| `std::io::path` | `Path` 相关操作 |
| `std::core::mem` / `alloc` | 分配器、`alloc::new`/`free`、`tmem`、`mem` |
| `std::collections` | `DString`、`List`、`HashMap` 等 |
| `std::string` | `string::format` 等 |
| `std::math` | 数学、随机 |
| `std::os` | 进程、环境变量 |
| `std::time::datetime` | 时间、格式化 |
| `std::thread` | 线程、互斥量 |

---

## 12. 测试

测试函数用 `@test` 标注，断言用 `test::eq`：

```c3
fn void test_add() @test {
    test::eq(add(1, 2), 3);
}
```

运行：`c3c test`，单个测试 `c3c test --test-filter test_add --test-show-output`。

---

## 13. 项目配置 `project.json`

C3 使用 `project.json` 描述构建：

```json
{
  "langrev": "1",
  "authors": ["Your Name"],
  "version": "0.1.0",
  "sources": ["src/**"],
  "dependencies": ["some_lib"],
  "targets": {
    "my_app": { "type": "executable" }
  }
}
```

- `dependencies`：依赖的 `.c3l` 库名。
- `linked-libraries`：要链接的 C 库（如 `"m"`）。
- `cpu` / `opt` / `safe`：编译目标与优化级别。

---

## 14. 最佳实践与坑

- **命名规则**由编译器强制：类型 `MyStruct`、常量 `MAX_SIZE`、其余 `snake_case`。
- **零初始化**：局部变量默认清零；`char[N] buf @noinit` 仅用于确定立即写满的缓冲。
- **错误处理**：能恢复用 `catch`/`??`；向上传播用 `!`；初始化等致命处才用 `!!`。
- **`(void)` 丢弃**：返回 `void?`/`sz?` 等且函数未标 `@maydiscard` 时，调用方必须 `(void)fn()`。
- **`tmem` 不逃逸**：`@pool()` / 函数返回即回收；要长期持有就 `.copy(mem)` 或 `init(mem)`。`List`/`DString` 默认 `tmem`。
- **时间**：取本地时间必须 `datetime::now().to_local()`，否则拿到 UTC。
- **`File?` 不能 `= null`**：用 `File` + `bool` 标志位管理可关闭资源。
- **流参数传指针**：`io::fprintf(&file, ...)`、`f.read(&buf, ...)`。
- **接口实现**：具体类型 `struct X (Iface)` + `@dynamic` 方法；通过 `(Iface)` 转型调用。
- **资源嵌入**：模板/配置用 `$embed` 编进二进制。
- **安全模式**：开发用默认 `--safe`（开启检查），发布用 `--fast`/`O2` 关闭大部分检查。

---

## 参考

- [C3 官方文档](https://c3-lang.org)
- 标准库源码：运行 `c3c --version` 查看 `Installed directory`，其下 `lib\std` 可查阅示例
