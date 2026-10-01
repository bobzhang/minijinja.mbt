///|
/// Stable merge sort with a comparator that may raise.
fn[T] stable_sort(
  items : Array[T],
  cmp : (T, T) -> Int raise TemplateError,
) -> Unit raise TemplateError {
  let n = items.length()
  if n < 2 {
    return
  }
  let buf = items.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = if lo + width < n { lo + width } else { n }
      let hi = if lo + 2 * width < n { lo + 2 * width } else { n }
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while i < mid && j < hi {
        if cmp(items[j], items[i]) < 0 {
          buf[k] = items[j]
          j += 1
        } else {
          buf[k] = items[i]
          i += 1
        }
        k += 1
      }
      while i < mid {
        buf[k] = items[i]
        i += 1
        k += 1
      }
      while j < hi {
        buf[k] = items[j]
        j += 1
        k += 1
      }
      lo += 2 * width
    }
    for x in 0..<n {
      items[x] = buf[x]
    }
    width *= 2
  }
}

///|
/// Marks a value as safe.  This converts it into a string.
fn filter_safe(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.string()
  a.finish()
  Value::from_safe_string(v)
}

///|
/// HTML escapes a string.
fn filter_escape(state : State, v : Value) -> Value raise TemplateError {
  if v.is_safe() {
    return v
  }
  // this tries to use the escaping flag of the current scope, then of the
  // initial state and if that is also not set it falls back to HTML.
  let auto_escape = match state.auto_escape() {
    NoEscape =>
      match (state.env().auto_escape_callback)(state.name()) {
        NoEscape => Html
        other => other
      }
    other => other
  }
  let buf = StringBuilder()
  let out = Output::new(buf)
  if auto_escape is Custom(_) {
    let old = state.auto_escape
    state.auto_escape = auto_escape
    state.env().format(v, state, out) catch {
      err => {
        state.auto_escape = old
        raise err
      }
    }
    state.auto_escape = old
  } else {
    write_escaped(out, auto_escape, v)
  }
  Value::from_safe_string(buf.to_string())
}

///|
fn filter_escape_fn(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.value()
  a.finish()
  filter_escape(state, v)
}

///|
fn filter_upper(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.string_input()
  a.finish()
  value.preserve_safety(@unicode.to_upper(value.as_str()))
}

///|
fn filter_lower(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.string_input()
  a.finish()
  value.preserve_safety(@unicode.to_lower(value.as_str()))
}

///|
fn filter_title(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.string()
  a.finish()
  let rv = StringBuilder()
  let mut capitalize = true
  for c in v {
    if c is ('-' | '(' | '{' | '[' | '<') || is_rust_whitespace(c) {
      rv.write_char(c)
      capitalize = true
    } else if capitalize {
      rv.write_string(@unicode.char_to_upper(c))
      capitalize = false
    } else {
      rv.write_string(@unicode.char_to_lower(c))
    }
  }
  Value::from_string(rv.to_string())
}

///|
fn filter_capitalize(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.string_input()
  a.finish()
  let s = value.as_str()
  let output = match s.get_char(0) {
    None => ""
    Some(first) =>
      @unicode.char_to_upper(first) +
      @unicode.to_lower(s.view(start_offset=first.utf16_len()))
  }
  value.preserve_safety(output)
}

///|
fn filter_replace(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.string_input()
  let from = a.string_input()
  let to = a.string_input()
  a.finish()
  let safety_aware = !(state.auto_escape() is NoEscape) &&
    (value.is_safe() || from.is_safe() || to.is_safe())
  if safety_aware {
    let output = rust_replace(
      value.format(state),
      from.as_str(),
      to.format(state),
    )
    Value::from_safe_string(output)
  } else {
    Value::from_string(rust_replace(value.as_str(), from.as_str(), to.as_str()))
  }
}

///|
/// Port of Rust's `str::replace` (an empty pattern inserts between chars).
fn rust_replace(s : String, from : String, to : String) -> String {
  if from.is_empty() {
    let sb = StringBuilder()
    sb.write_string(to)
    for c in s {
      sb.write_char(c)
      sb.write_string(to)
    }
    return sb.to_string()
  }
  s.replace_all(old=from, new=to)
}

///|
fn filter_length(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.value()
  a.finish()
  match v.len() {
    Some(len) => Value::from_int(len)
    None =>
      raise TemplateError::new(
        InvalidOperation,
        "cannot calculate length of value of type \{v.kind()}",
      )
  }
}

///|
fn cmp_helper(
  a : Value,
  b : Value,
  case_sensitive : Bool,
  reverse : Bool,
) -> Int {
  let ordering = if !case_sensitive {
    match (a.as_str(), b.as_str()) {
      (Some(a), Some(b)) =>
        compare_str(@unicode.case_fold(a), @unicode.case_fold(b))
      _ => a.cmp(b)
    }
  } else {
    a.cmp(b)
  }
  if reverse {
    -ordering
  } else {
    ordering
  }
}

