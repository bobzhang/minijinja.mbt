///|
/// Compares two strings by Unicode scalar values (like Rust's `str::cmp`
/// which compares UTF-8 bytes).
fn compare_str(a : String, b : String) -> Int {
  let la = a.length()
  let lb = b.length()
  let n = if la < lb { la } else { lb }
  for i in 0..<n {
    let x = a[i].to_int()
    let y = b[i].to_int()
    if x != y {
      // surrogates (U+D800..DFFF) encode code points above U+FFFF which
      // sort after all other BMP characters in UTF-8 order.
      let xs = x >= 0xD800 && x <= 0xDFFF
      let ys = y >= 0xD800 && y <= 0xDFFF
      if xs && !ys {
        return if y >= 0xE000 { 1 } else { 1 }
      }
      if ys && !xs {
        return -1
      }
      return if x < y { -1 } else { 1 }
    }
  }
  if la < lb {
    -1
  } else if la > lb {
    1
  } else {
    0
  }
}

///|
fn compare_int64(a : Int64, b : Int64) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn compare_big(a : BigInt, b : BigInt) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn f64_total_cmp(left : Double, right : Double) -> Int {
  let mut l = left.reinterpret_as_int64()
  let mut r = right.reinterpret_as_int64()
  l = l ^ ((l >> 63).reinterpret_as_uint64() >> 1).reinterpret_as_int64()
  r = r ^ ((r >> 63).reinterpret_as_uint64() >> 1).reinterpret_as_int64()
  compare_int64(l, r)
}

///|
fn cmp_f64(left : Double, right : Double) -> Int {
  if left == right {
    0
  } else {
    f64_total_cmp(left, right)
  }
}

///|
fn cmp_f64_big(left : Double, right : BigInt, upper : BigInt?) -> Int {
  match cmp_f64(left, bigint_to_f64(right)) {
    0 if !left.is_nan() && !left.is_inf() => {
      let trunc = f64_trunc_to_bigint(left)
      match upper {
        Some(max) if trunc > max => 1
        _ => {
          let c = compare_big(trunc, right)
          if c != 0 {
            c
          } else {
            let t = left.trunc()
            if left < t {
              -1
            } else if left > t {
              1
            } else {
              0
            }
          }
        }
      }
    }
    rv => rv
  }
}

///|
/// Compares numbers that `coerce` could not bring into a common lossless
/// representation.
fn cmp_uncoercible_numbers(left : Value, right : Value) -> Int {
  fn num(v : Value) -> (Double?, BigInt?) {
    match v {
      F64(x) => (Some(x), None)
      U64(x) => (None, Some(BigInt::from_uint64(x)))
      I64(x) => (None, Some(BigInt::from_int64(x)))
      U128(x) | I128(x) => (None, Some(x))
      _ => (None, None)
    }
  }

  match (num(left), num(right)) {
    ((Some(a), _), (Some(b), _)) => cmp_f64(a, b)
    ((Some(a), _), (_, Some(b))) => cmp_f64_big(a, b, Some(u128_max))
    ((_, Some(a)), (Some(b), _)) => -cmp_f64_big(b, a, Some(u128_max))
    ((_, Some(a)), (_, Some(b))) => compare_big(a, b)
    _ => 0
  }
}

///|
pub impl Eq for Value with fn equal(self, other) {
  match (self, other) {
    (NoneValue, NoneValue) => true
    (Undefined(_), Undefined(_)) => true
    (Str(a, _), Str(b, _)) => a == b
    (Bytes(a), Bytes(b)) => a == b
    _ =>
      match coerce(self, other, false) {
        Some(F64(a, b)) => a == b
        Some(Int(a, b)) => a == b
        Some(Big(a, b)) => a == b
        Some(Str(a, b)) => a == b
        None =>
          match (self, other) {
            (Object(a), Object(b)) => objects_equal(self, a, other, b)
            _ => false
          }
      }
  }
}

///|
fn objects_equal(av : Value, a : DynObject, bv : Value, b : DynObject) -> Bool {
  if av.is_tuple() != bv.is_tuple() {
    return false
  }
  if a.is_same_object(b) {
    return true
  }
  match (a.repr(), b.repr()) {
    (Map, Map) => {
      let mut need_length_fallback = true
      match (a.enumerator_len(), b.enumerator_len()) {
        (Some(a_len), Some(b_len)) => {
          if a_len != b_len {
            return false
          }
          need_length_fallback = false
        }
        _ => ()
      }
      let mut a_count = 0
      match a.try_iter_pairs() {
        Some(iter) =>
          for pair in iter {
            a_count += 1
            match b.get_value(pair.0) {
              Some(v) if v == pair.1 => ()
              _ => return false
            }
          }
        None => return false
      }
      if !need_length_fallback {
        true
      } else {
        a_count ==
        (match b.try_iter() {
          Some(it) => it.count()
          None => 0
        })
      }
    }
    (Seq | Iterable, Seq | Iterable) =>
      match (a.try_iter(), b.try_iter()) {
        (Some(ai), Some(bi)) =>
          for ;; {
            match (ai.next(), bi.next()) {
              (None, None) => break true
              (Some(x), Some(y)) => if x != y { break false }
              _ => break false
            }
          }
        _ => false
      }
    (Plain, Plain) => av.to_string() == bv.to_string()
    _ => false
  }
}

