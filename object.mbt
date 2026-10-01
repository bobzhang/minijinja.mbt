///|
/// Defines the natural representation of an object.
///
/// An [`ObjectRepr`] is a reduced form of [`ValueKind`] which only contains
/// value types that can be represented by objects.
pub(all) enum ObjectRepr {
  /// An object that has no reasonable representation.  Plain objects are
  /// not enumerable and do not support item access.
  Plain
  /// Represents a map or object.
  Map
  /// Represents a sequence (eg: array/list).
  Seq
  /// Represents a non indexable, iterable object.
  Iterable
} derive(Eq, Compare, Debug)

///|
/// Enumerators help define iteration behavior for [`Object`]s.
///
/// When Jinja wants to know the length of an object, if it's empty or not or
/// if it wants to iterate over it, it will ask the object for an enumerator.
pub(all) enum Enumerator {
  /// Marks non enumerable objects.
  NonEnumerable
  /// The empty enumerator.  It yields no elements.
  Empty
  /// A slice of static strings (yielded as string values).
  Str(Array[String])
  /// A dynamic iterator over values.
  Iter(Iter[Value])
  /// A dynamic iterator over key/value pairs (for maps).
  KeyValueIter(Iter[(Value, Value)])
  /// Indicates sequential iteration from `0` to `n - 1` through `get_value`.
  Seq(Int)
  /// A vector of known values to iterate over.
  Values(Array[Value])
}

///|
fn Enumerator::query_len(self : Enumerator) -> Int? {
  match self {
    Empty => Some(0)
    Values(v) => Some(v.length())
    Str(v) => Some(v.length())
    Iter(i) => i.size_hint()
    KeyValueIter(i) => i.size_hint()
    Seq(n) => Some(n)
    NonEnumerable => None
  }
}

///|
/// A trait that represents a dynamic object.
///
/// Implement this trait for your own types to expose them to templates via
/// [`Value::from_object`].  Every method has a default implementation, so
/// only the relevant ones need to be provided.
///
/// * `repr` defaults to [`ObjectRepr::Map`].
/// * `get_value` defaults to `None` (undefined).
/// * `enumerate` defaults to an empty enumerator for maps, sequences and
///   iterables and to [`Enumerator::NonEnumerable`] for plain objects.
/// * `call` and `call_method` fail by default.
/// * `render` returns `None` to request the default rendering.
/// * `custom_cmp` returns `None` to use the default comparison.  When it is
///   implemented it is consulted for equality and ordering against any other
///   object (it should return `None` for objects it does not understand).
pub(open) trait Object {
  fn repr(Self) -> ObjectRepr = _
  fn get_value(Self, Value) -> Value? = _
  fn get_value_by_str(Self, String) -> Value? = _
  fn enumerate(Self) -> Enumerator = _
  fn enumerator_len(Self) -> Int? = _
  fn is_true(Self) -> Bool = _
  fn call(Self, State, Array[Value]) -> Value raise TemplateError = _
  fn call_method(Self, State, String, Array[Value]) -> Value raise TemplateError = _
  fn render(Self) -> String? = _
  fn custom_cmp(Self, Value) -> Int? = _
}

///|
impl Object with fn custom_cmp(_self, _other) {
  None
}

///|
impl Object with fn repr(_self) {
  Map
}

///|
impl Object with fn get_value(_self, _key) {
  None
}

///|
impl Object with fn get_value_by_str(self, key) {
  self.get_value(Value::from_string(key))
}

///|
impl Object with fn enumerate(self) {
  match self.repr() {
    Plain => NonEnumerable
    _ => Empty
  }
}

///|
impl Object with fn enumerator_len(self) {
  self.enumerate().query_len()
}

///|
impl Object with fn is_true(self) {
  self.enumerator_len() != Some(0)
}

///|
impl Object with fn call(_self, _state, _args) {
  raise TemplateError::new(InvalidOperation, "object is not callable")
}

///|
impl Object with fn call_method(_self, _state, _name, _args) {
  raise TemplateError::from_kind(UnknownMethod)
}

///|
impl Object with fn render(_self) {
  None
}

///|
priv struct MergeSeqObject {
  values : Array[Value]
  total_len : Int?
  repr : ObjectRepr
  depth : Int
}

///|
/// The built-in object implementations.  Objects the engine needs to
/// recognize (the equivalent of Rust's `downcast_ref`) get their own variant,
/// everything else goes through the [`Object`] trait.
priv enum ObjectImpl {
  Seq(Array[Value])
  Map(Map[Value, Value])
  Tuple(Array[Value])
  Kwargs(Map[Value, Value])
  Namespace(Map[String, Value])
  MergeSeq(MergeSeqObject)
  Loop(LoopObject)
  ClosureRef(Closure)
  /// The `(grouper, list)` tuples produced by `groupby`
  Group(Value, Array[Value])
  Custom(&Object)
}

