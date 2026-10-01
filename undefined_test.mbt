// Ported from minijinja/tests/test_undefined.rs.
//
// `render!(in env, src, ...)` maps to `env.render_str(src, ctx)`; Rust's
// `()` context maps to an empty map.

///|
fn undef_empty_map() -> @minijinja.Value {
  @minijinja.Value::from_pairs([])
}

///|
/// Renders `source` with an empty context.
fn undef_render(
  env : @minijinja.Environment,
  source : String,
) -> String raise @minijinja.TemplateError {
  env.render_str(source, undef_empty_map())
}

///|
/// Renders `source` with `x` bound to an empty map.
fn undef_render_x(
  env : @minijinja.Environment,
  source : String,
) -> String raise @minijinja.TemplateError {
  env.render_str(
    source,
    @minijinja.Value::from_pairs([("x", undef_empty_map())]),
  )
}

///|
/// Renders `source` expecting a failure and returns the error kind.
fn undef_err_kind(
  env : @minijinja.Environment,
  source : String,
  ctx? : @minijinja.Value = undef_empty_map(),
) -> @minijinja.ErrorKind raise {
  try env.render_str(source, ctx) catch {
    e => e.kind()
  } noraise {
    s => fail("expected an error rendering \{repr(source)}, got \{repr(s)}")
  }
}

///|
/// Registers a `test` filter that mirrors the Rust filter taking a `String`
/// and asserting the undefined behavior and that the value is empty.
fn undef_add_test_filter(
  env : @minijinja.Environment,
  expected : @minijinja.UndefinedBehavior,
) -> Unit {
  env.add_filter("test", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.string()
    a.finish()
    guard state.undefined_behavior() == expected else {
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "unexpected undefined behavior",
      )
    }
    guard value == "" else {
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "expected empty string, got \{repr(value)}",
      )
    }
    @minijinja.Value::from_string(value)
  })
}

///|
/// Registers `test_rest_join` (Rust: `Rest<String>`) and `test_vec_join`
/// (Rust: `Vec<String>`).
fn undef_add_join_filters(env : @minijinja.Environment) -> Unit {
  env.add_filter("test_rest_join", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let values = []
    while a.has_more() {
      values.push(a.string())
    }
    @minijinja.Value::from_string(values.join("|"))
  })
  env.add_filter("test_vec_join", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let seq = a.value()
    a.finish()
    let values = []
    for item in seq.try_iter() {
      values.push(@minijinja.Args::new(state, [item]).string())
    }
    @minijinja.Value::from_string(values.join("|"))
  })
}

