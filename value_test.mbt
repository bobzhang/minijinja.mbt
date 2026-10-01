// Ported from minijinja/tests/test_value.rs.

///|
fn vt_ints(xs : Array[Int]) -> @minijinja.Value {
  @minijinja.Value::from_array(xs.map(@minijinja.Value::from_int))
}

///|
fn vt_render(
  source : String,
  ctx : Array[(String, @minijinja.Value)],
) -> String raise {
  @minijinja.Environment::new().render_str(
    source,
    @minijinja.Value::from_pairs(ctx),
  )
}

///|
/// Equivalent of `{:#?}` on a `Vec<Value>`.
fn vt_debug_vec(values : Array[@minijinja.Value]) -> String {
  @minijinja.Value::from_array(values).debug_string(pretty=true)
}

///|
fn vt_expect_err(
  f : () -> @minijinja.Value raise @minijinja.TemplateError,
) -> @minijinja.TemplateError raise {
  try f() catch {
    e => e
  } noraise {
    v => fail("expected an error, got \{v.debug_string()}")
  }
}

///|
fn vt_iter_fails(v : @minijinja.Value) -> Bool {
  try v.try_iter() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "value: sort" {
  let v = [
    @minijinja.Value::from_uint64(100UL),
    @minijinja.Value::from_int(80),
    @minijinja.Value::from_int(30),
    @minijinja.Value::from_bool(true),
    @minijinja.Value::from_bool(false),
    @minijinja.Value::from_bigint(99N),
    @minijinja.Value::from_double(1000.0),
  ]
  v.sort()
  assert_eq(
    vt_debug_vec(v),
    (
      #|[
      #|    False,
      #|    True,
      #|    30,
      #|    80,
      #|    99,
      #|    100,
      #|    1000.0,
      #|]
    ),
  )
}

///|
test "value: sort_different_types" {
  let v = [
    @minijinja.Value::from_uint64(100UL),
    @minijinja.Value::from_string("bar"),
    @minijinja.Value::from_int(1),
    vt_ints([1, 2]),
    @minijinja.Value::from_int(80),
    @minijinja.Value::from_int(30),
    @minijinja.Value::from_pairs([("a", @minijinja.Value::from_int(3))]),
    @minijinja.Value::from_pairs([("a", @minijinja.Value::from_int(2))]),
    @minijinja.Value::from_pairs([("b", @minijinja.Value::from_int(0))]),
    @minijinja.Value::from_pairs([("b", @minijinja.Value::from_int(3))]),
    vt_ints([0, 2]),
    @minijinja.Value::from_bool(true),
    @minijinja.Value::undefined(),
    @minijinja.Value::from_string("zzz"),
    @minijinja.Value::from_bool(false),
    @minijinja.Value::from_int(-100),
    @minijinja.Value::from_double(-50.0),
    @minijinja.Value::from_double(-75.0),
    @minijinja.Value::from_bigint(99N),
    @minijinja.Value::from_double(1000.0),
    vt_ints([0, 1]),
    vt_ints([1, 1]),
    @minijinja.Value::from_string("foo"),
    @minijinja.Value::none(),
    @minijinja.Value::from_int(0),
    @minijinja.Value::from_double(-1.0 / 0.0),
    @minijinja.Value::from_double(0.0 / 0.0),
    @minijinja.Value::from_double(1.0 / 0.0),
  ]
  v.sort()
  assert_eq(
    vt_debug_vec(v),
    (
      #|[
      #|    undefined,
      #|    None,
      #|    False,
      #|    True,
      #|    -inf,
      #|    -100,
      #|    -75.0,
      #|    -50.0,
      #|    0,
      #|    1,
      #|    30,
      #|    80,
      #|    99,
      #|    100,
      #|    1000.0,
      #|    inf,
      #|    NaN,
      #|    'bar',
      #|    'foo',
      #|    'zzz',
      #|    [
      #|        0,
      #|        1,
      #|    ],
      #|    [
      #|        0,
      #|        2,
      #|    ],
      #|    [
      #|        1,
      #|        1,
      #|    ],
      #|    [
      #|        1,
      #|        2,
      #|    ],
      #|    {
      #|        'a': 2,
      #|    },
      #|    {
      #|        'a': 3,
      #|    },
      #|    {
      #|        'b': 0,
      #|    },
      #|    {
      #|        'b': 3,
      #|    },
      #|]
    ),
  )
}

///|
/// Rust's borrowed conversions (`&T`, `Cow`, `Arc<str>`) have no MoonBit
/// equivalent; the test checks the plain value constructors instead.
test "value: borrowed_native_conversions" {
  assert_eq(@minijinja.Value::from_int(42), @minijinja.Value::from_int(42))
  assert_eq(
    @minijinja.Value::from_bool(true),
    @minijinja.Value::from_bool(true),
  )
  assert_eq(@minijinja.Value::none(), @minijinja.Value::none())
  assert_eq(
    @minijinja.Value::from_string("cow"),
    @minijinja.Value::from_string("cow"),
  )
  assert_eq(
    @minijinja.Value::from_string("arc"),
    @minijinja.Value::from_string("arc"),
  )
  assert_eq(
    @minijinja.Value::from_bytes(b"\x01\x02").kind(),
    @minijinja.ValueKind::Bytes,
  )
  let values = [@minijinja.Value::from_int(1), @minijinja.Value::from_int(2)]
  assert_eq(@minijinja.Value::from_array(values).to_string(), "[1, 2]")
  assert_true(@minijinja.Value::from_tuple(values).is_tuple())
}

///|
test "value: safe_string_roundtrip" {
  let v = @minijinja.Value::from_safe_string("<b>HTML</b>")
  let v2 = v
  assert_true(v.is_safe())
  assert_true(v2.is_safe())
  assert_eq(v.to_string(), v2.to_string())
}

///|
test "value: undefined_roundtrip" {
  let v = @minijinja.Value::undefined()
  let v2 = v
  assert_true(v.is_undefined())
  assert_true(v2.is_undefined())
}

///|
/// serde_json serialization is adapted to `Value::to_json_string`.
test "value: value_serialization" {
  assert_eq(@minijinja.Value::undefined().to_json_string(), "null")
  assert_eq(
    @minijinja.Value::from_safe_string("foo").to_json_string(),
    "\"foo\"",
  )
}

///|
test "value: float_to_string" {
  assert_eq(@minijinja.Value::from_double(42.4242).to_string(), "42.4242")
  assert_eq(@minijinja.Value::from_double(42.0).to_string(), "42.0")
}

///|
test "value: value_as_bytes" {
  assert_eq(@minijinja.Value::from_string("foo").as_bytes(), Some(b"foo"))
  assert_eq(@minijinja.Value::from_bytes(b"foo").as_bytes(), Some(b"foo"))
}

///|
test "value: value_by_index" {
  let val = vt_ints([1, 2, 3])
  assert_eq(val.get_item_by_index(0), @minijinja.Value::from_int(1))
  assert_true(val.get_item_by_index(4).is_undefined())
}

///|
struct VtMapPoint {
  x : Int
  y : Int
  z : Int
}

///|
impl @minijinja.Object for VtMapPoint with fn get_value(self, key) {
  match key.as_str() {
    Some("x") => Some(@minijinja.Value::from_int(self.x))
    Some("y") => Some(@minijinja.Value::from_int(self.y))
    Some("z") => Some(@minijinja.Value::from_int(self.z))
    _ => None
  }
}

///|
impl @minijinja.Object for VtMapPoint with fn enumerate(_self) {
  Str(["x", "y", "z"])
}

///|
test "value: map_object_iteration_and_indexing" {
  let rv = vt_render(
    "{% for key in point %}{{ key }}: {{ point[key] }}\n{% endfor %}",
    [
      (
        "point",
        @minijinja.Value::from_object(VtMapPoint::{ x: 1, y: 2, z: 3, }),
      ),
    ],
  )
  assert_eq(
    rv,
    (
      #|x: 1
      #|y: 2
      #|z: 3
      #|
    ),
  )
  let rv = vt_render("{{ [point.x, point.z, point.missing_attribute] }}", [
    ("point", @minijinja.Value::from_object(VtMapPoint::{ x: 1, y: 2, z: 3, })),
  ])
  assert_eq(rv, "[1, 3, undefined]")
}

///|
struct VtSeqPoint {
  x : Int
  y : Int
  z : Int
}

///|
impl @minijinja.Object for VtSeqPoint with fn repr(_self) {
  Seq
}

///|
impl @minijinja.Object for VtSeqPoint with fn get_value(self, index) {
  match index.as_usize() {
    Some(0) => Some(@minijinja.Value::from_int(self.x))
    Some(1) => Some(@minijinja.Value::from_int(self.y))
    Some(2) => Some(@minijinja.Value::from_int(self.z))
    _ => None
  }
}

///|
impl @minijinja.Object for VtSeqPoint with fn enumerate(_self) {
  Seq(3)
}

///|
test "value: seq_object_iteration_and_indexing" {
  let rv = vt_render(
    "{% for value in point %}{{ loop.index0 }}: {{ value }}\n{% endfor %}",
    [
      (
        "point",
        @minijinja.Value::from_object(VtSeqPoint::{ x: 1, y: 2, z: 3, }),
      ),
    ],
  )
  assert_eq(
    rv,
    (
      #|0: 1
      #|1: 2
      #|2: 3
      #|
    ),
  )
  let rv = vt_render("{{ [point[0], point[2], point[42]] }}", [
    ("point", @minijinja.Value::from_object(VtSeqPoint::{ x: 1, y: 2, z: 3, })),
  ])
  assert_eq(rv, "[1, 3, undefined]")
}

///|
/// `Value::from_object(vec![..])` maps to `Value::from_array`.
test "value: builtin_seq_objects" {
  let rv = vt_render("{{ val }}", [
    (
      "val",
      @minijinja.Value::from_array([
        @minijinja.Value::from_bool(true),
        @minijinja.Value::from_bool(false),
      ]),
    ),
  ])
  assert_eq(rv, "[True, False]")
  let rv = vt_render("{{ val }}", [
    (
      "val",
      @minijinja.Value::from_array([
        @minijinja.Value::from_string("foo"),
        @minijinja.Value::from_string("bar"),
      ]),
    ),
  ])
  assert_eq(rv, "['foo', 'bar']")
}

///|
test "value: value_object_interface" {
  let val = vt_ints([1, 2, 3, 4])
  let obj = val.as_object().unwrap()
  assert_eq(obj.enumerator_len(), Some(4))
  assert_eq(@minijinja.Value::from_dyn_object(obj).to_string(), "[1, 2, 3, 4]")
}

///|
struct VtThing {
  moo : Int
}

///|
impl @minijinja.Object for VtThing

///|
/// `DynObject::is::<T>()`/`downcast::<T>()` have no MoonBit equivalent (no
/// `Any`-style downcasting); only the object handle round trip is checked.
test "value: obj_downcast" {
  let x_value = @minijinja.Value::from_object(VtThing::{ moo: 42, })
  let value_as_obj = x_value.as_object()
  assert_true(value_as_obj is Some(_))
}

///|
struct VtSeqThing {
  moo : Int
}

///|
impl @minijinja.Object for VtSeqThing with fn get_value(_self, idx) {
  match idx.as_usize() {
    Some(i) if i < 3 => Some(idx)
    _ => None
  }
}

///|
impl @minijinja.Object for VtSeqThing with fn enumerate(_self) {
  Seq(3)
}

///|
/// `downcast_object_ref::<T>()` is not available in MoonBit; dropped.
test "value: seq_object_downcast" {
  let thing = VtSeqThing::{ moo: 42, }
  let obj = @minijinja.Value::from_object(thing)
  assert_true(obj.as_object() is Some(_))
  assert_eq(thing.moo, 42)
}

///|
/// `downcast_object_ref::<T>()` is not available in MoonBit; dropped.
test "value: struct_object_downcast" {
  let thing = VtThing::{ moo: 42, }
  let obj = @minijinja.Value::from_object(thing)
  assert_true(obj.as_object() is Some(_))
  assert_eq(thing.moo, 42)
}

///|
test "value: value_cmp" {
  assert_eq(vt_ints([1]), vt_ints([1]))
  assert_not_eq(vt_ints([1]), vt_ints([2]))
  assert_eq(@minijinja.Value::undefined(), @minijinja.Value::undefined())
}

///|
test "value: call_kwargs" {
  let env = @minijinja.Environment::new()
  env.add_template("foo", "")
  let tmpl = env.get_template("foo")
  let state = tmpl.new_state()
  let val = @minijinja.Value::from_function("f", (state, args) => {
    let kwargs = @minijinja.Args::new(state, args).kwargs()
    @minijinja.Value::from_int(kwargs.get("foo").as_i64().unwrap().to_int())
  })
  let rv = val.call(state, [
    @minijinja.Kwargs::from_pairs([("foo", @minijinja.Value::from_int(42))]).to_value(),
  ])
  assert_eq(rv, @minijinja.Value::from_int(42))
}

///|
test "value: kwargs_error" {
  let kwargs = @minijinja.Kwargs::from_pairs([
    ("foo", @minijinja.Value::from_int(42)),
  ])
  let bar = vt_expect_err(() => kwargs.get("bar"))
  assert_eq(bar.detail(), Some("missing keyword argument 'bar'"))
}

///|
test "value: return_none" {
  let env = @minijinja.Environment::empty()
  let val = @minijinja.Value::from_function("f", (_, _) => {
    @minijinja.Value::none()
  })
  let rv = val.call(env.empty_state(), [])
  assert_true(rv.is_none())
}

///|
test "value: filter_basics" {
  let env = @minijinja.Environment::new()
  env.add_filter("test", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let a = args.i64()
    let b = args.i64()
    args.finish()
    @minijinja.Value::from_int64(a + b)
  })
  assert_eq(
    env
    .empty_state()
    .apply_filter("test", [
      @minijinja.Value::from_int(23),
      @minijinja.Value::from_int(42),
    ]),
    @minijinja.Value::from_int(65),
  )
}

