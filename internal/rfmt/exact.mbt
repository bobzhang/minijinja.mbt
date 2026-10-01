///|
/// Returns the exact decimal expansion of a finite, non-negative double as
/// `(digits, point)` where the value equals `0.d1d2d3... * 10^point`.
/// Leading zeros are stripped; `digits` is empty for zero.
pub fn exact_decimal(x : Double) -> (String, Int) {
  let bits = x.abs().reinterpret_as_int64()
  let exp = ((bits >> 52) & 0x7FFL).to_int()
  let frac = bits & 0xFFFFFFFFFFFFFL
  let (mantissa, e) = if exp == 0 {
    (frac, -1074)
  } else {
    (frac | (1L << 52), exp - 1075)
  }
  if mantissa == 0L {
    return ("", 0)
  }
  let m = BigInt::from_int64(mantissa)
  // value = m * 2^e
  let (int_digits, frac_len) = if e >= 0 {
    ((m << e).to_string(), 0)
  } else {
    // m / 2^k = m * 5^k / 10^k
    let k = -e
    ((m * BigInt::from_int(5).pow(BigInt::from_int(k))).to_string(), k)
  }
  // int_digits represents the value * 10^frac_len
  let mut lead = 0
  while lead < int_digits.length() && int_digits[lead] == '0' {
    lead += 1
  }
  let mut trail = int_digits.length()
  while trail > lead && int_digits[trail - 1] == '0' {
    trail -= 1
  }
  let digits = int_digits.view(start_offset=lead, end_offset=trail).to_owned()
  let point = int_digits.length() - lead - frac_len
  (digits, point)
}

///|
/// Rounds a digit string (with decimal point position `point`) so that
/// `keep` digits remain, using round-half-to-even.  Returns the new digits
/// and point (the digit string may grow by one on carry).
pub fn round_digits(digits : String, point : Int, keep : Int) -> (String, Int) {
  if keep >= digits.length() {
    return (digits, point)
  }
  if keep < 0 {
    return ("", point)
  }
  let retained = digits.view(end_offset=keep).iter().to_array()
  let first_dropped = digits[keep]
  let rest_nonzero = {
    let mut nz = false
    for i in (keep + 1)..<digits.length() {
      if digits[i] != '0' {
        nz = true
        break
      }
    }
    nz
  }
  let last_retained = if keep > 0 {
    digits[keep - 1].to_int() - '0'.to_int()
  } else {
    0
  }
  let round_up = first_dropped > '5' ||
    (first_dropped == '5' && (rest_nonzero || last_retained % 2 != 0))
  let mut point = point
  if round_up {
    let mut i = retained.length() - 1
    let mut carry = true
    while i >= 0 && carry {
      if retained[i] == '9' {
        retained[i] = '0'
        i -= 1
      } else {
        retained[i] = (retained[i].to_int() + 1).unsafe_to_char()
        carry = false
      }
    }
    if carry {
      // 99.9 -> 100: the digit string keeps its length (the dropped last
      // digit is always a zero) and the decimal point moves.
      retained.insert(0, '1')
      retained.truncate(keep)
      point += 1
    }
  }
  (String::from_array(retained), point)
}

///|
/// Formats a double with a fixed number of fractional digits like Rust's
/// `format!("{:.prec$}", x)` (exact, round-half-to-even).
pub fn format_fixed(x : Double, prec : Int) -> String {
  if x.is_nan() {
    return "NaN"
  }
  if x.is_inf() {
    return if x > 0.0 { "inf" } else { "-inf" }
  }
  let neg = x.reinterpret_as_int64() < 0L
  let (digits, point) = exact_decimal(x)
  let (digits, point) = if digits.is_empty() {
    ("", 0)
  } else {
    round_digits(digits, point, point + prec)
  }
  // all digits are zero after rounding
  let int_part = if point <= 0 {
    "0"
  } else if digits.length() >= point {
    digits.view(end_offset=point).to_owned()
  } else {
    digits + "0".repeat(point - digits.length())
  }
  let frac = StringBuilder()
  for i in 0..<prec {
    let pos = point + i
    if pos >= 0 && pos < digits.length() {
      frac.write_char(digits[pos].to_int().unsafe_to_char())
    } else {
      frac.write_char('0')
    }
  }
  let sign = if neg { "-" } else { "" }
  if prec > 0 {
    sign + int_part + "." + frac.to_string()
  } else {
    sign + int_part
  }
}

///|
/// Formats a double in exponent notation with `prec` fractional digits like
/// Rust's `format!("{:.prec$e}", x)`.  Returns the mantissa digits (with a
/// decimal point when `prec > 0`) and the decimal exponent.
pub fn format_exp_parts(x : Double, prec : Int) -> (String, Int) {
  let (digits, point) = exact_decimal(x)
  if digits.is_empty() {
    let mantissa = if prec > 0 { "0." + "0".repeat(prec) } else { "0" }
    return (mantissa, 0)
  }
  let (digits, point) = round_digits(digits, point, prec + 1)
  let padded = digits + "0".repeat(prec + 1 - digits.length())
  let mantissa = if prec > 0 {
    padded.view(end_offset=1).to_owned() +
    "." +
    padded.view(start_offset=1, end_offset=prec + 1).to_owned()
  } else {
    padded.view(end_offset=1).to_owned()
  }
  (mantissa, point - 1)
}
