///|
priv struct JsonParser {
  src : String
  mut pos : Int
  sort_keys : Bool
}

///|
fn JsonParser::error(self : JsonParser, msg : String) -> TemplateError {
  TemplateError::new(
    CannotDeserialize,
    "invalid JSON at offset \{self.pos}: \{msg}",
  )
}

///|
fn JsonParser::skip_ws(self : JsonParser) -> Unit {
  while self.pos < self.src.length() {
    match self.src[self.pos] {
      ' ' | '\t' | '\n' | '\r' => self.pos += 1
      _ => break
    }
  }
}

///|
fn JsonParser::expect(
  self : JsonParser,
  lit : String,
) -> Unit raise TemplateError {
  if starts_with_at(self.src, self.pos, lit) {
    self.pos += lit.length()
  } else {
    raise self.error("expected \{lit}")
  }
}

///|
fn JsonParser::parse_value(self : JsonParser) -> Value raise TemplateError {
  self.skip_ws()
  if self.pos >= self.src.length() {
    raise self.error("unexpected end of input")
  }
  match self.src[self.pos] {
    '{' => {
      self.pos += 1
      let pairs : Array[(String, Value)] = []
      self.skip_ws()
      if unit_at(self.src, self.pos) == '}'.to_int() {
        self.pos += 1
      } else {
        for ;; {
          self.skip_ws()
          let key = self.parse_string()
          self.skip_ws()
          self.expect(":")
          let value = self.parse_value()
          pairs.push((key, value))
          self.skip_ws()
          if unit_at(self.src, self.pos) == ','.to_int() {
            self.pos += 1
          } else {
            self.expect("}")
            break
          }
        }
      }
      if self.sort_keys {
        pairs.sort_by((a, b) => compare_str(a.0, b.0))
      }
      let m : Map[Value, Value] = Map::new()
      for pair in pairs {
        m[Value::from_string(pair.0)] = pair.1
      }
      Value::from_map(m)
    }
    '[' => {
      self.pos += 1
      let items = []
      self.skip_ws()
      if unit_at(self.src, self.pos) == ']'.to_int() {
        self.pos += 1
      } else {
        for ;; {
          items.push(self.parse_value())
          self.skip_ws()
          if unit_at(self.src, self.pos) == ','.to_int() {
            self.pos += 1
          } else {
            self.expect("]")
            break
          }
        }
      }
      Value::from_array(items)
    }
    '"' => Value::from_string(self.parse_string())
    't' => {
      self.expect("true")
      Value::from_bool(true)
    }
    'f' => {
      self.expect("false")
      Value::from_bool(false)
    }
    'n' => {
      self.expect("null")
      Value::none()
    }
    _ => self.parse_number()
  }
}

