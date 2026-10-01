// Debug helpers mirroring the parts of upstream's `unstable_machinery`
// feature (`tokenize`, `parse`, `get_compiled_template`) that the CLI uses
// for `--dump`.  The output formats follow Rust's `Debug` formatting and
// are not considered stable API.

///|
/// Tokenizes `source` with the default syntax and returns the `Debug`
/// representation of every token (eg: `TemplateData("Hello ")`).
///
/// This mirrors upstream's `machinery::tokenize` and is meant for debugging
/// tools such as the CLI's `--dump=tokens`.
pub fn debug_tokens(
  source : String,
  trim_blocks? : Bool = false,
  lstrip_blocks? : Bool = false,
) -> Array[String] raise TemplateError {
  let ws = { keep_trailing_newline: false, lstrip_blocks, trim_blocks, }
  tokenize(source, false, SyntaxConfig::default(), ws).map(item => {
    item.0.debug_string()
  })
}

///|
/// Parses `source` with the default syntax and returns the pretty `Debug`
/// representation (`{:#?}`) of the AST.
///
/// This mirrors upstream's `machinery::parse` and is meant for debugging
/// tools such as the CLI's `--dump=ast`.
pub fn debug_ast(source : String, name : String) -> String raise TemplateError {
  let ast = parse(
    source,
    name,
    SyntaxConfig::default(),
    WhitespaceConfig::default(),
  )
  let f = @rfmt.Formatter::new(alternate=true)
  ast.fmt_debug(f)
  f.to_string()
}

///|
/// Returns the `Debug` representation of the compiled instructions of the
/// template: one entry per block (sorted by block name) followed by the
/// root instructions under the name `<root>`.
///
/// This mirrors upstream's `machinery::get_compiled_template` and is meant
/// for debugging tools such as the CLI's `--dump=instructions`.
pub fn Template::debug_instructions(
  self : Template,
) -> Array[(String, Array[String])] {
  let blocks = self.compiled.blocks.keys().to_array()
  blocks.sort_by((a, b) => compare_str(a, b))
  let rv = []
  for name in blocks {
    let instrs = self.compiled.blocks[name].instructions
    rv.push((name, instrs.map(i => i.debug_string())))
  }
  rv.push(
    (
      "<root>",
      self.compiled.instructions.instructions.map(i => i.debug_string()),
    ),
  )
  rv
}
