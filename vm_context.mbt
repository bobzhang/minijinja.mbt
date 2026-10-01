///|
/// A closure: values captured by macros declared in a frame.
priv struct Closure {
  values : Map[String, Value]
}

///|
priv struct Frame {
  locals : Map[String, Value]
  ctx : Value
  mut current_loop : LoopState?
  // normally a frame does not carry a closure, but it can when a macro is
  // declared.  Once that happens, all writes to the frames locals are also
  // duplicated into the closure.  Macros declared on that level, then share
  // the closure object to enclose the parent values.  This emulates the
  // behavior of closures in Jinja2.
  mut closure : Closure?
  mut closure_context : Closure?
}

///|
fn Frame::new(ctx : Value) -> Frame {
  {
    locals: Map::new(),
    ctx,
    current_loop: None,
    closure: None,
    closure_context: None,
  }
}

///|
fn Frame::default() -> Frame {
  Frame::new(Value::undefined())
}

///|
priv struct Stack {
  values : Array[Value]
}

///|
fn Stack::new() -> Stack {
  { values: [], }
}

///|
fn Stack::push(self : Stack, v : Value) -> Unit {
  self.values.push(v)
}

///|
fn Stack::pop(self : Stack) -> Value {
  match self.values.pop() {
    Some(v) => v
    None => abort("stack underflow")
  }
}

///|
fn Stack::try_pop(self : Stack) -> Value? {
  self.values.pop()
}

///|
fn Stack::peek(self : Stack) -> Value {
  self.values[self.values.length() - 1]
}

///|
fn Stack::reverse_top(self : Stack, n : Int) -> Unit {
  let len = self.values.length()
  let mut i = len - n
  let mut j = len - 1
  while i < j {
    let tmp = self.values[i]
    self.values[i] = self.values[j]
    self.values[j] = tmp
    i += 1
    j -= 1
  }
}

///|
/// Returns a copy of the top `n` (or popped count) values as call args.
fn Stack::get_call_args(self : Stack, n : Int?) -> Array[Value] {
  let n = match n {
    Some(n) => n
    None => self.pop().as_usize().unwrap_or(0)
  }
  let len = self.values.length()
  self.values[len - n:len].to_array()
}

///|
fn Stack::drop_top(self : Stack, n : Int) -> Unit {
  let len = self.values.length()
  self.values.truncate(len - n)
}

///|
priv struct Context {
  env : Environment
  stack : Array[Frame]
  mut outer_stack_depth : Int
  recursion_limit : Int
}

///|
fn Context::new(env : Environment) -> Context {
  {
    env,
    stack: [],
    outer_stack_depth: 0,
    recursion_limit: env.recursion_limit,
  }
}

///|
fn Context::new_with_frame(env : Environment, frame : Frame) -> Context {
  let rv = Context::new(env)
  rv.stack.push(frame)
  rv
}

///|
fn Context::top(self : Context) -> Frame {
  self.stack[self.stack.length() - 1]
}

///|
/// Stores a variable in the context.
fn Context::store(self : Context, key : String, value : Value) -> Unit {
  let top = self.top()
  if top.closure is Some(closure) {
    closure.values[key] = value
  }
  top.locals[key] = value
}

///|
/// Adds a value to a closure if missing.
fn Context::enclose(self : Context, key : String) -> Unit {
  guard self.top().closure is Some(closure) else { return }
  if !closure.values.contains(key) {
    let value = self.load(key).unwrap_or(Value::undefined())
    closure.values[key] = value
  }
}

///|
fn Context::closure(self : Context) -> Closure? {
  self.top().closure
}

///|
fn Context::take_closure(self : Context) -> Closure? {
  let top = self.top()
  let rv = top.closure
  top.closure = None
  rv
}

///|
fn Context::reset_closure(self : Context, closure : Closure?) -> Unit {
  self.top().closure = closure
}

///|
/// Return the base context value
fn Context::clone_base(self : Context) -> Value {
  match self.stack.get(0) {
    Some(frame) => frame.ctx
    None => Value::undefined()
  }
}

