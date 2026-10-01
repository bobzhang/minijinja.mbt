///|
let loop_object_keys : Array[String] = [
  "index0", "index", "length", "revindex", "revindex0", "first", "last", "depth",
  "depth0", "previtem", "nextitem",
]

///|
/// Wraps the loop iterator so that the previous and next items can be
/// looked at (`loop.previtem` and `loop.nextitem`).
priv struct AdjacentLoopItemIter {
  mut prev_item : Value?
  mut current_item : Value?
  mut next_item : Value?
  iter : Iter[Value]
}

///|
fn AdjacentLoopItemIter::next(self : AdjacentLoopItemIter) -> Value? {
  self.prev_item = self.current_item
  self.current_item = match self.next_item {
    Some(v) => {
      self.next_item = None
      Some(v)
    }
    None => self.iter.next()
  }
  self.current_item
}

///|
fn AdjacentLoopItemIter::prev_item(self : AdjacentLoopItemIter) -> Value {
  self.prev_item.unwrap_or(Value::undefined())
}

///|
fn AdjacentLoopItemIter::peek_next_item(self : AdjacentLoopItemIter) -> Value {
  match self.next_item {
    Some(v) => v
    None => {
      self.next_item = self.iter.next()
      self.next_item.unwrap_or(Value::undefined())
    }
  }
}

///|
/// The object behind the `loop` variable.
struct LoopObject {
  len : Int?
  /// The current index, `-1` before the first iteration.
  mut idx : Int
  depth : Int
  mut last_changed_value : Array[Value]?
  recurse_jump_target : Int?
  iter : AdjacentLoopItemIter
}

///|
fn LoopObject::get_value_by_str(self : LoopObject, key : String) -> Value? {
  let idx = self.idx
  // if we never iterated, then all attributes are undefined.
  if idx < 0 {
    return Some(Value::undefined())
  }
  match key {
    "index" => Some(Value::from_int(idx + 1))
    "index0" => Some(Value::from_int(idx))
    "length" =>
      Some(
        match self.len {
          Some(len) => Value::from_int(len)
          None => Value::undefined()
        },
      )
    "revindex" =>
      Some(
        match self.len {
          Some(len) => Value::from_int(if len > idx { len - idx } else { 0 })
          None => Value::undefined()
        },
      )
    "revindex0" =>
      Some(
        match self.len {
          Some(len) =>
            Value::from_int(if len - idx - 1 > 0 { len - idx - 1 } else { 0 })
          None => Value::undefined()
        },
      )
    "first" => Some(Value::from_bool(idx == 0))
    "last" =>
      Some(
        match self.len {
          Some(len) => Value::from_bool(len == 0 || idx == len - 1)
          None => Value::from_bool(false)
        },
      )
    "depth" => Some(Value::from_int(self.depth + 1))
    "depth0" => Some(Value::from_int(self.depth))
    "previtem" => Some(self.iter.prev_item())
    "nextitem" => Some(self.iter.peek_next_item())
    _ => None
  }
}

///|
fn LoopObject::call_method(
  self : LoopObject,
  name : String,
  args : Array[Value],
) -> Value raise TemplateError {
  match name {
    "changed" => {
      let value = args.copy()
      let changed = match self.last_changed_value {
        Some(last) => last != value
        None => true
      }
      if changed {
        self.last_changed_value = Some(value)
        Value::from_bool(true)
      } else {
        Value::from_bool(false)
      }
    }
    "cycle" =>
      if args.is_empty() {
        Value::undefined()
      } else {
        let idx = if self.idx < 0 { 0 } else { self.idx }
        args[idx % args.length()]
      }
    _ => raise TemplateError::from_kind(UnknownMethod)
  }
}

///|
fn LoopObject::render(self : LoopObject) -> String {
  let idx = if self.idx < 0 {
    "18446744073709551615"
  } else {
    self.idx.to_string()
  }
  let len = match self.len {
    Some(len) => len.to_string()
    None => "?"
  }
  "<loop \{idx}/\{len}>"
}

///|
/// Per frame loop state.
priv struct LoopState {
  with_loop_var : Bool
  /// If we're popping the frame, do we want to jump somewhere?  The first
  /// item is the target jump instruction, the second tells us if we need to
  /// end capturing.
  mut current_recursion_jump : (Int, Bool)?
  object : LoopObject
  value : Value
}

///|
fn LoopState::new(
  iter : Iter[Value],
  depth : Int,
  with_loop_var : Bool,
  recurse_jump_target : Int?,
  current_recursion_jump : (Int, Bool)?,
) -> LoopState {
  let object = {
    len: iter.size_hint(),
    idx: -1,
    depth,
    last_changed_value: None,
    recurse_jump_target,
    iter: { prev_item: None, current_item: None, next_item: None, iter, },
  }
  {
    with_loop_var,
    current_recursion_jump,
    object,
    value: Value::Object(DynObject::new(Loop(object))),
  }
}

///|
fn LoopState::did_not_iterate(self : LoopState) -> Bool {
  self.object.idx == 0
}

///|
fn LoopState::next(self : LoopState) -> Value? {
  self.object.idx += 1
  self.object.iter.next()
}
