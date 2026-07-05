struct User
{
	String name;
	String nick_name;
	int age;
}

fn void test_clone() @test
{
	User a = {
		.name = "tom",
		.nick_name = "tomcat",
		.age = 18
	};

	User* b = alloc::clone(tmem, a);

	test::ne(&a, b);
	test::ne(&a.age, &b.age);
	test::ne(&a.name, &b.nick_name);
	test::ne(&a.nick_name, &b.nick_name);

	test::eq(a.name, b.name);
	test::eq(a.nick_name, b.nick_name);
	test::eq(a.age, b.age);
}
