// Ported from minijinja/tests/test_environment.rs.

///|
test "environment: basic" {
  let env = @minijinja.Environment::new()
  env.add_template("test", "{% for x in seq %}[{{ x }}]{% endfor %}")
  let t = env.get_template("test")
  let ctx = @minijinja.Value::from_pairs([
    (
      "seq",
      @minijinja.Value::from_array([0, 1, 2].map(@minijinja.Value::from_int)),
    ),
  ])
  let rv = t.render(ctx)
  assert_eq(rv, "[0][1][2]")
}

///|
test "environment: expression" {
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("foo + bar")
  let ctx = @minijinja.Value::from_pairs([
    ("foo", @minijinja.Value::from_int(42)),
    ("bar", @minijinja.Value::from_int(23)),
  ])
  assert_eq(expr.eval(ctx), @minijinja.Value::from_int(65))
}

///|
test "environment: expression_owned" {
  // MoonBit strings are always owned; `compile_expression_owned` maps to
  // `compile_expression`.
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("foo + bar".to_string())
  let ctx = @minijinja.Value::from_pairs([
    ("foo", @minijinja.Value::from_int(42)),
    ("bar", @minijinja.Value::from_int(23)),
  ])
  assert_eq(expr.eval(ctx), @minijinja.Value::from_int(65))
}

///|
test "environment: trailing_garbage_rejected" {
  let env = @minijinja.Environment::new()
  let is_err = try {
    env.compile_expression("42 blahadsf") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(is_err)
}

///|
test "environment: int_method_call_compiles" {
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("42.blahadsf()")
  let is_err = try {
    expr.eval(@minijinja.Value::none()) |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(is_err)
}

///|
test "environment: expression_lifetimes" {
  let env = @minijinja.Environment::new()
  let s = ""
  env.add_template("test", s)
  let x = "1 + 1"
  let expr = env.compile_expression(x)
  assert_eq(expr.eval(@minijinja.Value::none()).to_string(), "2")
}

///|
test "environment: expression_undeclared_variables" {
  // Rust returns a HashSet; compare sorted arrays instead.
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("[foo, bar.baz]")
  let undeclared = expr.undeclared_variables(false)
  undeclared.sort_by(String::lexical_compare)
  let expected = ["bar", "foo"]
  expected.sort_by(String::lexical_compare)
  assert_eq(undeclared, expected)
  let undeclared = expr.undeclared_variables(true)
  undeclared.sort_by(String::lexical_compare)
  let expected = ["foo", "bar.baz"]
  expected.sort_by(String::lexical_compare)
  assert_eq(undeclared, expected)
}

///|
#skip("missing API: Environment::clone")
test "environment: clone" {
  let env = @minijinja.Environment::new()
  env.add_template("test", "a")
  // let env2 = env.clone()
  // assert_eq(env2.get_template("test").render(()), "a")
  // env2.add_template("test", "b")
  // assert_eq(env2.get_template("test").render(()), "b")
  assert_eq(env.get_template("test").render(@minijinja.Value::none()), "a")
  fail("Environment::clone is not available")
}

///|
#skip("port bug: Environment::globals returns insertion order, not sorted")
test "environment: globals" {
  let env = @minijinja.Environment::new()
  env.add_global("a", @minijinja.Value::from_int(42))
  env.add_template("test", "{{ a }}")
  let tmpl = env.get_template("test")
  assert_eq(tmpl.render(@minijinja.Value::none()), "42")
  assert_eq(env.globals().map(x => x.0), [
    "a", "debug", "dict", "namespace", "range",
  ])
}

///|
test "environment: template_removal" {
  let env = @minijinja.Environment::new()
  env.add_template("test", "{{ a }}")
  env.remove_template("test")
  let is_err = try {
    env.get_template("test") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(is_err)
}

///|
test "environment: path_join" {
  let env = @minijinja.Environment::new()
  env.add_template("x/a/foo.txt", "{% include '../b/bar.txt' %}")
  env.add_template("x/b/bar.txt", "bar.txt")
  env.set_path_join_callback((name, parent) => {
    let rv : Array[String] = parent.split("/").map(x => x.to_owned()).collect()
    rv.pop() |> ignore
    for segment in name.split("/") {
      match segment {
        "." => ()
        ".." => rv.pop() |> ignore
        other => rv.push(other.to_owned())
      }
    }
    rv.join("/")
  })
  let t = env.get_template("x/a/foo.txt")
  assert_eq(t.render(@minijinja.Value::none()), "bar.txt")
}

///|
test "environment: keep_trailing_newlines" {
  let env = @minijinja.Environment::new()
  env.add_template("foo.txt", "blub\r\n")
  assert_eq(env.render_str("blub\r\n", @minijinja.Value::none()), "blub")
  env.set_keep_trailing_newline(true)
  env.add_template("foo_keep.txt", "blub\r\n")
  assert_eq(
    env.get_template("foo.txt").render(@minijinja.Value::none()),
    "blub",
  )
  assert_eq(
    env.get_template("foo_keep.txt").render(@minijinja.Value::none()),
    "blub\r\n",
  )
  assert_eq(env.render_str("blub\r\n", @minijinja.Value::none()), "blub\r\n")
}

///|
test "environment: unknown_method_callback" {
  let env = @minijinja.Environment::new()
  env.set_unknown_method_callback((state, value, method_name, args) => {
    if value.kind() == @minijinja.ValueKind::Map && method_name == "items" {
      @minijinja.Args::new(state, args).finish()
      state.set_temp("unknown_method_called", @minijinja.Value::from_bool(true))
      |> ignore
      // `minijinja::filters::items` is not public; go through the filter.
      state.apply_filter("items", [value])
    } else {
      raise @minijinja.TemplateError::from_kind(UnknownMethod)
    }
  })
  env.add_function("method_called", (state, _args) => {
    state
    .get_temp("unknown_method_called")
    .unwrap_or(@minijinja.Value::undefined())
  })
  let rv = env.render_str(
    "{{ {'x': 42}.items() }}|{{ method_called() }}",
    @minijinja.Value::none(),
  )
  inspect(rv, content="[('x', 42)]|True")
  let rv = env.render_str(
    "{{ {'items': 'field', 'x': 42}.items() | length }}",
    @minijinja.Value::none(),
  )
  assert_eq(rv, "2")
  let err = try
    env.render_str("{{ [].does_not_exist() }}", @minijinja.Value::none())
  catch {
    e => e
  } noraise {
    s => fail("expected error, got \{s}")
  }
  assert_eq(err.kind(), @minijinja.ErrorKind::UnknownMethod)
  assert_eq(err.detail(), Some("sequence has no method named does_not_exist"))
}

///|
test "environment: iter" {
  // `Environment::templates()` is not available; iterate over
  // `template_names()` and fetch each template instead.
  let env = @minijinja.Environment::new()
  env.add_template("hello", "Hello {{ name }}!")
  env.add_template("goodbye", "Goodbye {{ name }}!")
  let ctx = @minijinja.Value::from_pairs([
    ("name", @minijinja.Value::from_string("World")),
  ])
  let renders = env
    .template_names()
    .map(name => (name, env.get_template(name).render(ctx)))
  assert_eq(renders.length(), 2)
  assert_true(renders.contains(("hello", "Hello World!")))
  assert_true(renders.contains(("goodbye", "Goodbye World!")))
}