///|
/// Looks up a variable in the context.
fn Context::load(self : Context, key : String) -> Value? {
  for i = self.stack.length() - 1; i >= 0; i = i - 1 {
    let frame = self.stack[i]
    // look at locals first
    if frame.locals.get(key) is Some(value) {
      return Some(value)
    }
    // if we are a loop, check if we are looking up the special loop var.
    if frame.current_loop is Some(l) && l.with_loop_var && key == "loop" {
      return Some(l.value)
    }
    if frame.closure_context is Some(closure) &&
      closure.values.get(key) is Some(value) {
      return Some(value)
    }
    // perform a fast lookup.  This one will not produce errors if the
    // context is undefined or of the wrong type.
    if frame.ctx.get_attr_fast(key) is Some(rv) {
      return Some(rv)
    }
  }
  self.env.get_global(key)
}

///|
/// Returns all known variables.
fn Context::known_variables(self : Context, with_globals : Bool) -> Set[String] {
  let seen : Set[String] = Set([])
  for i = self.stack.length() - 1; i >= 0; i = i - 1 {
    let frame = self.stack[i]
    for key, _ in frame.locals {
      seen.add(key)
    }
    if frame.current_loop is Some(l) && l.with_loop_var {
      seen.add("loop")
    }
    if frame.closure_context is Some(closure) {
      for key, _ in closure.values {
        seen.add(key)
      }
    }
    let iter = frame.ctx.try_iter() catch { _ => continue }
    for key in iter {
      if key.as_str() is Some(str_key) && !seen.contains(str_key) {
        let ok = frame.ctx.get_item(key) catch { _ => continue }
        ignore(ok)
        seen.add(str_key)
      }
    }
  }
  if with_globals {
    for key, _ in self.env.globals {
      seen.add(key)
    }
  }
  seen
}

///|
/// Pushes a new layer.
fn Context::push_frame(
  self : Context,
  frame : Frame,
) -> Unit raise TemplateError {
  self.stack.push(frame)
  self.check_depth() catch {
    err => {
      self.stack.pop() |> ignore
      raise err
    }
  }
}

///|
/// Pops the topmost layer.
fn Context::pop_frame(self : Context) -> Frame {
  match self.stack.pop() {
    Some(f) => f
    None => abort("empty frame stack")
  }
}

///|
/// Returns the root locals (exports)
fn Context::exports(self : Context) -> Map[String, Value] {
  self.stack[0].locals
}

///|
/// Returns the current locals mutably.
fn Context::current_locals(self : Context) -> Map[String, Value] {
  self.top().locals
}

///|
/// Returns the current innermost loop state.
fn Context::current_loop(self : Context) -> LoopState? {
  for i = self.stack.length() - 1; i >= 0; i = i - 1 {
    if self.stack[i].current_loop is Some(l) {
      return Some(l)
    }
  }
  None
}

///|
/// Advances the innermost loop and returns the next item.
fn Context::next_loop_item(self : Context) -> Value? {
  for i = self.stack.length() - 1; i >= 0; i = i - 1 {
    let frame = self.stack[i]
    if frame.current_loop is Some(l) {
      let item = l.next()
      if item is Some(_) {
        frame.locals.clear()
      }
      return item
    }
  }
  None
}

///|
fn Context::stack_depth(self : Context) -> Int {
  self.stack.length()
}

///|
fn Context::restore_stack_depth(self : Context, depth : Int) -> Unit {
  if self.stack.length() > depth {
    self.stack.truncate(depth)
  }
}

///|
/// The real depth of the context.
fn Context::depth(self : Context) -> Int {
  self.outer_stack_depth + self.stack.length()
}

///|
/// Increase the stack depth.
fn Context::incr_depth(self : Context, delta : Int) -> Unit raise TemplateError {
  self.outer_stack_depth += delta
  self.check_depth() catch {
    err => {
      self.outer_stack_depth -= delta
      raise err
    }
  }
}

///|
/// Decrease the stack depth.
fn Context::decr_depth(self : Context, delta : Int) -> Unit {
  self.outer_stack_depth -= delta
}

///|
fn Context::check_depth(self : Context) -> Unit raise TemplateError {
  if self.depth() > self.recursion_limit {
    raise TemplateError::new(InvalidOperation, "recursion limit exceeded")
  }
}

///|
/// Formats the context like MiniJinja's `ContextDebug` (sorted variables).
fn Context::fmt_debug(self : Context, f : @rfmt.Formatter) -> Unit {
  let vars = self.known_variables(false).to_array()
  vars.sort_by((a, b) => compare_str(a, b))
  let m = f.debug_map()
  for key in vars {
    let value = self.load(key).unwrap_or(Value::undefined())
    m.entry(f => f.write_str(@rfmt.str_debug(key)), f => value.fmt_debug(f))
    |> ignore
  }
  m.finish()
}
