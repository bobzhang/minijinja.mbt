// Ported from minijinja/tests/test_state.rs.
//
// MoonBit has no typed state extensions (`State::get_extension`,
// `get_or_insert_extension`, ...).  They are emulated with state temps
// (`State::get_temp` / `State::set_temp`) holding integer counters, which are
// shared across includes like extensions are.  `Captured::with_state_mut` is
// not needed because `State` is a reference type: the captured state is used
// directly.

///|
/// Emulates `state.get_or_insert_extension(Counter(default)).0 += 1` and
/// returns the new counter value.
fn state_inc_counter(state : @minijinja.State, key : String) -> Int {
  let old = match state.get_temp(key) {
    Some(v) => v.as_i64().unwrap().to_int()
    None => 0
  }
  let new = old + 1
  state.set_temp(key, @minijinja.Value::from_int(new)) |> ignore
  new
}

///|
/// Emulates `state.get_extension::<Counter>().map(|c| c.0)`.
fn state_get_counter(state : @minijinja.State, key : String) -> Int? {
  state.get_temp(key).map(v => v.as_i64().unwrap().to_int())
}

///|
test "state: lookup_global" {
  let env = @minijinja.Environment::new()
  env.add_function("lookup_global", (state, _args) => {
    state.lookup("the_global").unwrap_or(@minijinja.Value::undefined())
  })
  env.add_global("the_global", @minijinja.Value::from_bool(true))
  let rv = env.render_str("[{{ lookup_global() }}]", @minijinja.Value::none())
  assert_eq(rv, "[True]")
}

///|
test "state: temps" {
  let env = @minijinja.Environment::new()
  env.add_function("inc", (state, _args) => {
    let old = state
      .get_temp("my_counter")
      .unwrap_or(@minijinja.Value::from_int64(0L))
    let new = @minijinja.Value::from_int64(old.as_i64().unwrap() + 1L)
    state.set_temp("my_counter", new) |> ignore
    new
  })
  env.add_template("inc.txt", "{{ inc() }}")
  let rv = env.render_str(
    "{{ inc() }}|{% include 'inc.txt' %}|{% if true %}{{ inc() }}{% endif %}",
    @minijinja.Value::none(),
  )
  assert_eq(rv, "1|2|3")
}

///|
test "state: extensions" {
  // `assert_send::<State>()` has no MoonBit equivalent and is dropped.
  let env = @minijinja.Environment::new()
  env.add_function("inc", (state, _args) => {
    @minijinja.Value::from_int(state_inc_counter(state, "Counter"))
  })
  env.add_function("current", (state, _args) => {
    @minijinja.Value::from_int(state_get_counter(state, "Counter").unwrap_or(0))
  })
  env.add_template("inc.txt", "{{ inc() }}")
  let tmpl = env.template_from_str(
    "{{ inc() }}|{% include 'inc.txt' %}|{{ current() }}|{{ inc() }}",
  )
  let captured = tmpl.render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "1|2|2|3")
  assert_eq(state_get_counter(captured.state, "Counter").unwrap(), 3)
  // with_state_mut(|state| state.get_extension_mut::<Counter>().unwrap().0 += 1)
  state_inc_counter(captured.state, "Counter") |> ignore
  assert_eq(state_get_counter(captured.state, "Counter").unwrap(), 4)
  // with_state_mut(|state| state.get_or_insert_extension(Counter(99)).0)
  let got = match state_get_counter(captured.state, "Counter") {
    Some(v) => v
    None => {
      captured.state.set_temp("Counter", @minijinja.Value::from_int(99))
      |> ignore
      99
    }
  }
  assert_eq(got, 4)
}

///|
test "state: formatter_can_modify_state" {
  let env = @minijinja.Environment::new()
  env.set_formatter((out, state, value) => {
    state_inc_counter(state, "FormatCount") |> ignore
    // `minijinja::escape_formatter` is not public; this template has no
    // auto escaping, so writing the plain string form is equivalent.
    guard state.auto_escape() == @minijinja.AutoEscape::NoEscape else {
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "unexpected auto escape",
      )
    }
    out.write_str(value.to_string())
  })
  let captured = env
    .template_from_str("{{ 1 }}|{{ 2 }}")
    .render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "1|2")
  assert_eq(state_get_counter(captured.state, "FormatCount").unwrap(), 2)
}

