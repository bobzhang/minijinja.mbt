///|
fn test_value1(
  state : State,
  args : Array[Value],
  f : (Value) -> Bool,
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.value()
  a.finish()
  Value::from_bool(f(v))
}

///|
fn test_value2(
  state : State,
  args : Array[Value],
  f : (Value, Value) -> Bool,
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.value()
  let other = a.value()
  a.finish()
  Value::from_bool(f(v, other))
}

///|
fn test_is_odd(state : State, args : Array[Value]) -> Value raise TemplateError {
  test_value1(state, args, v => {
    match v.to_i128() {
      Some(x) => !(x % 2N).is_zero()
      None => false
    }
  })
}

///|
fn test_is_even(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  test_value1(state, args, v => {
    match v.to_i128() {
      Some(x) => (x % 2N).is_zero()
      None => false
    }
  })
}

///|
fn test_is_divisibleby(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  test_value2(state, args, (v, other) => {
    match coerce(v, other, false) {
      Some(Int(a, b)) => b != 0L && a % b == 0L
      Some(Big(a, b)) => !b.is_zero() && (a % b).is_zero()
      Some(F64(a, b)) => a % b == 0.0
      _ => false
    }
  })
}

///|
fn test_is_startingwith(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.string()
  let other = a.string()
  a.finish()
  Value::from_bool(v.has_prefix(other))
}

///|
fn test_is_endingwith(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let v = a.string()
  let other = a.string()
  a.finish()
  Value::from_bool(v.has_suffix(other))
}

///|
fn test_is_in(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let value = a.value()
  let other = a.value()
  a.finish()
  state.undefined_behavior().assert_iterable(other)
  let contained = value_contains(other, value) catch {
    _ => Value::from_bool(false)
  }
  Value::from_bool(contained.is_true())
}

///|
fn test_is_filter(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let name = a.str()
  a.finish()
  Value::from_bool(state.env().get_filter(name) is Some(_))
}

///|
fn test_is_test(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let name = a.str()
  a.finish()
  Value::from_bool(state.env().get_test(name) is Some(_))
}

///|
fn char_changes_case(ch : Char) -> Bool {
  @unicode.char_to_lower(ch) != ch.to_string() ||
  @unicode.char_to_upper(ch) != ch.to_string()
}

///|
fn is_lower_str(value : Value) -> Bool {
  guard value.as_str() is Some(name) else { return false }
  let mut has_cased = false
  for ch in name {
    if @unicode.is_uppercase(ch) ||
      (!@unicode.is_lowercase(ch) && char_changes_case(ch)) {
      return false
    }
    if @unicode.is_lowercase(ch) {
      has_cased = true
    }
  }
  has_cased
}

///|
fn is_upper_str(value : Value) -> Bool {
  guard value.as_str() is Some(name) else { return false }
  let mut has_cased = false
  for ch in name {
    if @unicode.is_lowercase(ch) ||
      (!@unicode.is_uppercase(ch) && char_changes_case(ch)) {
      return false
    }
    if @unicode.is_uppercase(ch) {
      has_cased = true
    }
  }
  has_cased
}

///|
fn is_sameas(value : Value, other : Value) -> Bool {
  match (value.as_object(), other.as_object()) {
    (Some(a), Some(b)) => a.is_same_object(b)
    (None, Some(_)) | (Some(_), None) => false
    (None, None) =>
      if value.kind() != other.kind() ||
        value.is_integer() != other.is_integer() {
        false
      } else {
        value == other
      }
  }
}

///|
fn register_builtin_tests(rv : Map[String, Value]) -> Unit {
  fn add1(
    rv : Map[String, Value],
    name : String,
    path : String,
    f : (Value) -> Bool,
  ) -> Unit {
    rv[name] = Value::from_function(path, (state, args) => {
      test_value1(state, args, f)
    })
  }

  fn add2(
    rv : Map[String, Value],
    names : Array[String],
    path : String,
    f : (Value, Value) -> Bool,
  ) -> Unit {
    let func = Value::from_function(path, (state, args) => {
      test_value2(state, args, f)
    })
    for name in names {
      rv[name] = func
    }
  }

  fn add(
    rv : Map[String, Value],
    name : String,
    path : String,
    f : NativeFunction,
  ) -> Unit {
    rv[name] = Value::from_function(path, f)
  }

  let t = "minijinja::tests::"
  let b = "minijinja::tests::builtins::"
  add1(rv, "undefined", t + "is_undefined", Value::is_undefined)
  add1(rv, "defined", t + "is_defined", v => !v.is_undefined())
  add1(rv, "none", t + "is_none", Value::is_none)
  let is_safe = Value::from_function(t + "is_safe", (state, args) => {
    test_value1(state, args, Value::is_safe)
  })
  rv["safe"] = is_safe
  rv["escaped"] = is_safe
  add1(rv, "boolean", b + "is_boolean", v => v.kind() == Bool)
  add(rv, "odd", b + "is_odd", test_is_odd)
  add(rv, "even", b + "is_even", test_is_even)
  add(rv, "divisibleby", b + "is_divisibleby", test_is_divisibleby)
  add1(rv, "number", b + "is_number", v => v.kind() is (Number | Bool))
  let is_integer = Value::from_function(b + "is_integer", (state, args) => {
    test_value1(state, args, Value::is_integer)
  })
  rv["integer"] = is_integer
  rv["int"] = is_integer
  add1(rv, "float", b + "is_float", v => v is F64(_))
  add1(rv, "string", b + "is_string", v => v.kind() == String)
  add1(rv, "sequence", b + "is_sequence", v => {
    v.is_undefined() || v.kind() == Seq
  })
  add1(rv, "iterable", b + "is_iterable", v => {
    let _ = v.try_iter() catch { _ => return false }
    true
  })
  add1(rv, "mapping", b + "is_mapping", v => v.kind() == Map)
  add(rv, "startingwith", b + "is_startingwith", test_is_startingwith)
  add(rv, "endingwith", b + "is_endingwith", test_is_endingwith)
  add1(rv, "lower", b + "is_lower", is_lower_str)
  add1(rv, "upper", b + "is_upper", is_upper_str)
  add2(rv, ["sameas"], b + "is_sameas", is_sameas)
  add2(rv, ["eq", "equalto", "=="], b + "is_eq", (a, b) => a == b)
  add2(rv, ["ne", "!="], b + "is_ne", (a, b) => a != b)
  add2(rv, ["lt", "lessthan", "<"], b + "is_lt", (a, b) => a.cmp(b) < 0)
  add2(rv, ["le", "<="], b + "is_le", (a, b) => a.cmp(b) <= 0)
  add2(rv, ["gt", "greaterthan", ">"], b + "is_gt", (a, b) => a.cmp(b) > 0)
  add2(rv, ["ge", ">="], b + "is_ge", (a, b) => a.cmp(b) >= 0)
  add(rv, "in", b + "is_in", test_is_in)
  add1(rv, "true", b + "is_true", v => v is Bool(true))
  add1(rv, "false", b + "is_false", v => v is Bool(false))
  add(rv, "filter", b + "is_filter", test_is_filter)
  add(rv, "test", b + "is_test", test_is_test)
}
