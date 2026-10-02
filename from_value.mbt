///|
/// Conversion from template values into MoonBit values.
///
/// This mirrors MiniJinja's `ArgType`: `from_value` receives `None` when the
/// argument is missing.  Implementations exist for the common primitive types,
/// `Value`, `Array[T]` and `T?` (where `undefined` and `none` map to `None`).
pub(open) trait FromValue {
  fn from_value(Value?) -> Self raise TemplateError
}

///|
fn missing_argument() -> TemplateError {
  TemplateError::from_kind(MissingArgument)
}

///|
pub impl FromValue for Value with fn from_value(v) {
  match v {
    Some(v) => {
      if v.is_kwargs() {
        raise unexpected_kwargs()
      }
      v
    }
    None => raise missing_argument()
  }
}

///|
pub impl FromValue for Bool with fn from_value(v) {
  match v {
    Some(v) => value_to_bool(v)
    None => raise missing_argument()
  }
}

///|
pub impl FromValue for Int with fn from_value(v) {
  match v {
    Some(v) => value_to_i32(v)
    None => raise missing_argument()
  }
}

///|
pub impl FromValue for Int64 with fn from_value(v) {
  match v {
    Some(v) => value_to_i64(v)
    None => raise missing_argument()
  }
}

///|
pub impl FromValue for UInt64 with fn from_value(v) {
  match v {
    Some(v) =>
      match v.as_uint64() {
        Some(u) => u
        None => raise unsupported_conversion(v.kind(), "u64")
      }
    None => raise missing_argument()
  }
}

///|
pub impl FromValue for Double with fn from_value(v) {
  match v {
    Some(v) => value_to_f64(v)
    None => raise missing_argument()
  }
}

///|
/// Strings are converted like MiniJinja's `String` argument type: any value
/// is stringified (keyword arguments are rejected).
pub impl FromValue for String with fn from_value(v) {
  match v {
    Some(v) => value_to_string(v)
    None => raise missing_argument()
  }
}

///|
pub impl[T : FromValue] FromValue for T? with fn from_value(v) {
  match v {
    Some(v) if v.is_undefined() || v.is_none() => None
    Some(v) => Some(T::from_value(Some(v)))
    None => None
  }
}

///|
/// Sequences and iterables are converted element by element.
pub impl[T : FromValue] FromValue for Array[T] with fn from_value(v) {
  match v {
    Some(Object(obj) as v) if obj.repr() is (Seq | Iterable) => {
      let rv = []
      for item in v.try_iter() {
        rv.push(T::from_value(Some(item)))
      }
      rv
    }
    Some(_) => raise TemplateError::new(InvalidOperation, "not iterable")
    None => []
  }
}

///|
/// Reads the next positional argument converted to `T`.
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::new()
///   env.add_function("add", (state, args) => {
///     let a = @minijinja.Args::new(state, args)
///     let x : Int = a.next()
///     let y : Int? = a.next()
///     a.finish()
///     @minijinja.Value::from_int(x + y.unwrap_or(1))
///   })
///   inspect(
///     env.render_str("{{ add(1) }} {{ add(1, 2) }}", @minijinja.Value::none()),
///     content="2 3",
///   )
/// }
/// ```
pub fn[T : FromValue] Args::next(self : Args) -> T raise TemplateError {
  T::from_value(self.next_raw())
}

///|
/// Reads a keyword argument converted to `T` and marks it used.  Missing
/// keyword arguments raise unless `T` is an option.
pub fn[T : FromValue] Kwargs::get_as(
  self : Kwargs,
  key : String,
) -> T raise TemplateError {
  let rv = T::from_value(self.values.get(Value::from_string(key))) catch {
    err => raise with_missing_kwarg_detail(err, key)
  }
  self.used.add(key)
  rv
}

///|
/// Converts a value into `T`.
pub fn[T : FromValue] Value::convert(self : Value) -> T raise TemplateError {
  T::from_value(Some(self))
}

///|
fn with_missing_kwarg_detail(
  err : TemplateError,
  key : String,
) -> TemplateError {
  if err.kind() == MissingArgument && err.detail() is None {
    err.set_detail("missing keyword argument '\{key}'")
  }
  err
}
