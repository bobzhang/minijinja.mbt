// Ported from minijinja/tests/test_tuples.rs.

///|
fn tt_render(source : String) -> String raise {
  @minijinja.Environment::new().render_str(
    source,
    @minijinja.Value::from_pairs([]),
  )
}

///|
test "tuples: tuple_literals" {
  let env = @minijinja.Environment::new()
  let empty = @minijinja.Value::from_pairs([])
  assert_eq(env.render_str("{{ () }}", empty), "()")
  assert_eq(env.render_str("{{ (1,) }}", empty), "(1,)")
  assert_eq(env.render_str("{{ (1, 2) }}", empty), "(1, 2)")
  assert_eq(
    env.render_str(
      "{{ (value, value + 1) }}",
      @minijinja.Value::from_pairs([("value", @minijinja.Value::from_int(1))]),
    ),
    "(1, 2)",
  )
  assert_eq(
    env.render_str("{% set value = 1, 2 %}{{ value }}", empty),
    "(1, 2)",
  )
}

///|
test "tuples: python_compatible_collection_rendering" {
  // Escaped (not a `#|` raw string) so the Jinja-level `\u0027` escapes are
  // preserved verbatim.
  let source = "{{ [none, true, false, \"plain\", \"has\\u0027quote\", \"has\\\"quote\", \"both\\u0027\\\"quotes\", \"\\x13\"] }}"
  assert_eq(
    tt_render(source),
    (
      #|[None, True, False, 'plain', "has'quote", 'has"quote', 'both\'"quotes', '\x13']
    ),
  )
  assert_eq(
    tt_render(
      (
        #|{{ ("bar", "baz") }}
      ),
    ),
    "('bar', 'baz')",
  )
  assert_eq(
    tt_render(
      (
        #|{{ {"key": "value"} }}
      ),
    ),
    "{'key': 'value'}",
  )
}

///|
test "tuples: tuple_sequence_behavior" {
  let env = @minijinja.Environment::new()
  assert_eq(
    env.render_str(
      "{{ value.0 }}|{{ value[-1] }}|{% for item in value %}{{ item }}{% endfor %}",
      @minijinja.Value::from_pairs([
        (
          "value",
          @minijinja.Value::from_tuple([
            @minijinja.Value::from_int(1),
            @minijinja.Value::from_int(2),
          ]),
        ),
      ]),
    ),
    "1|2|12",
  )
  assert_eq(tt_render("{{ (1, 2) == [1, 2] }}"), "False")
  assert_eq(tt_render("{{ (1, 2)|list }}"), "[1, 2]")
}

///|
test "tuples: tuple_operations_preserve_type" {
  assert_eq(tt_render("{{ (1, 2) + (3,) }}"), "(1, 2, 3)")
  assert_eq(tt_render("{{ (1, 2) * 2 }}"), "(1, 2, 1, 2)")
  assert_eq(tt_render("{{ (1, 2, 3)[1:] }}"), "(2, 3)")
  assert_eq(tt_render("{{ (1, 2, 3)[::-1] }}"), "(3, 2, 1)")
  let failed = try tt_render("{{ [1, 2] + (3,) }}") catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(failed)
}

///|
/// The Rust `Tuple` type maps to `Value::from_tuple`; the `Deref`/`into_vec`
/// checks and the serde round trip have no MoonBit equivalent and are
/// dropped.
test "tuples: rust_and_serde_tuples" {
  for len in 0..<5 {
    let values = Array::makei(len, i => @minijinja.Value::from_int(i))
    let value = @minijinja.Value::from_tuple(values)
    assert_eq(value.len(), Some(len))
    assert_eq(value.try_iter().to_array(), values)
  }
  let explicit = @minijinja.Value::from_tuple([
    @minijinja.Value::from_int(1),
    @minijinja.Value::from_int(2),
  ])
  assert_true(explicit.is_tuple())
  assert_eq(explicit.kind(), @minijinja.ValueKind::Seq)
  assert_eq(explicit.to_string(), "(1, 2)")
  assert_not_eq(
    explicit,
    @minijinja.Value::from_array([
      @minijinja.Value::from_int(1),
      @minijinja.Value::from_int(2),
    ]),
  )
  // `Value::from((1, 2))` is the same as an explicit tuple.
  let converted = @minijinja.Value::from_tuple([
    @minijinja.Value::from_int(1),
    @minijinja.Value::from_int(2),
  ])
  assert_true(converted.is_tuple())
  assert_eq(converted, explicit)
}

///|
/// Collecting an iterator of Rust tuples maps to an array of
/// `Value::from_tuple` items.
test "tuples: collecting_tuples_and_pairs" {
  let sequence = @minijinja.Value::from_array(
    [("key", 42)].map(pair => {
      @minijinja.Value::from_tuple([
        @minijinja.Value::from_string(pair.0),
        @minijinja.Value::from_int(pair.1),
      ])
    }),
  )
  assert_eq(sequence.to_string(), "[('key', 42)]")
  let map = @minijinja.Value::from_pairs([
    ("key", @minijinja.Value::from_int(42)),
  ])
  assert_eq(map.to_string(), "{'key': 42}")
}