///|
fn vt_increment(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let args = @minijinja.Args::new(state, args)
  let by = args.i64()
  args.finish()
  let old = state.get_temp("counter").bind(v => v.as_i64()).unwrap_or(0L)
  state.set_temp("counter", @minijinja.Value::from_int64(old + by)) |> ignore
  @minijinja.Value::from_int64(old + by)
}

///|
test "value: functions_with_mutable_state" {
  let env = @minijinja.Environment::new()
  env.add_function("increment", vt_increment)
  env.add_function("state_name", (state, _) => {
    @minijinja.Value::from_string(state.name())
  })
  env.add_filter("prefix", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let value = args.str()
    args.finish()
    @minijinja.Value::from_string("\{state.name()}:\{value}")
  })
  env.add_test("matches_counter", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let value = args.i64()
    args.finish()
    @minijinja.Value::from_bool(
      state.get_temp("counter") == Some(@minijinja.Value::from_int64(value)),
    )
  })
  let rv = env
    .template_from_str(
      "{{ increment(2) }} {{ increment(3) }} {{ state_name() }} {{ 'x'|prefix }} {{ 5 is matches_counter }}",
    )
    .render(@minijinja.Value::from_pairs([]))
  assert_eq(rv, "2 5 <string> <string>:x True")
  let state = env.empty_state()
  assert_true(
    state
    .apply_filter("prefix", [@minijinja.Value::from_string("x")])
    .to_string()
    .has_suffix(":x"),
  )
  assert_true(
    !state.perform_test("matches_counter", [@minijinja.Value::from_int(5)]),
  )
}

