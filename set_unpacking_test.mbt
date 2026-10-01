// Ported from minijinja/tests/test_set_unpacking.rs.

///|
test "set_unpacking: set_single_var" {
  let env = @minijinja.Environment::new()
  let result = env.render_str(
    "{%- set x = 42 -%}x={{ x }}",
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(result, "x=42")
}

///|
test "set_unpacking: set_tuple_parens" {
  let env = @minijinja.Environment::new()
  let result = env.render_str(
    "{%- set (a, b) = (1, 2) -%}a={{ a }}, b={{ b }}",
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(result, "a=1, b=2")
}

///|
test "set_unpacking: set_unpacked_no_parens" {
  let env = @minijinja.Environment::new()
  let result = env.render_str(
    (
      #|{%- set a, b, c, d = '', '', true, "default" -%}values: a={{ a }}, b={{ b }}, c={{ c }}, d={{ d }}
    ),
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(result, "values: a=, b=, c=True, d=default")
}
