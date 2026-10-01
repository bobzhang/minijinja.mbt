///|
/// Describes the kind of value.
pub(all) enum ValueKind {
  /// The value is undefined
  Undefined
  /// The value is the none singleton (`()`)
  Null
  /// The value is a [`Bool`]
  Bool
  /// The value is a number of a supported type.
  Number
  /// The value is a string.
  String
  /// The value is a byte array.
  Bytes
  /// The value is an array of other values.
  Seq
  /// The value is a key/value mapping.
  Map
  /// An iterable
  Iterable
  /// A plain object without specific behavior.
  Plain
  /// This value is invalid (holds an error).
  Invalid
} derive(Eq, Compare, Debug)

///|
pub fn ValueKind::to_string(self : ValueKind) -> String {
  match self {
    Undefined => "undefined"
    Null => "none"
    Bool => "bool"
    Number => "number"
    String => "string"
    Bytes => "bytes"
    Seq => "sequence"
    Map => "map"
    Iterable => "iterator"
    Plain => "plain object"
    Invalid => "invalid value"
  }
}

///|
pub impl Show for ValueKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
priv enum UndefinedType {
  Default
  Silent
} derive(Eq)

///|
priv enum StringType {
  Normal
  Safe
} derive(Eq)

///|
/// Represents a dynamically typed value in the template engine.
enum Value {
  Undefined(UndefinedType)
  NoneValue
  Bool(Bool)
  U64(UInt64)
  I64(Int64)
  F64(Double)
  U128(BigInt)
  I128(BigInt)
  Str(String, StringType)
  Bytes(Bytes)
  Invalid(TemplateError)
  Object(DynObject)
}

///|
/// The undefined value.
pub fn Value::undefined() -> Value {
  Undefined(Default)
}

///|
fn Value::silent_undefined() -> Value {
  Undefined(Silent)
}

///|
/// The `none` value.
pub fn Value::none() -> Value {
  NoneValue
}

///|
pub fn Value::from_bool(b : Bool) -> Value {
  Bool(b)
}

///|
pub fn Value::from_int(i : Int) -> Value {
  I64(i.to_int64())
}

///|
pub fn Value::from_int64(i : Int64) -> Value {
  I64(i)
}

///|
pub fn Value::from_uint64(i : UInt64) -> Value {
  U64(i)
}

///|
pub fn Value::from_double(f : Double) -> Value {
  F64(f)
}

///|
/// Creates a value from a big integer.  Values that fit into 64 bits are
/// stored as such, values outside of the 128 bit range become invalid.
pub fn Value::from_bigint(i : BigInt) -> Value {
  int_as_value(i)
}

///|
pub fn Value::from_string(s : String) -> Value {
  Str(s, Normal)
}

///|
pub fn Value::from_char(c : Char) -> Value {
  Str(c.to_string(), Normal)
}

///|
/// Creates a value from a safe string.
///
/// A safe string is one that will bypass auto escaping.
pub fn Value::from_safe_string(s : String) -> Value {
  Str(s, Safe)
}

///|
pub fn Value::from_bytes(b : Bytes) -> Value {
  Bytes(b)
}

///|
/// Creates a sequence value from an array.
pub fn Value::from_array(items : Array[Value]) -> Value {
  Object(DynObject::new(Seq(items)))
}

///|
/// Creates a tuple value.
pub fn Value::from_tuple(items : Array[Value]) -> Value {
  Object(DynObject::new(Tuple(items)))
}

///|
/// Creates a map value.
pub fn Value::from_map(m : Map[Value, Value]) -> Value {
  Object(DynObject::new(Map(m)))
}

///|
/// Creates a map value from string keys.
pub fn Value::from_str_map(m : Map[String, Value]) -> Value {
  let rv : Map[Value, Value] = Map::new(capacity=m.length())
  for k, v in m {
    rv[Value::from_string(k)] = v
  }
  Value::from_map(rv)
}

///|
/// Creates a map value from key/value pairs.
pub fn Value::from_pairs(pairs : Array[(String, Value)]) -> Value {
  let rv : Map[Value, Value] = Map::new(capacity=pairs.length())
  for pair in pairs {
    rv[Value::from_string(pair.0)] = pair.1
  }
  Value::from_map(rv)
}

///|
/// Creates a value from a dynamic object.
pub fn[T : Object] Value::from_object(obj : T) -> Value {
  Object(DynObject::new(Custom(obj)))
}

///|
/// Creates a value from a dynamic object handle.
pub fn Value::from_dyn_object(obj : DynObject) -> Value {
  Object(obj)
}

