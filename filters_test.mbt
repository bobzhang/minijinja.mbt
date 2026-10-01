// Ported from minijinja/tests/test_filters.rs.

///|
fn tf_empty() -> @minijinja.Value {
  @minijinja.Value::from_pairs([])
}

///|
fn tf_str(s : String) -> @minijinja.Value {
  @minijinja.Value::from_string(s)
}

///|
fn tf_render(env : @minijinja.Environment, src : String) -> String raise {
  env.template_from_str(src).render(tf_empty())
}

///|
test "filter_with_non" {
  let env = @minijinja.Environment::new()
  // Rust: fn filter(value: Option<String>) -> String
  env.add_filter("filter", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.opt_string()
    a.finish()
    tf_str("[\{value.unwrap_or("")}]")
  })
  let state = env.empty_state()
  let rv = state.apply_filter("filter", [@minijinja.Value::undefined()])
  assert_eq(rv, tf_str("[]"))
  let rv = state.apply_filter("filter", [@minijinja.Value::none()])
  assert_eq(rv, tf_str("[]"))
  let rv = state.apply_filter("filter", [tf_str("wat")])
  assert_eq(rv, tf_str("[wat]"))
}

///|
test "dotted_filter_name" {
  let env = @minijinja.Environment::new()
  env.add_filter("foo.bar.baz", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.string()
    a.finish()
    tf_str("<\{value}>")
  })
  let rv = tf_render(env, "{{ 'hello'|foo.bar.baz }}")
  assert_eq(rv, "<hello>")
  let rv = tf_render(env, "{{ 'hello'|foo . bar . baz }}")
  assert_eq(rv, "<hello>")
}

///|
test "kwargs_require_explicit_argument_type" {
  let env = @minijinja.Environment::new()
  // Rust: |_value: Value, optional: Option<Value>| optional.unwrap_or_default()
  env.add_filter("optional_value", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let _ = a.value()
    let optional = a.opt_value()
    a.finish()
    optional.unwrap_or(@minijinja.Value::undefined())
  })
  try env.render_str("{{ 1|optional_value(unexpected=2) }}", tf_empty()) catch {
    _ => ()
  } noraise {
    _ => fail("expected an error")
  }

  // Rust: |args: Rest<ValueOrKwargs>| args.last().is_some_and(|v| v.is_kwargs())
  env.add_function("accept_kwargs", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let rest = a.rest_with_kwargs()
    @minijinja.Value::from_bool(rest.last() is Some(value) && value.is_kwargs())
  })
  assert_eq(
    env.render_str("{{ accept_kwargs(answer=42) }}", tf_empty()),
    "True",
  )
}

///|
test "indent" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let none = @minijinja.Value::none()
  let yes = @minijinja.Value::from_bool(true)
  // Rust calls `minijinja::filters::indent` directly; the MoonBit port does
  // not expose the filter functions, so go through `State::apply_filter`.
  for
    case in [
      ("\n", none, none, ""),
      ("test\n", none, none, "test"),
      ("test\ntest1\n\ntest2\n", none, none, "test\n  test1\n\n  test2"),
      ("test\ntest1\n\ntest2\n", yes, none, "  test\n  test1\n\n  test2"),
      ("test\ntest1\n\ntest2\n", none, yes, "test\n  test1\n  \n  test2"),
      ("test\ntest1\n\ntest2\n", yes, yes, "  test\n  test1\n  \n  test2"),
    ] {
    let (input, first, blank, expected) = case
    let result = state.apply_filter("indent", [
      tf_str(input),
      @minijinja.Value::from_int(2),
      first,
      blank,
    ])
    assert_eq(result.as_str(), Some(expected))
  }
}

///|
test "indent_preserves_safe_input" {
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Html)
  let state = env.empty_state()
  let safe = state.apply_filter("indent", [
    @minijinja.Value::from_safe_string("<p>one</p>"),
    @minijinja.Value::from_int(2),
  ])
  assert_true(safe.is_safe())
  let unsafe_value = state.apply_filter("indent", [
    tf_str("<p>one</p>"),
    @minijinja.Value::from_int(2),
  ])
  assert_true(!unsafe_value.is_safe())
  let tmpl = env.template_from_str(
    "{% filter indent(2) %}<p>one</p>\n<p>two</p>{% endfilter %}",
  )
  assert_eq(tmpl.render(tf_empty()), "<p>one</p>\n  <p>two</p>")
}