///|
/// Rust's `ArgType` conversions (`String`, `Cow<str>`, `StringInput`,
/// `Rest<String>`, `Vec<String>`) map to the closest `Args` accessors.
test "value: mutable_state_argument_conversion_uses_state" {
  let env = @minijinja.Environment::new()
  env.set_undefined_behavior(Strict)
  env.add_global("conversion_value", @minijinja.Value::from_int(42))
  env.add_filter("lookup_from_state", (state, _args) => {
    guard state.lookup("conversion_value") is Some(value) else {
      raise @minijinja.TemplateError::new(InvalidOperation, "state required")
    }
    state.set_temp("converted", value) |> ignore
    value
  })
  env.add_filter("string", (state, args) => {
    @minijinja.Args::new(state, args).string() |> ignore
    @minijinja.Value::none()
  })
  env.add_filter("cow", (state, args) => {
    @minijinja.Args::new(state, args).string() |> ignore
    @minijinja.Value::none()
  })
  env.add_filter("string_input", (state, args) => {
    @minijinja.Args::new(state, args).string_input() |> ignore
    @minijinja.Value::none()
  })
  env.add_filter("rest", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    while args.has_more() {
      args.string() |> ignore
    }
    @minijinja.Value::none()
  })
  env.add_filter("vec", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let items = args.value()
    for item in items.try_iter() {
      @minijinja.StringInput::new(state, item) |> ignore
    }
    @minijinja.Value::none()
  })
  let state = env.empty_state()
  assert_eq(
    state.apply_filter("lookup_from_state", [@minijinja.Value::undefined()]),
    @minijinja.Value::from_int(42),
  )
  assert_eq(state.get_temp("converted"), Some(@minijinja.Value::from_int(42)))
  for filter in ["string", "cow", "string_input", "rest"] {
    assert_eq(
      vt_expect_err(() => {
        state.apply_filter(filter, [@minijinja.Value::undefined()])
      }).kind(),
      UndefinedError,
    )
  }
  assert_eq(
    vt_expect_err(() => {
      state.apply_filter("vec", [
        @minijinja.Value::from_array([@minijinja.Value::undefined()]),
      ])
    }).kind(),
    UndefinedError,
  )
  assert_eq(
    vt_expect_err(() => {
      state.apply_filter("replace", [
        @minijinja.Value::undefined(),
        @minijinja.Value::from_string("x"),
        @minijinja.Value::from_string("y"),
      ])
    }).kind(),
    UndefinedError,
  )
}