///|
fn filter_dictsort(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let v = a.value()
  a.finish()
  if v.kind() != Map {
    raise TemplateError::new(
      InvalidOperation,
      "cannot convert value into pair list",
    )
  }
  let by_value = kwargs.get_str("by") is Some("value")
  let case_sensitive = kwargs.get_bool("case_sensitive").unwrap_or(false)
  let reverse = kwargs.get_bool("reverse").unwrap_or(false)
  let rv : Array[(Value, Value)] = match v.as_object() {
    Some(obj) =>
      match obj.try_iter_pairs() {
        Some(iter) => iter.to_array()
        None => []
      }
    None => []
  }
  stable_sort(rv, (a, b) => {
    let (a, b) = if by_value { (a.1, b.1) } else { (a.0, b.0) }
    cmp_helper(a, b, case_sensitive, reverse)
  })
  kwargs.assert_all_used()
  Value::from_array(rv.map(pair => Value::from_tuple([pair.0, pair.1])))
}

///|
fn filter_items(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.value()
  a.finish()
  if v.kind() == Map {
    Value::make_iterable(() => {
      match v.as_object() {
        Some(obj) =>
          match obj.try_iter_pairs() {
            Some(iter) => iter.map(pair => Value::from_tuple([pair.0, pair.1]))
            None => Iter::empty()
          }
        None => Iter::empty()
      }
    })
  } else {
    raise TemplateError::new(
      InvalidOperation,
      "cannot convert value into pairs",
    )
  }
}

///|
fn filter_reverse(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  if value.kind() == String {
    let chars = value.as_str().unwrap_or("").iter().to_array()
    chars.rev_in_place()
    let output = String::from_array(chars)
    if value.is_safe() {
      Value::from_safe_string(output)
    } else {
      Value::from_string(output)
    }
  } else {
    value.reverse()
  }
}

///|
fn filter_trim(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.string_input()
  let chars = a.opt_string()
  a.finish()
  let s = value.as_str()
  let output = match chars {
    Some(chars) => {
      let set = chars.iter().to_array()
      let cs = s.iter().to_array()
      let mut start = 0
      let mut end = cs.length()
      while start < end && set.contains(cs[start]) {
        start += 1
      }
      while end > start && set.contains(cs[end - 1]) {
        end -= 1
      }
      String::from_array(cs[start:end].to_array())
    }
    None => trim_view(s).to_owned()
  }
  value.preserve_safety(output)
}

///|
fn filter_join(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let joiner = a.opt_string_input()
  a.finish()
  fn join_plain(items : Iter[Value], joiner : String) -> String {
    let output = StringBuilder()
    let mut first = true
    for item in items {
      if !first {
        output.write_string(joiner)
      }
      first = false
      output.write_string(item.to_string())
    }
    output.to_string()
  }

  fn join_safe(
    state : State,
    items : Iter[Value],
    joiner : String,
  ) -> String raise TemplateError {
    let output = StringBuilder()
    let mut first = true
    for item in items {
      if !first {
        output.write_string(joiner)
      }
      first = false
      if item.is_safe() {
        output.write_string(item.as_str().unwrap_or(""))
      } else {
        output.write_string(state.format(item))
      }
    }
    output.to_string()
  }

  let joiner_str = match joiner {
    Some(j) => j.as_str()
    None => ""
  }
  let iter = value.try_iter() catch {
    err =>
      raise TemplateError::new(
        InvalidOperation,
        "cannot join value of type \{value.kind()}",
      ).with_source(err)
  }
  if state.auto_escape() is NoEscape {
    return Value::from_string(join_plain(iter, joiner_str))
  }
  if joiner is Some(j) && j.is_safe() {
    return Value::from_safe_string(join_safe(state, iter, joiner_str))
  }
  // A plain joiner only becomes safe if at least one item is safe.  This is
  // the one case where the iterable must be inspected before output.
  let items = iter.to_array()
  if items.iter().any(Value::is_safe) {
    let joiner = match joiner {
      Some(j) => j.format(state)
      None => ""
    }
    Value::from_safe_string(join_safe(state, items.iter(), joiner))
  } else {
    Value::from_string(join_plain(items.iter(), joiner_str))
  }
}

///|
/// Port of `Arc<str>::try_from(Value)`.
fn value_to_arc_str(value : Value) -> String raise TemplateError {
  match value.to_str() {
    Some(s) => s
    None => raise TemplateError::new(InvalidOperation, "value is not a string")
  }
}

///|
/// Splits a string at Unicode whitespace (Rust's `split_whitespace`).
fn split_whitespace(s : String) -> Array[String] {
  let rv = []
  let cur = StringBuilder()
  let mut in_word = false
  for c in s {
    if is_rust_whitespace(c) {
      if in_word {
        rv.push(cur.to_string())
        cur.reset()
        in_word = false
      }
    } else {
      cur.write_char(c)
      in_word = true
    }
  }
  if in_word {
    rv.push(cur.to_string())
  }
  rv
}

///|
/// Port of `utils::splitn_whitespace`.
fn splitn_whitespace(s : String, maxsplits : Int) -> Array[String] {
  let rv = []
  let mut splits = 1
  let mut skip_ws = true
  let mut split_start : Int? = None
  let mut last_split_end = 0
  let mut idx = 0
  for c in s {
    let len = c.utf16_len()
    if splits >= maxsplits && !skip_ws {
      idx += len
      continue
    } else if is_rust_whitespace(c) {
      if split_start is Some(old) {
        rv.push(s.view(start_offset=old, end_offset=idx).to_owned())
        split_start = None
        last_split_end = idx
        splits += 1
        skip_ws = true
      }
    } else {
      skip_ws = false
      if split_start is None {
        split_start = Some(idx)
        last_split_end = idx
      }
    }
    idx += len
  }
  if last_split_end < s.length() {
    rv.push(s.view(start_offset=last_split_end).to_owned())
  }
  rv
}

