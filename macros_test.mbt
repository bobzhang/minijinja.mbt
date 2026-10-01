// Ported from minijinja/tests/test_macros.rs.
//
// The Rust `context!`, `render!` and `args!` macros have no MoonBit
// counterpart; they are expressed with `Value::from_pairs`, `merge_maps`,
// `Environment::render_str` and plain arrays respectively.

///|
fn mval(i : Int) -> @minijinja.Value {
  @minijinja.Value::from_int(i)
}

///|
fn mstr(s : String) -> @minijinja.Value {
  @minijinja.Value::from_string(s)
}

///|
test "macros: context" {
  let var1 = 23
  let ctx = @minijinja.Value::from_pairs([
    ("var1", mval(var1)),
    ("var2", mval(42)),
  ])
  assert_eq(ctx.get_attr("var1"), mval(23))
  assert_eq(ctx.get_attr("var2"), mval(42))
}

///|
test "macros: context preserves order" {
  let ctx = @minijinja.Value::from_pairs([
    ("zebra", mval(1)),
    ("apple", mval(2)),
  ])
  let keys = ctx.try_iter().map(key => key.to_string()).collect()
  assert_eq(keys, ["zebra", "apple"])
}

///|
test "macros: context merge" {
  let one = @minijinja.Value::from_pairs([("a", mval(1))])
  let two = @minijinja.Value::from_pairs([("b", mval(2)), ("a", mval(42))])
  // `context![..one, ..two]` expands to `merge_maps([two, one])`: the
  // macro reverses its merge sources and later maps take precedence.
  let ctx = @minijinja.merge_maps([two, one])
  assert_eq(ctx.get_attr("a"), mval(1))
  assert_eq(ctx.get_attr("b"), mval(2))
  let two = @minijinja.Value::from_pairs([("b", mval(2)), ("a", mval(42))])
  // `context!(a => 1, ..two)` expands to `merge_maps([two, {a: 1}])`.
  let ctx = @minijinja.merge_maps([
    two,
    @minijinja.Value::from_pairs([("a", mval(1))]),
  ])
  assert_eq(ctx.get_attr("a"), mval(1))
  assert_eq(ctx.get_attr("b"), mval(2))
}

///|
struct MergeX {}

///|
impl @minijinja.Object for MergeX with fn get_value(_self, key) {
  match key.as_str() {
    Some("a") => Some(mval(1))
    Some("b") => Some(mval(2))
    _ => None
  }
}

///|
test "macros: context merge custom" {
  let x = @minijinja.Value::from_object(MergeX::{ })
  // `context! { a => 42, ..x }` expands to `merge_maps([x, {a: 42}])`.
  let ctx = @minijinja.merge_maps([
    x,
    @minijinja.Value::from_pairs([("a", mval(42))]),
  ])
  assert_eq(ctx.get_attr("a"), mval(42))
  assert_eq(ctx.get_attr("b"), mval(2))
}