///|
test "value: shared_state_can_appear_in_any_argument_position" {
  let env = @minijinja.Environment::new()
  env.add_filter("state_last", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let value = args.str()
    args.finish()
    @minijinja.Value::from_string("\{state.name()}:\{value}")
  })
  env.add_filter("borrowed_state", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    args.value() |> ignore
    args.finish()
    @minijinja.Value::from_string(state.name())
  })
  assert_eq(
    env
    .template_from_named_str(
      "test", "{{ 'value'|state_last }}:{{ 'ignored'|borrowed_state }}",
    )
    .render(@minijinja.Value::from_pairs([])),
    "test:value:test",
  )
}

///|
test "value: mutable_state_value_calls" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let value = @minijinja.Value::from_function("increment", vt_increment)
  assert_eq(
    value.call(state, [@minijinja.Value::from_int(2)]),
    @minijinja.Value::from_int(2),
  )
  assert_eq(
    value.call(state, [@minijinja.Value::from_int(3)]),
    @minijinja.Value::from_int(5),
  )
}

///|
struct VtCallable {}

///|
impl @minijinja.Object for VtCallable with fn call(_self, state, _args) {
  state.set_temp("called", @minijinja.Value::from_bool(true)) |> ignore
  @minijinja.Value::from_string("called")
}

///|
impl @minijinja.Object for VtCallable with fn call_method(
  _self,
  state,
  name,
  _args,
) {
  state.set_temp("method", @minijinja.Value::from_string(name)) |> ignore
  @minijinja.Value::from_string(name)
}

///|
test "value: mutable_state_object_calls" {
  let env = @minijinja.Environment::new()
  let state = env.empty_state()
  let value = @minijinja.Value::from_object(VtCallable::{ })
  assert_eq(value.call(state, []), @minijinja.Value::from_string("called"))
  assert_eq(state.get_temp("called"), Some(@minijinja.Value::from_bool(true)))
  assert_eq(
    value.call_method(state, "ping", []),
    @minijinja.Value::from_string("ping"),
  )
  assert_eq(
    state.get_temp("method"),
    Some(@minijinja.Value::from_string("ping")),
  )
}

///|
test "value: rest_args" {
  let env = @minijinja.Environment::new()
  env.add_filter("sum", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let mut rv = args.i64()
    for v in args.rest() {
      rv += v.as_i64().unwrap()
    }
    @minijinja.Value::from_int64(rv)
  })
  assert_eq(
    env
    .empty_state()
    .apply_filter("sum", [
      @minijinja.Value::from_int(1),
      @minijinja.Value::from_int(2),
      @minijinja.Value::from_int(3),
      @minijinja.Value::from_int(4),
    ]),
    @minijinja.Value::from_int(1 + 2 + 3 + 4),
  )
}

///|
test "value: optional_args" {
  let env = @minijinja.Environment::new()
  env.add_filter("add", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let val = args.i64()
    let a = args.i64()
    let b = args.opt_i64()
    args.finish()
    // ensure we really get our value as first argument
    guard val == 23L else {
      raise @minijinja.TemplateError::new(InvalidOperation, "bad value")
    }
    let mut sum = val + a
    if b is Some(b) {
      sum += b
    }
    @minijinja.Value::from_int64(sum)
  })
  let state = env.empty_state()
  assert_eq(
    state.apply_filter("add", [
      @minijinja.Value::from_int(23),
      @minijinja.Value::from_int(42),
    ]),
    @minijinja.Value::from_int(65),
  )
  assert_eq(
    state.apply_filter("add", [
      @minijinja.Value::from_int(23),
      @minijinja.Value::from_int(42),
      @minijinja.Value::undefined(),
    ]),
    @minijinja.Value::from_int(65),
  )
  assert_eq(
    state.apply_filter("add", [
      @minijinja.Value::from_int(23),
      @minijinja.Value::from_int(42),
      @minijinja.Value::from_int(1),
    ]),
    @minijinja.Value::from_int(66),
  )
}

