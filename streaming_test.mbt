///|
test "render_to streams output" {
  let env = @minijinja.Environment::new()
  env.add_template(
    "t", "{% for x in [1, 2, 3] %}{{ x }}{% endfor %}{% block b %}[{{ 42 }}]{% endblock %}",
  )
  let chunks : Array[String] = []
  let state = env
    .get_template("t")
    .render_to(@minijinja.Value::none(), s => chunks.push(s.to_owned()))
  inspect(chunks.join(""), content="123[42]")
  assert_true(chunks.length() > 1)
  let block = StringBuilder()
  state.render_block_to("b", s => block.write_view(s))
  inspect(block.to_string(), content="[42]")
}

///|
test "render_to write failure" {
  let env = @minijinja.Environment::new()
  env.add_template("t", "hello")
  let tmpl = env.get_template("t")
  try tmpl.render_to(@minijinja.Value::none(), _ => fail("disk full")) catch {
    err => assert_true(err.kind() == WriteFailure)
  } noraise {
    _ => fail("expected an error")
  }
}
