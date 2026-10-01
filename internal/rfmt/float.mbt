///|
/// Splits a finite, non-zero double into its shortest round-trip decimal
/// digits and the position of the decimal point relative to those digits.
///
/// The value equals `0.d1d2d3... * 10^point`, i.e. `point` digits are in
/// front of the decimal point.
fn decompose(x : Double) -> (String, Int) {
  let s = x.abs().to_string()
  let (mantissa, exp) = match s.find("e") {
    Some(idx) => {
      let exp_str = s.view(start_offset=idx + 1)
      let exp = @string.parse_int(exp_str) catch { _ => 0 }
      (s.view(end_offset=idx), exp)
    }
    None => (s[:], 0)
  }
  let digits = StringBuilder()
  let mut int_len = 0
  let mut seen_dot = false
  for c in mantissa {
    if c == '.' {
      seen_dot = true
    } else {
      digits.write_char(c)
      if !seen_dot {
        int_len += 1
      }
    }
  }
  // strip leading zeros
  let d = digits.to_string()
  let mut lead = 0
  while lead < d.length() && d[lead] == '0' {
    lead += 1
  }
  let mut trail = d.length()
  while trail > lead && d[trail - 1] == '0' {
    trail -= 1
  }
  let core = d.view(start_offset=lead, end_offset=trail).to_owned()
  (core, int_len - lead + exp)
}

///|
fn zeros(n : Int) -> String {
  let sb = StringBuilder()
  for _ in 0..<n {
    sb.write_char('0')
  }
  sb.to_string()
}

///|
fn layout_plain(digits : String, point : Int) -> String {
  let len = digits.length()
  if point <= 0 {
    "0." + zeros(-point) + digits
  } else if point >= len {
    digits + zeros(point - len)
  } else {
    digits.view(end_offset=point).to_owned() +
    "." +
    digits.view(start_offset=point).to_owned()
  }
}

///|
fn is_negative(x : Double) -> Bool {
  x.reinterpret_as_int64() < 0L
}

///|
/// Formats a double like Rust's `Display` implementation for `f64`.
///
/// Rust never uses exponent notation for `Display`; `1e100` is printed with
/// all of its zeros and integral values have no fractional part (`50`).
pub fn f64_display(x : Double) -> String {
  if x.is_nan() {
    return "NaN"
  }
  if x.is_inf() {
    return if x > 0.0 { "inf" } else { "-inf" }
  }
  let sign = if is_negative(x) { "-" } else { "" }
  if x == 0.0 {
    return sign + "0"
  }
  let (digits, point) = decompose(x)
  sign + layout_plain(digits, point)
}

///|
/// Formats a double like Rust's `Debug` implementation for `f64`.
///
/// Values with a magnitude of at least `1e16` or smaller than `1e-4` use
/// exponent notation (`1e16`, `1.5e-7`), everything else uses the plain
/// notation with at least one fractional digit (`50.0`).
pub fn f64_debug(x : Double) -> String {
  if x.is_nan() {
    return "NaN"
  }
  if x.is_inf() {
    return if x > 0.0 { "inf" } else { "-inf" }
  }
  let sign = if is_negative(x) { "-" } else { "" }
  if x == 0.0 {
    return sign + "0.0"
  }
  let (digits, point) = decompose(x)
  let abs = x.abs()
  if abs < 1.0e-4 || abs >= 1.0e16 {
    let rest = digits.view(start_offset=1).to_owned()
    let mantissa = digits.view(end_offset=1).to_owned() +
      (if rest.is_empty() { "" } else { "." + rest })
    sign + mantissa + "e" + (point - 1).to_string()
  } else {
    let plain = layout_plain(digits, point)
    sign + (if plain.contains(".") { plain } else { plain + ".0" })
  }
}
