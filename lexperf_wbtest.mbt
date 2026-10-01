///|
test "bench: lexer shapes" (b : @bench.T) {
  let text = "x".repeat(1000)
  let tags = "{{ a }}".repeat(140)
  b.bench(name="lex_text", () => {
    b.keep(
      tokenize(
        text,
        false,
        SyntaxConfig::default(),
        WhitespaceConfig::default(),
      ) catch {
        _ => abort("x")
      },
    )
  })
  b.bench(name="lex_tags", () => {
    b.keep(
      tokenize(
        tags,
        false,
        SyntaxConfig::default(),
        WhitespaceConfig::default(),
      ) catch {
        _ => abort("x")
      },
    )
  })
}