///|
/// Port of Rust's `str::splitn`.
fn rust_splitn(s : String, n : Int, sep : String) -> Array[String] {
  let rv = []
  if n == 0 {
    return rv
  }
  if sep.is_empty() {
    // Rust splits around every char including an empty first and last
    // element.
    let parts = [""]
    for c in s {
      parts.push(c.to_string())
    }
    parts.push("")
    let mut i = 0
    while i < parts.length() && rv.length() < n - 1 {
      rv.push(parts[i])
      i += 1
    }
    if i < parts.length() {
      let rest = StringBuilder()
      for j in i..<parts.length() {
        rest.write_string(parts[j])
      }
      rv.push(rest.to_string())
    }
    return rv
  }
  let mut start = 0
  while rv.length() < n - 1 {
    match find_from(s, start, sep) {
      Some(rel) => {
        rv.push(s.view(start_offset=start, end_offset=start + rel).to_owned())
        start = start + rel + sep.length()
      }
      None => break
    }
  }
  rv.push(s.view(start_offset=start).to_owned())
  rv
}

///|
fn filter_split(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let split = match a.opt_value() {
    Some(v) => Some(value_to_arc_str(v))
    None => None
  }
  let maxsplits = a.opt_i64()
  a.finish()
  let string = value_to_arc_str(value)
  let maxsplits = match maxsplits {
    Some(x) if x >= 0L => Some(clamp_int(x + 1L))
    _ => None
  }
  let preserve_safety = value.kind() == String && value.is_safe()
  let wrap = (item : String) => {
    if preserve_safety {
      Value::from_safe_string(item)
    } else {
      Value::from_string(item)
    }
  }
  let parts = match (split, maxsplits) {
    (None, None) => split_whitespace(string)
    (Some(sep), None) => rust_splitn(string, 0x7FFFFFFF, sep)
    (None, Some(n)) => splitn_whitespace(string, n)
    (Some(sep), Some(n)) => rust_splitn(string, n, sep)
  }
  Value::from_array(parts.map(wrap))
}

///|
fn filter_lines(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  let string = value_to_arc_str(value)
  let preserve_safety = value.kind() == String && value.is_safe()
  Value::from_array(
    rust_lines(string).map(line => {
      if preserve_safety {
        Value::from_safe_string(line)
      } else {
        Value::from_string(line)
      }
    }),
  )
}

///|
fn filter_default(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let rest = a.rest()
  if rest.length() > 2 {
    raise TemplateError::from_kind(TooManyArguments)
  }
  let other = rest.get(0).unwrap_or(Value::from_string(""))
  let lax = match rest.get(1) {
    Some(lax) => state.undefined_behavior().is_true(lax)
    None => false
  }
  if value.is_undefined() || (lax && !value.is_true()) {
    other
  } else {
    value
  }
}

///|
fn filter_abs(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  match value {
    U64(_) | U128(_) => value
    I64(x) =>
      if x == -0x7FFFFFFFFFFFFFFFL - 1L {
        I128(-BigInt::from_int64(x))
      } else if x < 0L {
        I64(-x)
      } else {
        value
      }
    I128(x) =>
      if x == i128_min {
        raise TemplateError::new(InvalidOperation, "overflow on abs")
      } else {
        int_as_value(if x < 0N { -x } else { x })
      }
    F64(x) => F64(x.abs())
    _ => raise TemplateError::new(InvalidOperation, "cannot get absolute value")
  }
}

///|
/// Port of Rust's saturating `f64 as i128` cast.
fn f64_to_i128_sat(v : Double) -> BigInt {
  if v.is_nan() {
    0N
  } else {
    let t = f64_trunc_to_bigint(v)
    if t > i128_max {
      i128_max
    } else if t < i128_min {
      i128_min
    } else {
      t
    }
  }
}