///|
test "value: values_in_vec" {
  let env = @minijinja.Environment::new()
  env.add_filter("upper", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let value = args.str()
    args.finish()
    @minijinja.Value::from_string(value.to_upper())
  })
  env.add_filter("sum", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let value = args.value()
    args.finish()
    let mut rv = 0L
    for item in value.try_iter() {
      rv += item.as_i64().unwrap()
    }
    @minijinja.Value::from_int64(rv)
  })
  let state = env.empty_state()
  assert_eq(
    state.apply_filter("upper", [@minijinja.Value::from_string("Hello World!")]),
    @minijinja.Value::from_string("HELLO WORLD!"),
  )
  assert_eq(
    state.apply_filter("sum", [vt_ints([1, 2])]),
    @minijinja.Value::from_int(3),
  )
}

///|
test "value: seq_object_borrow" {
  let env = @minijinja.Environment::new()
  env.add_filter("connect", (state, args) => {
    let args = @minijinja.Args::new(state, args)
    let values = args.value().as_object().unwrap()
    args.finish()
    let rv = StringBuilder()
    if values.try_iter() is Some(iter) {
      for item in iter {
        rv.write_string(item.to_string())
      }
    }
    @minijinja.Value::from_string(rv.to_string())
  })
  let state = env.empty_state()
  assert_eq(
    state.apply_filter("connect", [
      @minijinja.Value::from_array([
        @minijinja.Value::from_string("HELLO"),
        @minijinja.Value::from_int(42),
      ]),
    ]),
    @minijinja.Value::from_string("HELLO42"),
  )
}

///|
fn vt_range(n : Int) -> Iter[@minijinja.Value] {
  Array::makei(n, i => @minijinja.Value::from_int(i)).iter()
}

///|
fn vt_chars_a_to_e() -> Iter[@minijinja.Value] {
  ['a', 'b', 'c', 'd', 'e'].map(@minijinja.Value::from_char).iter()
}

///|
test "value: one_shot_iterator" {
  let value = @minijinja.Value::make_one_shot_iterator(vt_range(10))
  assert_eq(value.to_string(), "<iterator>")
  let rv = vt_render("{% for item in iter %}[{{ item }}]{% endfor %}", [
    ("iter", value),
  ])
  assert_eq(rv, "[0][1][2][3][4][5][6][7][8][9]")
  let rv = vt_render(
    "{% for item in iter %}- {{ item }}: {{ loop.index }} / {{ loop.length|default('?') }}\n{% endfor %}",
    [("iter", @minijinja.Value::make_one_shot_iterator(vt_chars_a_to_e()))],
  )
  assert_eq(
    rv,
    (
      #|- a: 1 / ?
      #|- b: 2 / ?
      #|- c: 3 / ?
      #|- d: 4 / ?
      #|- e: 5 / ?
      #|
    ),
  )
  let rv = vt_render(
    "{% for item in iter %}{{ item }}{% endfor %}{% for item in iter %}{{ item }}{% endfor %}",
    [("iter", @minijinja.Value::make_one_shot_iterator(vt_chars_a_to_e()))],
  )
  assert_eq(rv, "abcde")
}

///|
test "value: make_iterable" {
  let value = @minijinja.Value::make_iterable(() => vt_range(10))
  assert_eq(value.to_string(), "[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]")
  let rv = vt_render("{% for item in iter %}[{{ item }}]{% endfor %}", [
    ("iter", value),
  ])
  assert_eq(rv, "[0][1][2][3][4][5][6][7][8][9]")
  let rv = vt_render(
    "{% for item in iter %}- {{ item }}: {{ loop.index }} / {{ loop.length }}\n{% endfor %}",
    [("iter", @minijinja.Value::make_iterable(() => vt_chars_a_to_e()))],
  )
  assert_eq(
    rv,
    (
      #|- a: 1 / 5
      #|- b: 2 / 5
      #|- c: 3 / 5
      #|- d: 4 / 5
      #|- e: 5 / 5
      #|
    ),
  )
  let rv = vt_render(
    "{% for item in iter %}- {{ item }}: {{ loop.index }} / {{ loop.length|default('?') }}\n{% endfor %}",
    [
      (
        "iter",
        @minijinja.Value::make_iterable(() => {
          vt_range(10).filter(x => x.as_i64().unwrap() % 2L == 0L)
        }),
      ),
    ],
  )
  assert_eq(
    rv,
    (
      #|- 0: 1 / ?
      #|- 2: 2 / ?
      #|- 4: 3 / ?
      #|- 6: 4 / ?
      #|- 8: 5 / ?
      #|
    ),
  )
}

///|
test "value: complex_key" {
  let m : Map[@minijinja.Value, @minijinja.Value] = Map([])
  m[vt_ints([0, 0])] = @minijinja.Value::from_string("origin")
  m[vt_ints([0, 1])] = @minijinja.Value::from_string("right")
  let value = @minijinja.Value::from_map(m)
  assert_eq(
    value.get_item(vt_ints([0, 0])),
    @minijinja.Value::from_string("origin"),
  )
  assert_eq(value.get_item(vt_ints([0, 42])), @minijinja.Value::undefined())
}

// test_deserialize and test_serde_argument are dropped: they rely on serde
// `Deserialize`, which has no MoonBit equivalent.

///|
struct VtWeirdSeq {}

///|
impl @minijinja.Object for VtWeirdSeq with fn repr(_self) {
  Seq
}

