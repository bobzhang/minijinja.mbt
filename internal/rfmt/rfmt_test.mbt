///|
test "f64 display" {
  inspect(@rfmt.f64_display(50.0), content="50")
  inspect(@rfmt.f64_display(0.5), content="0.5")
  inspect(@rfmt.f64_display(-2.25), content="-2.25")
  inspect(
    @rfmt.f64_display(1.0e100),
    content="10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  )
  inspect(@rfmt.f64_display(1.0e-7), content="0.0000001")
  inspect(@rfmt.f64_display(0.1 + 0.2), content="0.30000000000000004")
  inspect(@rfmt.f64_display(-0.0), content="-0")
  inspect(@rfmt.f64_display(1.0 / 0.0), content="inf")
  inspect(@rfmt.f64_display(-1.0 / 0.0), content="-inf")
  inspect(@rfmt.f64_display(0.0 / 0.0), content="NaN")
}

///|
test "f64 debug" {
  inspect(@rfmt.f64_debug(50.0), content="50.0")
  inspect(@rfmt.f64_debug(0.11), content="0.11")
  inspect(@rfmt.f64_debug(1.0e15), content="1000000000000000.0")
  inspect(@rfmt.f64_debug(1.0e16), content="1e16")
  inspect(@rfmt.f64_debug(1.5e300), content="1.5e300")
  inspect(@rfmt.f64_debug(0.0001), content="0.0001")
  inspect(@rfmt.f64_debug(0.00001), content="1e-5")
  inspect(@rfmt.f64_debug(-1.25e-7), content="-1.25e-7")
  inspect(@rfmt.f64_debug(0.0), content="0.0")
  inspect(@rfmt.f64_debug(5.0e-324), content="5e-324")
}

///|
test "str debug" {
  inspect(@rfmt.str_debug("a\"b\\c\n\t'"), content="\"a\\\"b\\\\c\\n\\t'\"")
  inspect(@rfmt.str_debug("\u{1}é"), content="\"\\u{1}é\"")
}

///|
test "pretty debug builders" {
  fn render(alternate : Bool) -> String {
    let f = @rfmt.Formatter::new(alternate~)
    f
    .debug_struct("Error")
    .field("kind", f => f.write_str("SyntaxError"))
    .field("list", f => {
      f
      .debug_list()
      .entry(f => f.write_str("1"))
      .entry(f => {
        f
        .debug_map()
        .entry(f => f.write_str("a"), f => f.write_str("b"))
        .finish()
      })
      .finish()
    })
    .field("empty", f => f.debug_list().finish())
    .field("tuple", f => {
      f.debug_tuple("Some").field(f => f.write_str("1")).finish()
    })
    .finish()
    f.to_string()
  }

  inspect(
    render(false),
    content="Error { kind: SyntaxError, list: [1, {a: b}], empty: [], tuple: Some(1) }",
  )
  inspect(
    render(true),
    content=(
      #|Error {
      #|    kind: SyntaxError,
      #|    list: [
      #|        1,
      #|        {
      #|            a: b,
      #|        },
      #|    ],
      #|    empty: [],
      #|    tuple: Some(
      #|        1,
      #|    ),
      #|}
    ),
  )
}