///|
/// A type erased object.  Values hold objects through this handle which
/// carries a stable identity.
pub struct DynObject {
  priv id : Int
  priv inner : ObjectImpl
}

///|
let object_id_counter : Ref[Int] = { val: 0, }

///|
fn DynObject::new(inner : ObjectImpl) -> DynObject {
  object_id_counter.val += 1
  { id: object_id_counter.val, inner, }
}

///|
/// Returns `true` if both handles point to the same object.
pub fn DynObject::is_same_object(self : DynObject, other : DynObject) -> Bool {
  self.id == other.id
}

///|
/// Returns the representation of the object.
pub fn DynObject::repr(self : DynObject) -> ObjectRepr {
  match self.inner {
    Seq(_) | Tuple(_) => Seq
    Map(_) | Kwargs(_) | Namespace(_) | Loop(_) => Map
    MergeSeq(m) => m.repr
    ClosureRef(_) => Plain
    Group(_, _) => Seq
    Custom(o) => o.repr()
  }
}

///|
/// Looks up an item (or attribute) on the object.
pub fn DynObject::get_value(self : DynObject, key : Value) -> Value? {
  match self.inner {
    Seq(items) | Tuple(items) =>
      match key.as_usize() {
        Some(idx) if idx < items.length() => Some(items[idx])
        _ => None
      }
    Map(m) | Kwargs(m) => m.get(key)
    Namespace(m) =>
      match key.as_str() {
        Some(s) => m.get(s)
        None => None
      }
    MergeSeq(m) => merge_seq_get_value(m, key)
    ClosureRef(_) => None
    Group(grouper, list) =>
      match (key.as_usize(), key.as_str()) {
        (Some(0), None) | (None, Some("grouper")) => Some(grouper)
        (Some(1), None) | (None, Some("list")) =>
          Some(Value::make_iterable(() => list.iter()))
        _ => None
      }
    Loop(l) =>
      match key.as_str() {
        Some(s) => l.get_value_by_str(s)
        None => None
      }
    Custom(o) => o.get_value(key)
  }
}

///|
/// Looks up an attribute by a string key.
pub fn DynObject::get_value_by_str(self : DynObject, key : String) -> Value? {
  match self.inner {
    Seq(_) | Tuple(_) | MergeSeq(_) | Group(_, _) =>
      self.get_value(Value::from_string(key))
    Map(m) | Kwargs(m) =>
      if m.length() <= 12 {
        // like MiniJinja: small maps are scanned without building a key
        for k, v in m {
          if k is Str(s, _) && s == key {
            return Some(v)
          }
        }
        None
      } else {
        m.get(Value::from_string(key))
      }
    Namespace(m) => m.get(key)
    Loop(l) => l.get_value_by_str(key)
    ClosureRef(_) => None
    Custom(o) => o.get_value_by_str(key)
  }
}

///|
/// Returns the enumerator of the object.
pub fn DynObject::enumerate(self : DynObject) -> Enumerator {
  match self.inner {
    Seq(items) => Seq(items.length())
    Tuple(items) => if items.is_empty() { Empty } else { Seq(items.length()) }
    Map(m) | Kwargs(m) => {
      let pairs = m.to_array()
      KeyValueIter(pairs.iter())
    }
    Namespace(m) => {
      let keys = m.keys().to_array()
      keys.sort_by((a, b) => compare_str(a, b))
      Values(keys.map(Value::from_string))
    }
    MergeSeq(m) => merge_seq_enumerate(m)
    Loop(_) => Str(loop_object_keys)
    ClosureRef(_) => NonEnumerable
    Group(_, _) => Seq(2)
    Custom(o) => o.enumerate()
  }
}

///|
/// Returns the length of the enumerator if known.
pub fn DynObject::enumerator_len(self : DynObject) -> Int? {
  match self.inner {
    Seq(items) | Tuple(items) => Some(items.length())
    Map(m) | Kwargs(m) => Some(m.length())
    Namespace(m) => Some(m.length())
    MergeSeq(m) => m.total_len
    Loop(_) => Some(loop_object_keys.length())
    ClosureRef(_) => None
    Group(_, _) => Some(2)
    Custom(o) => o.enumerator_len()
  }
}

///|
/// Returns the truthiness of the object.
pub fn DynObject::is_true(self : DynObject) -> Bool {
  match self.inner {
    Custom(o) => o.is_true()
    _ => self.enumerator_len() != Some(0)
  }
}