///|
impl @minijinja.Object for VtWeirdSeq with fn enumerate(_self) {
  Iter(['a', 'b'].map(@minijinja.Value::from_char).iter())
}

///|
impl @minijinja.Object for VtWeirdSeq with fn get_value(_self, key) {
  match key.as_usize() {
    Some(0) => Some(@minijinja.Value::from_bool(true))
    Some(1) => Some(@minijinja.Value::from_bool(false))
    _ => None
  }
}

///|
test "value: seq_custom_iter" {
  let v = @minijinja.Value::from_object(VtWeirdSeq::{ })
  assert_eq(v.get_item_by_index(0), @minijinja.Value::from_bool(true))
  assert_eq(v.get_item_by_index(1), @minijinja.Value::from_bool(false))
  let vec = v.try_iter().to_array()
  assert_eq(vec, [
    @minijinja.Value::from_char('a'),
    @minijinja.Value::from_char('b'),
  ])
  let obj = v.as_object().unwrap()
  let vec = obj.try_iter_pairs().unwrap().to_array()
  assert_eq(vec, [
    (@minijinja.Value::from_int(0), @minijinja.Value::from_char('a')),
    (@minijinja.Value::from_int(1), @minijinja.Value::from_char('b')),
  ])
}

///|
struct VtWeirdMap {}

///|
impl @minijinja.Object for VtWeirdMap with fn repr(_self) {
  Map
}

///|
impl @minijinja.Object for VtWeirdMap with fn enumerate(_self) {
  Iter(['a', 'b'].map(@minijinja.Value::from_char).iter())
}

///|
impl @minijinja.Object for VtWeirdMap with fn get_value(_self, key) {
  match key.as_str() {
    Some("a") => Some(@minijinja.Value::from_bool(true))
    Some("b") => Some(@minijinja.Value::from_bool(false))
    _ => None
  }
}

///|
test "value: map_custom_iter" {
  let v = @minijinja.Value::from_object(VtWeirdMap::{ })
  assert_eq(v.get_attr("a"), @minijinja.Value::from_bool(true))
  assert_eq(v.get_attr("b"), @minijinja.Value::from_bool(false))
  let vec = v.try_iter().to_array()
  assert_eq(vec, [
    @minijinja.Value::from_char('a'),
    @minijinja.Value::from_char('b'),
  ])
  let obj = v.as_object().unwrap()
  let vec = obj.try_iter_pairs().unwrap().to_array()
  assert_eq(vec, [
    (@minijinja.Value::from_string("a"), @minijinja.Value::from_bool(true)),
    (@minijinja.Value::from_string("b"), @minijinja.Value::from_bool(false)),
  ])
}

///|
struct VtPlainX {}

///|
impl @minijinja.Object for VtPlainX with fn repr(_self) {
  Plain
}

///|
/// Rust renders plain objects through their derived `Debug` impl (`X`);
/// MoonBit has no such fallback so the object renders itself explicitly.
impl @minijinja.Object for VtPlainX with fn render(_self) {
  Some("X")
}

///|
test "value: plain_object" {
  let x = @minijinja.Value::from_object(VtPlainX::{ })
  assert_true(vt_iter_fails(x))
  assert_eq(
    vt_render("{{ x }}|{{ x.missing_attr is undefined }}", [("x", x)]),
    "X|True",
  )
}

///|
struct VtOddMap {}

///|
impl @minijinja.Object for VtOddMap with fn get_value(_self, key) {
  Some(key)
}

///|
impl @minijinja.Object for VtOddMap with fn enumerate(_self) {
  Str(["a", "b", "c"])
}

///|
struct VtValueThing {}

///|
impl @minijinja.Object for VtValueThing with fn repr(_self) {
  Iterable
}

///|
impl @minijinja.Object for VtValueThing with fn enumerate(_self) {
  Values([@minijinja.Value::from_bool(false), @minijinja.Value::from_bool(true)])
}

///|
/// The serde bytes case is dropped (no `Serde` wrapper) and the `RevThing`
/// case is dropped because `Enumerator::RevIter` does not exist in MoonBit.
test "value: reverse" {
  // reverse vectors
  assert_eq(vt_ints([0, 1, 2]).reverse().to_string(), "[2, 1, 0]")
  // regular iterators (non reversible)
  assert_eq(
    @minijinja.Value::make_iterable(() => vt_range(3)).reverse().to_string(),
    "[2, 1, 0]",
  )
  // strings
  assert_eq(@minijinja.Value::from_string("abc").reverse().to_string(), "cba")
  // undefined
  assert_true(@minijinja.Value::undefined().reverse().is_undefined())
  // none
  assert_true(@minijinja.Value::none().reverse().is_none())
  let odd_map = @minijinja.Value::from_object(VtOddMap::{ })
  assert_eq(odd_map.len(), Some(3))
  assert_eq(
    vt_render("{% set r = m|reverse %}{{ m }}|{{ r }}|{{ r }}", [("m", odd_map)]),
    "{'a': 'a', 'b': 'b', 'c': 'c'}|['c', 'b', 'a']|['c', 'b', 'a']",
  )
  let value_thing = @minijinja.Value::from_object(VtValueThing::{ })
  assert_eq(value_thing.len(), Some(2))
  assert_eq(
    vt_render("{% set r = m|reverse %}{{ m }}|{{ r }}|{{ r }}", [
      ("m", value_thing),
    ]),
    "[False, True]|[True, False]|[True, False]",
  )
  assert_eq(
    vt_expect_err(() => @minijinja.Value::from_int(42).reverse()).to_string(),
    "invalid operation: cannot reverse values of type number",
  )
}

