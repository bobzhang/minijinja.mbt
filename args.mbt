///|
fn unexpected_kwargs() -> TemplateError {
  TemplateError::new(TooManyArguments, "unexpected keyword arguments")
}

///|
/// Keyword arguments passed to a filter, test or function.
///
/// Keyword arguments are represented as a special map value which is passed
/// as the last argument.  Use [`Args::kwargs`] to extract them, then fetch
/// individual arguments with [`Kwargs::get`] (or the typed getters) and
/// finally call [`Kwargs::assert_all_used`] so that unknown keyword
/// arguments are reported.
pub struct Kwargs {
  priv values : Map[Value, Value]
  priv used : Set[String]
}

///|
/// Creates keyword arguments from name/value pairs.
pub fn Kwargs::from_pairs(pairs : Array[(String, Value)]) -> Kwargs {
  let values : Map[Value, Value] = Map([])
  for pair in pairs {
    values[Value::from_string(pair.0)] = pair.1
  }
  { values, used: Set([]), }
}

///|
/// Converts the keyword arguments back into a value.
pub fn Kwargs::to_value(self : Kwargs) -> Value {
  Value::from_kwargs_map(self.values)
}

///|
/// Given a value, extracts the kwargs if there are any.
fn Kwargs::extract(value : Value) -> Kwargs? {
  match value {
    Object({ inner: Kwargs(values), .. }) => Some({ values, used: Set([]), })
    _ => None
  }
}

///|
/// Returns the raw value of a keyword argument without marking it used.
pub fn Kwargs::peek(self : Kwargs, key : String) -> Value? {
  self.values.get(Value::from_string(key))
}

///|
/// Gets a required keyword argument (any value) and marks it as used.
pub fn Kwargs::get(self : Kwargs, key : String) -> Value raise TemplateError {
  match self.values.get(Value::from_string(key)) {
    Some(v) => {
      if v.is_kwargs() {
        raise unexpected_kwargs()
      }
      self.used.add(key)
      v
    }
    None =>
      raise TemplateError::new(
        MissingArgument,
        "missing keyword argument '\{key}'",
      )
  }
}

///|
/// Gets an optional keyword argument and marks it as used.  Undefined and
/// none values are treated as missing (like `Option<Value>`).
pub fn Kwargs::get_opt(
  self : Kwargs,
  key : String,
) -> Value? raise TemplateError {
  let rv = self.peek_opt(key)
  self.used.add(key)
  rv
}

///|
fn Kwargs::peek_opt(self : Kwargs, key : String) -> Value? raise TemplateError {
  match self.values.get(Value::from_string(key)) {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => {
      if v.is_kwargs() {
        raise unexpected_kwargs()
      }
      Some(v)
    }
    None => None
  }
}

///|
/// Converts an optional keyword argument and marks it used only if the
/// conversion succeeded (like MiniJinja's `Kwargs::get`).
fn[T] Kwargs::get_converted(
  self : Kwargs,
  key : String,
  convert : (Value) -> T raise TemplateError,
) -> T? raise TemplateError {
  let rv = match self.peek_opt(key) {
    Some(v) => Some(convert(v))
    None => None
  }
  self.used.add(key)
  rv
}

///|
/// Gets an optional boolean keyword argument.
pub fn Kwargs::get_bool(
  self : Kwargs,
  key : String,
) -> Bool? raise TemplateError {
  self.get_converted(key, value_to_bool)
}

///|
/// Gets an optional integer keyword argument.
pub fn Kwargs::get_int(
  self : Kwargs,
  key : String,
) -> Int64? raise TemplateError {
  self.get_converted(key, value_to_i64)
}

///|
/// Gets an optional non-negative integer keyword argument.
pub fn Kwargs::get_usize(
  self : Kwargs,
  key : String,
) -> Int? raise TemplateError {
  self.get_converted(key, value_to_usize)
}

///|
/// Gets an optional string keyword argument (strict: must be a string).
pub fn Kwargs::get_str(
  self : Kwargs,
  key : String,
) -> String? raise TemplateError {
  self.get_converted(key, value_to_str)
}

///|
/// Checks if a keyword argument exists.
pub fn Kwargs::has(self : Kwargs, key : String) -> Bool {
  self.values.contains(Value::from_string(key))
}

///|
/// Returns the names of all passed keyword arguments.
pub fn Kwargs::args(self : Kwargs) -> Array[String] {
  let rv = []
  for k, _ in self.values {
    if k.as_str() is Some(s) {
      rv.push(s)
    }
  }
  rv
}

