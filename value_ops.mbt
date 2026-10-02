///|
let i128_max : BigInt = (1N << 127) - 1N

///|
let i128_min : BigInt = -(1N << 127)

///|
let u128_max : BigInt = (1N << 128) - 1N

///|
let i64_max_big : BigInt = BigInt::from_int64(0x7FFFFFFFFFFFFFFFL)

///|
let i64_min_big : BigInt = BigInt::from_int64(-0x7FFFFFFFFFFFFFFFL - 1L)

///|
/// `i128::MIN` as a positive `u128` (`2^127`).
let min_i128_as_pos_u128 : BigInt = 1N << 127

///|
let max_repeated_len = 100_000_000

///|
fn in_i128(v : BigInt) -> Bool {
  v >= i128_min && v <= i128_max
}

///|
fn in_i64(v : BigInt) -> Bool {
  v >= i64_min_big && v <= i64_max_big
}

///|
/// Converts an integer (assumed to be in the i128 range) into a value,
/// using a 64 bit representation if possible.
fn int_as_value(v : BigInt) -> Value {
  if in_i64(v) {
    I64(v.to_int64())
  } else if in_i128(v) {
    I128(v)
  } else if v >= 0N && v <= u128_max {
    U128(v)
  } else {
    Invalid(TemplateError::new(InvalidOperation, "integer out of range"))
  }
}

///|
/// Wraps a u128 into the i128 range (Rust's `as i128` cast).
fn wrap_u128_to_i128(v : BigInt) -> BigInt {
  if v > i128_max {
    v - (1N << 128)
  } else {
    v
  }
}

///|
/// Port of Rust's saturating `f64 as i64` cast.
fn f64_to_i64_sat(v : Double) -> Int64 {
  if v.is_nan() {
    0L
  } else if v >= 9223372036854775807.0 {
    0x7FFFFFFFFFFFFFFFL
  } else if v <= -9223372036854775808.0 {
    -0x7FFFFFFFFFFFFFFFL - 1L
  } else {
    v.to_int64()
  }
}

///|
/// Port of Rust's saturating `f64 as u64` cast.
fn f64_to_u64_sat(v : Double) -> UInt64 {
  if v.is_nan() || v <= 0.0 {
    0UL
  } else if v >= 18446744073709551615.0 {
    0xFFFFFFFFFFFFFFFFUL
  } else {
    v.to_uint64()
  }
}

///|
/// Exactly converts the integral part of a finite double into a big
/// integer (truncating towards zero).
fn f64_trunc_to_bigint(v : Double) -> BigInt {
  if v.is_nan() || v.is_inf() {
    return 0N
  }
  let bits = v.reinterpret_as_int64()
  let negative = bits < 0L
  let exp = ((bits >> 52) & 0x7FFL).to_int()
  let mantissa = bits & 0xFFFFFFFFFFFFFL
  if exp == 0 {
    // subnormals are always < 1
    return 0N
  }
  let m = BigInt::from_int64(mantissa | (1L << 52))
  let shift = exp - 1075
  let rv = if shift >= 0 {
    m << shift
  } else if shift > -64 {
    m >> -shift
  } else {
    0N
  }
  if negative {
    -rv
  } else {
    rv
  }
}