///|
/// `downcast_object_ref::<Vec<i32>>()` is dropped (no downcasting).
test "value: object_vec" {
  let value = vt_ints([1, 2, 3, 4])
  assert_eq(value.get_item_by_index(0).as_i64(), Some(1L))
  let iter = value.try_iter()
  assert_eq(iter.size_hint(), Some(4))
  assert_eq(iter.map(x => x.as_i64().unwrap()).to_array(), [1L, 2L, 3L, 4L])
  assert_eq(value.to_string(), "[1, 2, 3, 4]")
}

// test_object_vec_deque, test_object_linked_list, test_object_hash_set and
// test_object_btree_set are dropped: MoonBit has no `Value` conversions for
// these Rust collection types (they all become `from_array`, covered above).

///|
/// `HashMap`/`BTreeMap` conversions map to `Value::from_pairs`/`from_map`;
/// `downcast_object_ref` checks are dropped.
test "value: object_hash_map" {
  let value = @minijinja.Value::from_pairs([
    ("foo", @minijinja.Value::from_int(1)),
    ("bar", @minijinja.Value::from_int(2)),
  ])
  let iter = value.try_iter()
  assert_eq(iter.size_hint(), Some(2))
  assert_eq(value.get_attr("foo").as_i64(), Some(1L))
  let value = @minijinja.Value::from_pairs([
    ("foo", @minijinja.Value::from_int(1)),
  ])
  assert_eq(value.try_iter().map(x => x.as_str().unwrap()).to_array(), ["foo"])
  assert_eq(value.to_string(), "{'foo': 1}")
  let m : Map[@minijinja.Value, @minijinja.Value] = Map([])
  m[@minijinja.Value::from_bool(true)] = @minijinja.Value::from_int(1)
  let value = @minijinja.Value::from_map(m)
  assert_eq(
    value.get_item(@minijinja.Value::from_bool(true)).as_i64(),
    Some(1L),
  )
  assert_eq(value.to_string(), "{True: 1}")
}

///|
/// See `object_hash_map`: `BTreeMap` maps to `Value::from_pairs`/`from_map`.
test "value: object_btree_map" {
  let value = @minijinja.Value::from_pairs([
    ("bar", @minijinja.Value::from_int(2)),
    ("foo", @minijinja.Value::from_int(1)),
  ])
  let iter = value.try_iter()
  assert_eq(iter.size_hint(), Some(2))
  assert_eq(value.get_attr("foo").as_i64(), Some(1L))
  let value = @minijinja.Value::from_pairs([
    ("foo", @minijinja.Value::from_int(1)),
  ])
  assert_eq(value.try_iter().map(x => x.as_str().unwrap()).to_array(), ["foo"])
  assert_eq(value.to_string(), "{'foo': 1}")
  let m : Map[@minijinja.Value, @minijinja.Value] = Map([])
  m[@minijinja.Value::from_bool(true)] = @minijinja.Value::from_int(1)
  let value = @minijinja.Value::from_map(m)
  assert_eq(
    value.get_item(@minijinja.Value::from_bool(true)).as_i64(),
    Some(1L),
  )
  assert_eq(value.to_string(), "{True: 1}")
}

// test_downcast_arg is dropped: it relies on typed object downcasting of
// function arguments (`&A`, `Arc<B>`), which MoonBit does not support.

///|
struct VtEqThing {
  rev : Bool
}

///|
impl @minijinja.Object for VtEqThing with fn get_value(_self, key) {
  match key.as_str() {
    Some("a") => Some(@minijinja.Value::from_int(1))
    Some("b") => Some(@minijinja.Value::from_int(2))
    _ => None
  }
}

///|
impl @minijinja.Object for VtEqThing with fn enumerate(self) {
  if self.rev {
    Str(["b", "a"])
  } else {
    Str(["a", "b"])
  }
}

///|
test "value: map_eq" {
  let t1 = @minijinja.Value::from_object(VtEqThing::{ rev: false, })
  let t2 = @minijinja.Value::from_object(VtEqThing::{ rev: true, })
  assert_eq(t1.to_string(), "{'a': 1, 'b': 2}")
  assert_eq(t2.to_string(), "{'b': 2, 'a': 1}")
  assert_eq(t1, t2)
}

///|
test "value: float_eq" {
  let a = @minijinja.Value::from_bigint(9007199254740992N)
  let b = @minijinja.Value::from_double(@math.pow(2.0, 53.0))
  assert_eq(a, b)
  let xa = @minijinja.Value::from_bigint(9223372036854775807N)
  let xb = @minijinja.Value::from_double(9223372036854775807L.to_double())
  assert_not_eq(xa, xb)
}

///|
struct VtMadMap {}

///|
impl @minijinja.Object for VtMadMap with fn get_value(_self, key) {
  match key.as_str() {
    Some("a") => Some(@minijinja.Value::from_int(1))
    Some("b") => Some(@minijinja.Value::from_int(2))
    _ => None
  }
}

///|
impl @minijinja.Object for VtMadMap with fn enumerate(_self) {
  let mut idx = 0
  Iter(
    Iter::new(() => {
      idx += 1
      match idx {
        1 => Some(@minijinja.Value::from_string("a"))
        2 => Some(@minijinja.Value::from_string("b"))
        _ => None
      }
    }),
  )
}

