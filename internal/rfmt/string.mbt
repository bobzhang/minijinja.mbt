///|
fn write_hex_escape(sb : StringBuilder, code : Int) -> Unit {
  sb.write_string("\\u{")
  sb.write_string(code.to_string(radix=16))
  sb.write_char('}')
}

///|
/// Returns `true` if Rust's `char::escape_debug` would print the character
/// verbatim.  This is an approximation of Rust's `is_printable` table which
/// covers control characters, separators and other common non-printables.
pub fn is_printable(c : Char) -> Bool {
  let code = c.to_int()
  if code < 0x20 || (code >= 0x7f && code < 0xa0) {
    return false
  }
  match code {
    0xad | 0x34f | 0x61c | 0x115f | 0x1160 | 0x17b4 | 0x17b5 | 0x180e => false
    0x200b..=0x200f | 0x2028..=0x202e | 0x2060..=0x206f => false
    0xfeff | 0xfff9..=0xfffb | 0xfffe | 0xffff => false
    0xd800..=0xdfff => false
    0xe000..=0xf8ff => false
    0xf0000..=0x10ffff => false
    _ => true
  }
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
      c =>
        if is_printable(c) {
          sb.write_char(c)
        } else {
          write_hex_escape(sb, c.to_int())
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