///|
/// Calls the object.
pub fn DynObject::call(
  self : DynObject,
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  match self.inner {
    Loop(_) =>
      raise TemplateError::new(
        InvalidOperation,
        "loop recursion cannot be called this way",
      )
    Custom(o) => o.call(state, args)
    _ => raise TemplateError::new(InvalidOperation, "object is not callable")
  }
}

///|
/// Calls a method on the object.
pub fn DynObject::call_method(
  self : DynObject,
  state : State,
  name : String,
  args : Array[Value],
) -> Value raise TemplateError {
  match self.inner {
    Loop(l) => l.call_method(name, args)
    Custom(o) => o.call_method(state, name, args)
    _ => raise TemplateError::from_kind(UnknownMethod)
  }
}

///|
/// Returns an iterator over the values of the object if it is enumerable.
pub fn DynObject::try_iter(self : DynObject) -> Iter[Value]? {
  match self.inner {
    Seq(items) | Tuple(items) => return Some(items.iter())
    Map(m) | Kwargs(m) => return Some(m.keys())
    _ => ()
  }
  match self.enumerate() {
    NonEnumerable => None
    Empty => Some(Iter::empty())
    Seq(n) => {
      let mut idx = 0
      Some(
        Iter::new(
          () => {
            if idx < n {
              let rv = self
                .get_value(Value::from_int(idx))
                .unwrap_or(Value::undefined())
              idx += 1
              Some(rv)
            } else {
              None
            }
          },
          size_hint=n,
        ),
      )
    }
    Iter(iter) => Some(iter)
    KeyValueIter(iter) =>
      if self.repr() is Map {
        Some(iter.map(pair => pair.0))
      } else {
        Some(iter.map(pair => Value::from_tuple([pair.0, pair.1])))
      }
    Str(strs) => Some(strs.iter().map(Value::from_string))
    Values(v) => Some(v.iter())
  }
}

///|
/// Returns an iterator over the key/value pairs of the object.  For
/// sequences the keys are the indexes.
pub fn DynObject::try_iter_pairs(self : DynObject) -> Iter[(Value, Value)]? {
  if self.repr() is Map {
    match self.inner {
      Map(m) | Kwargs(m) => return Some(m.iter())
      _ => ()
    }
    match self.enumerate() {
      KeyValueIter(iter) => Some(iter)
      _ => {
        guard self.try_iter() is Some(iter) else { return None }
        Some(
          iter.map(key => {
            (key, self.get_value(key).unwrap_or(Value::undefined()))
          }),
        )
      }
    }
  } else {
    guard self.try_iter() is Some(iter) else { return None }
    Some(iter.mapi((idx, item) => (Value::from_int(idx), item)))
  }
}

///|
/// Renders the object into a formatter (shared by `Display` and `Debug`).
fn DynObject::render(self : DynObject, f : @rfmt.Formatter) -> Unit {
  match self.inner {
    Tuple(items) => {
      f.write_str("(")
      for idx, value in items {
        if idx != 0 {
          f.write_str(", ")
        }
        value.fmt_debug(f)
      }
      if items.length() == 1 {
        f.write_str(",")
      }
      f.write_str(")")
      return
    }
    Loop(l) => {
      f.write_str(l.render())
      return
    }
    Group(grouper, list) => {
      f
      .debug_tuple("")
      .field(f => grouper.fmt_debug(f))
      .field(f => {
        let l = f.debug_list()
        for v in list {
          l.entry(f => v.fmt_debug(f)) |> ignore
        }
        l.finish()
      })
      .finish()
      return
    }
    Custom(o) =>
      if o.render() is Some(s) {
        f.write_str(s)
        return
      }
    _ => ()
  }
  match self.repr() {
    Map => {
      let m = f.debug_map()
      if self.try_iter_pairs() is Some(iter) {
        for pair in iter {
          let (key, value) = pair
          m.entry(f => key.fmt_debug(f), f => value.fmt_debug(f)) |> ignore
        }
      }
      m.finish()
    }
    Seq | Iterable if self.enumerator_len() is Some(_) => {
      let l = f.debug_list()
      if self.try_iter() is Some(iter) {
        for value in iter {
          l.entry(f => value.fmt_debug(f)) |> ignore
        }
      }
      l.finish()
    }
    Seq | Iterable => f.write_str("<iterator>")
    Plain => f.write_str("<object>")
  }
}

///|
fn merge_seq_get_value(m : MergeSeqObject, key : Value) -> Value? {
  if m.repr != Seq {
    return None
  }
  guard key.as_usize() is Some(idx) else { return None }
  let mut current_idx = 0
  for value in m.values {
    let len = value.len().unwrap_or(0)
    if idx < current_idx + len {
      return try value.get_item(Value::from_int(idx - current_idx)) catch {
        _ => None
      } noraise {
        v => Some(v)
      }
    }
    current_idx += len
  }
  None
}