///|
/// Creates a value from an error.  The value is invalid and raises the
/// error as soon as it is used by the engine.
pub fn Value::from_error(err : TemplateError) -> Value {
  Invalid(err)
}

///|
/// Creates an iterable that iterates over the iterator produced by `maker`.
/// The maker is invoked every time the value is iterated.
pub fn Value::make_iterable(maker : () -> Iter[Value]) -> Value {
  Value::from_object(IterableObject::{ maker, })
}

///|
/// Creates an iterable that can only be iterated over once.
pub fn Value::make_one_shot_iterator(iter : Iter[Value]) -> Value {
  let mut done = false
  let shared = Iter::new(() => {
    if done {
      return None
    }
    match iter.next() {
      Some(v) => Some(v)
      None => {
        done = true
        None
      }
    }
  })
  Value::make_iterable(() => Iter::new(() => shared.next()))
}

///|
/// Creates a map object from closures: `keys` enumerates the keys and `get`
/// looks up a value by key.
pub fn Value::make_object_map(
  keys : () -> Iter[Value],
  get : (Value) -> Value?,
) -> Value {
  Value::from_object(ProxyMapObject::{ keys, get, })
}

///|
/// Creates a callable value from a function.
pub fn Value::from_function(
  name : String,
  func : (State, Array[Value]) -> Value raise TemplateError,
) -> Value {
  Value::from_object(FunctionObject::{ name, func, })
}

///|
/// Returns the kind of the value.
pub fn Value::kind(self : Value) -> ValueKind {
  match self {
    Undefined(_) => Undefined
    Bool(_) => Bool
    U64(_) | I64(_) | F64(_) | U128(_) | I128(_) => Number
    NoneValue => Null
    Str(_, _) => String
    Bytes(_) => Bytes
    Invalid(_) => Invalid
    Object(obj) =>
      match obj.repr() {
        Map => Map
        Seq => Seq
        Iterable => Iterable
        Plain => Plain
      }
  }
}

///|
/// Returns `true` if the value is a number.
pub fn Value::is_number(self : Value) -> Bool {
  self is (U64(_) | I64(_) | F64(_) | U128(_) | I128(_))
}

///|
/// Returns `true` if the value is an integer.
pub fn Value::is_integer(self : Value) -> Bool {
  self is (U64(_) | I64(_) | U128(_) | I128(_))
}

///|
/// Returns `true` if the map represents keyword arguments.
pub fn Value::is_kwargs(self : Value) -> Bool {
  self is Object({ inner: Kwargs(_), .. })
}

///|
/// Returns `true` if the value is a tuple.
pub fn Value::is_tuple(self : Value) -> Bool {
  self is Object({ inner: Tuple(_), .. })
}

///|
/// Is this value considered true?
pub fn Value::is_true(self : Value) -> Bool {
  match self {
    Bool(b) => b
    U64(x) => x != 0
    I64(x) => x != 0
    U128(x) | I128(x) => !x.is_zero()
    F64(x) => x != 0.0
    Str(s, _) => !s.is_empty()
    Bytes(b) => b.length() != 0
    NoneValue | Undefined(_) | Invalid(_) => false
    Object(obj) => obj.is_true()
  }
}

///|
/// Returns `true` if this value is safe.
pub fn Value::is_safe(self : Value) -> Bool {
  self is Str(_, Safe)
}

///|
/// Returns `true` if this value is undefined.
pub fn Value::is_undefined(self : Value) -> Bool {
  self is Undefined(_)
}

///|
/// Returns `true` if this value is none.
pub fn Value::is_none(self : Value) -> Bool {
  self is NoneValue
}

///|
/// If the value is a string, return it.  Bytes are returned if they are
/// valid UTF-8.
pub fn Value::as_str(self : Value) -> String? {
  match self {
    Str(s, _) => Some(s)
    Bytes(b) => utf8_decode_strict(b)
    _ => None
  }
}

///|
/// Like `as_str` but bytes are decoded lossily.
pub fn Value::to_str(self : Value) -> String? {
  match self {
    Str(s, _) => Some(s)
    Bytes(b) => Some(utf8_decode_lossy(b))
    _ => None
  }
}

///|
/// If the value is bytes (or a string), return the UTF-8 bytes.
pub fn Value::as_bytes(self : Value) -> Bytes? {
  match self {
    Str(s, _) => Some(@utf8.encode(s))
    Bytes(b) => Some(b)
    _ => None
  }
}

///|
/// Returns the object handle if the value is an object.
pub fn Value::as_object(self : Value) -> DynObject? {
  match self {
    Object(o) => Some(o)
    _ => None
  }
}

