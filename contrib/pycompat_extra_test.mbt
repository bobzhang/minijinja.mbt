// Additional pycompat tests (not ported from upstream).

///|
test "pycompat unicode predicates" {
  assert_true(eval_expr("'٣४'.isdigit()").is_true())
  assert_true(eval_expr("'½Ⅷ'.isnumeric()").is_true())
  assert_false(eval_expr("'1a'.isdigit()").is_true())
  assert_true(eval_expr("'helloा'.isalpha()").is_true())
  assert_false(eval_expr("'hello!'.isalpha()").is_true())
  assert_true(eval_expr("'über2'.isalnum()").is_true())
  assert_true(eval_expr("'\u{3000}\\t'.isspace()").is_true())
  assert_false(eval_expr("'ü'.isascii()").is_true())
  assert_true(eval_expr("'äöü'.islower()").is_true())
  assert_true(eval_expr("'ÄÖÜ'.isupper()").is_true())
  // Rust semantics: `all` over no characters is true
  assert_true(eval_expr("''.islower()").is_true())
}

///|
test "pycompat string methods edge cases" {
  assert_eq(eval_expr("'straße'.upper()").as_str(), Some("STRASSE"))
  assert_eq(eval_expr("'ΟΔΟΣ'.lower()").as_str(), Some("οδος"))
  assert_eq(eval_expr("'\u{3000} x \\n'.strip()").as_str(), Some("x"))
  assert_eq(eval_expr("'xxaxx'.lstrip('x')").as_str(), Some("axx"))
  assert_eq(eval_expr("'abc'.replace('', '-')").as_str(), Some("-a-b-c-"))
  assert_eq(eval_expr("'abc'.replace('', '-', 2)").as_str(), Some("-a-bc"))
  assert_eq(eval_expr("'aaa'.replace('a', 'b', 0)").as_str(), Some("aaa"))
  assert_eq(eval_expr("'aaa'.replace('a', 'b', -1)").as_str(), Some("bbb"))
  // indexes are counted in characters
  assert_eq(eval_expr("'👋 hello'.find('h')").as_usize(), Some(2))
  assert_eq(eval_expr("'👋 hello 👋'.rfind('👋')").as_usize(), Some(8))
  assert_eq(eval_expr("'abc'.find('x')").as_i64(), Some(-1L))
  assert_eq(eval_expr("'abc'.rfind('')").as_usize(), Some(3))
  assert_eq(eval_expr("'abc'.count('')").as_usize(), Some(4))
  assert_eq(eval_expr("'aaaa'.count('aa')").as_usize(), Some(2))
  assert_true(eval_expr("'a\\nb\\n'.splitlines() == ['a', 'b']").is_true())
  assert_true(eval_expr("'a\\n\\nb'.splitlines() == ['a', '', 'b']").is_true())
  assert_true(eval_expr("'a\\rb'.splitlines() == ['a\\rb']").is_true())
  assert_true(eval_expr("''.splitlines() == []").is_true())
  assert_true(
    eval_expr("'a\\nb\\n'.splitlines(true) == ['a\\n', 'b\\n']").is_true(),
  )
  assert_eq(eval_expr("', '.join(['a', 1, none])").as_str(), Some("a, 1, None"))
  assert_eq(eval_expr("'{a}-{0}'.format('x', a='y')").as_str(), Some("y-x"))
  assert_true(eval_expr("'abc'.startswith(['x', 'a'])").is_true())
  assert_true(
    eval_err_expr("'abc'.endswith(['x', 1])").contains(
      "tuple for endswith must contain only strings, not number",
    ),
  )
  assert_true(eval_err_expr("'abc'.upper(1)").contains("too many arguments"))
  assert_true(eval_err_expr("'abc'.foo()").contains("unknown method"))
  assert_true(eval_err_expr("42.foo()").contains("unknown method"))
  // safety is preserved by capitalize (like the core filter)
  let env = pycompat_env()
  let rv = env.render_str(
    "{{ x.capitalize() }}",
    @minijinja.Value::from_pairs([
      ("x", @minijinja.Value::from_safe_string("<b>hi</b>")),
    ]),
  )
  assert_eq(rv, "<b>hi</b>")
}

///|
test "pycompat map and seq methods" {
  assert_true(eval_expr("{}.keys()|list == []").is_true())
  assert_true(eval_expr("{'a': 1, 'b': 2}.values()|list == [1, 2]").is_true())
  assert_true(eval_expr("[1, [2], [2], 3].count([2]) == 2").is_true())
  assert_true(eval_expr("['a', 'b'].count('c') == 0").is_true())
  assert_true(eval_err_expr("[1].index(1)").contains("unknown method"))
}