///|
fn merge_seq_enumerate(m : MergeSeqObject) -> Enumerator {
  // iterates over all values in sequence, without recursion through nested
  // merged sequences (they are flattened at construction when too deep).
  let values = m.values
  let mut idx = 0
  let mut current : Iter[Value]? = None
  let iter = Iter::new(
    () => {
      for ;; {
        match current {
          Some(it) =>
            match it.next() {
              Some(v) => break Some(v)
              None => current = None
            }
          None => {
            if idx >= values.length() {
              break None
            }
            let v = values[idx]
            idx += 1
            current = Some(
              v.try_iter() catch {
                err => Iter::singleton(Value::from_error(err))
              },
            )
          }
        }
      }
    },
    size_hint?=m.total_len,
  )
  Iter(iter)
}

///|
let merge_seq_max_depth = 32

///|
fn merge_seq_depth_for_values(values : Array[Value]) -> Int {
  let mut max = 0
  for value in values {
    if value is Object({ inner: MergeSeq(m), .. }) && m.depth > max {
      max = m.depth
    }
  }
  max + 1
}

///|
fn make_merge_seq(values : Array[Value], repr : ObjectRepr) -> Value {
  let mut values = values
  let mut depth = merge_seq_depth_for_values(values)
  if depth > merge_seq_max_depth {
    let flattened = []
    for value in values {
      let pending = [value]
      while pending.pop() is Some(v) {
        if v is Object({ inner: MergeSeq(m), .. }) {
          for i = m.values.length() - 1; i >= 0; i = i - 1 {
            pending.push(m.values[i])
          }
        } else {
          flattened.push(v)
        }
      }
    }
    values = flattened
    depth = merge_seq_depth_for_values(values)
  }
  let mut total_len : Int? = Some(0)
  for v in values {
    match (total_len, v.len()) {
      (Some(a), Some(b)) => total_len = Some(a + b)
      _ => total_len = None
    }
  }
  Value::Object(DynObject::new(MergeSeq({ values, total_len, repr, depth, })))
}

///|
/// An iterable object backed by a closure that creates a fresh iterator.
priv struct IterableObject {
  maker : () -> Iter[Value]
}

///|
impl Object for IterableObject with fn repr(_self) {
  Iterable
}

///|
impl Object for IterableObject with fn enumerate(self) {
  Iter((self.maker)())
}

///|
/// A map object backed by closures.
priv struct ProxyMapObject {
  keys : () -> Iter[Value]
  get : (Value) -> Value?
}

///|
impl Object for ProxyMapObject with fn get_value(self, key) {
  (self.get)(key)
}

///|
impl Object for ProxyMapObject with fn enumerate(self) {
  Iter((self.keys)())
}

///|
/// A callable function object.
priv struct FunctionObject {
  name : String
  func : (State, Array[Value]) -> Value raise TemplateError
}

///|
impl Object for FunctionObject with fn repr(_self) {
  Plain
}

///|
impl Object for FunctionObject with fn call(self, state, args) {
  (self.func)(state, args)
}

///|
impl Object for FunctionObject with fn render(self) {
  Some(self.name)
}

///|
/// A map that merges multiple maps (later maps take precedence).
priv struct MergeDictObject {
  values : Array[Value]
}

///|
impl Object for MergeDictObject with fn get_value(self, key) {
  for i = self.values.length() - 1; i >= 0; i = i - 1 {
    let v = self.values[i].get_item(key) catch { _ => continue }
    if !v.is_undefined() {
      return Some(v)
    }
  }
  None
}

///|
impl Object for MergeDictObject with fn enumerate(self) {
  let keys : Array[Value] = []
  for value in self.values {
    if value.kind() is Map {
      let iter = value.try_iter() catch { _ => continue }
      for k in iter {
        keys.push(k)
      }
    }
  }
  // like a BTreeSet: sorted and deduplicated
  keys.sort_by((a, b) => a.cmp(b))
  let rv : Array[Value] = []
  for k in keys {
    if rv.last() is Some(last) && last.cmp(k) == 0 {
      continue
    }
    rv.push(k)
  }
  Values(rv)
}

///|
/// Merges multiple maps (or map-like values) into a single lazy map.  Later
/// maps take precedence.
pub fn merge_maps(values : Array[Value]) -> Value {
  if values.length() == 1 {
    values[0]
  } else {
    Value::from_object(MergeDictObject::{ values, })
  }
}
