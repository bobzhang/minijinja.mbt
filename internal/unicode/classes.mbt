///|
/// Port of Rust's `char::is_alphabetic` (the derived `Alphabetic` property).
pub fn is_alphabetic(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_alphabetic()
  } else {
    in_ranges(alphabetic_table, cp)
  }
}

///|
/// Port of Rust's `char::is_numeric` (general categories `Nd`, `Nl` and
/// `No`).
pub fn is_numeric(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_digit()
  } else {
    in_ranges(numeric_table, cp)
  }
}

///|
/// Port of Rust's `char::is_alphanumeric`.
pub fn is_alphanumeric(c : Char) -> Bool {
  is_alphabetic(c) || is_numeric(c)
}

///|
/// Port of Rust's `char::is_whitespace` (the `White_Space` property).
pub fn is_whitespace(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    cp == 0x20 || (cp >= 0x09 && cp <= 0x0d)
  } else {
    in_ranges(white_space_table, cp)
  }
}

///|
/// Returns `true` for characters of the general category `L` (`Lu`, `Ll`,
/// `Lt`, `Lm` and `Lo`), like `unicode_categories`' `is_letter`.
pub fn is_letter(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_alphabetic()
  } else {
    in_ranges(letter_table, cp)
  }
}

///|
/// Port of Rust's `str::trim` (strips `White_Space` on both ends).
pub fn trim(s : StringView) -> StringView {
  trim_end(trim_start(s))
}

///|
/// Port of Rust's `str::trim_start`.
pub fn trim_start(s : StringView) -> StringView {
  let mut view = s
  while view is [c, .. rest] && is_whitespace(c) {
    view = rest
  }
  view
}

///|
/// Port of Rust's `str::trim_end`.
pub fn trim_end(s : StringView) -> StringView {
  let mut view = s
  while view is [.. rest, c] && is_whitespace(c) {
    view = rest
  }
  view
}

///|
/// Port of `char::is_grapheme_extended` (the Grapheme_Extend property).
pub fn is_grapheme_extended(c : Char) -> Bool {
  let cp = c.to_int()
  cp >= 0x300 && in_ranges(grapheme_extend_table, cp)
}

///|
/// Port of `core::unicode::printable::is_printable`: everything except
/// control, format, surrogate, private use, unassigned and separator
/// characters (the space excepted) prints verbatim in `escape_debug`.
pub fn is_printable(c : Char) -> Bool {
  let cp = c.to_int()
  if cp >= 0x20 && cp < 0x7f {
    true
  } else {
    in_ranges(printable_table, cp)
  }
}
