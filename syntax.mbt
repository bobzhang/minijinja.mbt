///|
/// The delimiter configuration for the environment and the parser.
///
/// MiniJinja allows you to override the syntax configuration for templates by
/// setting different delimiters.  The end markers can be shared, but the
/// start markers need to be distinct.  It would thus not be valid to
/// configure `{{` to be the marker for both variables and blocks.
pub struct SyntaxConfig {
  priv block_start : String
  priv block_end : String
  priv variable_start : String
  priv variable_end : String
  priv comment_start : String
  priv comment_end : String
  priv line_statement_prefix : String
  priv line_comment_prefix : String
  priv is_default : Bool
}

///|
/// Returns the default syntax configuration (`{% %}`, `{{ }}`, `{# #}`).
pub fn SyntaxConfig::default() -> SyntaxConfig {
  {
    block_start: "{%",
    block_end: "%}",
    variable_start: "{{",
    variable_end: "}}",
    comment_start: "{#",
    comment_end: "#}",
    line_statement_prefix: "",
    line_comment_prefix: "",
    is_default: true,
  }
}

///|
/// Creates a new syntax configuration with custom delimiters.
///
/// Delimiters are given as `(start, end)` pairs.  Line statement and line
/// comment prefixes are disabled unless given.  Raises `InvalidDelimiter` if
/// the start delimiters are not distinct.
pub fn SyntaxConfig::new(
  block_delimiters? : (String, String) = ("{%", "%}"),
  variable_delimiters? : (String, String) = ("{{", "}}"),
  comment_delimiters? : (String, String) = ("{#", "#}"),
  line_statement_prefix? : String = "",
  line_comment_prefix? : String = "",
) -> SyntaxConfig raise TemplateError {
  let (block_start, block_end) = block_delimiters
  let (variable_start, variable_end) = variable_delimiters
  let (comment_start, comment_end) = comment_delimiters
  let is_default = block_start == "{%" &&
    block_end == "%}" &&
    variable_start == "{{" &&
    variable_end == "}}" &&
    comment_start == "{#" &&
    comment_end == "#}" &&
    line_statement_prefix == "" &&
    line_comment_prefix == ""
  let rv = {
    block_start,
    block_end,
    variable_start,
    variable_end,
    comment_start,
    comment_end,
    line_statement_prefix,
    line_comment_prefix,
    is_default,
  }
  if !is_default {
    rv.validated_start_delims() |> ignore
  }
  rv
}

///|
fn SyntaxConfig::validated_start_delims(
  self : SyntaxConfig,
) -> Array[String] raise TemplateError {
  let delims = []
  for
    pair in [
      (self.variable_start, true),
      (self.block_start, true),
      (self.comment_start, true),
      (self.line_statement_prefix, false),
      (self.line_comment_prefix, false),
    ] {
    let (delim, required) = pair
    if delim.is_empty() {
      if required {
        raise TemplateError::from_kind(InvalidDelimiter)
      }
    } else if delims.contains(delim) {
      raise TemplateError::from_kind(InvalidDelimiter)
    } else {
      delims.push(delim)
    }
  }
  delims
}

///|
/// Returns the block delimiters.
pub fn SyntaxConfig::block_delimiters(self : SyntaxConfig) -> (String, String) {
  (self.block_start, self.block_end)
}

///|
/// Returns the variable delimiters.
pub fn SyntaxConfig::variable_delimiters(
  self : SyntaxConfig,
) -> (String, String) {
  (self.variable_start, self.variable_end)
}

///|
/// Returns the comment delimiters.
pub fn SyntaxConfig::comment_delimiters(
  self : SyntaxConfig,
) -> (String, String) {
  (self.comment_start, self.comment_end)
}

///|
/// Returns the line statement prefix if set.
pub fn SyntaxConfig::line_statement_prefix(self : SyntaxConfig) -> String? {
  if self.line_statement_prefix.is_empty() {
    None
  } else {
    Some(self.line_statement_prefix)
  }
}

///|
/// Returns the line comment prefix if set.
pub fn SyntaxConfig::line_comment_prefix(self : SyntaxConfig) -> String? {
  if self.line_comment_prefix.is_empty() {
    None
  } else {
    Some(self.line_comment_prefix)
  }
}

///|
/// Internal config struct to control whitespace in the engine.
struct WhitespaceConfig {
  keep_trailing_newline : Bool
  lstrip_blocks : Bool
  trim_blocks : Bool
} derive(Default)
