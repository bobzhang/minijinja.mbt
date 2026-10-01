///|
/// The cost of a single macro call against the stack limit.
let macro_recursion_cost = 4

///|
/// The cost of a single include against the stack limit.
let include_recursion_cost = 10

///|
priv struct MacroObject {
  name : Value
  arg_spec : Array[Value]
  instructions : Instructions
  offset : Int
  state_id : Int
  closure : Closure?
  caller_reference : Bool
}

///|
fn MacroObject::prepare_args(
  self : MacroObject,
  args : Array[Value],
) -> (Array[Value], Value?) raise TemplateError {
  let (args, kwargs) = match args.last() {
    Some(Object({ inner: Kwargs(kw), .. })) =>
      (args[0:args.length() - 1].to_array(), Some(kw))
    _ => (args, None)
  }
  if args.length() > self.arg_spec.length() {
    raise TemplateError::from_kind(TooManyArguments)
  }
  let kwargs_used : Set[String] = Set([])
  let arg_values = []
  for idx, name in self.arg_spec {
    guard name.as_str() is Some(name) else {
      arg_values.push(Value::undefined())
      continue
    }
    let kwarg = match kwargs {
      Some(kw) => kw.get(Value::from_string(name))
      None => None
    }
    match (args.get(idx), kwarg) {
      (Some(_), Some(_)) =>
        raise TemplateError::new(
          TooManyArguments,
          "duplicate argument `\{name}`",
        )
      (Some(arg), None) => arg_values.push(arg)
      (None, Some(kwarg)) => {
        kwargs_used.add(name)
        arg_values.push(kwarg)
      }
      (None, None) => arg_values.push(Value::undefined())
    }
  }
  let caller = if self.caller_reference {
    kwargs_used.add("caller")
    Some(
      match kwargs {
        Some(kw) =>
          kw.get(Value::from_string("caller")).unwrap_or(Value::undefined())
        None => Value::undefined()
      },
    )
  } else {
    None
  }
  if kwargs is Some(kw) {
    for key, _ in kw {
      if key.as_str() is Some(key) && !kwargs_used.contains(key) {
        raise TemplateError::new(
          TooManyArguments,
          "unknown keyword argument `\{key}`",
        )
      }
    }
  }
  (arg_values, caller)
}

///|
impl Object for MacroObject with fn enumerate(_self) {
  Str(["name", "arguments", "caller"])
}

///|
impl Object for MacroObject with fn get_value(self, key) {
  match key.as_str() {
    Some("name") => Some(self.name)
    Some("arguments") => Some(Value::from_array(self.arg_spec.copy()))
    Some("caller") => Some(Value::from_bool(self.caller_reference))
    _ => None
  }
}

///|
impl Object for MacroObject with fn call(self, state, args) {
  if state.id != self.state_id {
    raise TemplateError::new(
      InvalidOperation,
      "cannot call this macro. template state went away.",
    )
  }
  let (arg_values, caller) = self.prepare_args(args)
  let buf = StringBuilder()
  eval_macro(
    state,
    self.instructions,
    self.offset,
    Output::new(buf),
    self.closure,
    caller,
    arg_values,
  )
  |> ignore
  if state.auto_escape is NoEscape {
    Value::from_string(buf.to_string())
  } else {
    Value::from_safe_string(buf.to_string())
  }
}

///|
impl Object for MacroObject with fn render(self) {
  Some("<macro \{self.name}>")
}

///|
/// The object behind `{% import ... as module %}`.
priv struct ModuleObject {
  values : Map[Value, Value]
  captured : Value
}

///|
impl Object for ModuleObject with fn get_value(self, key) {
  self.values.get(key)
}

///|
impl Object for ModuleObject with fn enumerate(self) {
  Values(self.values.keys().to_array())
}

///|
impl Object for ModuleObject with fn render(self) {
  Some(self.captured.to_string())
}
