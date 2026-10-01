// Ported from minijinja/tests/test_loader.rs.

///|
fn loader_create_env() -> @minijinja.Environment raise {
  let env = @minijinja.Environment::new()
  // `add_template_owned` maps to `add_template`: MoonBit strings are owned.
  let template = "Hello World!"
  env.add_template("hello", template)
  env
}

///|
test "loader: basic" {
  let env = loader_create_env()
  let t = env.get_template("hello")
  assert_eq(t.render(@minijinja.Value::none()), "Hello World!")
}

///|
test "loader: dynamic" {
  let env = @minijinja.Environment::new()
  let template = "Hello World 2!"
  env.add_template("hello2", template)
  env.set_loader(name => {
    match name {
      "hello" => Some("Hello World!")
      _ => None
    }
  })
  let t = env.get_template("hello")
  assert_eq(t.render(@minijinja.Value::none()), "Hello World!")
  let t = env.get_template("hello2")
  assert_eq(t.render(@minijinja.Value::none()), "Hello World 2!")
  let err = try env.get_template("missing") catch {
    e => e
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(
    err.to_string(),
    "template not found: template \"missing\" does not exist",
  )
}

///|
test "loader: source_replace_static" {
  let env = @minijinja.Environment::new()
  env.add_template("a", "1")
  env.add_template("a", "2")
  let rv = env.get_template("a").render(@minijinja.Value::none())
  assert_eq(rv, "2")
}

///|
test "loader: source_replace_dynamic" {
  let env = @minijinja.Environment::new()
  env.add_template("a", "1")
  env.add_template("a", "2")
  env.set_loader(_ => None)
  let rv = env.get_template("a").render(@minijinja.Value::none())
  assert_eq(rv, "2")
}