///|
test "macros: render" {
  let env = @minijinja.Environment::new()
  let rv = env.render_str(
    "Hello {{ name }}!",
    @minijinja.Value::from_pairs([("name", mstr("World"))]),
  )
  assert_eq(rv, "Hello World!")
  let rv = @minijinja.Environment::new().render_str(
    "Hello {{ name }}!",
    @minijinja.Value::from_pairs([("name", mstr("World"))]),
  )
  assert_eq(rv, "Hello World!")
  let rv = @minijinja.Environment::new().render_str(
    "Hello World!",
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(rv, "Hello World!")
}

///|
test "macros: args" {
  // `args!` builds a `&[Value]`; in MoonBit argument lists are plain arrays
  // and kwargs are a trailing `Kwargs::to_value()`.  The `type_name_of_val`
  // assertions have no MoonBit equivalent and are dropped.
  let state = @minijinja.Environment::new().empty_state()
  let args : Array[@minijinja.Value] = []
  assert_eq(args.length(), 0)
  let args = [mval(1), mval(2)]
  assert_eq(args[0], mval(1))
  assert_eq(args[1], mval(2))
  let args = [
    mval(1),
    mval(2),
    @minijinja.Kwargs::from_pairs([("foo", mval(42)), ("bar", mval(23))]).to_value(),
  ]
  assert_eq(args[0], mval(1))
  assert_eq(args[1], mval(2))
  let kwargs = @minijinja.Args::new(state, [args[2]]).kwargs()
  assert_eq(kwargs.get_int("foo"), Some(42L))
  assert_eq(kwargs.get_int("bar"), Some(23L))
  assert_true(args[2].is_kwargs())
}

///|
test "macros: macro passing" {
  let env = @minijinja.Environment::new()
  let tmpl = env.template_from_str("{% macro m(a) %}{{ a }}{% endmacro %}")
  let rendered = tmpl.render_captured(@minijinja.Value::none())
  let m = rendered.state.lookup("m").unwrap()
  assert_eq(m.get_attr("name").as_str(), Some("m"))
  let rv = m.call(rendered.state, [mval(42)])
  assert_eq(rv.as_str(), Some("42"))

  // if we call the macro on an empty state it errors
  let empty_state = env.empty_state()
  let err = try m.call(empty_state, [mval(42)]) catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(err.kind(), @minijinja.ErrorKind::InvalidOperation)
  assert_eq(
    err.detail(),
    Some("cannot call this macro. template state went away."),
  )
}

///|
struct LeakX {}

///|
impl @minijinja.Object for LeakX with fn get_value(_self, _name) {
  None
}

///|
test "macros: no leak" {
  // The Rust test also asserts that the object is dropped (via `Drop`).
  // MoonBit is garbage collected, so only the rendered output is checked.
  let ctx = @minijinja.Value::from_pairs([
    ("x", @minijinja.Value::from_object(LeakX::{ })),
  ])
  let env = @minijinja.Environment::new()
  env.add_template("x", "{% macro meh() %}{{ x }}{{ meh }}{% endmacro %}")
  let rv = env.render_str(
    (
      #|
      #|        {%- from 'x' import meh %}
      #|        {{- meh() }}
      #|        {%- set closure = x %}
      #|        {%- macro foo() %}{{ foo }}{{ closure }}{% endmacro %}
      #|        {{- foo() -}}
      #|
      #|        {%- for y in range(3) %}
      #|            {%- set closure = x %}
      #|            {%- macro foo() %}{{ foo }}{{ closure }}{% endmacro %}
      #|            {{- foo() -}}
      #|        {%- endfor -%}
      #|
    ),
    ctx,
  )
  assert_eq(
    rv, "{}<macro meh><macro foo>{}<macro foo>{}<macro foo>{}<macro foo>{}",
  )
}

///|
test "macros: nested macro bug" {
  // https://github.com/mitsuhiko/minijinja/issues/434
  let rv = @minijinja.Environment::new().render_str(
    (
      #|
      #|    {% set a = 42 %}
      #|    {% macro m1(var) -%}
      #|      {{ var }}
      #|    {%- endmacro %}
      #|
      #|    {% macro m2(x=a) -%}
      #|      {{ m1(x) }}
      #|    {%- endmacro %}
      #|
      #|    {{ m2() }}
      #|
    ),
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(rv.trim().to_owned(), "42")
}

///|
test "macros: nested macro can escape invocation" {
  let rv = @minijinja.Environment::new().render_str(
    (
      #|
      #|        {%- set first = namespace() -%}
      #|        {%- set second = namespace() -%}
      #|        {%- macro outer(target, value) -%}
      #|            {%- macro inner() -%}{{ value }}{%- endmacro -%}
      #|            {%- set target.inner = inner -%}
      #|        {%- endmacro -%}
      #|        {{- outer(first, "first") -}}
      #|        {{- outer(second, "second") -}}
      #|        {{- first.inner() }}|{{ second.inner() -}}
      #|
    ),
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(rv, "first|second")
}

///|
test "macros: nested macro can escape into state" {
  let env = @minijinja.Environment::new()
  env.add_function("stash", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.value()
    a.finish()
    state.set_temp("macro", value) |> ignore
    mstr("")
  })
  env.add_function("call_stashed", (state, args) => {
    @minijinja.Args::new(state, args).finish()
    let value = state.get_temp("macro").unwrap()
    value.call(state, [])
  })
  let rv = env.render_str(
    (
      #|
      #|            {%- macro outer(value) -%}
      #|                {%- macro inner() -%}{{ value }}{%- endmacro -%}
      #|                {{- stash(inner) -}}
      #|            {%- endmacro -%}
      #|            {{- outer("captured") -}}
      #|            {{- call_stashed() -}}
      #|
    ),
    @minijinja.Value::none(),
  )
  assert_eq(rv, "captured")
}

///|
test "macros: escaped macro survives failed invocation" {
  // `State::get_or_insert_extension` is replaced by a state temp.
  let env = @minijinja.Environment::new()
  env.add_function("stash", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.value()
    a.finish()
    state.set_temp("macro", value) |> ignore
    let calls = match state.get_temp("calls") {
      Some(v) => v.as_i64().unwrap() + 1L
      None => 1L
    }
    state.set_temp("calls", @minijinja.Value::from_int64(calls)) |> ignore
    if calls == 1L {
      mstr("")
    } else {
      raise @minijinja.TemplateError::new(InvalidOperation, "boom")
    }
  })
  let captured = env
    .template_from_str(
      (
        #|
        #|            {%- block body -%}
        #|                {%- macro outer(value) -%}
        #|                    {%- macro inner() -%}{{ value }}{%- endmacro -%}
        #|                    {{- stash(inner) -}}
        #|                {%- endmacro -%}
        #|                {{- outer("captured") -}}
        #|            {%- endblock -%}
        #|
      ),
    )
    .render_captured(@minijinja.Value::none())
  try captured.state.render_block("body") catch {
    _ => ()
  } noraise {
    _ => fail("expected an error")
  }
  let value = captured.state.get_temp("macro").unwrap()
  let rv = value.call(captured.state, [])
  assert_eq(rv.as_str(), Some("captured"))
}

///|
test "macros: caller bug" {
  // https://github.com/mitsuhiko/minijinja/issues/434
  let rv = @minijinja.Environment::new().render_str(
    (
      #|
      #|    {% set a = 42 %}
      #|    {% set b = 23 %}
      #|
      #|    {% macro m1(var) -%}
      #|      {{ caller(var) }}
      #|    {%- endmacro %}
      #|
      #|    {% macro m2(x=a) -%}
      #|      {% call(var) m1(x) %}{{ var }}|{{ b }}{% endcall %}
      #|    {%- endmacro %}
      #|
      #|    {{ m2() }}
      #|
    ),
    @minijinja.Value::from_pairs([]),
  )
  assert_eq(rv.trim().to_owned(), "42|23")
}

///|
test "macros: unenclosed resolve" {
  // https://github.com/mitsuhiko/minijinja/issues/535
  // the current intended logic here is that a the state can
  // observe real globals and the initial template context, but
  // no other modifications.  Normally the call block can only
  // see what it encloses explicitly, but since it does not
  // refer to anything here it in fact has an empty closure.
  let env = @minijinja.Environment::new()
  env.add_global("ctx_global", mstr("ctx global"))
  env.add_function("resolve", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let name = a.str()
    a.finish()
    state.lookup(name).unwrap_or(@minijinja.Value::undefined())
  })
  let rv = env.render_str(
    (
      #|
      #|    {%- set template_global = 'template global' %}
      #|    {%- macro wrapper() %}{{ caller() }}{% endmacro %}
      #|    {%- call wrapper() %}
      #|        {{- resolve('render_global') }}|
      #|        {{- resolve('ctx_global') }}|
      #|        {{- resolve('template_global') }}
      #|    {%- endcall -%}
      #|
    ),
    @minijinja.Value::from_pairs([("render_global", mstr("render global"))]),
  )
  assert_eq(rv, "render global|ctx global|")
}