///|
test "string_filters_preserve_safety" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let safe = @minijinja.Value::from_safe_string(" Hello\nWorld ")
  let plain = tf_str(" Hello\nWorld ")
  for filter in ["upper", "lower", "capitalize", "reverse", "trim", "last"] {
    assert_true(state.apply_filter(filter, [safe]).is_safe())
    assert_true(!state.apply_filter(filter, [plain]).is_safe())
  }
  for filter in ["split", "lines"] {
    let result = state.apply_filter(filter, [safe])
    assert_true(result.try_iter().all(item => item.is_safe()))
    let result = state.apply_filter(filter, [plain])
    assert_true(result.try_iter().all(item => !item.is_safe()))
  }
}

///|
test "byte_string_filter_semantics" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  // "éa".as_bytes()
  let reversed = state.apply_filter("reverse", [
    @minijinja.Value::from_bytes(b"\xc3\xa9a"),
  ])
  assert_eq(reversed.kind(), Bytes)
  assert_eq(reversed.as_bytes(), Some(b"a\xa9\xc3"))
  let bytes = @minijinja.Value::from_bytes(b"a\xffb\nc")
  for filter in ["split", "lines"] {
    let items = state
      .apply_filter(filter, [bytes])
      .try_iter()
      .map(item => item.to_string())
      .to_array()
    assert_eq(items, ["a\u{FFFD}b", "c"])
  }
}

///|
test "composing_filters_escape_unsafe_fragments" {
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Html)
  let template = env.template_from_str(
    "{{ source|replace('x', replacement) }}|" +
    "{{ values|join(delimiter) }}|" +
    "{{ format_string|format(user) }}",
  )
  let output = template.render(
    @minijinja.Value::from_pairs([
      ("source", @minijinja.Value::from_safe_string("<b>x</b>")),
      ("replacement", tf_str("<i>y</i>")),
      (
        "values",
        @minijinja.Value::from_array([
          @minijinja.Value::from_safe_string("<b>a</b>"),
          tf_str("<i>b</i>"),
        ]),
      ),
      ("delimiter", tf_str("<hr>")),
      ("format_string", @minijinja.Value::from_safe_string("<b>%s</b>")),
      ("user", tf_str("<i>x</i>")),
    ]),
  )
  assert_eq(
    output,
    "<b>&lt;i&gt;y&lt;&#x2f;i&gt;</b>|" +
    "<b>a</b>&lt;hr&gt;&lt;i&gt;b&lt;&#x2f;i&gt;|" +
    "<b>&lt;i&gt;x&lt;&#x2f;i&gt;</b>",
  )
  let state = template.new_state()
  let result = state.apply_filter("replace", [
    tf_str("<b>TEXT</b>"),
    tf_str("TEXT"),
    @minijinja.Value::from_safe_string("<i>y</i>"),
  ])
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("&lt;b&gt;<i>y</i>&lt;&#x2f;b&gt;"))
  let result = state.apply_filter("join", [
    @minijinja.Value::from_array([tf_str("<b>a</b>"), tf_str("<i>b</i>")]),
    @minijinja.Value::from_safe_string("<hr>"),
  ])
  assert_true(result.is_safe())
  assert_eq(
    result.as_str(),
    Some("&lt;b&gt;a&lt;&#x2f;b&gt;<hr>&lt;i&gt;b&lt;&#x2f;i&gt;"),
  )
  for
    case in [
      ("replace", [tf_str("<b>x</b>"), tf_str("x"), tf_str("y")]),
      (
        "join",
        [@minijinja.Value::from_array([tf_str("<b>a</b>")]), tf_str(",")],
      ),
      (
        "format",
        [tf_str("<b>%s</b>"), @minijinja.Value::from_safe_string("<i>x</i>")],
      ),
    ] {
    let (filter, args) = case
    assert_true(!state.apply_filter(filter, args).is_safe())
  }
}