///|
test "state: render_block_restores_state_after_error" {
  let env = @minijinja.Environment::new()
  env.add_function("fail_after_first", (state, _args) => {
    let calls = state_inc_counter(state, "Calls")
    if calls == 1 {
      @minijinja.Value::from_string("ok")
    } else {
      raise @minijinja.TemplateError::new(InvalidOperation, "boom")
    }
  })
  let captured = env
    .template_from_str(
      "{% block bad %}{% set leaked = 'yes' %}{% for x in [1] %}{{ fail_after_first() }}{% endfor %}{% endblock %}{% block good %}{{ leaked|default('clean') }}{% endblock %}",
    )
    .render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "okclean")
  let err = try captured.state.render_block("bad") catch {
    e => e
  } noraise {
    s => fail("expected an error, got \{s}")
  }
  assert_eq(err.kind(), @minijinja.ErrorKind::InvalidOperation)
  assert_eq(captured.state.current_block(), None)
  assert_eq(captured.state.lookup("leaked"), None)
  assert_eq(state_get_counter(captured.state, "Calls").unwrap(), 2)
  assert_eq(captured.state.render_block("good"), "clean")
}

///|
test "state: render_block_restores_auto_escape_after_error" {
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => @minijinja.AutoEscape::Html)
  env.add_function("fail_after_first", (state, _args) => {
    let calls = state_inc_counter(state, "Calls")
    if calls == 1 {
      @minijinja.Value::from_string("ok")
    } else {
      raise @minijinja.TemplateError::new(InvalidOperation, "boom")
    }
  })
  env.add_function("recover", (state, _args) => {
    try state.render_block("bad") catch {
      _ => ()
    } noraise {
      _ =>
        raise @minijinja.TemplateError::new(
          InvalidOperation,
          "expected render_block to fail",
        )
    }
    @minijinja.Value::from_string("recovered")
  })
  let output = env
    .template_from_str(
      "{% block bad %}{% autoescape false %}{{ fail_after_first() }}{% endautoescape %}{% endblock %}{{ recover() }}{{ value }}",
    )
    .render(
      @minijinja.Value::from_pairs([
        ("value", @minijinja.Value::from_string("<em>")),
      ]),
    )
  assert_eq(output, "okrecovered&lt;em&gt;")
}

///|
test "state: render_block_restores_state_after_setup_error" {
  let env = @minijinja.Environment::new()
  env.set_recursion_limit(0)
  env.add_global("global", @minijinja.Value::from_int(42))
  let tmpl = env.template_from_str("{% block test %}unreachable{% endblock %}")
  let state = tmpl.new_state()
  let original_name = state.name()
  let err = try state.render_block("test") catch {
    e => e
  } noraise {
    s => fail("expected an error, got \{s}")
  }
  assert_eq(err.detail(), Some("recursion limit exceeded"))
  assert_eq(state.name(), original_name)
  assert_eq(state.current_block(), None)
  assert_eq(state.lookup("global"), Some(@minijinja.Value::from_int(42)))
}

///|
test "state: include_restores_state_after_setup_error" {
  let env = @minijinja.Environment::new()
  env.set_recursion_limit(2)
  env.add_function("include_after_first", (state, _args) => {
    let calls = state_inc_counter(state, "Calls")
    @minijinja.Value::from_bool(calls > 1)
  })
  env.add_template("included", "included")
  env.add_template(
    "main", "{% block bad %}{% if include_after_first() %}{% include 'included' %}{% endif %}{% endblock %}{% block good %}clean{% endblock %}",
  )
  let captured = env
    .get_template("main")
    .render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "clean")
  let err = try captured.state.render_block("bad") catch {
    e => e
  } noraise {
    s => fail("expected an error, got \{s}")
  }
  assert_eq(err.detail(), Some("recursion limit exceeded"))
  assert_eq(captured.state.name(), "main")
  assert_eq(captured.state.current_block(), None)
  assert_eq(captured.state.render_block("good"), "clean")
}

///|
test "state: super_restores_state_after_setup_error" {
  let env = @minijinja.Environment::new()
  env.set_recursion_limit(2)
  env.add_function("super_on_second", (state, _args) => {
    let calls = state_inc_counter(state, "Calls")
    @minijinja.Value::from_bool(calls == 2)
  })
  env.add_template("parent", "{% block body %}parent{% endblock %}")
  env.add_template(
    "child", "{% extends 'parent' %}{% block body %}{% if super_on_second() %}{{ super() }}{% endif %}{% endblock %}",
  )
  let captured = env
    .get_template("child")
    .render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "")
  let err = try captured.state.render_block("body") catch {
    e => e
  } noraise {
    s => fail("expected an error, got \{s}")
  }
  assert_eq(err.detail(), Some("recursion limit exceeded"))
  assert_eq(captured.state.current_block(), None)
  assert_eq(captured.state.render_block("body"), "")
}

///|
test "state: known_variables" {
  let env = @minijinja.Environment::new()
  env.add_global("foo", @minijinja.Value::from_int(42))
  let state = env.empty_state()
  let vars = state.known_variables()
  vars.sort_by(String::lexical_compare) // Rust sorts lexicographically
  assert_eq(vars, ["debug", "dict", "foo", "namespace", "range"])
}