///|
/// Returns the error of an invalid value.
fn Value::as_error(self : Value) -> TemplateError? {
  match self {
    Invalid(e) => Some(e)
    _ => None
  }
}

///|
/// Returns the length of the contained value.
///
/// Strings return the number of Unicode scalar values, bytes the number of
/// bytes and objects the length of their enumerator (if known).
pub fn Value::len(self : Value) -> Int? {
  match self {
    Str(s, _) => Some(scalar_count(s))
    Bytes(b) => Some(b.length())
    Object(obj) => obj.enumerator_len()
    _ => None
  }
}

///|
/// Raises the error of an invalid value, otherwise returns the value.
fn Value::validate(self : Value) -> Value raise TemplateError {
  match self {
    Invalid(err) => raise err.internal_clone()
    _ => self
  }
}

///|
/// Looks up an attribute by attribute name.
///
/// This this returns undefined if an item does not exist, but it raises an
/// error if the value itself is undefined.
pub fn Value::get_attr(self : Value, key : String) -> Value raise TemplateError {
  match self {
    Undefined(_) => raise TemplateError::from_kind(UndefinedError)
    Object(obj) => obj.get_value_by_str(key).unwrap_or(Value::undefined())
    _ => Value::undefined()
  }
}

///|
fn Value::get_attr_fast(self : Value, key : String) -> Value? {
  match self {
    Object(obj) => obj.get_value_by_str(key)
    _ => None
  }
}

///|
/// Looks up an index of the value.
pub fn Value::get_item_by_index(
  self : Value,
  idx : Int,
) -> Value raise TemplateError {
  self.get_item(Value::from_int(idx))
}

///|
/// Looks up an item (or attribute) by key.
///
/// This returns undefined if the item does not exist but raises an error if
/// the value itself is undefined.
pub fn Value::get_item(self : Value, key : Value) -> Value raise TemplateError {
  match self {
    Undefined(_) => raise TemplateError::from_kind(UndefinedError)
    _ => self.get_item_opt(key).unwrap_or(Value::undefined())
  }
}

///|
/// Resolves a (possibly negative) index.
fn resolve_index(key : Value, len : () -> Int?) -> Int? {
  match key.as_i64() {
    Some(i) if i < 0L =>
      match len() {
        Some(l) => {
          let rv = l.to_int64() + i
          if rv < 0L {
            None
          } else {
            Some(rv.to_int())
          }
        }
        None => None
      }
    Some(i) => if i > 0x7FFFFFFFL { None } else { Some(i.to_int()) }
    None => None
  }
}