///|
test "undefined: lenient_undefined" {
  let env = @minijinja.Environment::new()
  undef_add_test_filter(env, @minijinja.UndefinedBehavior::Lenient)
  assert_true(env.undefined_behavior() == @minijinja.UndefinedBehavior::Lenient)
  assert_eq(undef_render(env, "<{{ true.missing_attribute }}>"), "<>")
  assert_eq(
    undef_err_kind(env, "{{ undefined.missing_attribute }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_render(env, "<{% for x in undefined %}...{% endfor %}>"),
    "<>",
  )
  assert_eq(undef_render(env, "{{ 'foo' is in(undefined) }}"), "False")
  assert_eq(undef_render(env, "<{{ undefined }}>"), "<>")
  assert_eq(undef_render(env, "{{ not undefined }}"), "True")
  assert_eq(undef_render(env, "{{ undefined is undefined }}"), "True")
  assert_eq(undef_render_x(env, "{{ x.foo is undefined }}"), "True")
  assert_eq(undef_render(env, "{{ undefined|list }}"), "[]")
  assert_eq(undef_render(env, "<{{ undefined|test }}>"), "<>")
  assert_eq(undef_render(env, "{{ 42 in undefined }}"), "False")
}

///|
test "undefined: semi_strict_undefined" {
  let env = @minijinja.Environment::new()
  env.set_undefined_behavior(@minijinja.UndefinedBehavior::SemiStrict)
  undef_add_join_filters(env)
  assert_eq(
    undef_err_kind(env, "{{ true.missing_attribute }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined.missing_attribute }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "<{% for x in undefined %}...{% endfor %}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ 'foo' is in(undefined) }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(undef_render(env, "<{% if undefined %}42{% endif %}>"), "<>")
  assert_eq(
    undef_err_kind(env, "<{{ undefined }}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(undef_render(env, "{{ not undefined }}"), "True")
  assert_eq(undef_render(env, "{{ undefined is undefined }}"), "True")
  assert_eq(undef_render(env, "<{{ 42 if false }}>"), "<>")
  assert_eq(undef_render_x(env, "{{ x.foo is undefined }}"), "True")
  assert_eq(undef_render_x(env, "<{% if x.foo %}...{% endif %}>"), "<>")
  assert_eq(
    undef_err_kind(env, "{{ undefined|list }}"),
    @minijinja.ErrorKind::InvalidOperation,
  )
  assert_eq(
    undef_err_kind(env, "{{ 42 in undefined }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|upper }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|int }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|float }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|string }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|test_rest_join }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ [undefined]|test_vec_join }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  // bool follows is_true semantics: SemiStrict allows it (returns false), Strict errors
  assert_eq(undef_render(env, "{{ undefined|bool }}"), "False")
  // none|int should still work (undefined check only applies to undefined, not none)
  assert_eq(undef_render(env, "{{ none|int }}"), "0")
  assert_eq(
    undef_render(env, "{{ undefined|default('FALLBACK') }}"),
    "FALLBACK",
  )
  assert_eq(
    undef_err_kind(env, "{{ foo == 'foo' }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ foo ~ 'x' }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ foo|default(bar) }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
}

///|
test "undefined: strict_undefined" {
  let env = @minijinja.Environment::new()
  env.set_undefined_behavior(@minijinja.UndefinedBehavior::Strict)
  undef_add_join_filters(env)
  assert_eq(
    undef_err_kind(env, "{{ true.missing_attribute }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined.missing_attribute }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "<{% for x in undefined %}...{% endfor %}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ 'foo' is in(undefined) }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "<{% if undefined %}42{% endif %}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "<{{ undefined }}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "<{{ not undefined }}>"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(undef_render(env, "{{ undefined is undefined }}"), "True")
  assert_eq(undef_render(env, "<{{ 42 if false }}>"), "<>")
  assert_eq(undef_render_x(env, "{{ x.foo is undefined }}"), "True")
  assert_eq(
    undef_err_kind(
      env,
      "{% if x.foo %}...{% endif %}",
      ctx=@minijinja.Value::from_pairs([("x", undef_empty_map())]),
    ),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|list }}"),
    @minijinja.ErrorKind::InvalidOperation,
  )
  assert_eq(
    undef_err_kind(env, "{{ 42 in undefined }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined in [1, 2, 3] }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined in 'abc' }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|upper }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|int }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|float }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|bool }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|string }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ undefined|test_rest_join }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  assert_eq(
    undef_err_kind(env, "{{ [undefined]|test_vec_join }}"),
    @minijinja.ErrorKind::UndefinedError,
  )
  // none|int should still work (only undefined is rejected)
  assert_eq(undef_render(env, "{{ none|int }}"), "0")
  assert_eq(
    undef_render(env, "{{ undefined|default('FALLBACK') }}"),
    "FALLBACK",
  )
}

///|
test "undefined: chainable_undefined" {
  let env = @minijinja.Environment::new()
  env.set_undefined_behavior(@minijinja.UndefinedBehavior::Chainable)
  undef_add_test_filter(env, @minijinja.UndefinedBehavior::Chainable)
  assert_eq(undef_render(env, "<{{ true.missing_attribute }}>"), "<>")
  assert_eq(undef_render(env, "<{{ undefined.missing_attribute }}>"), "<>")
  assert_eq(
    undef_render(env, "<{% for x in undefined %}...{% endfor %}>"),
    "<>",
  )
  assert_eq(undef_render_x(env, "{{ x.foo is undefined }}"), "True")
  assert_eq(undef_render(env, "{{ 'foo' is in(undefined) }}"), "False")
  assert_eq(undef_render(env, "<{{ undefined }}>"), "<>")
  assert_eq(undef_render(env, "{{ not undefined }}"), "True")
  assert_eq(undef_render(env, "{{ undefined is undefined }}"), "True")
  assert_eq(undef_render(env, "{{ undefined|list }}"), "[]")
  assert_eq(undef_render(env, "<{{ undefined|test }}>"), "<>")
  assert_eq(undef_render(env, "{{ 42 in undefined }}"), "False")
}