///|
test "value: eq_regression" {
  // merged objects used to not have a length.  let's make sure that they have
  let vars = @minijinja.Value::from_pairs([])
  let new_vars = @minijinja.merge_maps([vars])
  assert_eq(vars.len(), Some(0))
  assert_eq(new_vars.len(), Some(0))
  assert_eq(vars, new_vars)

  // we also want to make sure that objects with unknown lengths are properly
  // checked.
  let normal_map = @minijinja.Value::from_pairs([
    ("a", @minijinja.Value::from_int(1)),
    ("b", @minijinja.Value::from_int(2)),
  ])
  let mad_map = @minijinja.Value::from_object(VtMadMap::{ })
  assert_eq(mad_map.len(), None)
  assert_eq(mad_map, normal_map)
  assert_eq(normal_map, mad_map)
  assert_not_eq(
    mad_map,
    @minijinja.Value::from_pairs([
      ("a", @minijinja.Value::from_int(1)),
      ("b", @minijinja.Value::from_int(2)),
      ("c", @minijinja.Value::from_int(3)),
    ]),
  )
  assert_not_eq(
    mad_map,
    @minijinja.Value::from_pairs([("a", @minijinja.Value::from_int(1))]),
  )
}

///|
test "value: sorting" {
  let values = [
    @minijinja.Value::from_double(-1.0 / 0.0),
    @minijinja.Value::from_double(1.0),
    @minijinja.Value::from_double(0.0 / 0.0),
    @minijinja.Value::from_double(1.0 / 0.0),
    @minijinja.Value::from_double(42.0),
    @minijinja.Value::from_int(41),
    @minijinja.Value::from_int(128),
    @minijinja.Value::from_int(-2),
    @minijinja.Value::from_double(-5.0),
    @minijinja.Value::from_int(32),
    @minijinja.Value::from_bool(true),
    @minijinja.Value::from_bool(false),
    vt_ints([1, 2, 3]),
    vt_ints([1, 2, 3, 4]),
    vt_ints([1]),
    @minijinja.Value::from_string("whatever"),
    @minijinja.Value::from_string("floats"),
    @minijinja.Value::from_string("the"),
    @minijinja.Value::from_string("boat"),
    @minijinja.Value::undefined(),
    @minijinja.Value::none(),
    @minijinja.Value::from_error(
      @minijinja.TemplateError::new(InvalidOperation, "shit hit the fan"),
    ),
  ]
  values.sort()
  assert_eq(
    vt_debug_vec(values),
    (
      #|[
      #|    undefined,
      #|    None,
      #|    False,
      #|    True,
      #|    -inf,
      #|    -5.0,
      #|    -2,
      #|    1.0,
      #|    32,
      #|    41,
      #|    42.0,
      #|    128,
      #|    inf,
      #|    NaN,
      #|    'boat',
      #|    'floats',
      #|    'the',
      #|    'whatever',
      #|    [
      #|        1,
      #|    ],
      #|    [
      #|        1,
      #|        2,
      #|        3,
      #|    ],
      #|    [
      #|        1,
      #|        2,
      #|        3,
      #|        4,
      #|    ],
      #|    <invalid value: invalid operation: shit hit the fan>,
      #|]
    ),
  )
}

///|
test "value: bytes" {
  let byte_value = @minijinja.Value::from_bytes(b"\x01\x02\x03\x04")
  assert_eq(byte_value.kind(), @minijinja.ValueKind::Bytes)
  assert_true(vt_iter_fails(byte_value))
  assert_eq(byte_value.debug_string(), "b'\\x01\\x02\\x03\\x04'")
  assert_eq(byte_value.get_item_by_index(0), @minijinja.Value::from_int(1))
  assert_eq(
    byte_value.reverse(),
    @minijinja.Value::from_bytes(b"\x04\x03\x02\x01"),
  )
  assert_eq(
    vt_render("{{ x[1:-1] }}", [
      ("x", @minijinja.Value::from_bytes(b"\x01\x4c\x41\x04")),
    ]),
    "LA",
  )
  let not_byte_value = vt_ints([1, 2, 3, 4])
  assert_eq(not_byte_value.kind(), @minijinja.ValueKind::Seq)
  assert_true(!vt_iter_fails(not_byte_value))
  assert_eq(not_byte_value.debug_string(), "[1, 2, 3, 4]")
  assert_eq(
    @minijinja.Value::from_bytes(b"'foo\"").debug_string(),
    "b'\\'foo\"'",
  )
}

///|
struct VtCmpX {
  v : Int
}

///|
impl @minijinja.Object for VtCmpX with fn repr(_self) {
  Plain
}

///|
impl @minijinja.Object for VtCmpX with fn render(self) {
  // Today these compare by string fallback
  Some(self.v.to_string())
}

///|
test "value: plain_object_compare" {
  let v1 = @minijinja.Value::from_object(VtCmpX::{ v: 4, })
  let v1_clone = v1
  let v2 = @minijinja.Value::from_object(VtCmpX::{ v: 0, })
  assert_true(v1 == v1_clone)
  assert_true(v1 >= v1_clone)
  assert_true(v2 < v1)
  assert_true(v2 != v1)
  assert_true(v1 != vt_ints([1, 2, 3]))
  assert_true(v1 > vt_ints([1, 2, 3]))
}

///|
/// `Object::custom_cmp` does not exist in the MoonBit port; the objects
/// fall back to comparing by their rendered string, which yields the same
/// order here.
test "value: custom_object_compare" {
  let nums = [4, 3, 2, 1, 0].map(i => {
    @minijinja.Value::from_object(VtCmpX::{ v: i, })
  })
  let seq = @minijinja.Value::from_array(nums)
  let rv = vt_render("{{ seq|sort|join('|') }}", [("seq", seq)])
  assert_eq(rv, "0|1|2|3|4")
}