///|
/// Compares two values like MiniJinja's `Ord` implementation.
pub fn Value::cmp(self : Value, other : Value) -> Int {
  let kind_ordering = self.kind().compare(other.kind())
  if kind_ordering != 0 {
    return if kind_ordering < 0 { -1 } else { 1 }
  }
  match (self, other) {
    (NoneValue, NoneValue) => 0
    (Undefined(_), Undefined(_)) => 0
    (Str(a, _), Str(b, _)) => compare_str(a, b)
    (Bytes(a), Bytes(b)) => {
      let la = a.length()
      let lb = b.length()
      let n = if la < lb { la } else { lb }
      for i in 0..<n {
        if a[i] != b[i] {
          return if a[i] < b[i] { -1 } else { 1 }
        }
      }
      compare_int64(la.to_int64(), lb.to_int64())
    }
    (U128(a), U128(b)) => compare_big(a, b)
    _ =>
      match coerce(self, other, false) {
        Some(F64(a, b)) => cmp_f64(a, b)
        Some(Int(a, b)) => compare_int64(a, b)
        Some(Big(a, b)) => compare_big(a, b)
        Some(Str(a, b)) => compare_str(a, b)
        None => {
          if self.is_number() && other.is_number() {
            return cmp_uncoercible_numbers(self, other)
          }
          guard self is Object(a) && other is Object(b) else { return 0 }
          let at = self.is_tuple()
          let bt = other.is_tuple()
          if at != bt {
            return if at { 1 } else { -1 }
          }
          if a.is_same_object(b) {
            return 0
          }
          match (a.repr(), b.repr()) {
            (Map, Map) =>
              match (a.try_iter_pairs(), b.try_iter_pairs()) {
                (Some(ai), Some(bi)) =>
                  for ;; {
                    match (ai.next(), bi.next()) {
                      (None, None) => break 0
                      (None, Some(_)) => break -1
                      (Some(_), None) => break 1
                      (Some(x), Some(y)) => {
                        let c = x.0.cmp(y.0)
                        if c != 0 {
                          break c
                        }
                        let c = x.1.cmp(y.1)
                        if c != 0 {
                          break c
                        }
                      }
                    }
                  }
                _ => 0
              }
            (Seq | Iterable, Seq | Iterable) =>
              match (a.try_iter(), b.try_iter()) {
                (Some(ai), Some(bi)) =>
                  for ;; {
                    match (ai.next(), bi.next()) {
                      (None, None) => break 0
                      (None, Some(_)) => break -1
                      (Some(_), None) => break 1
                      (Some(x), Some(y)) => {
                        let c = x.cmp(y)
                        if c != 0 {
                          break c
                        }
                      }
                    }
                  }
                _ => 0
              }
            (Plain, Plain) => compare_str(self.to_string(), other.to_string())
            _ => 0
          }
        }
      }
  }
}

///|
pub impl Compare for Value with fn compare(self, other) {
  self.cmp(other)
}

///|
pub impl Hash for Value with fn hash_combine(self, hasher) {
  match self {
    NoneValue | Undefined(_) => hasher.combine_int(0)
    Str(s, _) => hasher.combine_string(s)
    Bool(b) => hasher.combine_bool(b)
    Invalid(e) => {
      hasher.combine_string(e.kind().name())
      hasher.combine_string(e.detail().unwrap_or(""))
    }
    Bytes(b) => hasher.combine(b)
    Object(o) => {
      hasher.combine_bool(self.is_tuple())
      if o.try_iter_pairs() is Some(iter) {
        for pair in iter {
          pair.0.hash_combine(hasher)
          pair.1.hash_combine(hasher)
        }
      }
    }
    U64(_) | I64(_) | F64(_) | U128(_) | I128(_) =>
      match self.as_i64() {
        Some(v) => hasher.combine_int64(v)
        None =>
          match as_f64(self, true) {
            Some(f) => hasher.combine_int64(f.reinterpret_as_int64())
            None => hasher.combine_int(0)
          }
      }
  }
}
