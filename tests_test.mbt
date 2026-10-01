// Ported from minijinja/tests/test_tests.rs.

///|
test "basics" {
  let env = @minijinja.Environment::new()
  // Rust: fn test(_: &State, a: u32, b: u32) -> bool { assert_eq!(a, 23); a == b }
  env.add_test("test", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let x = a.usize()
    let y = a.usize()
    a.finish()
    if x != 23 {
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "assertion failed: a == 23 (a = \{x})",
      )
    }
    @minijinja.Value::from_bool(x == y)
  })
  let state = env.empty_state()
  assert_true(
    state.perform_test("test", [
      @minijinja.Value::from_int(23),
      @minijinja.Value::from_int(23),
    ]),
  )
}

///|
test "dotted_test_name" {
  let env = @minijinja.Environment::new()
  env.add_test("foo.bar.baz", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.i32()
    a.finish()
    @minijinja.Value::from_bool(value == 42)
  })
  let rv = env
    .template_from_str("{{ 42 is foo.bar.baz }}")
    .render(@minijinja.Value::from_pairs([]))
  assert_eq(rv, "True")
  let rv = env
    .template_from_str("{{ 42 is foo . bar . baz }}")
    .render(@minijinja.Value::from_pairs([]))
  assert_eq(rv, "True")
}
