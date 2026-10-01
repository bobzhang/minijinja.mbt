///|
fn in_ranges(table : FixedArray[Int], cp : Int) -> Bool {
  // table is a flat list of inclusive [start, end] pairs sorted by start
  let n = table.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < table[mid * 2] {
      continue lo, mid
    } else if cp > table[mid * 2 + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn lookup_single(table : FixedArray[Int], cp : Int) -> Int? {
  let n = table.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    let key = table[mid * 2]
    if cp < key {
      continue lo, mid
    } else if cp > key {
      continue mid + 1, hi
    } else {
      break Some(table[mid * 2 + 1])
    }
  } nobreak {
    None
  }
}

///|
fn lookup_multi(keys : FixedArray[Int], cp : Int) -> Int? {
  for lo = 0, hi = keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < keys[mid] {
      continue lo, mid
    } else if cp > keys[mid] {
      continue mid + 1, hi
    } else {
      break Some(mid)
    }
  } nobreak {
    None
  }
}

///|
/// Port of `unicode_ident::is_xid_start`.
pub fn is_xid_start(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_alphabetic()
  } else {
    in_ranges(xid_start_table, cp)
  }
}

///|
/// Port of `unicode_ident::is_xid_continue`.
pub fn is_xid_continue(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
  } else {
    in_ranges(xid_continue_table, cp)
  }
}

///|
/// Port of Rust's `char::is_uppercase`.
pub fn is_uppercase(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_uppercase()
  } else {
    in_ranges(uppercase_table, cp)
  }
}

///|
/// Port of Rust's `char::is_lowercase`.
pub fn is_lowercase(c : Char) -> Bool {
  let cp = c.to_int()
  if cp < 0x80 {
    c.is_ascii_lowercase()
  } else {
    in_ranges(lowercase_table, cp)
  }
}

///|
fn write_mapped(
  sb : StringBuilder,
  c : Char,
  single : FixedArray[Int],
  multi_keys : FixedArray[Int],
  multi_values : FixedArray[String],
) -> Unit {
  let cp = c.to_int()
  match lookup_single(single, cp) {
    Some(m) => sb.write_char(m.unsafe_to_char())
    None =>
      match lookup_multi(multi_keys, cp) {
        Some(idx) => sb.write_string(multi_values[idx])
        None => sb.write_char(c)
      }
  }
}

///|
/// Port of Rust's `char::to_uppercase` (may produce multiple characters).
pub fn char_to_upper(c : Char) -> String {
  let sb = StringBuilder()
  write_mapped(sb, c, upper_single, upper_multi_keys, upper_multi_values)
  sb.to_string()
}

///|
/// Port of Rust's `char::to_lowercase` (may produce multiple characters).
pub fn char_to_lower(c : Char) -> String {
  let sb = StringBuilder()
  write_mapped(sb, c, lower_single, lower_multi_keys, lower_multi_values)
  sb.to_string()
}

///|
/// Port of Rust's `str::to_uppercase`.
pub fn to_upper(s : StringView) -> String {
  let sb = StringBuilder()
  for c in s {
    write_mapped(sb, c, upper_single, upper_multi_keys, upper_multi_values)
  }
  sb.to_string()
}

///|
fn is_case_ignorable(c : Char) -> Bool {
  // a pragmatic approximation of the Case_Ignorable property
  match c {
    '\'' | '.' | ':' | '^' | '`' | '\u{ad}' | '\u{b7}' | '\u{2019}' => true
    _ => {
      let cp = c.to_int()
      (cp >= 0x300 && cp <= 0x36f) || (cp >= 0x2b0 && cp <= 0x2ff)
    }
  }
}

///|
fn is_cased(c : Char) -> Bool {
  is_uppercase(c) || is_lowercase(c)
}

///|
/// Port of Rust's `str::to_lowercase`, including the final sigma rule.
pub fn to_lower(s : StringView) -> String {
  let chars = s.iter().to_array()
  let sb = StringBuilder()
  for i, c in chars {
    if c == 'Σ' {
      // Final_Sigma: preceded by a cased letter and not followed by one
      // (ignoring case-ignorable characters in between).
      let preceded = for j = i - 1; j >= 0; j = j - 1 {
        if is_case_ignorable(chars[j]) {
          continue
        }
        break is_cased(chars[j])
      } nobreak {
        false
      }
      let followed = for j = i + 1; j < chars.length(); j = j + 1 {
        if is_case_ignorable(chars[j]) {
          continue
        }
        break is_cased(chars[j])
      } nobreak {
        false
      }
      sb.write_char(if preceded && !followed { 'ς' } else { 'σ' })
    } else {
      write_mapped(sb, c, lower_single, lower_multi_keys, lower_multi_values)
    }
  }
  sb.to_string()
}

///|
/// Full Unicode case folding (as used by `unicase` comparisons).
pub fn case_fold(s : StringView) -> String {
  let sb = StringBuilder()
  for c in s {
    write_mapped(sb, c, fold_single, fold_multi_keys, fold_multi_values)
  }
  sb.to_string()
}