///|
test "join_streams_when_safety_is_known" {
  // The Rust test checks (via a `Drop` impl) that `join` releases each item
  // before pulling the next one.  MoonBit is garbage collected and has no
  // destructors, so only the streaming calls themselves are exercised here.
  fn make_iterable() -> @minijinja.Value {
    @minijinja.Value::make_iterable(fn() {
      [tf_str("first"), tf_str("done")].iter()
    })
  }

  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let _ = state.apply_filter("join", [make_iterable(), tf_str(",")])
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Html)
  let template = env.template_from_str("")
  let state = template.new_state()
  let _ = state.apply_filter("join", [
    make_iterable(),
    @minijinja.Value::from_safe_string(","),
  ])
}

///|
test "safe_format_escapes_without_autoescape" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let result = state.apply_filter("format", [
    @minijinja.Value::from_safe_string("<b>%(user)s</b>"),
    @minijinja.Value::from_pairs([("user", tf_str("<i>x</i>"))]),
  ])
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("<b>&lt;i&gt;x&lt;&#x2f;i&gt;</b>"))
  let result = state.apply_filter("format", [
    @minijinja.Value::from_safe_string("%d"),
    @minijinja.Value::from_int(42),
  ])
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("42"))
  let result = state.apply_filter("format", [
    @minijinja.Value::from_safe_string("%.5s"),
    tf_str("<é"),
  ])
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("&lt;é"))
  let error = try
    state.apply_filter("format", [
      @minijinja.Value::from_safe_string("%c"),
      @minijinja.Value::from_int(60),
    ])
  catch {
    e => e
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(
    error
    .to_string()
    .contains("character formatting is not supported for safe format strings"),
  )
}

///|
test "abs_overflow" {
  // Rust calls `minijinja::filters::abs` directly; use `apply_filter`.
  let state = @minijinja.Environment::new().empty_state()
  let ok = state.apply_filter("abs", [
    @minijinja.Value::from_int64(-0x7FFFFFFFFFFFFFFFL - 1L),
  ])
  assert_eq(ok, @minijinja.Value::from_bigint(9223372036854775808N))
  let err = try
    state.apply_filter("abs", [
      @minijinja.Value::from_bigint(-170141183460469231731687303715884105728N),
    ])
  catch {
    e => e
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(err.to_string(), "invalid operation: overflow on abs")
}

///|
test "chain_lists" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ [1, 2] | chain([3, 4]) | list }}")
  assert_eq(result, "[1, 2, 3, 4]")
}

///|
test "chain_length" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ [1, 2] | chain([3, 4, 5]) | length }}")
  assert_eq(result, "5")
}

///|
test "chain_dicts" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ {'a': 1} | chain({'b': 2}) | items | list }}")
  assert_eq(result, "[('a', 1), ('b', 2)]")
}

///|
test "chain_dict_lookup" {
  let env = @minijinja.Environment::new()
  // Last dict wins for lookups
  let result = tf_render(env, "{{ ({'a': 1} | chain({'a': 2}))['a'] }}")
  assert_eq(result, "2")
}

///|
test "chain_multiple" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ [1] | chain([2], [3, 4]) | list }}")
  assert_eq(result, "[1, 2, 3, 4]")
}

///|
test "chain_with_iteration" {
  let env = @minijinja.Environment::new()
  let result = tf_render(
    env, "{% for item in [1, 2] | chain([3, 4]) %}{{ item }}{% endfor %}",
  )
  assert_eq(result, "1234")
}

///|
test "chain_indexing" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ ([1, 2] | chain([3, 4]))[2] }}")
  assert_eq(result, "3")
}

///|
test "zip_basic" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ [1, 2, 3] | zip(['a', 'b', 'c']) | list }}")
  assert_eq(result, "[(1, 'a'), (2, 'b'), (3, 'c')]")
}

///|
test "zip_different_lengths" {
  let env = @minijinja.Environment::new()
  // Should stop at the shortest iterable
  let result = tf_render(env, "{{ [1, 2] | zip(['a', 'b', 'c']) | list }}")
  assert_eq(result, "[(1, 'a'), (2, 'b')]")
}

///|
test "zip_multiple_iterables" {
  let env = @minijinja.Environment::new()
  let result = tf_render(
    env, "{{ [1, 2, 3] | zip(['a', 'b', 'c'], ['x', 'y', 'z']) | list }}",
  )
  assert_eq(result, "[(1, 'a', 'x'), (2, 'b', 'y'), (3, 'c', 'z')]")
}

