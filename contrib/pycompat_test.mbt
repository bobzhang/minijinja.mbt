///|
test "test_string_methods" {
  assert_eq(eval_expr("'foo'.upper()").as_str(), Some("FOO"))
  assert_eq(eval_expr("'FoO'.lower()").as_str(), Some("foo"))
  assert_eq(eval_expr("' foo '.strip()").as_str(), Some("foo"))
  assert_eq(eval_expr("'!foo?!!!'.strip('!?')").as_str(), Some("foo"))
  assert_eq(eval_expr("'!!!foo?!!!'.rstrip('!?')").as_str(), Some("!!!foo"))
  assert_eq(eval_expr("'!!!foo?!!!'.lstrip('!?')").as_str(), Some("foo?!!!"))
  assert_true(eval_expr("'foobar'.islower()").is_true())
  assert_true(eval_expr("'FOOBAR'.isupper()").is_true())
  assert_true(eval_expr("' \\n'.isspace()").is_true())
  assert_true(eval_expr("'abc'.isalpha()").is_true())
  assert_true(eval_expr("'abc123'.isalnum()").is_true())
  assert_true(eval_expr("'abc%@#'.isascii()").is_true())
  assert_eq(eval_expr("'foobar'.replace('o', 'x')").as_str(), Some("fxxbar"))
  assert_eq(eval_expr("'foobar'.replace('o', 'x', 1)").as_str(), Some("fxobar"))
  assert_eq(eval_expr("'foo bar'.title()").as_str(), Some("Foo Bar"))
  assert_eq(eval_expr("'foo bar'.capitalize()").as_str(), Some("Foo bar"))
  assert_eq(eval_expr("'foo barooo'.count('oo')").as_usize(), Some(2))
  assert_eq(eval_expr("'foo barooo'.find('oo')").as_usize(), Some(1))
  assert_eq(eval_expr("'foo barooo'.rfind('oo')").as_usize(), Some(8))
  assert_true(eval_expr("'a b c'.split() == ['a', 'b', 'c']").is_true())
  assert_true(eval_expr("'a  b  c'.split() == ['a', 'b', 'c']").is_true())
  assert_true(eval_expr("'a  b  c'.split(none, 1) == ['a', 'b  c']").is_true())
  assert_true(eval_expr("'abcbd'.split('b', 1) == ['a', 'cbd']").is_true())
  assert_true(
    eval_expr("'a\\nb\\r\\nc'.splitlines() == ['a', 'b', 'c']").is_true(),
  )
  assert_true(
    eval_expr("'a\\nb\\r\\nc'.splitlines(true) == ['a\\n', 'b\\r\\n', 'c']").is_true(),
  )
  assert_true(eval_expr("'foobarbaz'.startswith('foo')").is_true())
  assert_true(eval_expr("'foobarbaz'.startswith(('foo', 'bar'))").is_true())
  assert_false(eval_expr("'barfoobaz'.startswith(('foo', 'baz'))").is_true())
  assert_true(eval_expr("'foobarbaz'.endswith('baz')").is_true())
  assert_true(eval_expr("'foobarbaz'.endswith(('baz', 'bar'))").is_true())
  assert_false(eval_expr("'foobarbazblah'.endswith(('baz', 'bar'))").is_true())
  assert_eq(eval_expr("'|'.join([1, 2, 3])").as_str(), Some("1|2|3"))
}

///|
test "test_dict_methods" {
  assert_true(eval_expr("{'x': 42}.keys()|list == ['x']").is_true())
  assert_true(eval_expr("{'x': 42}.values()|list == [42]").is_true())
  assert_true(eval_expr("{'x': 42}.items()|list == [('x', 42)]").is_true())
  assert_true(eval_expr("{'x': 42}.get('x') == 42").is_true())
  assert_true(eval_expr("{'x': 42}.get('y') is none").is_true())
  assert_true(eval_expr("{'x': 42}.get('x', 47) == 42").is_true())
  assert_true(eval_expr("{'x': 42}.get('y', 47) == 47").is_true())
  assert_true(
    eval_expr(
      "{'items': 'FIELD', 'x': 42}.items()|list == [('items', 'FIELD'), ('x', 42)]",
    ).is_true(),
  )
  let env = pycompat_env()
  env.add_global(
    "item_fn",
    @minijinja.Value::from_function("item_fn", (_, _) => {
      @minijinja.Value::from_int(42)
    }),
  )
  assert_true(
    env
    .compile_expression("{'items': item_fn, 'x': 23}.items()|list|length == 2")
    .eval(@minijinja.Value::none())
    .is_true(),
  )
  assert_true(
    env
    .compile_expression("{'items': item_fn}['items']() == 42")
    .eval(@minijinja.Value::none())
    .is_true(),
  )
}

///|
test "test_list_methods" {
  assert_true(eval_expr("[1, 2, 2, 3].count(2) == 2").is_true())
}

///|
test "test_errors" {
  assert_true(
    eval_err_expr("'abc'.split(1, 2)").contains("value is not a string"),
  )
  assert_true(
    eval_err_expr("'abc'.startswith(1)").contains(
      "startswith argument must be string or a tuple of strings, not number",
    ),
  )
  assert_true(eval_err_expr("{'x': 42}.get()").contains("missing argument"))
}
