// Additional tests for the random functions (not ported from upstream).

///|
test "unseeded random functions" {
  // without RAND_SEED the generator is seeded from an entropy source
  for _ in 0..<20 {
    let n = render("{{ randrange(5, 10) }}")
    assert_true(["5", "6", "7", "8", "9"].contains(n))
    let v = render("{{ ['a', 'b']|random }}")
    assert_true(v == "a" || v == "b")
  }
  // different renders produce different sequences (with overwhelming
  // probability)
  let a = render("{{ lipsum(1) }}")
  let b = render("{{ lipsum(1) }}")
  assert_true(a != b)
}

///|
test "seeded random functions" {
  // the seed is per render and advances within a render
  let a = render("{% set RAND_SEED = 7 %}{{ randrange(1000) }}")
  let b = render("{% set RAND_SEED = 7 %}{{ randrange(1000) }}")
  assert_eq(a, b)
  let c = render(
    "{% set RAND_SEED = 7 %}{{ randrange(1000) }}|{{ randrange(1000) }}",
  )
  assert_true(c.has_prefix(a + "|"))
  // RAND_SEED can also be passed in the context
  assert_eq(
    render("{{ randrange(10) }}|{{ randrange(10) }}", ctx=[
      ("RAND_SEED", @minijinja.Value::from_int(42)),
    ]),
    "0|6",
  )
  // lipsum keyword arguments
  assert_eq(
    render("{% set RAND_SEED = 42 %}{{ lipsum(n=1, min=3, max=4) }}"),
    "Nulla curae morbi.\n\n",
  )
  assert_true(render("{{ lipsum(1, html=true) }}").has_prefix("<p>"))
}

///|
test "random errors" {
  assert_eq(
    render_err("{{ 42|random }}"),
    "invalid operation: can only select random elements from sequences (in <string>:1)",
  )
  assert_eq(render("{{ []|random }}"), "")
}
