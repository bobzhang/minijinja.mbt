///|
test "include consumes candidates lazily" {
  let env = @minijinja.Environment::new()
  env.add_template("a", "A")
  env.add_template("main", "{% include names %}{{ names|list }}")
  let names = @minijinja.Value::make_one_shot_iterator(
    [@minijinja.Value::from_string("a"), @minijinja.Value::from_string("b")].iter(),
  )
  let ctx = @minijinja.Value::from_pairs([("names", names)])
  inspect(env.get_template("main").render(ctx), content="A['b']")
}