///|
test "zip_with_iteration" {
  let env = @minijinja.Environment::new()
  let result = tf_render(
    env, "{% for num, letter in [1, 2, 3] | zip(['a', 'b', 'c']) %}{{ num }}{{ letter }}{% endfor %}",
  )
  assert_eq(result, "1a2b3c")
}

///|
test "zip_empty_list" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ [] | zip([1, 2, 3]) | list }}")
  assert_eq(result, "[]")
}

///|
test "zip_non_iterable_error" {
  let env = @minijinja.Environment::new()
  let tmpl = env.template_from_str("{{ [1, 2, 3] | zip(42) | list }}")
  let err = try tmpl.render(tf_empty()) catch {
    e => e
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(err.to_string().contains("zip filter argument must be iterable"))
}

///|
test "zip_single_iterable" {
  let env = @minijinja.Environment::new()
  // Zip with no additional arguments should return list of single-element tuples
  let result = tf_render(env, "{{ [1, 2, 3] | zip() | list }}")
  assert_eq(result, "[(1,), (2,), (3,)]")
}

///|
test "higher_order_filters_propagate_mutable_state" {
  fn bump(state : @minijinja.State, key : String) -> Unit {
    let prev = match state.get_temp(key) {
      Some(v) => v.as_i64().unwrap_or(0L)
      None => 0L
    }
    let _ = state.set_temp(key, @minijinja.Value::from_int64(prev + 1L))
  }

  let env = @minijinja.Environment::new()
  env.add_filter("stateful_double", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.i64()
    a.finish()
    bump(state, "filter_calls")
    @minijinja.Value::from_int64(value * 2L)
  })
  env.add_test("stateful_odd", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.i64()
    a.finish()
    bump(state, "test_calls")
    @minijinja.Value::from_bool(value % 2L != 0L)
  })
  env.add_function("call_counts", (state, args) => {
    @minijinja.Args::new(state, args).finish()
    let get = key => {
      state.get_temp(key).unwrap_or(@minijinja.Value::undefined())
    }
    tf_str("\{get("filter_calls")}:\{get("test_calls")}")
  })
  let result = tf_render(
    env,
    "{{ [1, 2, 3]|map('stateful_double')|list }}|" +
    "{{ [1, 2, 3, 4]|select('stateful_odd')|list }}|{{ call_counts() }}",
  )
  assert_eq(result, "[2, 4, 6]|[1, 3]|3:4")
}

///|
test "sort_attribute_list" {
  let env = @minijinja.Environment::new()
  let result = tf_render(
    env, "{{ [{'a': 1, 'b': 2, 'c': 5}, {'a': 2, 'b': 1, 'c': 6}] | sort(attribute='b,a') }}",
  )
  assert_eq(result, "[{'a': 2, 'b': 1, 'c': 6}, {'a': 1, 'b': 2, 'c': 5}]")
}

///|
test "sort_attribute_list_reverse" {
  let env = @minijinja.Environment::new()
  let city = (name, country) => {
    @minijinja.Value::from_pairs([
      ("name", tf_str(name)),
      ("country", tf_str(country)),
    ])
  }
  let ctx = @minijinja.Value::from_pairs([
    (
      "cities",
      @minijinja.Value::from_array([
        city("Sydney", "Australia"),
        city("Sydney", "Canada"),
        city("Kochi", "India"),
        city("Kochi", "Japan"),
      ]),
    ),
  ])
  let tmpl = env.template_from_str(
    "{{ cities | sort(attribute='name, country', reverse=true) " +
    "| map(attribute='country')}}",
  )
  let result = tmpl.render(ctx)
  assert_eq(result, "['Canada', 'Australia', 'Japan', 'India']")
}

///|
test "sort_attribute_list_single" {
  let env = @minijinja.Environment::new()
  let result = tf_render(
    env, "{{ [{'a': 1, 'b': 2}, {'a': 2, 'b': 1}] | sort(attribute='b,') }}",
  )
  assert_eq(result, "[{'a': 2, 'b': 1}, {'a': 1, 'b': 2}]")
}