///|
fn Value::get_item_opt(self : Value, key : Value) -> Value? {
  match self {
    Object(obj) =>
      match obj.repr() {
        Map | Plain => obj.get_value(key)
        Iterable => {
          if obj.get_value(key) is Some(rv) {
            return Some(rv)
          }
          // The default behavior is to try to index into the iterable as if
          // nth() was called.  This lets one slice an array and then index
          // into it.
          if resolve_index(key, () => obj.enumerator_len()) is Some(idx) &&
            obj.try_iter() is Some(iter) {
            return iter.nth(idx)
          }
          None
        }
        Seq =>
          match resolve_index(key, () => obj.enumerator_len()) {
            Some(idx) => obj.get_value(Value::from_int(idx))
            None => obj.get_value(key)
          }
      }
    Str(s, _) => {
      guard resolve_index(key, () => Some(scalar_count(s))) is Some(idx) else {
        return None
      }
      let mut i = 0
      for c in s {
        if i == idx {
          return Some(Value::from_char(c))
        }
        i += 1
      }
      None
    }
    Bytes(b) => {
      guard resolve_index(key, () => Some(b.length())) is Some(idx) else {
        return None
      }
      if idx < b.length() {
        Some(U64(b[idx].to_uint64()))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Iterates over the value.
///
/// Depending on the kind of the value the iterator has a different behavior:
/// maps yield their keys, sequences and iterables their items, strings
/// their characters and undefined/none values nothing.
pub fn Value::try_iter(self : Value) -> Iter[Value] raise TemplateError {
  match self {
    NoneValue | Undefined(_) => Iter::empty()
    Str(s, _) => {
      let chars = s.iter()
      let len = scalar_count(s)
      Iter::new(() => chars.next().map(Value::from_char), size_hint=len)
    }
    Object(obj) =>
      match obj.try_iter() {
        Some(iter) => iter
        None =>
          raise TemplateError::new(
            InvalidOperation,
            "\{self.kind()} is not iterable",
          )
      }
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "\{self.kind()} is not iterable",
      )
  }
}

///|
/// Returns a reversed view of this value.
///
/// This is implemented for the following types with the following
/// behaviors: undefined or none (returns itself), strings (reverses the
/// characters), bytes, sequences and iterables.
pub fn Value::reverse(self : Value) -> Value raise TemplateError {
  match self {
    Undefined(_) | NoneValue => self
    Str(s, _) => {
      let chars = s.iter().to_array()
      chars.rev_in_place()
      Value::from_string(String::from_array(chars))
    }
    Bytes(b) => {
      let arr = b.to_array()
      arr.rev_in_place()
      Value::from_bytes(Bytes::from_array(arr))
    }
    Object(o) =>
      match o.enumerate() {
        NonEnumerable =>
          raise TemplateError::new(
            InvalidOperation,
            "cannot reverse values of type \{self.kind()}",
          )
        Empty => Value::make_iterable(() => Iter::empty())
        Seq(l) =>
          Value::make_iterable(() => {
            let mut idx = l
            Iter::new(
              () => {
                if idx > 0 {
                  idx -= 1
                  Some(
                    o
                    .get_value(Value::from_int(idx))
                    .unwrap_or(Value::undefined()),
                  )
                } else {
                  None
                }
              },
              size_hint=l,
            )
          })
        Iter(iter) => {
          let v = iter.to_array()
          v.rev_in_place()
          Value::make_iterable(() => v.iter())
        }
        KeyValueIter(iter) => {
          let v = if o.repr() is Map {
            iter.map(pair => pair.0).to_array()
          } else {
            iter.map(pair => Value::from_tuple([pair.0, pair.1])).to_array()
          }
          v.rev_in_place()
          Value::make_iterable(() => v.iter())
        }
        Str(strs) => {
          let v = strs.map(Value::from_string)
          v.rev_in_place()
          Value::make_iterable(() => v.iter())
        }
        Values(values) => {
          let v = values.copy()
          v.rev_in_place()
          Value::make_iterable(() => v.iter())
        }
      }
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "cannot reverse values of type \{self.kind()}",
      )
  }
}

///|
/// Calls the value directly.
pub fn Value::call(
  self : Value,
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  match self {
    Object(obj) => obj.call(state, args)
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "value of type \{self.kind()} is not callable",
      )
  }
}

///|
/// Calls a method on the value.
pub fn Value::call_method(
  self : Value,
  state : State,
  name : String,
  args : Array[Value],
) -> Value raise TemplateError {
  let rv = try {
    match self {
      Object(obj) => obj.call_method(state, name, args)
      _ => raise TemplateError::from_kind(UnknownMethod)
    }
  } catch {
    err => {
      let mut err = err
      if err.kind() == UnknownMethod {
        if state.env().unknown_method_callback is Some(callback) {
          let res = try callback(state, self, name, args) catch {
            callback_err => {
              if callback_err.kind() != UnknownMethod {
                raise callback_err
              }
              err = callback_err
              Value::undefined()
            }
          } noraise {
            result => return result
          }
          ignore(res)
        }
        // Calling values stored on objects by using method syntax is
        // supported as a fallback.
        if self.as_object() is Some(obj) &&
          obj.get_value(Value::from_string(name)) is Some(value) {
          return value.call(state, args)
        }
        if err.detail() is None {
          err.set_detail("\{self.kind()} has no method named \{name}")
        }
      }
      raise err
    }
  }
  rv
}

///|
/// Looks up a dotted path (`foo.0.bar`).
fn Value::get_path(self : Value, path : String) -> Value raise TemplateError {
  let mut rv = self
  for part in path.split(".") {
    match parse_usize(part) {
      Some(num) => rv = rv.get_item_by_index(num)
      None => rv = rv.get_attr(part.to_owned())
    }
  }
  rv
}

///|
fn Value::get_path_or_default(
  self : Value,
  path : String,
  default : Value,
) -> Value {
  let val = self.get_path(path) catch { _ => return default }
  if val.is_undefined() {
    default
  } else {
    val
  }
}

///|
/// Parses a non-negative decimal integer like Rust's `str::parse::<usize>`.
fn parse_usize(s : StringView) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut rv = 0L
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    rv = rv * 10L + (c.to_int() - '0'.to_int()).to_int64()
    if rv > 0x7FFFFFFFL {
      return None
    }
  }
  Some(rv.to_int())
}

///|
/// Formats the value like MiniJinja's `Display` (what `{{ value }}`
/// renders).
pub fn Value::to_string(self : Value) -> String {
  match self {
    Str(s, _) => s
    _ => {
      let f = @rfmt.Formatter::new()
      self.fmt_display(f)
      f.to_string()
    }
  }
}

