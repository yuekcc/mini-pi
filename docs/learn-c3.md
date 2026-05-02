# C3 语言学习笔记

从修复 `src/skill/skill.c3` 内存问题中学习到的 C3 语言特性。

## 1. 内存管理

### 1.1 分配器（Allocator）
C3 使用显式的分配器进行内存管理：

```c
// 使用 alloc::new 分配对象
Skill* skill = alloc::new(allocator, Skill);

// 使用 alloc::free 释放对象
alloc::free(allocator, skill);

// String 类型有专门的 free 方法
self.path.free(allocator);
self.name.free(allocator);
```

### 1.2 临时分配器（tmem）vs 通用分配器（mem）
- `tmem`：临时分配器，在 `@pool()` 块结束时自动清理
- `mem`：通用分配器，需要手动管理生命周期

```c
@pool()
{
    List{Path} paths;
    paths.init(tmem);  // 使用 tmem，pool 块结束时自动释放
    // ...
    context.init(mem, paths.to_array(tmem));  // array 也用 tmem
}
```

### 1.3 @pool() 宏
`@pool()` 创建一个临时分配作用域，退出时自动清理所有用 `tmem` 分配的内存：

```c
@pool()
{
    // 这里用 tmem 分配的所有内存会在块结束时自动释放
    String temp = "hello".copy(tmem);
    // temp 会自动释放，无需手动调用 free
}
```

## 2. 集合遍历

### 2.1 HashMap 遍历
C3 的 HashMap 遍历使用 `@each` 宏，而不是普通的 `foreach`：

```c
// 正确：使用 @each 宏
self.data.@each(; name, skill)
{
    skill.free(self.allocator);
    alloc::free(self.allocator, skill);
};

// 错误：不能这样遍历 HashMap
// foreach (name, skill : self.data)  // 编译错误
```

### 2.2 List 初始化
List 必须显式初始化才能使用：

```c
List{Path} paths;
paths.init(tmem);  // 必须初始化！
find_skill_dirs(&paths);
```

## 3. 静态变量

### 3.1 模块级别变量
C3 中模块级别的变量**不需要** `static` 关键字，默认就是模块私有的：

```c
// 正确：模块级别变量
SkillHub _global_context;
bool _context_initialized = false;

// 错误：C3 不支持模块级别的 static
// static SkillHub _global_context;  // 编译错误
```

### 3.2 函数内静态变量
函数内的静态变量使用 `static` 关键字（但我们这次没用到）：

```c
fn SomeType* get_instance()
{
    static SomeType instance;  // 函数内静态变量
    return &instance;
}
```

## 4. 字符串处理

### 4.1 String 的 copy 和 free
```c
// 复制字符串（分配新内存）
self.path = dir.str_view().copy(allocator);

// 释放字符串
self.path.free(allocator);

// 检查空字符串
if (self.path != "") { ... }
```

### 4.2 字符串连接
```c
// 使用 string::join 连接字符串数组
String body = string::join(tmem, body_lines.to_array(tmem), "\n");
```

## 5. 错误处理

### 5.1 错误展开操作符 `!!`
```c
// 如果出错会 panic
Path skill_file = dir.append(tmem, "SKILL.md")!!;
String text = (String)file::load_path(tmem, skill_file)!!;
```

### 5.2 默认值操作符 `??`
```c
String name = markdown.front_matter.get_string("name") ?? "";
String description = markdown.front_matter.get_string("description") ?? "";
```

## 6. 结构体和方法

### 6.1 结构体定义
```c
struct Skill
{
    String name;
    String description;
    String content;
    String path;
    bool ready;
}
```

### 6.2 结构体方法
使用 `&self` 作为第一个参数定义方法：

```c
fn void Skill.free(&self, Allocator allocator)
{
    if (self.path != "") self.path.free(allocator);
    if (self.name != "") self.name.free(allocator);
    // ...
}

fn Skill* Skill.init(&self, Allocator allocator, Path dir)
{
    self.path = dir.str_view().copy(allocator);
    // ...
    return self;
}
```

## 7. 模块系统

### 7.1 模块声明和导入
```c
module skill;  // 声明当前模块

import std::collections::map;      // 导入 HashMap
import std::collections::list;     // 导入 List
import std::io::path;              // 导入路径处理
import std::os::env;
import std::io;
```

## 8. 常见陷阱和修复

### 8.1 未初始化的 List
```c
// 错误
List{Path} paths;
find_skill_dirs(&paths);  // paths 未初始化！

// 正确
List{Path} paths;
paths.init(tmem);
find_skill_dirs(&paths);
```

### 8.2 错误的 HashMap 遍历
```c
// 错误
foreach (name, skill : self.data) { ... }

// 正确
self.data.@each(; name, skill) { ... };
```

### 8.3 静态变量的模块级别声明
```c
// 错误（模块级别）
static SkillHub context;

// 正确（模块级别）
SkillHub _global_context;
```

### 8.4 String 释放方式
```c
// 错误：Allocator 没有 free 方法
allocator.free(self.path);

// 正确：String 有自己的 free 方法
self.path.free(allocator);
```

## 9. defer 语句

C3 支持 `defer` 语句，在函数退出时执行：

```c
fn void test_skill_context() @test
{
    SkillHub context;
    // ...
    context.init(mem, paths.to_array(tmem));
    defer context.free();  // 函数退出时自动调用
    // ...
}
```

## 10. 测试

### 10.1 测试函数声明
```c
fn void test_use_skill_hub() @test
{
    // 测试代码
    assert(context1 != null);
}
```

### 10.2 运行测试
```bash
# 运行所有测试
c3c test

# 运行特定测试
c3c test --test-filter test_skill_context

# 显示测试输出
c3c test --test-filter test_use_skill_hub --test-show-output
```

## 总结

C3 是一门手动内存管理的系统编程语言，特点包括：
- 显式分配器（Allocator）管理内存
- 临时分配器（tmem）+ `@pool()` 简化临时内存管理
- 丰富的标准库容器（HashMap, List, etc.）
- 宏系统（如 `@each`）用于特定操作
- 模块系统清晰，模块级别变量默认私有