///|
test "macros: macro state sees enclosed variables" {
  let env = @minijinja.Environment::new()
  env.add_function("is_known", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let name = a.str()
    a.finish()
    @minijinja.Value::from_bool(
      state.known_variables().iter().any(variable => variable == name),
    )
  })
  let rv = env.render_str(
    "{% set foo = 42 %}{% macro test() %}{{ foo }}:{{ is_known('foo') }}{% endmacro %}{{ test() }}",
    @minijinja.Value::none(),
  )
  assert_eq(rv, "42:True")
}

///|
test "macros: macro callbacks can render blocks" {
  let env = @minijinja.Environment::new()
  env.add_function("render_block", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let name = a.str()
    a.finish()
    mstr(state.render_block(name))
  })
  let rv = env.render_str(
    "{% macro invoke() %}{{ render_block('body') }}{% endmacro %}{% block body %}body{% endblock %}|{{ invoke() }}|{{ render_block('body') }}",
    @minijinja.Value::none(),
  )
  assert_eq(rv, "body|body|body")
}

///|
test "macros: macro debug includes enclosed variables" {
  let env = @minijinja.Environment::new()
  let rv = env.render_str(
    "{% set captured = 'needle' %}{% macro test() %}{{ captured }}|{{ debug() }}{% endmacro %}{{ test() }}",
    @minijinja.Value::none(),
  )
  assert_true(rv.contains("\"captured\": 'needle'"), msg=rv)
}

///|
struct StateProbe {
  seen : Ref[@minijinja.State?]
}

///|
impl @minijinja.Object for StateProbe with fn call(self, state, _args) {
  // Rust compares raw `State` pointers; MoonBit uses `physical_equal`.
  // `State::get_or_insert_extension` is replaced by a state temp.
  match self.seen.val {
    None => self.seen.val = Some(state)
    Some(previous) =>
      assert_true(physical_equal(previous, state)) catch {
        _ =>
          raise @minijinja.TemplateError::new(
            InvalidOperation,
            "macro did not reuse the state",
          )
      }
  }
  let count = match state.get_temp("call_count") {
    Some(v) => v.as_i64().unwrap() + 1L
    None => 1L
  }
  let rv = @minijinja.Value::from_int64(count)
  state.set_temp("call_count", rv) |> ignore
  rv
}

///|
test "macros: macro reuses mutable state" {
  let env = @minijinja.Environment::new()
  env.add_global(
    "probe",
    @minijinja.Value::from_object(StateProbe::{ seen: Ref(None), }),
  )
  let rv = env.render_str(
    "{{ probe() }}{% macro test() %}{{ probe() }}{% endmacro %}{{ test() }}",
    @minijinja.Value::none(),
  )
  assert_eq(rv, "12")
}

// test_conversions is dropped: it exercises serde `Serialize` vs `From`
// precedence inside `context!`, which has no MoonBit equivalent.
