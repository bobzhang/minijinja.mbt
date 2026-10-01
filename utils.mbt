///|
/// Controls the autoescaping behavior.
pub(all) enum AutoEscape {
  /// Do not apply auto escaping.
  NoEscape
  /// Use HTML auto escaping rules.
  Html
  /// Use escaping rules suitable for JSON/JavaScript or YAML.
  Json
  /// A custom auto escape format.  The default formatter fails for it.
  Custom(String)
} derive(Eq)

///|
fn AutoEscape::debug_name(self : AutoEscape) -> String {
  match self {
    NoEscape => "None"
    Html => "Html"
    Json => "Json"
    Custom(name) => "Custom(\{@rfmt.str_debug(name)})"
  }
}

///|
/// Defines the behavior of undefined values in the engine.
pub(all) enum UndefinedBehavior {
  /// The default, somewhat lenient undefined behavior.
  ///
  /// * **printing:** allowed (returns empty string)
  /// * **iteration:** allowed (returns empty array)
  /// * **attribute access of undefined values:** fails
  /// * **if true:** allowed (is considered false)
  Lenient
  /// Like `Lenient`, but also allows chaining of undefined lookups.
  Chainable
  /// Like strict, but does not error when the undefined is checked for
  /// truthiness.
  SemiStrict
  /// Complains very quickly about undefined values.
  Strict
} derive(Eq)

///|
fn UndefinedBehavior::handle_undefined(
  self : UndefinedBehavior,
  parent_was_undefined : Bool,
) -> Value raise TemplateError {
  match (self, parent_was_undefined) {
    (Lenient, false) | (Strict, false) | (SemiStrict, false) | (Chainable, _) =>
      Value::undefined()
    (Lenient, true) | (Strict, true) | (SemiStrict, true) =>
      raise TemplateError::from_kind(UndefinedError)
  }
}

///|
fn UndefinedBehavior::is_true(
  self : UndefinedBehavior,
  value : Value,
) -> Bool raise TemplateError {
  match (self, value) {
    // silent undefined doesn't error, even in strict mode
    (Strict, Undefined(Default)) =>
      raise TemplateError::from_kind(UndefinedError)
    _ => value.is_true()
  }
}

///|
fn UndefinedBehavior::try_iter(
  self : UndefinedBehavior,
  value : Value,
) -> Iter[Value] raise TemplateError {
  self.assert_iterable(value)
  value.try_iter()
}

///|
fn UndefinedBehavior::assert_iterable(
  self : UndefinedBehavior,
  value : Value,
) -> Unit raise TemplateError {
  match (self, value) {
    (Strict | SemiStrict, Undefined(Default)) =>
      raise TemplateError::from_kind(UndefinedError)
    _ => ()
  }
}

///|
fn UndefinedBehavior::assert_value_not_undefined(
  self : UndefinedBehavior,
  value : Value,
) -> Unit raise TemplateError {
  match (self, value) {
    (Strict | SemiStrict, Undefined(Default)) =>
      raise TemplateError::from_kind(UndefinedError)
    _ => ()
  }
}

///|
fn needs_html_escaping(s : String) -> Bool {
  for i in 0..<s.length() {
    match s[i] {
      '<' | '>' | '&' | '"' | '\'' | '/' => return true
      _ => ()
    }
  }
  false
}

///|
/// HTML escapes a string (`<`, `>`, `&`, `"`, `'` and `/`).
pub fn html_escape(s : String) -> String {
  if !needs_html_escaping(s) {
    return s
  }
  let sb = StringBuilder()
  write_html_escaped(sb, s)
  sb.to_string()
}

///|
fn write_html_escaped(sb : StringBuilder, s : String) -> Unit {
  let mut start = 0
  for i in 0..<s.length() {
    let rep = match s[i] {
      '<' => "&lt;"
      '>' => "&gt;"
      '&' => "&amp;"
      '"' => "&quot;"
      '\'' => "&#x27;"
      '/' => "&#x2f;"
      _ => continue
    }
    if start < i {
      sb.write_view(s.view(start_offset=start, end_offset=i))
    }
    sb.write_string(rep)
    start = i + 1
  }
  if start < s.length() {
    sb.write_view(s.view(start_offset=start))
  }
}

///|
fn is_ascii_integer_str(s : String) -> Bool {
  if s.is_empty() {
    return false
  }
  let start = if s[0] == '-' { 1 } else { 0 }
  if start == s.length() {
    return false
  }
  for i in start..<s.length() {
    if !(s[i] >= '0' && s[i] <= '9') {
      return false
    }
  }
  true
}

///|
fn write_with_html_escaping(out : Output, value : Value) -> Unit {
  match value {
    U64(v) => return out.write_str(v.to_string())
    I64(v) => return out.write_str(v.to_string())
    Bool(v) => return out.write_str(if v { "True" } else { "False" })
    _ => ()
  }
  match value.as_str() {
    Some(s) =>
      if is_ascii_integer_str(s) || !needs_html_escaping(s) {
        out.write_str(s)
      } else {
        out.write_str(html_escape(s))
      }
    None =>
      if value.kind() is (Undefined | Null | Bool | Number) {
        out.write_str(value.to_string())
      } else {
        out.write_str(html_escape(value.to_string()))
      }
  }
}

///|
/// Writes a value to the output with the given auto escaping applied.
fn write_escaped(
  out : Output,
  auto_escape : AutoEscape,
  value : Value,
) -> Unit raise TemplateError {
  // safe strings bypass all of this
  if value is Str(s, Safe) {
    return out.write_str(s)
  }
  match auto_escape {
    NoEscape => out.write_str(value.to_string())
    Html => write_with_html_escaping(out, value)
    Json => out.write_str(value_to_json_string(value, false))
    Custom(name) =>
      raise TemplateError::new(
        InvalidOperation,
        "Default formatter does not know how to format to custom format '\{name}'",
      )
  }
}
