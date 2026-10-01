///|
/// Returns `true` if `s` contains `pat` at UTF-16 offset `off`.
fn starts_with_at(s : String, off : Int, pat : String) -> Bool {
  let plen = pat.length()
  if off < 0 || off + plen > s.length() {
    return false
  }
  for i in 0..<plen {
    if s[off + i] != pat[i] {
      return false
    }
  }
  true
}

///|
/// Finds `needle` in `haystack` starting at `off`.  Returns the offset
/// relative to `off` (like `memstr` on a sub slice).
fn find_from(haystack : String, off : Int, needle : String) -> Int? {
  let nlen = haystack.length()
  let plen = needle.length()
  if plen == 0 {
    return Some(0)
  }
  let mut i = off
  while i + plen <= nlen {
    if starts_with_at(haystack, i, needle) {
      return Some(i - off)
    }
    i += 1
  }
  None
}

///|
/// Returns the code unit at `idx` or `-1` when out of bounds.
fn unit_at(s : String, idx : Int) -> Int {
  if idx >= 0 && idx < s.length() {
    s[idx].to_int()
  } else {
    -1
  }
}

///|
/// Decodes the character starting at UTF-16 offset `idx`.
fn char_at(s : String, idx : Int) -> Char? {
  if idx < 0 || idx >= s.length() {
    return None
  }
  let c1 = s[idx].to_int()
  if c1 >= 0xD800 && c1 <= 0xDBFF && idx + 1 < s.length() {
    let c2 = s[idx + 1].to_int()
    if c2 >= 0xDC00 && c2 <= 0xDFFF {
      let cp = 0x10000 + ((c1 - 0xD800) << 10) + (c2 - 0xDC00)
      return Some(cp.unsafe_to_char())
    }
  }
  Some(c1.unsafe_to_char())
}

///|
/// Port of Rust's `char::is_whitespace` (Unicode `White_Space`).
fn is_rust_whitespace(c : Char) -> Bool {
  match c.to_int() {
    0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680 => true
    0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 => true
    _ => false
  }
}

///|
/// Port of Rust's `u8::is_ascii_whitespace` applied to a code unit.
fn is_ascii_ws_unit(u : Int) -> Bool {
  u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0C || u == 0x0D
}

///|
/// Port of Rust's `str::trim_end`.
fn trim_end_view(s : StringView) -> StringView {
  let mut end = s.length()
  while end > 0 {
    let u = s[end - 1].to_int()
    if u >= 0xDC00 && u <= 0xDFFF {
      // surrogate pairs are never whitespace
      break
    }
    if is_rust_whitespace(u.unsafe_to_char()) {
      end -= 1
    } else {
      break
    }
  }
  s.view(end_offset=end)
}

///|
/// Port of Rust's `str::trim_start`.
fn trim_start_view(s : StringView) -> StringView {
  let mut start = 0
  let len = s.length()
  while start < len {
    let u = s[start].to_int()
    if u >= 0xD800 && u <= 0xDFFF {
      break
    }
    if is_rust_whitespace(u.unsafe_to_char()) {
      start += 1
    } else {
      break
    }
  }
  s.view(start_offset=start)
}

///|
/// Port of Rust's `str::trim`.
fn trim_view(s : StringView) -> StringView {
  trim_start_view(trim_end_view(s))
}

///|
/// Number of Unicode scalars in a string.
fn scalar_count(s : StringView) -> Int {
  s.char_length()
}

///|
priv struct Unescaper {
  out : StringBuilder
  mut pending_surrogate : Int
}

///|
fn Unescaper::push_char(self : Unescaper, c : Char) -> Unit raise TemplateError {
  if self.pending_surrogate != 0 {
    raise TemplateError::from_kind(BadEscape)
  }
  self.out.write_char(c)
}

///|
fn Unescaper::push_u16(self : Unescaper, c : Int) -> Unit raise TemplateError {
  let is_surrogate = c >= 0xD800 && c <= 0xDFFF
  if self.pending_surrogate == 0 && !is_surrogate {
    self.out.write_char(c.unsafe_to_char())
  } else if !is_surrogate {
    raise TemplateError::from_kind(BadEscape)
  } else if self.pending_surrogate == 0 {
    self.pending_surrogate = c
  } else {
    let prev = self.pending_surrogate
    if prev >= 0xD800 && prev <= 0xDBFF && c >= 0xDC00 && c <= 0xDFFF {
      let cp = 0x10000 + ((prev - 0xD800) << 10) + (c - 0xDC00)
      self.out.write_char(cp.unsafe_to_char())
      self.pending_surrogate = 0
    } else {
      raise TemplateError::from_kind(BadEscape)
    }
  }
}

///|
fn hex_value(c : Char) -> Int {
  match c {
    '0'..='9' => c.to_int() - '0'.to_int()
    'a'..='f' => c.to_int() - 'a'.to_int() + 10
    'A'..='F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// Unescapes a string literal from a template.
fn unescape(s : StringView) -> String raise TemplateError {
  let u = { out: StringBuilder(), pending_surrogate: 0, }
  let chars = s.iter().to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    i += 1
    if c != '\\' {
      u.push_char(c)
      continue
    }
    if i >= n {
      raise TemplateError::from_kind(BadEscape)
    }
    let d = chars[i]
    i += 1
    match d {
      '"' | '\\' | '/' | '\'' => u.push_char(d)
      'b' => u.push_char('\u{08}')
      'f' => u.push_char('\u{0C}')
      'n' => u.push_char('\n')
      'r' => u.push_char('\r')
      't' => u.push_char('\t')
      'u' => {
        // exactly four hex digits (missing ones are treated as invalid)
        let mut val = 0
        for _ in 0..<4 {
          let h = if i < n { hex_value(chars[i]) } else { -1 }
          if h < 0 {
            raise TemplateError::from_kind(BadEscape)
          }
          val = val * 16 + h
          i += 1
        }
        u.push_u16(val)
      }
      'x' => {
        if i + 2 > n {
          raise TemplateError::from_kind(BadEscape)
        }
        let h1 = hex_value(chars[i])
        let h2 = hex_value(chars[i + 1])
        i += 2
        if h1 < 0 || h2 < 0 {
          raise TemplateError::from_kind(BadEscape)
        }
        u.push_char((h1 * 16 + h2).unsafe_to_char())
      }
      '0'..='7' => {
        let mut val = d.to_int() - '0'.to_int()
        let mut count = 0
        while count < 2 && i < n && chars[i] >= '0' && chars[i] <= '7' {
          val = val * 8 + (chars[i].to_int() - '0'.to_int())
          i += 1
          count += 1
        }
        if val > 255 {
          raise TemplateError::from_kind(BadEscape)
        }
        u.push_char(val.unsafe_to_char())
      }
      _ => {
        u.push_char('\\')
        u.push_char(d)
      }
    }
  }
  if u.pending_surrogate != 0 {
    raise TemplateError::from_kind(BadEscape)
  }
  u.out.to_string()
}
