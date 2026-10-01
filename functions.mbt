///|
fn func_range(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let lower = a.i64()
  let upper = a.opt_i64()
  let step = a.opt_i64()
  a.finish()
  let (start, end) = match upper {
    Some(upper) => (lower, upper)
    None => (0L, lower)
  }
  let step = step.unwrap_or(1L)
  if step == 0L {
    raise TemplateError::new(
      InvalidOperation,
      "cannot create range with step of 0",
    )
  }
  // compute the length with unsigned arithmetic so that large ranges do
  // not overflow
  let len : UInt64 = if step > 0L {
    if end > start {
      let distance = (end - start).reinterpret_as_uint64()
      let step = step.reinterpret_as_uint64()
      distance / step + (if distance % step != 0UL { 1UL } else { 0UL })
    } else {
      0UL
    }
  } else if start <= end {
    0UL
  } else {
    let distance = (start - end).reinterpret_as_uint64()
    let step = (-step).reinterpret_as_uint64()
    distance / step + (if distance % step != 0UL { 1UL } else { 0UL })
  }
  if len > 100000UL {
    raise TemplateError::new(InvalidOperation, "range has too many elements")
  }
  let len = len.to_int()
  Value::make_iterable(() => {
    let mut i = 0
    Iter::new(
      () => {
        if i < len {
          let rv = start + i.to_int64() * step
          i += 1
          Some(Value::from_int64(rv))
        } else {
          None
        }
      },
      size_hint=len,
    )
  })
}

///|
fn func_dict(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let update_with = a.kwargs()
  let value = a.opt_value()
  a.finish()
  let rv : Map[Value, Value] = Map([])
  match value {
    None => ()
    Some(Undefined(_)) => ()
    Some(Object(obj)) if obj.repr() is Map =>
      if obj.try_iter_pairs() is Some(iter) {
        for pair in iter {
          rv[pair.0] = pair.1
        }
      }
    Some(_) => raise TemplateError::from_kind(InvalidOperation)
  }
  for k, v in update_with.values {
    rv[k] = v
  }
  Value::from_map(rv)
}

///|
fn func_debug(state : State, args : Array[Value]) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let args = a.rest()
  let f = @rfmt.Formatter::new(alternate=true)
  if args.is_empty() {
    state.fmt_debug(f)
  } else if args.length() == 1 {
    args[0].fmt_debug(f)
  } else {
    let l = f.debug_list()
    for v in args {
      l.entry(f => v.fmt_debug(f)) |> ignore
    }
    l.finish()
  }
  Value::from_string(f.to_string())
}

///|
fn func_namespace(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let defaults = match a.next_raw() {
    Some(v) if !(v.is_undefined() || v.is_none()) => Some(v)
    _ => None
  }
  a.finish()
  let ns : Map[String, Value] = Map([])
  if defaults is Some(defaults) {
    match defaults {
      Object(obj) if obj.repr() is Map =>
        match obj.try_iter_pairs() {
          Some(pairs) =>
            for pair in pairs {
              if pair.0.as_str() is Some(key) {
                ns[key] = pair.1
              }
            }
          None =>
            raise TemplateError::new(
              InvalidOperation,
              "expected object or keyword arguments, got \{defaults.kind()}",
            )
        }
      _ =>
        raise TemplateError::new(
          InvalidOperation,
          "expected object or keyword arguments, got \{defaults.kind()}",
        )
    }
  }
  Object(DynObject::new(Namespace(ns)))
}

///|
fn register_builtin_globals(rv : Map[String, Value]) -> Unit {
  let b = "minijinja::functions::builtins::"
  rv["range"] = Value::from_function(b + "range", func_range)
  rv["dict"] = Value::from_function(b + "dict", func_dict)
  rv["debug"] = Value::from_function(b + "debug", func_debug)
  rv["namespace"] = Value::from_function(b + "namespace", func_namespace)
}