///|
fn JsonParser::parse_string(self : JsonParser) -> String raise TemplateError {
  if unit_at(self.src, self.pos) != '"'.to_int() {
    raise self.error("expected string")
  }
  self.pos += 1
  let sb = StringBuilder()
  for ;; {
    if self.pos >= self.src.length() {
      raise self.error("unterminated string")
    }
    let c = self.src[self.pos]
    self.pos += 1
    match c {
      '"' => break
      '\\' => {
        let e = unit_at(self.src, self.pos)
        self.pos += 1
        match e.unsafe_to_char() {
          '"' => sb.write_char('"')
          '\\' => sb.write_char('\\')
          '/' => sb.write_char('/')
          'b' => sb.write_char('\u{08}')
          'f' => sb.write_char('\u{0C}')
          'n' => sb.write_char('\n')
          'r' => sb.write_char('\r')
          't' => sb.write_char('\t')
          'u' => {
            let mut cp = 0
            for _ in 0..<4 {
              let h = hex_value(unit_at(self.src, self.pos).unsafe_to_char())
              if h < 0 {
                raise self.error("invalid unicode escape")
              }
              cp = cp * 16 + h
              self.pos += 1
            }
            if cp >= 0xD800 &&
              cp <= 0xDBFF &&
              starts_with_at(self.src, self.pos, "\\u") {
              let save = self.pos
              self.pos += 2
              let mut lo = 0
              let mut ok = true
              for _ in 0..<4 {
                let h = hex_value(unit_at(self.src, self.pos).unsafe_to_char())
                if h < 0 {
                  ok = false
                  break
                }
                lo = lo * 16 + h
                self.pos += 1
              }
              if ok && lo >= 0xDC00 && lo <= 0xDFFF {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
              } else {
                self.pos = save
              }
            }
            if cp >= 0xD800 && cp <= 0xDFFF {
              raise self.error("lone leading surrogate in hex escape")
            }
            sb.write_char(cp.unsafe_to_char())
          }
          _ => raise self.error("invalid escape")
        }
      }
      c => {
        let u = c.to_int()
        if u < 0x20 {
          raise self.error("control character in string")
        }
        if u >= 0xD800 && u <= 0xDBFF {
          // a surrogate pair in the source text
          let lo = unit_at(self.src, self.pos)
          if lo >= 0xDC00 && lo <= 0xDFFF {
            self.pos += 1
            sb.write_char(
              (0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)).unsafe_to_char(),
            )
            continue
          }
          raise self.error("invalid unicode code point")
        }
        if u >= 0xDC00 && u <= 0xDFFF {
          raise self.error("invalid unicode code point")
        }
        sb.write_char(u.unsafe_to_char())
      }
    }
  }
  sb.to_string()
}

///|
fn JsonParser::parse_number(self : JsonParser) -> Value raise TemplateError {
  // JSON grammar: -?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
  let start = self.pos
  let negative = unit_at(self.src, self.pos) == '-'.to_int()
  if negative {
    self.pos += 1
  }
  let digits_start = self.pos
  if unit_at(self.src, self.pos) == '0'.to_int() {
    self.pos += 1
  } else if is_digit_unit(unit_at(self.src, self.pos)) {
    while is_digit_unit(unit_at(self.src, self.pos)) {
      self.pos += 1
    }
  } else {
    raise self.error("invalid number")
  }
  let int_end = self.pos
  let mut is_float = false
  if unit_at(self.src, self.pos) == '.'.to_int() {
    is_float = true
    self.pos += 1
    if !is_digit_unit(unit_at(self.src, self.pos)) {
      raise self.error("invalid number")
    }
    while is_digit_unit(unit_at(self.src, self.pos)) {
      self.pos += 1
    }
  }
  let e = unit_at(self.src, self.pos)
  if e == 'e'.to_int() || e == 'E'.to_int() {
    is_float = true
    self.pos += 1
    let sign = unit_at(self.src, self.pos)
    if sign == '+'.to_int() || sign == '-'.to_int() {
      self.pos += 1
    }
    if !is_digit_unit(unit_at(self.src, self.pos)) {
      raise self.error("invalid number")
    }
    while is_digit_unit(unit_at(self.src, self.pos)) {
      self.pos += 1
    }
  }
  let text = self.src.view(start_offset=start, end_offset=self.pos).to_owned()
  if !is_float {
    guard parse_uint_radix(
        self.src.view(start_offset=digits_start, end_offset=int_end),
        10,
      )
      is Some(magnitude) else {
      raise self.error("invalid number")
    }
    if negative {
      // like serde_json, `-0` becomes a negative zero float
      if magnitude.is_zero() {
        return Value::from_double(-0.0)
      }
      let v = -magnitude
      if in_i64(v) {
        return Value::from_int64(v.to_int64())
      }
    } else if magnitude <= max_u64_big {
      return Value::from_uint64(magnitude.to_uint64())
    }
  }
  let f = @string.parse_double(text) catch {
    _ => raise self.error("number out of range")
  }
  Value::from_double(f)
}