///|
/// Asserts that all kwargs were used.
pub fn Kwargs::assert_all_used(self : Kwargs) -> Unit raise TemplateError {
  for key, _ in self.values {
    match key.as_str() {
      Some(key) =>
        if !self.used.contains(key) {
          raise TemplateError::new(
            TooManyArguments,
            "unknown keyword argument '\{key}'",
          )
        }
      None =>
        raise TemplateError::new(
          InvalidOperation,
          "non string keys passed to kwargs",
        )
    }
  }
}

///|
/// Port of `bool::try_from(Value)`.
fn value_to_bool(v : Value) -> Bool raise TemplateError {
  match v {
    Bool(b) => b
    _ => raise unsupported_conversion(v.kind(), "bool")
  }
}

///|
/// Port of `i64::try_from(Value)`.
fn value_to_i64(v : Value) -> Int64 raise TemplateError {
  match v.to_i128() {
    Some(i) if in_i64(i) => i.to_int64()
    _ => raise unsupported_conversion(v.kind(), "i64")
  }
}

///|
/// Port of `usize::try_from(Value)` (bounded to `Int`).
fn value_to_usize(v : Value) -> Int raise TemplateError {
  match v.to_i128() {
    Some(i) if i >= 0N && i <= 0x7FFFFFFFN => i.to_int()
    _ => raise unsupported_conversion(v.kind(), "usize")
  }
}

///|
/// Port of `i32::try_from(Value)`.
fn value_to_i32(v : Value) -> Int raise TemplateError {
  match v.to_i128() {
    Some(i) if i >= -0x80000000N && i <= 0x7FFFFFFFN => i.to_int()
    _ => raise unsupported_conversion(v.kind(), "i32")
  }
}

///|
/// Port of `f64::try_from(Value)`.
fn value_to_f64(v : Value) -> Double raise TemplateError {
  match v {
    U64(x) => x.to_double()
    I64(x) => x.to_double()
    U128(x) | I128(x) => bigint_to_f64(x)
    F64(x) => x
    _ => raise unsupported_conversion(v.kind(), "f64")
  }
}

///|
/// Port of `<&str as ArgType>` (the value must be a string).
fn value_to_str(v : Value) -> String raise TemplateError {
  match v.as_str() {
    Some(s) => s
    None => raise TemplateError::new(InvalidOperation, "value is not a string")
  }
}

///|
/// Port of `value_to_string_cow` / `String` conversion.
fn value_to_string(v : Value) -> String raise TemplateError {
  match v {
    Str(s, _) => s
    _ => {
      if v.is_kwargs() {
        raise TemplateError::new(
          InvalidOperation,
          "cannot convert kwargs to string",
        )
      }
      v.to_string()
    }
  }
}

///|
/// A string coerced from a value together with its safety provenance.
pub struct StringInput {
  priv value : String
  priv safe : Bool
}

///|
/// Coerces a value into a string while retaining its safety provenance.
pub fn StringInput::new(
  state : State,
  value : Value,
) -> StringInput raise TemplateError {
  state.undefined_behavior().assert_value_not_undefined(value)
  { value: value_to_string(value), safe: value.is_safe(), }
}

///|
/// Returns the coerced string.
pub fn StringInput::as_str(self : StringInput) -> String {
  self.value
}

///|
/// Returns `true` if the original value was marked safe.
pub fn StringInput::is_safe(self : StringInput) -> Bool {
  self.safe
}

///|
/// Formats the string for insertion into a safe result.  Safe inputs are
/// returned unchanged, other inputs are escaped like the `escape` filter.
pub fn StringInput::format(
  self : StringInput,
  state : State,
) -> String raise TemplateError {
  if self.safe {
    self.value
  } else {
    filter_escape(state, Value::from_string(self.value)).to_string()
  }
}

///|
/// Wraps a derived string while preserving the input's safety.
pub fn StringInput::preserve_safety(
  self : StringInput,
  value : String,
) -> Value {
  if self.safe {
    Value::from_safe_string(value)
  } else {
    Value::from_string(value)
  }
}

///|
/// A cursor over the arguments passed to a filter, test or function.
///
/// The conversion rules follow MiniJinja's argument conversion: missing
/// required arguments raise `MissingArgument`, leftover arguments raise
/// `TooManyArguments` in [`Args::finish`], optional arguments treat
/// `undefined` and `none` as missing, and keyword arguments (if accepted)
/// have to be extracted first with [`Args::kwargs`].
pub struct Args {
  priv state : State
  priv values : Array[Value]
  priv mut end : Int
  priv mut idx : Int
}

///|
/// Creates an argument cursor.
pub fn Args::new(state : State, values : Array[Value]) -> Args {
  { state, values, end: values.length(), idx: 0, }
}