///|
pub impl Show for Value with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn Value::fmt_display(self : Value, f : @rfmt.Formatter) -> Unit {
  match self {
    Undefined(_) => ()
    Bool(b) => f.write_str(if b { "True" } else { "False" })
    U64(v) => f.write_str(v.to_string())
    I64(v) => f.write_str(v.to_string())
    F64(v) => f.write_str(format_f64_display(v))
    NoneValue => f.write_str("None")
    Invalid(err) => f.write_str("<invalid value: \{err}>")
    I128(v) | U128(v) => f.write_str(v.to_string())
    Str(s, _) => f.write_str(s)
    Bytes(b) => f.write_str(utf8_decode_lossy(b))
    Object(obj) => obj.render(f)
  }
}

///|
/// Formats a float like `{{ value }}` renders it.
fn format_f64_display(v : Double) -> String {
  if v.is_nan() {
    "NaN"
  } else if v.is_inf() {
    if v > 0.0 {
      "inf"
    } else {
      "-inf"
    }
  } else {
    let num = @rfmt.f64_display(v)
    if num.contains(".") {
      num
    } else {
      num + ".0"
    }
  }
}

///|
/// Formats the value like MiniJinja's `Debug` (a Python like repr).
pub fn Value::debug_string(self : Value, pretty? : Bool = false) -> String {
  let f = @rfmt.Formatter::new(alternate=pretty)
  self.fmt_debug(f)
  f.to_string()
}

///|
fn Value::fmt_debug(self : Value, f : @rfmt.Formatter) -> Unit {
  match self {
    Undefined(_) => f.write_str("undefined")
    Bool(b) => f.write_str(if b { "True" } else { "False" })
    U64(v) => f.write_str(v.to_string())
    I64(v) => f.write_str(v.to_string())
    F64(v) => f.write_str(@rfmt.f64_debug(v))
    NoneValue => f.write_str("None")
    Invalid(err) => f.write_str("<invalid value: \{err}>")
    I128(v) | U128(v) => f.write_str(v.to_string())
    Str(s, _) => f.write_str(python_string_repr(s))
    Bytes(b) => {
      let sb = StringBuilder()
      sb.write_string("b'")
      for byte in b {
        let c = byte.to_int()
        match c {
          0x22 => sb.write_char('"')
          0x09 => sb.write_string("\\t")
          0x0A => sb.write_string("\\n")
          0x0D => sb.write_string("\\r")
          0x27 => sb.write_string("\\'")
          0x5C => sb.write_string("\\\\")
          _ =>
            if c >= 0x20 && c < 0x7f {
              sb.write_char(c.unsafe_to_char())
            } else {
              sb.write_string("\\x")
              let hex = c.to_string(radix=16)
              if hex.length() < 2 {
                sb.write_char('0')
              }
              sb.write_string(hex)
            }
        }
      }
      sb.write_char('\'')
      f.write_str(sb.to_string())
    }
    Object(obj) => obj.render(f)
  }
}

///|
/// Formats a string like Python's `repr`.
fn python_string_repr(value : String) -> String {
  let quote = if value.contains("'") && !value.contains("\"") {
    '"'
  } else {
    '\''
  }
  let sb = StringBuilder()
  sb.write_char(quote)
  for ch in value {
    match ch {
      '\'' if quote == '\'' => sb.write_string("\\'")
      '"' if quote == '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => {
        let cp = ch.to_int()
        if is_control_char(cp) {
          if cp <= 0xff {
            let hex = cp.to_string(radix=16)
            sb.write_string("\\x")
            if hex.length() < 2 {
              sb.write_char('0')
            }
            sb.write_string(hex)
          } else {
            let hex = cp.to_string(radix=16)
            sb.write_string("\\u")
            for _ in hex.length()..<4 {
              sb.write_char('0')
            }
            sb.write_string(hex)
          }
        } else {
          sb.write_char(ch)
        }
      }
    }
  }
  sb.write_char(quote)
  sb.to_string()
}

///|
/// Port of Rust's `char::is_control` (general category Cc).
fn is_control_char(cp : Int) -> Bool {
  cp < 0x20 || (cp >= 0x7f && cp < 0xa0)
}

///|
/// Decodes UTF-8 bytes, returning `None` for invalid input.
fn utf8_decode_strict(b : Bytes) -> String? {
  try @utf8.decode(b) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
}

///|
/// Decodes UTF-8 bytes replacing invalid sequences with U+FFFD.
fn utf8_decode_lossy(b : Bytes) -> String {
  @utf8.decode_lossy(b)
}