///|
test "sort_stable_reverse" {
  let env = @minijinja.Environment::new()

  // Test sorting a list of 2-tuples using 0th element as the key, in reverse
  // order. The sort should be stable and preserve the relative order of the
  // equivalent keys.
  let test_cases = [
    ("[[1, 2], [1, 3], [1, 4]]", "[[1, 2], [1, 3], [1, 4]]"),
    ("[[1, 2], [1, 3], [2, 4]]", "[[2, 4], [1, 2], [1, 3]]"),
    ("[[3, 1], [2, 2], [1, 3]]", "[[3, 1], [2, 2], [1, 3]]"),
    ("[[3, 3], [2, 2], [1, 1]]", "[[3, 3], [2, 2], [1, 1]]"),
    ("[[1, 2], [2, 2], [3, 2]]", "[[3, 2], [2, 2], [1, 2]]"),
    ("[[1, 2], [3, 3], [2, 4], [3, 4]]", "[[3, 3], [3, 4], [2, 4], [1, 2]]"),
    (
      "[[1, 2], [2, 2], [3, 2], [1, 1], [2, 2], [3, 3]]", "[[3, 2], [3, 3], [2, 2], [2, 2], [1, 2], [1, 1]]",
    ),
  ]
  for case in test_cases {
    let (input, expected) = case
    let stmt = "{{ \{input} | sort(attribute='0', reverse=true) }}"
    let result = tf_render(env, stmt)
    assert_eq(result, expected)
  }

  // Test stable reverse-sorting with multi-attribute key.
  let result = tf_render(
    env,
    "{{ [{'a': 1, 'b': 1, 'c': 1}, {'a': 1, 'b': 1, 'c': 2}] " +
    "| sort(attribute='a,b', reverse=true) }}",
  )
  assert_eq(result, "[{'a': 1, 'b': 1, 'c': 1}, {'a': 1, 'b': 1, 'c': 2}]")
}

///|
test "sort_strings" {
  let env = @minijinja.Environment::new()
  let result = tf_render(env, "{{ ['aa', 'CC', 'bb'] | sort }}")
  assert_eq(result, "['aa', 'bb', 'CC']")
  let result = tf_render(env, "{{ ['aa', 'CC', 'bb'] | sort(reverse=True) }}")
  assert_eq(result, "['CC', 'bb', 'aa']")
  let result = tf_render(
    env, "{{ ['aa', 'CC', 'bb'] | sort(case_sensitive=True) }}",
  )
  assert_eq(result, "['CC', 'aa', 'bb']")
  let result = tf_render(
    env, "{{ ['aa', 'CC', 'bb'] | sort(case_sensitive=True, reverse=True) }}",
  )
  assert_eq(result, "['bb', 'aa', 'CC']")
}

///|
test "tojson_uses_jinja_spacing" {
  let env = @minijinja.Environment::new()
  let src =
    #|{{ {"function": {"name": "get_weather", "parameters": {"type": "object"}}, "type": "function"}|tojson }}
  let expected =
    #|{"function": {"name": "get_weather", "parameters": {"type": "object"}}, "type": "function"}
  assert_eq(tf_render(env, src), expected)
}

///|
test "escape_filter_custom_formatter" {
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Custom("Markdown"))
  env.set_formatter((out, state, value) => {
    if value.is_safe() && value.kind() == String {
      out.write_str(value.as_str().unwrap_or(""))
      return
    }
    match state.auto_escape() {
      Custom("Markdown") => {
        let escaped = value.to_string().replace_all(old="*", new="\\*")
        out.write_str(escaped)
      }
      // `escape_formatter` is not public in the MoonBit port; approximate
      // it for the auto-escape modes reachable in this test.
      Html => out.write_str(@minijinja.html_escape(value.to_string()))
      _ => out.write_str(value.to_string())
    }
  })
  let result = env
    .template_from_str("{{ value|e }}")
    .render(@minijinja.Value::from_pairs([("value", tf_str("*"))]))
  assert_eq(result, "\\*")
  let result = env
    .template_from_str("{% autoescape false %}{{ value|e }}{% endautoescape %}")
    .render(@minijinja.Value::from_pairs([("value", tf_str("*"))]))
  assert_eq(result, "\\*")
  let result = env
    .template_from_str("{{ '%s'|safe|format(value) }}|{{ values|join('*') }}")
    .render(
      @minijinja.Value::from_pairs([
        ("value", tf_str("*")),
        (
          "values",
          @minijinja.Value::from_array([
            @minijinja.Value::from_safe_string("ok"),
            tf_str("end"),
          ]),
        ),
      ]),
    )
  assert_eq(result, "\\*|ok\\*end")
}