///|
/// Extracts the trailing keyword arguments.  Must be called before any
/// positional argument is read.
pub fn Args::kwargs(self : Args) -> Kwargs {
  if self.end > 0 && Kwargs::extract(self.values[self.end - 1]) is Some(kw) {
    self.end -= 1
    kw
  } else {
    { values: Map([]), used: Set([]), }
  }
}

///|
fn Args::next_raw(self : Args) -> Value? {
  let rv = if self.idx < self.end { Some(self.values[self.idx]) } else { None }
  self.idx += 1
  rv
}

///|
/// Returns `true` if there are positional arguments left.
pub fn Args::has_more(self : Args) -> Bool {
  self.idx < self.end
}

///|
/// A required argument of any type (keyword arguments are rejected).
pub fn Args::value(self : Args) -> Value raise TemplateError {
  match self.next_raw() {
    Some(v) => {
      if v.is_kwargs() {
        raise unexpected_kwargs()
      }
      v
    }
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional argument of any type.
pub fn Args::opt_value(self : Args) -> Value? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => {
      if v.is_kwargs() {
        raise unexpected_kwargs()
      }
      Some(v)
    }
    None => None
  }
}

///|
/// A required argument that may also be keyword arguments.
pub fn Args::value_or_kwargs(self : Args) -> Value raise TemplateError {
  match self.next_raw() {
    Some(v) => v
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// A required string argument (the value is converted to a string).
pub fn Args::string(self : Args) -> String raise TemplateError {
  match self.next_raw() {
    Some(v) => {
      self.state.undefined_behavior().assert_value_not_undefined(v)
      value_to_string(v)
    }
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional string argument (the value is converted to a string).
pub fn Args::opt_string(self : Args) -> String? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_string(v))
    None => None
  }
}

///|
/// A required strict string argument (must be a string value).
pub fn Args::str(self : Args) -> String raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_str(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional strict string argument.
pub fn Args::opt_str(self : Args) -> String? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_str(v))
    None => None
  }
}

///|
/// A required string argument that retains safety provenance.
pub fn Args::string_input(self : Args) -> StringInput raise TemplateError {
  match self.next_raw() {
    Some(v) => {
      self.state.undefined_behavior().assert_value_not_undefined(v)
      { value: value_to_string(v), safe: v.is_safe(), }
    }
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional string argument that retains safety provenance.
pub fn Args::opt_string_input(self : Args) -> StringInput? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some({ value: value_to_string(v), safe: v.is_safe(), })
    None => None
  }
}

///|
/// A required 64 bit integer argument.
pub fn Args::i64(self : Args) -> Int64 raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_i64(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional 64 bit integer argument.
pub fn Args::opt_i64(self : Args) -> Int64? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_i64(v))
    None => None
  }
}

///|
/// A required 32 bit integer argument.
pub fn Args::i32(self : Args) -> Int raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_i32(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional 32 bit integer argument.
pub fn Args::opt_i32(self : Args) -> Int? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_i32(v))
    None => None
  }
}

///|
/// A required non-negative integer argument.
pub fn Args::usize(self : Args) -> Int raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_usize(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional non-negative integer argument.
pub fn Args::opt_usize(self : Args) -> Int? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_usize(v))
    None => None
  }
}

///|
/// A required boolean argument.
pub fn Args::bool(self : Args) -> Bool raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_bool(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// An optional boolean argument.
pub fn Args::opt_bool(self : Args) -> Bool? raise TemplateError {
  match self.next_raw() {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(value_to_bool(v))
    None => None
  }
}

///|
/// A required float argument.
pub fn Args::f64(self : Args) -> Double raise TemplateError {
  match self.next_raw() {
    Some(v) => value_to_f64(v)
    None => raise TemplateError::from_kind(MissingArgument)
  }
}

///|
/// All remaining positional arguments (keyword arguments are rejected).
pub fn Args::rest(self : Args) -> Array[Value] raise TemplateError {
  let rv = []
  while self.idx < self.end {
    let v = self.values[self.idx]
    if v.is_kwargs() {
      raise unexpected_kwargs()
    }
    rv.push(v)
    self.idx += 1
  }
  rv
}

///|
/// All remaining arguments including keyword arguments.
pub fn Args::rest_with_kwargs(self : Args) -> Array[Value] {
  let rv = []
  while self.idx < self.end {
    rv.push(self.values[self.idx])
    self.idx += 1
  }
  rv
}

///|
/// Ensures that all arguments were consumed.
pub fn Args::finish(self : Args) -> Unit raise TemplateError {
  if self.idx < self.end {
    raise TemplateError::from_kind(TooManyArguments)
  }
}
