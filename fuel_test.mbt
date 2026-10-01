// Ported from minijinja/tests/test_fuel.rs

///|
test "fuel: basic" {
  let env = @minijinja.Environment::new()
  assert_eq(env.fuel(), None)
  env.set_fuel(Some(100L))
  assert_eq(env.fuel(), Some(100L))
  env.add_template("test", "{% for x in seq %}{{ x }}\n{% endfor %}")
  let t = env.get_template("test")
  fn seq(n : Int) -> @minijinja.Value {
    @minijinja.Value::from_pairs([
      (
        "seq",
        @minijinja.Value::from_array(
          Array::makei(n, i => @minijinja.Value::from_int(i)),
        ),
      ),
    ])
  }

  // this will still manage to run with 100 fuel
  let rv = t.render(seq(15))
  // like Rust's `str::lines`, a trailing newline does not start a new line
  assert_eq(rv.trim_end(chars="\n").split("\n").count(), 15)
  // this is above the limit
  try t.render(seq(20)) catch {
    err => assert_true(err.kind() == OutOfFuel)
  } noraise {
    _ => fail("expected out of fuel")
  }
}

///|
test "fuel: macro fuel" {
  let env = @minijinja.Environment::new()
  env.set_fuel(Some(100L))
  env.add_template(
    "test",
    (
      #|
      #|        {% macro x() %}{% for item in range(5) %}...{% endfor %}{% endmacro %}
      #|        {% for count in range(macros) %}{{ x() }}{% endfor %}
      #|    
    ),
  )
  let t = env.get_template("test")
  // this should succeed
  t.render(
    @minijinja.Value::from_pairs([("macros", @minijinja.Value::from_int(3))]),
  )
  |> ignore
  // but running more macros should not
  try
    t.render(
      @minijinja.Value::from_pairs([("macros", @minijinja.Value::from_int(5))]),
    )
  catch {
    err => assert_true(err.kind() == OutOfFuel)
  } noraise {
    _ => fail("expected out of fuel")
  }
}