///|
fn clamp_big(v : BigInt, lo : BigInt, hi : BigInt) -> BigInt {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
/// Converts a big integer to the nearest double.
fn bigint_to_f64(v : BigInt) -> Double {
  if in_i64(v) {
    return v.to_int64().to_double()
  }
  @string.parse_double(v.to_string()) catch {
    _ => if v > 0N { 1.0 / 0.0 } else { -1.0 / 0.0 }
  }
}

///|
/// Port of `i128::try_from(Value)`.
fn Value::to_i128(self : Value) -> BigInt? {
  match self {
    Bool(b) => Some(if b { 1N } else { 0N })
    I64(v) => Some(BigInt::from_int64(v))
    U64(v) => Some(BigInt::from_uint64(v))
    F64(v) => {
      let i = f64_to_i64_sat(v)
      if i.to_double() == v {
        Some(BigInt::from_int64(i))
      } else {
        None
      }
    }
    I128(v) => Some(v)
    U128(v) => if v <= i128_max { Some(v) } else { None }
    _ => None
  }
}

///|
/// Port of `u128::try_from(Value)`.
fn Value::to_u128(self : Value) -> BigInt? {
  match self {
    U128(v) => Some(v)
    _ =>
      match self.to_i128() {
        Some(v) if v >= 0N => Some(v)
        _ => None
      }
  }
}

///|
/// Returns the value as `Int64` if it is an integer (or an integral float)
/// that fits.
pub fn Value::as_i64(self : Value) -> Int64? {
  match self {
    I64(v) => Some(v)
    U64(v) =>
      if v <= 0x7FFFFFFFFFFFFFFFUL {
        Some(v.reinterpret_as_int64())
      } else {
        None
      }
    _ =>
      match self.to_i128() {
        Some(v) if in_i64(v) => Some(v.to_int64())
        _ => None
      }
  }
}

///|
/// Returns the value as a non-negative `Int` index if possible.
pub fn Value::as_usize(self : Value) -> Int? {
  match self.as_i64() {
    Some(v) if v >= 0L && v <= 0x7FFFFFFFL => Some(v.to_int())
    _ => None
  }
}

///|
/// Port of upstream's `as_usize` with Rust's 64 bit `usize`.
fn Value::as_usize64(self : Value) -> UInt64? {
  match self.to_i128() {
    Some(v) if v >= 0N && v <= max_u64_big => Some(v.to_uint64())
    _ => None
  }
}

///|
/// Returns the value as `Double` if it is a number (or a bool).
pub fn Value::as_f64(self : Value) -> Double? {
  as_f64(self, true)
}

///|
fn as_f64(value : Value, lossy : Bool) -> Double? {
  match value {
    Bool(b) => Some(if b { 1.0 } else { 0.0 })
    U64(x) => {
      let rv = x.to_double()
      if lossy || f64_to_u64_sat(rv) == x {
        Some(rv)
      } else {
        None
      }
    }
    I64(x) => {
      let rv = x.to_double()
      if lossy || f64_to_i64_sat(rv) == x {
        Some(rv)
      } else {
        None
      }
    }
    U128(x) => {
      let rv = bigint_to_f64(x)
      // Rust's `rv as u128` saturates
      if lossy || clamp_big(f64_trunc_to_bigint(rv), 0N, u128_max) == x {
        Some(rv)
      } else {
        None
      }
    }
    I128(x) => {
      let rv = bigint_to_f64(x)
      if lossy || clamp_big(f64_trunc_to_bigint(rv), i128_min, i128_max) == x {
        Some(rv)
      } else {
        None
      }
    }
    F64(x) => Some(x)
    _ => None
  }
}

///|
priv enum CoerceResult {
  Int(Int64, Int64)
  Big(BigInt, BigInt)
  F64(Double, Double)
  Str(String, String)
}

///|
fn big_pair(a : BigInt, b : BigInt) -> CoerceResult {
  if in_i64(a) && in_i64(b) {
    Int(a.to_int64(), b.to_int64())
  } else {
    Big(a, b)
  }
}

///|
fn coerce(a : Value, b : Value, lossy : Bool) -> CoerceResult? {
  match (a, b) {
    (I64(x), I64(y)) => Some(Int(x, y))
    (U64(x), U64(y)) =>
      Some(big_pair(BigInt::from_uint64(x), BigInt::from_uint64(y)))
    (U128(x), U128(y)) =>
      Some(big_pair(wrap_u128_to_i128(x), wrap_u128_to_i128(y)))
    (Str(x, _), Str(y, _)) => Some(Str(x, y))
    (I128(x), I128(y)) => Some(big_pair(x, y))
    (F64(x), F64(y)) => Some(F64(x, y))
    (F64(x), _) =>
      match as_f64(b, lossy) {
        Some(y) => Some(F64(x, y))
        None => None
      }
    (_, F64(y)) =>
      match as_f64(a, lossy) {
        Some(x) => Some(F64(x, y))
        None => None
      }
    _ =>
      match (a.to_i128(), b.to_i128()) {
        (Some(x), Some(y)) => Some(big_pair(x, y))
        _ => None
      }
  }
}

///|
fn impossible_op(op : String, lhs : Value, rhs : Value) -> TemplateError {
  TemplateError::new(
    InvalidOperation,
    "tried to use \{op} operator on unsupported types \{lhs.kind()} and \{rhs.kind()}",
  )
}

///|
fn failed_op(op : String, lhs : Value, rhs : Value) -> TemplateError {
  TemplateError::new(
    InvalidOperation,
    "unable to calculate \{lhs} \{op} \{rhs}",
  )
}

///|
/// Checks a big integer result against the i128 range.
fn checked_i128(v : BigInt) -> BigInt? {
  if in_i128(v) {
    Some(v)
  } else {
    None
  }
}

///|
fn checked_i64_add(a : Int64, b : Int64) -> Int64? {
  let r = a + b
  if ((a ^ r) & (b ^ r)) < 0L {
    None
  } else {
    Some(r)
  }
}

///|
fn checked_i64_sub(a : Int64, b : Int64) -> Int64? {
  let r = a - b
  if ((a ^ b) & (a ^ r)) < 0L {
    None
  } else {
    Some(r)
  }
}

///|
fn small_mul_safe(a : Int64) -> Bool {
  a <= 3037000499L && a >= -3037000499L
}

///|
fn int_binop(
  op : String,
  lhs : Value,
  rhs : Value,
  big_op : (BigInt, BigInt) -> BigInt?,
  fast : (Int64, Int64) -> Int64?,
) -> Value raise TemplateError {
  guard coerce(lhs, rhs, true) is Some(c) else {
    raise impossible_op(op, lhs, rhs)
  }
  match c {
    Int(a, b) =>
      match fast(a, b) {
        Some(r) => I64(r)
        None =>
          match big_op(BigInt::from_int64(a), BigInt::from_int64(b)) {
            Some(r) => int_as_value(r)
            None => raise failed_op(op, lhs, rhs)
          }
      }
    Big(a, b) =>
      match big_op(a, b) {
        Some(r) => int_as_value(r)
        None => raise failed_op(op, lhs, rhs)
      }
    F64(a, b) =>
      match op {
        "-" => F64(a - b)
        "*" => F64(a * b)
        _ => F64(a + b)
      }
    Str(_, _) => raise impossible_op(op, lhs, rhs)
  }
}

///|
/// Adds two values.
fn value_add(lhs : Value, rhs : Value) -> Value raise TemplateError {
  // fast path for the most common case
  if small_int(lhs) is Some(a) &&
    small_int(rhs) is Some(b) &&
    checked_i64_add(a, b) is Some(r) {
    return I64(r)
  }
  if lhs.is_tuple() || rhs.is_tuple() {
    if lhs.is_tuple() && rhs.is_tuple() {
      let values = lhs.try_iter().to_array()
      for v in rhs.try_iter() {
        values.push(v)
      }
      return Value::from_tuple(values)
    }
    raise impossible_op("+", lhs, rhs)
  }
  if lhs.kind() is (Seq | Iterable) && rhs.kind() is (Seq | Iterable) {
    let values = [lhs, rhs]
    let depth = merge_seq_depth_for_values(values)
    if depth > merge_seq_max_depth {
      match (lhs.len(), rhs.len()) {
        (Some(a), Some(b)) => {
          let rv = Array(capacity=a + b)
          for v in lhs.try_iter() {
            rv.push(v)
          }
          for v in rhs.try_iter() {
            rv.push(v)
          }
          return Value::from_array(rv)
        }
        _ => ()
      }
    }
    return make_merge_seq(values, Iterable)
  }
  match coerce(lhs, rhs, true) {
    Some(Str(a, b)) => Value::from_string(a + b)
    Some(_) =>
      int_binop("+", lhs, rhs, (a, b) => checked_i128(a + b), checked_i64_add)
    None => raise impossible_op("+", lhs, rhs)
  }
}

///|
fn value_sub(lhs : Value, rhs : Value) -> Value raise TemplateError {
  if small_int(lhs) is Some(a) &&
    small_int(rhs) is Some(b) &&
    checked_i64_sub(a, b) is Some(r) {
    return I64(r)
  }
  int_binop("-", lhs, rhs, (a, b) => checked_i128(a - b), checked_i64_sub)
}

///|
fn value_mul(lhs : Value, rhs : Value) -> Value raise TemplateError {
  if small_int(lhs) is Some(a) &&
    small_int(rhs) is Some(b) &&
    small_mul_safe(a) &&
    small_mul_safe(b) {
    return I64(a * b)
  }
  let str_and_n = match (lhs.as_str(), rhs.as_str()) {
    (Some(s), _) => Some((s, rhs))
    (_, Some(s)) => Some((s, lhs))
    _ => None
  }
  if str_and_n is Some((s, n)) {
    guard n.as_usize64() is Some(n) else {
      raise TemplateError::new(
        InvalidOperation,
        "strings can only be multiplied with integers",
      )
    }
    let byte_len = utf8_len(s)
    if byte_len == 0 || n == 0UL {
      return Value::from_string("")
    }
    if n > (max_repeated_len / byte_len).to_uint64() {
      raise TemplateError::new(InvalidOperation, "repeated string is too large")
    }
    return Value::from_string(s.repeat(n.to_int()))
  }
  // like upstream: the first object operand is picked before filtering, so
  // `map * seq` is an unsupported operation rather than a repetition
  let seq_and_n = match (lhs, rhs) {
    (Object(o), _) | (_, Object(o)) if !(o.repr() is (Iterable | Seq)) => None
    (Object(o), _) => Some((o, rhs))
    (_, Object(o)) => Some((o, lhs))
    _ => None
  }
  if seq_and_n is Some((seq, n)) {
    return repeat_iterable(n, seq)
  }
  int_binop("*", lhs, rhs, (a, b) => checked_i128(a * b), (a, b) => {
    if small_mul_safe(a) && small_mul_safe(b) {
      Some(a * b)
    } else {
      None
    }
  })
}

///|
fn repeat_iterable(n : Value, seq : DynObject) -> Value raise TemplateError {
  guard n.as_usize64() is Some(n) else {
    raise TemplateError::new(
      InvalidOperation,
      "sequences and iterables can only be multiplied with integers",
    )
  }
  guard seq.enumerator_len() is Some(len) else {
    raise TemplateError::new(
      InvalidOperation,
      "cannot repeat unsized iterables",
    )
  }
  let is_tuple = seq.inner is Tuple(_)
  if len == 0 || n == 0UL {
    return if is_tuple { Value::from_tuple([]) } else { Value::from_array([]) }
  }
  if n > (max_repeated_len / len).to_uint64() {
    raise TemplateError::new(InvalidOperation, "repeated sequence is too large")
  }
  let n = n.to_int()
  let repeated_len = len * n
  if seq.inner is Tuple(items) {
    let values = Array(capacity=repeated_len)
    for _ in 0..<n {
      for v in items {
        values.push(v)
      }
    }
    return Value::from_tuple(values)
  }
  Value::make_iterable(() => {
    let mut round = 0
    let mut current : Iter[Value]? = None
    Iter::new(
      () => {
        for ;; {
          match current {
            Some(it) =>
              match it.next() {
                Some(v) => break Some(v)
                None => current = None
              }
            None => {
              if round >= n {
                break None
              }
              round += 1
              current = match seq.try_iter() {
                Some(it) => Some(it)
                None =>
                  Some(
                    Iter::repeat(
                      Value::from_error(
                        TemplateError::new(
                          InvalidOperation,
                          "iterable did not iterate against expectations",
                        ),
                      ),
                    ).take(len),
                  )
              }
            }
          }
        }
      },
      size_hint=repeated_len,
    )
  })
}

///|
fn value_div(lhs : Value, rhs : Value) -> Value raise TemplateError {
  guard as_f64(lhs, true) is Some(a) else { raise impossible_op("/", lhs, rhs) }
  guard as_f64(rhs, true) is Some(b) else { raise impossible_op("/", lhs, rhs) }
  if b == 0.0 {
    raise failed_op("/", lhs, rhs)
  }
  F64(a / b)
}

///|
/// Floor division and remainder on big integers.
fn int_div_rem_floor(a : BigInt, b : BigInt) -> (BigInt, BigInt)? {
  // BigInt division truncates towards zero (like Rust's checked_div)
  let mut quotient = a / b
  let mut remainder = a % b
  if !in_i128(quotient) {
    return None
  }
  if !remainder.is_zero() && (remainder < 0N) != (b < 0N) {
    quotient = quotient - 1N
    remainder = remainder + b
    if !in_i128(quotient) || !in_i128(remainder) {
      return None
    }
  }
  Some((quotient, remainder))
}

///|
fn copysign(magnitude : Double, sign : Double) -> Double {
  let neg = sign.reinterpret_as_int64() < 0L
  let m = magnitude.abs()
  if neg {
    -m
  } else {
    m
  }
}

///|
fn float_div_rem_floor(a : Double, b : Double) -> (Double, Double) {
  let mut remainder = a % b
  let mut quotient = (a - remainder) / b
  if remainder != 0.0 {
    if (remainder < 0.0) != (b < 0.0) {
      remainder += b
      quotient -= 1.0
    }
  } else {
    remainder = copysign(0.0, b)
  }
  if quotient != 0.0 {
    let mut floored = quotient.floor()
    if quotient - floored > 0.5 {
      floored += 1.0
    }
    quotient = floored
  } else {
    quotient = copysign(0.0, a / b)
  }
  (quotient, remainder)
}

///|
fn value_rem(lhs : Value, rhs : Value) -> Value raise TemplateError {
  match coerce(lhs, rhs, true) {
    Some(Int(a, b)) if b != 0L =>
      if b == -1L {
        I64(0L)
      } else {
        let r = a % b
        if r != 0L && (r < 0L) != (b < 0L) {
          I64(r + b)
        } else {
          I64(r)
        }
      }
    Some(Big(a, b)) if !b.is_zero() =>
      if a == i128_min && b == -1N {
        I64(0L)
      } else {
        match int_div_rem_floor(a, b) {
          Some((_, r)) => int_as_value(r)
          None => raise failed_op("%", lhs, rhs)
        }
      }
    Some(F64(a, b)) if b != 0.0 => F64(float_div_rem_floor(a, b).1)
    Some(Int(_, _) | Big(_, _) | F64(_, _)) => raise failed_op("%", lhs, rhs)
    _ => raise impossible_op("%", lhs, rhs)
  }
}

///|
fn value_int_div(lhs : Value, rhs : Value) -> Value raise TemplateError {
  let big = match coerce(lhs, rhs, true) {
    Some(Int(a, b)) if b != 0L => {
      if a != -0x7FFFFFFFFFFFFFFFL - 1L || b != -1L {
        let q = a / b
        let r = a % b
        return if r != 0L && (r < 0L) != (b < 0L) {
          I64(q - 1L)
        } else {
          I64(q)
        }
      }
      Some((BigInt::from_int64(a), BigInt::from_int64(b)))
    }
    Some(Big(a, b)) if !b.is_zero() => Some((a, b))
    Some(F64(a, b)) if b != 0.0 => return F64(float_div_rem_floor(a, b).0)
    Some(Int(_, _) | Big(_, _) | F64(_, _)) => raise failed_op("//", lhs, rhs)
    _ => raise impossible_op("//", lhs, rhs)
  }
  guard big is Some((a, b)) else { abort("unreachable") }
  if a == i128_min && b == -1N {
    U128(min_i128_as_pos_u128)
  } else {
    match int_div_rem_floor(a, b) {
      Some((q, _)) => int_as_value(q)
      None => raise failed_op("//", lhs, rhs)
    }
  }
}

///|
fn checked_pow_i128(a : BigInt, b : BigInt) -> BigInt? {
  // the exponent must fit into a u32
  if b < 0N || b > BigInt::from_uint64(0xFFFFFFFFUL) {
    return None
  }
  if a.is_zero() {
    return Some(if b.is_zero() { 1N } else { 0N })
  }
  if a == 1N {
    return Some(1N)
  }
  if a == -1N {
    return Some(if (b % 2N).is_zero() { 1N } else { -1N })
  }
  // |a| >= 2, so anything beyond 2^127 overflows
  if b > 128N {
    return None
  }
  let mut rv = 1N
  let n = b.to_int()
  for _ in 0..<n {
    rv = rv * a
    if !in_i128(rv) {
      return None
    }
  }
  Some(rv)
}

///|
fn value_pow(lhs : Value, rhs : Value) -> Value raise TemplateError {
  match coerce(lhs, rhs, true) {
    Some(Int(a, b)) =>
      match checked_pow_i128(BigInt::from_int64(a), BigInt::from_int64(b)) {
        Some(v) => int_as_value(v)
        None => raise failed_op("**", lhs, rhs)
      }
    Some(Big(a, b)) =>
      match checked_pow_i128(a, b) {
        Some(v) => int_as_value(v)
        None => raise failed_op("**", lhs, rhs)
      }
    Some(F64(a, b)) => F64(@math.pow(a, b))
    _ => raise impossible_op("**", lhs, rhs)
  }
}

///|
fn value_neg(val : Value) -> Value raise TemplateError {
  if val.kind() != Number {
    raise TemplateError::from_kind(InvalidOperation)
  }
  match val {
    F64(x) => F64(-x)
    U128(x) if x == min_i128_as_pos_u128 => U128(min_i128_as_pos_u128)
    I64(x) if x != -0x7FFFFFFFFFFFFFFFL - 1L => I64(-x)
    _ =>
      match val.to_i128() {
        Some(x) =>
          match checked_i128(-x) {
            Some(v) => int_as_value(v)
            None => raise TemplateError::new(InvalidOperation, "overflow")
          }
        None => raise TemplateError::from_kind(InvalidOperation)
      }
  }
}

///|
fn string_concat(left : Value, right : Value) -> Value {
  Value::from_string(left.to_string() + right.to_string())
}

///|
/// Implements a containment operation on values.
fn value_contains(
  container : Value,
  value : Value,
) -> Value raise TemplateError {
  // Special case where if the container is undefined, it cannot hold
  // values.  For strict containment checks the vm has a special case.
  if container.is_undefined() {
    return Bool(false)
  }
  let rv = match container.as_str() {
    Some(s) =>
      match value.as_str() {
        Some(s2) => s.contains(s2)
        None => s.contains(value.to_string())
      }
    None =>
      match container {
        Object(obj) =>
          match obj.repr() {
            Plain => false
            Map => obj.get_value(value) is Some(_)
            Seq | Iterable =>
              match obj.try_iter() {
                Some(iter) => iter.any(v => v == value)
                None => false
              }
          }
        _ =>
          raise TemplateError::new(
            InvalidOperation,
            "cannot perform a containment check on this value",
          )
      }
  }
  Bool(rv)
}

///|
fn get_offset_and_len(
  start : Int64?,
  stop : Int64?,
  end : () -> Int,
) -> (Int, Int) {
  let start_v = start.unwrap_or(0L)
  let stop_neg = match stop {
    None => true
    Some(x) => x < 0L
  }
  if start_v < 0L || stop_neg {
    let end = end().to_int64()
    let start = if start_v < 0L {
      let r = end + start_v
      if r < 0L {
        0L
      } else {
        r
      }
    } else {
      start_v
    }
    let stop = match stop {
      None => end
      Some(x) if x < 0L => {
        let r = end + x
        if r < 0L {
          0L
        } else {
          r
        }
      }
      Some(x) => x
    }
    let len = if stop > start { stop - start } else { 0L }
    (clamp_int(start), clamp_int(len))
  } else {
    let stop_v = stop.unwrap()
    let len = if stop_v > start_v { stop_v - start_v } else { 0L }
    (clamp_int(start_v), clamp_int(len))
  }
}

///|
fn clamp_int(v : Int64) -> Int {
  if v > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else if v < -0x80000000L {
    -0x80000000
  } else {
    v.to_int()
  }
}

///|
/// Ceiling division for non-negative numbers without overflow.
fn ceil_div64(a : Int64, b : Int64) -> Int64 {
  a / b + (if a % b != 0L { 1L } else { 0L })
}

///|
/// Port of `range_step_backwards`: the indexes visited by a negative step.
/// `step` is the (positive) magnitude of the step.
fn range_step_backwards(
  start : Int64?,
  stop : Int64?,
  step : Int64,
  end : Int,
) -> Array[Int] {
  // Upstream yields index 0 for empty sequences here and panics with an
  // out of bounds access (`[][::-1]`); an empty slice is the sane result.
  if end == 0 {
    return []
  }
  let end64 = end.to_int64()
  let last = if end64 > 0L { end64 - 1L } else { 0L }
  let start = match start {
    None => last
    Some(s) if s >= end64 => last
    Some(s) if s >= 0L => s
    Some(s) => {
      let r = end64 + s
      if r < 0L {
        0L
      } else {
        r
      }
    }
  }
  let stop = match stop {
    None => 0L
    Some(s) if s < 0L => {
      let r = end64 + s
      if r < 0L {
        0L
      } else {
        r
      }
    }
    Some(s) => s
  }
  let rv = []
  if stop > start {
    return rv
  }
  let length = if stop == 0L {
    start / step + 1L
  } else {
    ceil_div64(start - stop, step)
  }
  let mut i = start
  while i >= stop && rv.length().to_int64() < length {
    rv.push(i.to_int())
    if i < step {
      break
    }
    i -= step
  }
  rv
}

///|
fn[T] slice_array(
  items : Array[T],
  start : Int64?,
  stop : Int64?,
  step : Int64,
) -> Array[T] {
  if step > 0L {
    let (s, len) = get_offset_and_len(start, stop, () => items.length())
    let rv = []
    let n = items.length().to_int64()
    let s64 = s.to_int64()
    let end = if len.to_int64() > n - s64 { n } else { s64 + len.to_int64() }
    let mut i = s64
    while i < end {
      rv.push(items[i.to_int()])
      if step > end - i {
        break
      }
      i += step
    }
    rv
  } else {
    // `-step` would overflow for the minimum value
    let magnitude = if step == -0x7FFFFFFFFFFFFFFFL - 1L {
      0x7FFFFFFFFFFFFFFFL
    } else {
      -step
    }
    range_step_backwards(start, stop, magnitude, items.length()).map(i => {
      items[i]
    })
  }
}

///|
/// Slices a value.
fn value_slice(
  value : Value,
  start : Value,
  stop : Value,
  step : Value,
) -> Value raise TemplateError {
  let start = if start.is_none() {
    None
  } else {
    match start.as_i64() {
      Some(v) => Some(v)
      None => raise unsupported_conversion(start.kind(), "i64")
    }
  }
  let stop = if stop.is_none() {
    None
  } else {
    match stop.as_i64() {
      Some(v) => Some(v)
      None => raise unsupported_conversion(stop.kind(), "i64")
    }
  }
  let step = if step.is_none() {
    1L
  } else {
    match step.as_i64() {
      Some(v) => v
      None => raise unsupported_conversion(step.kind(), "i64")
    }
  }
  if step == 0L {
    raise TemplateError::new(InvalidOperation, "cannot slice by step size of 0")
  }
  let kind = value.kind()
  match value {
    Str(s, _) => {
      let chars = s.iter().to_array()
      Value::from_string(
        String::from_array(slice_array(chars, start, stop, step)),
      )
    }
    Bytes(b) => {
      let bytes = b.to_array()
      Value::from_bytes(
        Bytes::from_array(slice_array(bytes, start, stop, step)),
      )
    }
    Undefined(_) | NoneValue => Value::from_array([])
    Object(obj) if obj.repr() is (Seq | Iterable) => {
      if value.is_tuple() {
        let values = match obj.try_iter() {
          Some(iter) => iter.to_array()
          None => []
        }
        return Value::from_tuple(slice_array(values, start, stop, step))
      }
      if step > 0L {
        let total = obj.enumerator_len()
        let (s, len) = get_offset_and_len(start, stop, () => total.unwrap_or(0))
        let step = step.to_int()
        // like Rust's `skip(s).take(len).step_by(step)` the size is known if
        // the length of the underlying object is known.
        let size_hint = match total {
          Some(n) => {
            let avail = if n - s < 0 {
              0
            } else if n - s < len {
              n - s
            } else {
              len
            }
            Some((avail + step - 1) / step)
          }
          None => None
        }
        Value::make_iterable(() => {
          match obj.try_iter() {
            Some(iter) => {
              let mut skipped = false
              let mut remaining = len
              Iter::new(
                () => {
                  if !skipped {
                    skipped = true
                    for _ in 0..<s {
                      if iter.next() is None {
                        remaining = 0
                        break
                      }
                    }
                  }
                  if remaining <= 0 {
                    return None
                  }
                  let rv = iter.next()
                  if rv is None {
                    remaining = 0
                    return None
                  }
                  remaining -= 1
                  // skip step - 1 items
                  for _ in 1..<step {
                    if remaining <= 0 {
                      break
                    }
                    if iter.next() is None {
                      remaining = 0
                      break
                    }
                    remaining -= 1
                  }
                  rv
                },
                size_hint?,
              )
            }
            None => Iter::empty()
          }
        })
      } else {
        Value::make_iterable(() => {
          match obj.try_iter() {
            Some(iter) => {
              let vec = iter.to_array()
              let magnitude = if step == -0x7FFFFFFFFFFFFFFFL - 1L {
                0x7FFFFFFFFFFFFFFFL
              } else {
                -step
              }
              range_step_backwards(start, stop, magnitude, vec.length())
              .map(i => vec[i])
              .iter()
            }
            None => Iter::empty()
          }
        })
      }
    }
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "value of type \{kind} cannot be sliced",
      )
  }
}

///|
fn unsupported_conversion(kind : ValueKind, target : String) -> TemplateError {
  TemplateError::new(InvalidOperation, "cannot convert \{kind} to \{target}")
}

///|
/// Number of bytes the string takes up as UTF-8.
fn utf8_len(s : String) -> Int {
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    n += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// Returns the value as `Int64` if it is a (signed or unsigned) 64 bit
/// integer that fits.  Used by arithmetic fast paths.
fn small_int(v : Value) -> Int64? {
  match v {
    I64(a) => Some(a)
    U64(a) if a <= 0x7FFFFFFFFFFFFFFFUL => Some(a.reinterpret_as_int64())
    _ => None
  }
}