///|
/// Parses an integer like Rust's `str::parse::<i128>`.
fn parse_i128(s : String) -> BigInt? {
  let (neg, digits) = if s.has_prefix("-") {
    (true, s.view(start_offset=1))
  } else if s.has_prefix("+") {
    (false, s.view(start_offset=1))
  } else {
    (false, s[:])
  }
  for c in digits {
    if c < '0' || c > '9' {
      return None
    }
  }
  match parse_uint_radix(digits, 10) {
    Some(v) => {
      let v = if neg { -v } else { v }
      if in_i128(v) {
        Some(v)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Parses a float like Rust's `str::parse::<f64>`.
fn parse_f64_rust(s : String) -> Double raise TemplateError {
  let lower = s.to_lower()
  let body = if lower.has_prefix("-") || lower.has_prefix("+") {
    lower.view(start_offset=1).to_owned()
  } else {
    lower
  }
  let neg = lower.has_prefix("-")
  match body {
    "inf" | "infinity" => return if neg { -1.0 / 0.0 } else { 1.0 / 0.0 }
    "nan" => return 0.0 / 0.0
    _ => ()
  }
  let mut ok = !body.is_empty() && !body.contains("_")
  let mut seen_digit = false
  for c in body {
    match c {
      '0'..='9' => seen_digit = true
      '.' | 'e' | '+' | '-' => ()
      _ => ok = false
    }
  }
  if !ok || !seen_digit {
    raise TemplateError::new(InvalidOperation, "invalid float literal")
  }
  @string.parse_double(s) catch {
    _ => raise TemplateError::new(InvalidOperation, "invalid float literal")
  }
}

///|
fn filter_int(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  match value {
    Undefined(_) | NoneValue => {
      state.undefined_behavior().assert_value_not_undefined(value)
      Value::from_int(0)
    }
    Bool(x) => U64(if x { 1UL } else { 0UL })
    U64(_) | I64(_) | U128(_) | I128(_) => value
    F64(v) => int_as_value(f64_to_i128_sat(v))
    Str(s, _) =>
      match parse_i128(s) {
        Some(i) => int_as_value(i)
        None => int_as_value(f64_to_i128_sat(parse_f64_rust(s)))
      }
    Bytes(_) | Object(_) =>
      raise TemplateError::new(
        InvalidOperation,
        "cannot convert \{value.kind()} to integer",
      )
    Invalid(_) => value.validate()
  }
}

///|
fn filter_float(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  match value {
    Undefined(_) | NoneValue => {
      state.undefined_behavior().assert_value_not_undefined(value)
      F64(0.0)
    }
    Bool(x) => F64(if x { 1.0 } else { 0.0 })
    Str(s, _) => F64(parse_f64_rust(s))
    Invalid(_) => value.validate()
    _ =>
      match as_f64(value, true) {
        Some(f) => F64(f)
        None =>
          raise TemplateError::new(
            InvalidOperation,
            "cannot convert \{value.kind()} to float",
          )
      }
  }
}

///|
fn filter_sum(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let values = a.value()
  a.finish()
  let mut rv = Value::from_int(0)
  let iter = state.undefined_behavior().try_iter(values)
  for value in iter {
    if value.is_undefined() {
      state.undefined_behavior().handle_undefined(false) |> ignore
      continue
    } else if !value.is_number() && value.kind() != Bool {
      raise TemplateError::new(
        InvalidOperation,
        "can only sum numbers, got \{value.kind()}",
      )
    }
    rv = value_add(rv, value)
  }
  rv
}

///|
fn filter_attr(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let key = a.value()
  a.finish()
  value.get_item(key)
}

///|
fn round_with_negative_precision(
  value : Double,
  precision : Int,
) -> Double raise TemplateError {
  if value.is_nan() || value.is_inf() {
    return value
  }
  let decimal_place = -precision
  let zero = if value.reinterpret_as_int64() < 0L { -0.0 } else { 0.0 }
  if decimal_place >= 309 {
    return zero
  }
  let (digits, point) = @rfmt.exact_decimal(value)
  if digits.is_empty() {
    return zero
  }
  // keep the digits up to (and including) the 10^decimal_place position
  let keep = point - decimal_place
  if keep < 0 {
    return zero
  }
  let (rounded, new_point) = @rfmt.round_digits(digits, point, keep)
  if rounded.is_empty() || rounded.iter().all(c => c == '0') {
    return zero
  }
  let sign = if value < 0.0 { "-" } else { "" }
  let exp = new_point - rounded.length()
  let rv = @string.parse_double("\{sign}\{rounded}e\{exp}") catch {
    _ => raise TemplateError::new(InvalidOperation, "unable to round value")
  }
  if rv.is_inf() {
    raise TemplateError::new(
      InvalidOperation,
      "rounded value is too large to represent",
    )
  }
  rv
}

///|
fn filter_round(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let precision = a.opt_i32()
  a.finish()
  match value {
    I64(_) | I128(_) | U64(_) | U128(_) => value
    F64(val) => {
      let precision = precision.unwrap_or(0)
      if precision >= 0 {
        if precision > 1074 {
          F64(val)
        } else {
          let s = @rfmt.format_fixed(val, precision)
          F64(@string.parse_double(s) catch { _ => val })
        }
      } else {
        F64(round_with_negative_precision(val, precision))
      }
    }
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "cannot round value (\{value.kind()})",
      )
  }
}

///|
fn filter_first(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  match value.as_str() {
    Some(s) =>
      match s.get_char(0) {
        Some(c) => Value::from_char(c)
        None => Value::undefined()
      }
    None =>
      match value.as_object() {
        Some(obj) =>
          match obj.try_iter() {
            Some(iter) => iter.next().unwrap_or(Value::undefined())
            None =>
              raise TemplateError::new(
                InvalidOperation,
                "cannot get first item from value",
              )
          }
        None =>
          raise TemplateError::new(
            InvalidOperation,
            "cannot get first item from value",
          )
      }
  }
}

///|
fn filter_last(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  match value.as_str() {
    Some(s) =>
      match s.iter().last() {
        Some(ch) =>
          if value.is_safe() {
            Value::from_safe_string(ch.to_string())
          } else {
            Value::from_char(ch)
          }
        None => Value::undefined()
      }
    None =>
      if value.kind() is (Seq | Iterable) {
        let rev = value.reverse()
        rev.try_iter().next().unwrap_or(Value::undefined())
      } else {
        raise TemplateError::new(
          InvalidOperation,
          "cannot get last item from value",
        )
      }
  }
}

///|
fn try_iter_to_list(
  state : State,
  value : Value,
) -> Iter[Value] raise TemplateError {
  state.undefined_behavior().try_iter(value) catch {
    err =>
      raise TemplateError::new(InvalidOperation, "cannot convert value to list").with_source(
        err,
      )
  }
}

///|
fn filter_min(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  let mut rv : Value? = None
  for item in try_iter_to_list(state, value) {
    match rv {
      None => rv = Some(item)
      Some(cur) => if item.cmp(cur) < 0 { rv = Some(item) }
    }
  }
  rv.unwrap_or(Value::undefined())
}

///|
fn filter_max(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  let mut rv : Value? = None
  for item in try_iter_to_list(state, value) {
    match rv {
      None => rv = Some(item)
      // Rust's `Iterator::max` returns the last maximum element
      Some(cur) => if item.cmp(cur) >= 0 { rv = Some(item) }
    }
  }
  rv.unwrap_or(Value::undefined())
}

///|
fn filter_sort(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.value()
  a.finish()
  let items = try_iter_to_list(state, value).to_array()
  let case_sensitive = kwargs.get_bool("case_sensitive").unwrap_or(false)
  let reverse = kwargs.get_bool("reverse").unwrap_or(false)
  match kwargs.get_str("attribute") {
    Some(attr) => {
      let keys = []
      for key in attr.split(",") {
        if !key.is_empty() {
          keys.push(trim_view(key).to_owned())
        }
      }
      if keys.length() > 1 {
        stable_sort(items, (a, b) => {
          let key_a = Value::from_array(
            keys.map(k => a.get_path_or_default(k, Value::undefined())),
          )
          let key_b = Value::from_array(
            keys.map(k => b.get_path_or_default(k, Value::undefined())),
          )
          cmp_helper(key_a, key_b, case_sensitive, reverse)
        })
      } else {
        let key = if !keys.is_empty() { keys[0] } else { attr }
        stable_sort(items, (a, b) => {
          let av = a.get_path(key) catch { _ => return 0 }
          let bv = b.get_path(key) catch { _ => return 0 }
          cmp_helper(av, bv, case_sensitive, reverse)
        })
      }
    }
    None =>
      stable_sort(items, (a, b) => cmp_helper(a, b, case_sensitive, reverse))
  }
  kwargs.assert_all_used()
  Value::from_array(items)
}

///|
fn filter_list(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  Value::from_array(try_iter_to_list(state, value).to_array())
}

///|
fn filter_string(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  state.undefined_behavior().assert_value_not_undefined(value)
  if value.kind() == String {
    value
  } else {
    Value::from_string(value.to_string())
  }
}

///|
fn filter_bool(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  Value::from_bool(state.undefined_behavior().is_true(value))
}

///|
fn filter_slice(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let count = a.usize()
  let fill_with = a.opt_value()
  a.finish()
  if count == 0 {
    raise TemplateError::new(InvalidOperation, "count cannot be 0")
  }
  let items = state.undefined_behavior().try_iter(value).to_array()
  let len = items.length()
  let items_per_slice = len / count
  let slices_with_extra = len % count
  let mut offset = 0
  let rv = []
  for slice in 0..<count {
    let start = offset + slice * items_per_slice
    if slice < slices_with_extra {
      offset += 1
    }
    let end = offset + (slice + 1) * items_per_slice
    let tmp = items[start:end].to_array()
    if fill_with is Some(filler) && slice >= slices_with_extra {
      tmp.push(filler)
    }
    rv.push(Value::from_array(tmp))
  }
  Value::from_array(rv)
}

///|
fn filter_batch(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let count = a.usize()
  let fill_with = a.opt_value()
  a.finish()
  if count == 0 {
    raise TemplateError::new(InvalidOperation, "count cannot be 0")
  }
  let rv = []
  let mut tmp = []
  for item in state.undefined_behavior().try_iter(value) {
    if tmp.length() == count {
      rv.push(Value::from_array(tmp))
      tmp = []
    }
    tmp.push(item)
  }
  if !tmp.is_empty() {
    if fill_with is Some(filler) {
      for _ in 0..<(count - tmp.length()) {
        tmp.push(filler)
      }
    }
    rv.push(Value::from_array(tmp))
  }
  Value::from_array(rv)
}

///|
fn filter_tojson(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.value()
  let indent = match a.opt_value() {
    Some(indent) => Some(indent)
    None => kwargs.get_opt("indent")
  }
  a.finish()
  let indent = match indent {
    None => None
    Some(Bool(true)) => Some(2)
    Some(Bool(false)) => None
    Some(val) => Some(value_to_usize(val))
  }
  kwargs.assert_all_used()
  let s = try {
    match indent {
      Some(indent) =>
        value_to_json_with_style(value, Pretty(" ".repeat(indent)))
      None => value_to_json_with_style(value, Spaced)
    }
  } catch {
    err =>
      raise TemplateError::new(InvalidOperation, "cannot serialize to JSON").with_source(
        err,
      )
  }
  // When this filter is used the return value is safe for both HTML and JSON
  let rv = StringBuilder()
  for c in s {
    match c {
      '<' => rv.write_string("\\u003c")
      '>' => rv.write_string("\\u003e")
      '&' => rv.write_string("\\u0026")
      '\'' => rv.write_string("\\u0027")
      _ => rv.write_char(c)
    }
  }
  Value::from_safe_string(rv.to_string())
}

///|
fn filter_indent(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.string_input()
  let width = a.opt_usize()
  let indent_first_line = a.opt_bool()
  let indent_blank_lines = a.opt_bool()
  a.finish()
  fn strip_trailing_newline(input : String) -> String {
    let mut s = input
    if s.has_suffix("\n") {
      s = s.view(end_offset=s.length() - 1).to_owned()
    }
    if s.has_suffix("\r") {
      s = s.view(end_offset=s.length() - 1).to_owned()
    }
    s
  }

  let width = match width {
    Some(width) => width
    None => kwargs.get_usize("width").unwrap_or(4)
  }
  let indent_first_line = match indent_first_line {
    Some(v) => v
    None => kwargs.get_bool("first").unwrap_or(false)
  }
  let indent_blank_lines = match indent_blank_lines {
    Some(v) => v
    None => kwargs.get_bool("blank").unwrap_or(false)
  }
  kwargs.assert_all_used()
  let input = strip_trailing_newline(value.as_str())
  let indent_with = " ".repeat(width)
  let output = StringBuilder()
  let lines = input.split("\n").to_array()
  let mut start = 0
  if !indent_first_line {
    output.write_view(lines[0])
    output.write_char('\n')
    start = 1
  }
  for i in start..<lines.length() {
    let line = lines[i]
    if line.is_empty() {
      if indent_blank_lines {
        output.write_string(indent_with)
      }
    } else {
      output.write_string(indent_with)
      output.write_view(line)
    }
    output.write_char('\n')
  }
  value.preserve_safety(strip_trailing_newline(output.to_string()))
}

///|
fn percent_encode(bytes : Bytes) -> String {
  let sb = StringBuilder()
  for b in bytes {
    let c = b.to_int()
    let keep = (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '/'.to_int() ||
      c == '.'.to_int() ||
      c == '-'.to_int() ||
      c == '_'.to_int()
    if keep {
      sb.write_char(c.unsafe_to_char())
    } else {
      sb.write_char('%')
      let hex = c.to_string(radix=16).to_upper()
      if hex.length() < 2 {
        sb.write_char('0')
      }
      sb.write_string(hex)
    }
  }
  sb.to_string()
}

///|
fn filter_urlencode(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  if value.kind() == Map {
    let rv = StringBuilder()
    let mut first = true
    for k in value.try_iter() {
      let v = value.get_item(k)
      if v.is_none() || v.is_undefined() {
        continue
      }
      if !first {
        rv.write_char('&')
      }
      first = false
      rv.write_string(percent_encode(@utf8.encode(k.to_string())))
      rv.write_char('=')
      rv.write_string(percent_encode(@utf8.encode(v.to_string())))
    }
    Value::from_string(rv.to_string())
  } else {
    match value {
      NoneValue | Undefined(_) => Value::from_string("")
      Bytes(b) => Value::from_string(percent_encode(b))
      Str(s, _) => Value::from_string(percent_encode(@utf8.encode(s)))
      _ => Value::from_string(percent_encode(@utf8.encode(value.to_string())))
    }
  }
}

///|
fn select_or_reject(
  state : State,
  invert : Bool,
  value : Value,
  attr : String?,
  test_name : String?,
  args : Array[Value],
) -> Value raise TemplateError {
  let rv = []
  let test_fn = match test_name {
    Some(test_name) =>
      match state.env().get_test(test_name) {
        Some(t) => Some(t)
        None => raise TemplateError::from_kind(UnknownTest)
      }
    None => None
  }
  for value in state.undefined_behavior().try_iter(value) {
    let test_value = match attr {
      Some(attr) => value.get_path(attr)
      None => value
    }
    let passed = match test_fn {
      Some(test_fn) => {
        let new_args = [test_value]
        for arg in args {
          new_args.push(arg)
        }
        test_fn.call(state, new_args).is_true()
      }
      None => test_value.is_true()
    }
    if passed != invert {
      rv.push(value)
    }
  }
  Value::from_array(rv)
}

///|
fn filter_select(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let test_name = a.opt_string()
  let rest = a.rest_with_kwargs()
  select_or_reject(state, false, value, None, test_name, rest)
}

///|
fn filter_selectattr(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let attr = a.string()
  let test_name = a.opt_string()
  let rest = a.rest_with_kwargs()
  select_or_reject(state, false, value, Some(attr), test_name, rest)
}

///|
fn filter_reject(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let test_name = a.opt_string()
  let rest = a.rest_with_kwargs()
  select_or_reject(state, true, value, None, test_name, rest)
}

///|
fn filter_rejectattr(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let attr = a.string()
  let test_name = a.opt_string()
  let rest = a.rest_with_kwargs()
  select_or_reject(state, true, value, Some(attr), test_name, rest)
}

///|
fn filter_map(state : State, args : Array[Value]) -> Value raise TemplateError {
  let outer = Args::new(state, args)
  let value = outer.value()
  let rest = outer.rest_with_kwargs()
  // attribute mapping
  let a = Args::new(state, rest)
  let kwargs = a.kwargs()
  let args = a.rest()
  let rv = []
  if kwargs.get_opt("attribute") is Some(attr) {
    if !args.is_empty() {
      raise TemplateError::from_kind(TooManyArguments)
    }
    let default = if kwargs.has("default") {
      kwargs.get("default")
    } else {
      Value::undefined()
    }
    for value in state.undefined_behavior().try_iter(value) {
      let sub_val = try {
        match attr.as_str() {
          Some(path) => Ok(value.get_path(path))
          None => Ok(value.get_item(attr))
        }
      } catch {
        err => Err(err)
      }
      rv.push(
        match sub_val {
          Ok(attr) => if attr.is_undefined() { default } else { attr }
          Err(_) if !default.is_undefined() => default
          Err(err) => raise err
        },
      )
    }
    kwargs.assert_all_used()
    return Value::from_array(rv)
  }

  // filter mapping
  guard args.get(0) is Some(filter_name) else {
    raise TemplateError::new(InvalidOperation, "filter name is required")
  }
  guard filter_name.as_str() is Some(filter_name) else {
    raise TemplateError::new(InvalidOperation, "filter name must be a string")
  }
  guard state.env().get_filter(filter_name) is Some(filter) else {
    raise TemplateError::from_kind(UnknownFilter)
  }
  for value in state.undefined_behavior().try_iter(value) {
    let new_args = [value]
    for i in 1..<args.length() {
      new_args.push(args[i])
    }
    rv.push(filter.call(state, new_args))
  }
  Value::from_array(rv)
}

///|
/// The `(grouper, list)` tuples produced by `groupby`.
priv struct GroupTuple {
  grouper : Value
  list : Array[Value]
}

///|
impl Object for GroupTuple with fn repr(_self) {
  Seq
}

///|
impl Object for GroupTuple with fn get_value(self, key) {
  match (key.as_usize(), key.as_str()) {
    (Some(0), None) | (None, Some("grouper")) => Some(self.grouper)
    (Some(1), None) | (None, Some("list")) => {
      let list = self.list
      Some(Value::make_iterable(() => list.iter()))
    }
    _ => None
  }
}

///|
impl Object for GroupTuple with fn enumerate(_self) {
  Seq(2)
}

///|
impl Object for GroupTuple with fn render(self) {
  let f = @rfmt.Formatter::new()
  f
  .debug_tuple("")
  .field(f => self.grouper.fmt_debug(f))
  .field(f => {
    let l = f.debug_list()
    for v in self.list {
      l.entry(f => v.fmt_debug(f)) |> ignore
    }
    l.finish()
  })
  .finish()
  Some(f.to_string())
}

///|
fn filter_groupby(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.value()
  let attribute = a.opt_str()
  a.finish()
  let default = kwargs.get_opt("default").unwrap_or(Value::undefined())
  let case_sensitive = kwargs.get_bool("case_sensitive").unwrap_or(false)
  let attr = match attribute {
    Some(attr) => attr
    None => value_to_str(kwargs.get("attribute"))
  }
  let items = value.try_iter().to_array()
  stable_sort(items, (a, b) => {
    let a = a.get_path_or_default(attr, default)
    let b = b.get_path_or_default(attr, default)
    cmp_helper(a, b, case_sensitive, false)
  })
  kwargs.assert_all_used()
  let rv = []
  let mut grouper : Value? = None
  let mut list = []
  for item in items {
    let group_by = item.get_path_or_default(attr, default)
    if grouper is Some(last_grouper) &&
      cmp_helper(last_grouper, group_by, case_sensitive, false) != 0 {
      rv.push(Value::from_object(GroupTuple::{ grouper: last_grouper, list, }))
      list = []
    }
    grouper = Some(group_by)
    list.push(item)
  }
  if !list.is_empty() {
    rv.push(
      Value::from_object(GroupTuple::{
        grouper: grouper.unwrap_or(Value::undefined()),
        list,
      }),
    )
  }
  Value::from_array(rv)
}

///|
fn filter_unique(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let kwargs = a.kwargs()
  let values = a.value()
  a.finish()
  let attr = kwargs.get_str("attribute")
  let case_sensitive = kwargs.get_bool("case_sensitive").unwrap_or(false)
  kwargs.assert_all_used()
  let rv = []
  let seen : Array[Value] = []
  for item in state.undefined_behavior().try_iter(values) {
    let value_to_compare = match attr {
      Some(attr) => item.get_path_or_default(attr, Value::undefined())
      None => item
    }
    let memorized_value = if case_sensitive {
      value_to_compare
    } else {
      match value_to_compare.as_str() {
        Some(s) => Value::from_string(@unicode.to_lower(s))
        None => value_to_compare
      }
    }
    // BTreeSet semantics: membership is decided by the ordering
    if !seen.iter().any(v => v.cmp(memorized_value) == 0) {
      rv.push(item)
      seen.push(memorized_value)
    }
  }
  Value::from_array(rv)
}

///|
fn filter_chain(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let others = a.rest()
  let all_values = [value]
  for o in others {
    all_values.push(o)
  }
  if all_values.iter().all(v => v.kind() == Map) {
    Value::from_object(MergeDictObject::{ values: all_values, })
  } else if all_values.iter().all(v => v.kind() == Seq) {
    make_merge_seq(all_values, Seq)
  } else {
    // General iterator chaining behavior
    Value::make_iterable(() => {
      let mut idx = 0
      let mut current : Iter[Value]? = None
      Iter::new(() => {
        for ;; {
          match current {
            Some(it) =>
              match it.next() {
                Some(v) => break Some(v)
                None => current = None
              }
            None => {
              if idx >= all_values.length() {
                break None
              }
              let v = all_values[idx]
              idx += 1
              current = Some(
                v.try_iter() catch {
                  err => Iter::singleton(Value::from_error(err))
                },
              )
            }
          }
        }
      })
    })
  }
}

///|
fn filter_zip(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let others = a.rest()
  let all_values = [value]
  for o in others {
    all_values.push(o)
  }
  // Validate all values are iterable and calculate minimum length
  let mut known_len : Int? = None
  for val in all_values {
    let _ = val.try_iter() catch {
      _ =>
        raise TemplateError::new(
          InvalidOperation,
          "zip filter argument must be iterable, got \{val.kind()}",
        )
    }
    match val.len() {
      Some(len) =>
        known_len = Some(
          match known_len {
            None => len
            Some(current_min) =>
              if len < current_min {
                len
              } else {
                current_min
              }
          },
        )
      None => {
        known_len = None
        break
      }
    }
  }
  Value::make_iterable(() => {
    let iters = []
    for val in all_values {
      let it = val.try_iter() catch { _ => return Iter::empty() }
      iters.push(it)
    }
    Iter::new(
      () => {
        if iters.is_empty() {
          return None
        }
        let tuple = []
        for it in iters {
          match it.next() {
            Some(val) => tuple.push(val)
            None => return None
          }
        }
        Some(Value::from_tuple(tuple))
      },
      size_hint?=known_len,
    )
  })
}

///|
fn filter_pprint(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  a.finish()
  Value::from_string(value.debug_string(pretty=true))
}

///|
fn register_builtin_filters(rv : Map[String, Value]) -> Unit {
  fn add(
    rv : Map[String, Value],
    name : String,
    path : String,
    f : NativeFunction,
  ) -> Unit {
    rv[name] = Value::from_function(path, f)
  }

  add(rv, "safe", "minijinja::filters::safe", filter_safe)
  let escape = Value::from_function(
    "minijinja::filters::escape", filter_escape_fn,
  )
  rv["escape"] = escape
  rv["e"] = escape
  let b = "minijinja::filters::builtins::"
  add(rv, "lower", b + "lower", filter_lower)
  add(rv, "upper", b + "upper", filter_upper)
  add(rv, "title", b + "title", filter_title)
  add(rv, "capitalize", b + "capitalize", filter_capitalize)
  add(rv, "replace", b + "replace", filter_replace)
  let length = Value::from_function(b + "length", filter_length)
  rv["length"] = length
  rv["count"] = length
  add(rv, "dictsort", b + "dictsort", filter_dictsort)
  add(rv, "items", b + "items", filter_items)
  add(rv, "reverse", b + "reverse", filter_reverse)
  add(rv, "trim", b + "trim", filter_trim)
  add(rv, "join", b + "join", filter_join)
  add(rv, "split", b + "split", filter_split)
  add(rv, "lines", b + "lines", filter_lines)
  add(rv, "default", b + "default", filter_default)
  add(rv, "d", b + "default", filter_default)
  add(rv, "round", b + "round", filter_round)
  add(rv, "abs", b + "abs", filter_abs)
  add(rv, "int", b + "int", filter_int)
  add(rv, "float", b + "float", filter_float)
  add(rv, "attr", b + "attr", filter_attr)
  add(rv, "first", b + "first", filter_first)
  add(rv, "last", b + "last", filter_last)
  add(rv, "min", b + "min", filter_min)
  add(rv, "max", b + "max", filter_max)
  add(rv, "sort", b + "sort", filter_sort)
  add(rv, "list", b + "list", filter_list)
  add(rv, "string", b + "string", filter_string)
  add(rv, "bool", b + "bool", filter_bool)
  add(rv, "batch", b + "batch", filter_batch)
  add(rv, "slice", b + "slice", filter_slice)
  add(rv, "sum", b + "sum", filter_sum)
  add(rv, "indent", b + "indent", filter_indent)
  add(rv, "select", b + "select", filter_select)
  add(rv, "reject", b + "reject", filter_reject)
  add(rv, "selectattr", b + "selectattr", filter_selectattr)
  add(rv, "rejectattr", b + "rejectattr", filter_rejectattr)
  add(rv, "map", b + "map", filter_map)
  add(rv, "groupby", b + "groupby", filter_groupby)
  add(rv, "unique", b + "unique", filter_unique)
  add(rv, "chain", b + "chain", filter_chain)
  add(rv, "zip", b + "zip", filter_zip)
  add(rv, "pprint", b + "pprint", filter_pprint)
  add(rv, "format", b + "format", filter_format)
  add(rv, "tojson", b + "tojson", filter_tojson)
  add(rv, "urlencode", b + "urlencode", filter_urlencode)
}