///|
/// Parses a JSON document into a value.
///
/// Unlike `@json.parse` this preserves the distinction between integers
/// (`4`) and floats (`4.0`).  With `sort_keys` set, object keys are sorted
/// (this matches the behavior of `serde_json` without `preserve_order`).
pub fn Value::from_json_str(
  s : String,
  sort_keys? : Bool = false,
) -> Value raise TemplateError {
  let p = { src: s, pos: 0, sort_keys, }
  let rv = p.parse_value()
  p.skip_ws()
  if p.pos != s.length() {
    raise p.error("trailing characters")
  }
  rv
}

///|
/// Converts a MoonBit `Json` value into a value.
pub fn Value::from_json(j : Json) -> Value {
  match j {
    Null => Value::none()
    True => Value::from_bool(true)
    False => Value::from_bool(false)
    Number(n, ..) =>
      if n == n.trunc() && n.abs() < 9007199254740992.0 {
        Value::from_int64(n.to_int64())
      } else {
        Value::from_double(n)
      }
    String(s) => Value::from_string(s)
    Array(items) => Value::from_array(items.map(Value::from_json))
    Object(m) => {
      let rv : Map[Value, Value] = Map::new()
      for k, v in m {
        rv[Value::from_string(k)] = Value::from_json(v)
      }
      Value::from_map(rv)
    }
  }
}

///|
/// JSON output styles.
priv enum JsonStyle {
  /// serde_json's compact formatter (`[1,2]`)
  Compact
  /// MiniJinja's `tojson` formatter (`[1, 2]`)
  Spaced
  /// serde_json's pretty formatter with the given indentation
  Pretty(String)
}

///|
/// Formats a float like `serde_json` (which uses `ryu`).
fn json_float(f : Double) -> String {
  if f.is_nan() || f.is_inf() {
    return "null"
  }
  let s = @rfmt.f64_display(f)
  if f == 0.0 {
    return s + ".0"
  }
  let neg = f < 0.0
  let digits = StringBuilder()
  let mut point = 0
  // reconstruct digits and decimal point position from the plain notation
  let body = if neg { s.view(start_offset=1).to_owned() } else { s }
  let int_part = match body.find(".") {
    Some(idx) => body.view(end_offset=idx).to_owned()
    None => body
  }
  let frac_part = match body.find(".") {
    Some(idx) => body.view(start_offset=idx + 1).to_owned()
    None => ""
  }
  let all = int_part + frac_part
  let mut lead = 0
  while lead < all.length() && all[lead] == '0' {
    lead += 1
  }
  let mut trail = all.length()
  while trail > lead && all[trail - 1] == '0' {
    trail -= 1
  }
  digits.write_view(all.view(start_offset=lead, end_offset=trail))
  point = int_part.length() - lead
  let d = digits.to_string()
  let len = d.length()
  let sign = if neg { "-" } else { "" }
  if point >= len && point <= 16 {
    sign + d + "0".repeat(point - len) + ".0"
  } else if point > 0 && point <= 16 {
    sign +
    d.view(end_offset=point).to_owned() +
    "." +
    d.view(start_offset=point).to_owned()
  } else if point > -5 && point <= 0 {
    sign + "0." + "0".repeat(-point) + d
  } else {
    let exp = point - 1
    let mantissa = if len == 1 {
      d
    } else {
      d.view(end_offset=1).to_owned() + "." + d.view(start_offset=1).to_owned()
    }
    sign + mantissa + "e" + exp.to_string()
  }
}

///|
fn write_json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\u{08}' => sb.write_string("\\b")
      '\u{0C}' => sb.write_string("\\f")
      c =>
        if c.to_int() < 0x20 {
          let hex = c.to_int().to_string(radix=16)
          sb.write_string("\\u00")
          if hex.length() < 2 {
            sb.write_char('0')
          }
          sb.write_string(hex)
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
}

