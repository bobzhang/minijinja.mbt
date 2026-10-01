///|
async test "parser snapshots" {
  run_snapshot_suite(
    "parser",
    "testdata/parser-inputs",
    "test_parser__parser@",
    (name, contents) => {
      let f = @rfmt.Formatter::new(alternate=true)
      let result = capture(() => {
        parse(
          contents,
          name,
          SyntaxConfig::default(),
          WhitespaceConfig::default(),
        )
      })
      match result {
        Ok(ast) => f.debug_tuple("Ok").field(f => ast.fmt_debug(f)).finish()
        Err(err) => f.debug_tuple("Err").field(f => err.fmt_debug(f)).finish()
      }
      f.to_string()
    },
  )
}
