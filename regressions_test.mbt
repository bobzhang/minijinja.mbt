// Ported from minijinja/tests/test_regressions.rs.

///|
fn rg_render(src : String) -> String raise {
  @minijinja.Environment::new().render_str(
    src,
    @minijinja.Value::from_pairs([]),
  )
}

///|
fn rg_is_err(
  env : @minijinja.Environment,
  src : String,
  ctx : @minijinja.Value,
) -> Bool {
  try env.render_str(src, ctx) catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "constant_logical_operators_preserve_operands" {
  assert_eq(rg_render("{{ 7 and 0 }}"), "0")
  assert_eq(rg_render("{{ 0 and 7 }}"), "0")
  assert_eq(rg_render("{{ 0 or 7 }}"), "7")
  assert_eq(rg_render("{{ 7 or 0 }}"), "7")
}

///|
test "repeated_sequence_size_limit" {
  let err = try rg_render("{{ [0] * 2**30 }}") catch {
    e => e.to_string()
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(err.contains("repeated sequence is too large"))
}

///|
test "upper_and_lower_reject_non_strings" {
  assert_eq(
    rg_render(
      "{{ missing is upper }}|{{ 1 is upper }}|{{ missing is lower }}|{{ 1 is lower }}",
    ),
    "False|False|False|False",
  )
  assert_eq(
    rg_render(
      "{{ 'FOO 1' is upper }}|{{ 'foo 1' is lower }}|{{ '' is upper }}|{{ 'Aǅ' is upper }}|{{ 'aǅ' is lower }}",
    ),
    "True|True|False|False|False",
  )
}

///|
test "undefined_is_a_sequence" {
  assert_eq(
    rg_render("{{ missing is iterable }}|{{ missing is sequence }}"),
    "True|True",
  )
}

///|
test "booleans_are_numbers" {
  assert_eq(
    rg_render(
      "{{ true is number }}|{{ [true, 1]|select('number')|list }}|{{ [true, true]|sum }}",
    ),
    "True|[True, 1]|2",
  )
}

///|
test "division_by_zero_errors" {
  let env = @minijinja.Environment::new()
  for source in ["{{ 1 / 0 }}", "{{ -1 / 0 }}", "{{ 0 / 0 }}"] {
    assert_true(
      rg_is_err(env, source, @minijinja.Value::from_pairs([])),
      msg=source,
    )
  }
}

///|
test "round_uses_bankers_rounding" {
  let env = @minijinja.Environment::new()
  assert_eq(
    rg_render("{{ 2.5|round }}|{{ 2.675|round(2) }}|{{ -2.5|round }}"),
    "2.0|2.67|-2.0",
  )
  assert_eq(
    rg_render(
      "{{ 250.0|round(-2) }}|{{ 350.0|round(-2) }}|{{ 9.5e22|round(-22) }}",
    ),
    "200.0|400.0|90000000000000000000000.0",
  )
  let inf = 1.0 / 0.0
  assert_eq(
    env.render_str(
      "{{ positive|round(-309) }}|{{ negative|round(-309) }}",
      @minijinja.Value::from_pairs([
        ("positive", @minijinja.Value::from_double(inf)),
        ("negative", @minijinja.Value::from_double(-inf)),
      ]),
    ),
    "inf|-inf",
  )
  assert_true(
    rg_is_err(
      env,
      "{{ value|round(-308) }}",
      @minijinja.Value::from_pairs([
        ("value", @minijinja.Value::from_double(1.7e308)),
      ]),
    ),
  )
}