///|
fn write_json(
  sb : StringBuilder,
  value : Value,
  style : JsonStyle,
  depth : Int,
) -> Unit raise TemplateError {
  fn newline(sb : StringBuilder, style : JsonStyle, depth : Int) -> Unit {
    if style is Pretty(indent) {
      sb.write_char('\n')
      for _ in 0..<depth {
        sb.write_string(indent)
      }
    }
  }

  let item_sep = match style {
    Compact | Pretty(_) => ","
    Spaced => ", "
  }
  let key_sep = match style {
    Compact => ":"
    Spaced | Pretty(_) => ": "
  }
  match value {
    Bool(b) => sb.write_string(if b { "true" } else { "false" })
    U64(v) => sb.write_string(v.to_string())
    I64(v) => sb.write_string(v.to_string())
    U128(v) | I128(v) => sb.write_string(v.to_string())
    F64(f) => sb.write_string(json_float(f))
    NoneValue | Undefined(_) | Invalid(_) => sb.write_string("null")
    Str(s, _) => write_json_string(sb, s)
    Bytes(b) => {
      sb.write_char('[')
      let mut first = true
      for byte in b {
        if !first {
          sb.write_string(item_sep)
        }
        first = false
        newline(sb, style, depth + 1)
        sb.write_string(byte.to_int().to_string())
      }
      if !first {
        newline(sb, style, depth)
      }
      sb.write_char(']')
    }
    Object(obj) =>
      match obj.repr() {
        Plain => write_json_string(sb, value.to_string())
        Seq | Iterable => {
          sb.write_char('[')
          let mut first = true
          if obj.try_iter() is Some(iter) {
            for item in iter {
              if !first {
                sb.write_string(item_sep)
              }
              first = false
              newline(sb, style, depth + 1)
              write_json(sb, item, style, depth + 1)
            }
          }
          if !first {
            newline(sb, style, depth)
          }
          sb.write_char(']')
        }
        Map => {
          sb.write_char('{')
          let mut first = true
          if obj.try_iter_pairs() is Some(iter) {
            for pair in iter {
              let (k, v) = pair
              if !first {
                sb.write_string(item_sep)
              }
              first = false
              newline(sb, style, depth + 1)
              // serde_json's map key serializer
              match k {
                Str(s, _) => write_json_string(sb, s)
                U64(_) | I64(_) | U128(_) | I128(_) =>
                  write_json_string(sb, k.to_string())
                Bool(b) =>
                  write_json_string(sb, if b { "true" } else { "false" })
                F64(f) if !f.is_nan() && !f.is_inf() =>
                  write_json_string(sb, json_float(f))
                Object(o) if o.repr() is Plain =>
                  write_json_string(sb, k.to_string())
                F64(_) =>
                  raise TemplateError::new(
                    BadSerialization,
                    "float key must be finite (got NaN or +/-inf)",
                  )
                _ =>
                  raise TemplateError::new(
                    BadSerialization,
                    "key must be a string",
                  )
              }
              sb.write_string(key_sep)
              write_json(sb, v, style, depth + 1)
            }
          }
          if !first {
            newline(sb, style, depth)
          }
          sb.write_char('}')
        }
      }
  }
}

///|
fn value_to_json_with_style(
  value : Value,
  style : JsonStyle,
) -> String raise TemplateError {
  let sb = StringBuilder()
  write_json(sb, value, style, 0)
  sb.to_string()
}

///|
/// Serializes a value to compact JSON (used by the JSON auto escape mode).
fn value_to_json_string(value : Value, spaced : Bool) -> String {
  value_to_json_with_style(value, if spaced { Spaced } else { Compact }) catch {
    _ => "null"
  }
}

///|
/// Serializes the value to JSON.  With `indent` the output is pretty
/// printed.
pub fn Value::to_json_string(
  self : Value,
  indent? : Int,
) -> String raise TemplateError {
  match indent {
    Some(n) => value_to_json_with_style(self, Pretty(" ".repeat(n)))
    None => value_to_json_with_style(self, Compact)
  }
}
