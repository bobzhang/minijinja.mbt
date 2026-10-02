///|
fn write_hex_escape(sb : StringBuilder, code : Int) -> Unit {
  sb.write_string("\\u{")
  sb.write_string(code.to_string(radix=16))
  sb.write_char('}')
}

///|
/// Writes a string escaped like Rust's `<str as Debug>::fmt`, including the
/// surrounding double quotes.
pub fn write_str_debug(sb : StringBuilder, s : StringView) -> Unit {
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\u{0}' => sb.write_string("\\0")
      // like `escape_debug_ext` with `escape_grapheme_extended: true`
      c =>
        if @unicode.is_grapheme_extended(c) || !@unicode.is_printable(c) {
          write_hex_escape(sb, c.to_int())
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
}

///|
/// Returns a string escaped like Rust's `format!("{:?}", s)`.
pub fn str_debug(s : StringView) -> String {
  let sb = StringBuilder()
  write_str_debug(sb, s)
  sb.to_string()
}
