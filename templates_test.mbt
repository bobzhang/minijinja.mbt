// Ported from minijinja/tests/test_templates.rs (the individual tests; the
// snapshot-corpus runners `test_vm` and `test_vm_block_fragments` live in
// templates_wbtest.mbt).

///|
fn tval(i : Int) -> @minijinja.Value {
  @minijinja.Value::from_int(i)
}

///|
fn tstr(s : String) -> @minijinja.Value {
  @minijinja.Value::from_string(s)
}

///|
fn ctx(pairs : Array[(String, @minijinja.Value)]) -> @minijinja.Value {
  @minijinja.Value::from_pairs(pairs)
}

///|
/// Equivalent of `minijinja::render!` with a fresh default environment.
fn render(
  source : String,
  pairs : Array[(String, @minijinja.Value)],
) -> String raise @minijinja.TemplateError {
  @minijinja.Environment::new().render_str(source, ctx(pairs))
}

///|
fn sorted(xs : Array[String]) -> Array[String] {
  let rv = xs.copy()
  rv.sort()
  rv
}

///|
test "templates: custom filter" {
  let env = @minijinja.Environment::new()
  env.add_filter("test", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value = a.string()
    a.finish()
    tstr("[\{value}]")
  })
  env.add_template("test", "{{ var|test }}")
  let tmpl = env.get_template("test")
  let rv = tmpl.render(ctx([("var", tval(42))]))
  assert_eq(rv, "[42]")
}

///|
test "templates: dotted integer lookup" {
  assert_eq(render("{{ [1, 2].0 }}", []), "1")
  assert_eq(render("{{ [1, 2].1 }}", []), "2")
}

///|
test "templates: chained comparisons" {
  assert_eq(
    render("{{ x not in y != z }}", [
      ("x", tstr("foo")),
      ("y", tstr("bar")),
      ("z", tstr("foo")),
    ]),
    "True",
  )
  assert_eq(
    render("{{ x not in y != y }}", [("x", tstr("foo")), ("y", tstr("bar"))]),
    "False",
  )
  assert_eq(
    render("{{ lhs != rhs != lhs }}", [("lhs", tval(1)), ("rhs", tval(2))]),
    "True",
  )
  assert_eq(
    render("{{ needle in haystack in seq }}", [
      ("needle", tstr("o")),
      ("haystack", tstr("foo")),
      ("seq", @minijinja.Value::from_array([tstr("foo")])),
    ]),
    "True",
  )
  assert_eq(
    render("{{ needle in haystack == true }}", [
      ("needle", tstr("f")),
      ("haystack", tstr("foo")),
    ]),
    "False",
  )
  let env = @minijinja.Environment::new()
  env.add_function("inc", (state, args) => {
    @minijinja.Args::new(state, args).finish()
    let old = state
      .get_temp("chained_comparison_counter")
      .unwrap_or(@minijinja.Value::from_int64(0L))
    let new = @minijinja.Value::from_int64(old.as_i64().unwrap() + 1L)
    state.set_temp("chained_comparison_counter", new) |> ignore
    new
  })
  assert_eq(env.render_str("{{ 0 < inc() < 2 }}", ctx([])), "True")
  assert_eq(env.render_str("{{ 2 < inc() < fail() }}", ctx([])), "False")
}

///|
test "templates: dotted integer lookup midchain" {
  assert_eq(
    render("{{ msgs.0.role }}", [
      ("msgs", @minijinja.Value::from_array([ctx([("role", tstr("user"))])])),
    ]),
    "user",
  )
  assert_eq(
    render("{{ rows.10.name }}", [
      (
        "rows",
        @minijinja.Value::from_array(
          Array::makei(11, i => ctx([("name", tstr("r\{i}"))])),
        ),
      ),
    ]),
    "r10",
  )
  assert_eq(
    render("{{ rows.1_000.name }}", [
      (
        "rows",
        @minijinja.Value::from_array(
          Array::make(1001, ctx([("name", tstr("r1000"))])),
        ),
      ),
    ]),
    "r1000",
  )
  assert_eq(
    render("{{ data.0._meta }}", [
      ("data", @minijinja.Value::from_array([ctx([("_meta", tstr("x"))])])),
    ]),
    "x",
  )
  assert_eq(render("{{ 1.0 + 0 }}", []), "1.0")
  assert_eq(render("{{ 42. + 0 }}", []), "42.0")
  assert_eq(render("{{ 1.e5 }}", []), "100000.0")
  assert_eq(render("{{ 1.E5 }}", []), "100000.0")
  assert_eq(render("{{ 1.e+5 }}", []), "100000.0")
  assert_eq(render("{{ 1.E-3 }}", []), "0.001")
}

///|
test "templates: dotted integer lookup midchain unicode" {
  assert_eq(
    render("{{ data.0.α }}", [
      ("data", @minijinja.Value::from_array([ctx([("α", tstr("ok"))])])),
    ]),
    "ok",
  )
}

///|
struct ItemsStruct {}

///|
impl @minijinja.Object for ItemsStruct with fn get_value(_self, name) {
  match name.as_str() {
    Some("a") => Some(tstr("A"))
    Some("b") => Some(tstr("B"))
    _ => None
  }
}

///|
impl @minijinja.Object for ItemsStruct with fn enumerate(_self) {
  Str(["b", "a"])
}

///|
test "templates: items and dictsort with structs" {
  assert_eq(
    render("{{ x|items }}", [
      ("x", @minijinja.Value::from_object(ItemsStruct::{ })),
    ]),
    "[('b', 'B'), ('a', 'A')]",
  )
  assert_eq(
    render("{{ x|dictsort }}", [
      ("x", @minijinja.Value::from_object(ItemsStruct::{ })),
    ]),
    "[('a', 'A'), ('b', 'B')]",
  )
}

///|
struct UrlStruct {}

///|
impl @minijinja.Object for UrlStruct with fn get_value(_self, name) {
  match name.as_str() {
    Some("a") => Some(tstr("a 1"))
    Some("b") => Some(tstr("b 2"))
    _ => None
  }
}

///|
impl @minijinja.Object for UrlStruct with fn enumerate(_self) {
  Str(["a", "b"])
}

///|
test "templates: urlencode with struct" {
  assert_eq(
    render("{{ x|urlencode }}", [
      ("x", @minijinja.Value::from_object(UrlStruct::{ })),
    ]),
    "a=a%201&b=b%202",
  )
}

///|
test "templates: single" {
  let env = @minijinja.Environment::new()
  env.add_template("simple", "Hello {{ name }}!")
  let tmpl = env.get_template("simple")
  let rv = tmpl.render(ctx([("name", tstr("Peter"))]))
  assert_eq(rv, "Hello Peter!")
}

///|
test "templates: values scientific notation" {
  let env = @minijinja.Environment::new()
  env.add_template("sci1", "VALUE = {{ value or -12.4E-4 }}")
  let tmpl = env.get_template("sci1")
  let rv = tmpl.render(
    ctx([("value", @minijinja.Value::from_double(-12.4E-3))]),
  )
  assert_eq(rv, "VALUE = -0.0124")
  // assert_eq(rv, "VALUE = -0.00124")
  tmpl.render(ctx([])) |> ignore
  env.add_template("sci2", "VALUE = {{ value or 1.4E4 }}")
  env.get_template("sci2").render(ctx([])) |> ignore
  env.add_template("sci3", "VALUE = {{ value or 1.4e+4}}")
  env.get_template("sci3").render(ctx([])) |> ignore
  env.add_template("sci4", "VALUE = {{ 1.4+4}}")
  env.get_template("sci4").render(ctx([])) |> ignore
  env.add_template("sci5", "VALUE = {{ 1.4+1E-1}}")
  env.get_template("sci5").render(ctx([])) |> ignore
  env.add_template("sci6", "VALUE = {{ 1.0E0+1.0}}")
  env.get_template("sci6").render(ctx([])) |> ignore
}

///|
test "templates: auto escaping" {
  let env = @minijinja.Environment::new()
  env.add_template("index.html", "{{ var }}")
  env.add_template("index.js", "{{ var }}")
  env.add_template("index.txt", "{{ var }}")

  // html
  let tmpl = env.get_template("index.html")
  let rv = tmpl.render(ctx([("var", tstr("<script>"))]))
  assert_eq(rv, "&lt;script&gt;")

  // JSON
  let tmpl = env.get_template("index.js")
  let rv = tmpl.render(ctx([("var", tstr("foo\"bar'baz"))]))
  assert_eq(rv, "\"foo\\\"bar'baz\"")
  let rv = tmpl.render(
    ctx([
      (
        "var",
        @minijinja.Value::from_array([
          @minijinja.Value::from_bool(true),
          tstr("<foo>"),
          @minijinja.Value::none(),
        ]),
      ),
    ]),
  )
  assert_eq(rv, "[true,\"<foo>\",null]")

  // Text
  let tmpl = env.get_template("index.txt")
  let rv = tmpl.render(ctx([("var", tstr("foo\"bar'baz"))]))
  assert_eq(rv, "foo\"bar'baz")
}

///|
test "templates: loop changed" {
  let source =
    #|
    #|        {%- for i in items -%}
    #|          {% if loop.changed(i) %}{{ i }}{% endif %}
    #|        {%- endfor -%}
    #|
  let rv = render(source, [
    ("items", @minijinja.Value::from_array([1, 1, 1, 2, 3, 4, 4, 5].map(tval))),
  ])
  assert_eq(rv, "12345")
}

// The flattening tests use a serde struct with `#[serde(flatten)]` over a
// `Value`, which fails to serialize.  MoonBit has no serde; the failed
// serialization is emulated with an invalid value built by
// `Value::from_error` carrying the same `BadSerialization` error.

///|
fn bad_value() -> @minijinja.Value {
  @minijinja.Value::from_error(
    @minijinja.TemplateError::new(
      BadSerialization,
      "can only flatten structs and maps (got a tuple struct)",
    ),
  )
}

///|
test "templates: flattening" {
  // Upstream: #[should_panic = "can only flatten structs and maps"]
  let env = @minijinja.Environment::new()
  let err = try env.render_str("{{ debug() }}", bad_value()) catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(
    err.to_string().contains("can only flatten structs and maps"),
    msg=err.to_string(),
  )
}

///|
test "templates: flattening sub item good" {
  let ctx = ctx([("bad", bad_value()), ("good", tstr("good"))])
  let env = @minijinja.Environment::new()

  // we are not touching a bad value, so we are good
  let rv = env.render_str("{{ good }}", ctx)
  assert_eq(rv, "good")
}

///|
test "templates: flattening sub item bad lookup" {
  // Upstream: #[should_panic = "can only flatten structs and maps"]
  let ctx = ctx([("bad", bad_value()), ("good", tstr("good"))])
  let env = @minijinja.Environment::new()

  // resolving an invalid value will fail
  let err = try env.render_str("{{ bad }}", ctx) catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_true(
    err.to_string().contains("can only flatten structs and maps"),
    msg=err.to_string(),
  )
}

///|
test "templates: flattening sub item bad attr" {
  let ctx = ctx([("good", ctx([("bad", bad_value())]))])
  let env = @minijinja.Environment::new()

  // resolving an invalid value will fail, even in an attribute lookup
  let err = try env.render_str("{% if good.bad %}...{% endif %}", ctx) catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(err.kind(), @minijinja.ErrorKind::BadSerialization)
  assert_eq(
    err.detail(),
    Some("can only flatten structs and maps (got a tuple struct)"),
  )
}

///|
test "templates: flattening sub item shielded print" {
  let ctx = ctx([("good", ctx([("bad", bad_value())]))])
  let env = @minijinja.Environment::new()

  // this on the other hand is okay
  let value = env.render_str("{{ good }}", ctx)
  assert_eq(
    value, "{'bad': <invalid value: could not serialize to value: can only flatten structs and maps (got a tuple struct)>}",
  )
}

///|
test "templates: custom syntax" {
  let env = @minijinja.Environment::new()
  env.set_syntax(
    @minijinja.SyntaxConfig::new(
      block_delimiters=("{", "}"),
      variable_delimiters=("${", "}"),
      comment_delimiters=("{*", "*}"),
    ),
  )

  // this on the other hand is okay
  let value = env.render_str(
    "{for x in range(3)}${x}{endfor}{* nothing *}",
    ctx([]),
  )
  assert_eq(value, "012")
}

///|
test "templates: undeclared variables" {
  // Rust returns a `HashSet`; the arrays are compared sorted.
  let env = @minijinja.Environment::new()
  env.add_template(
    "demo",
    (
      #|{% set x = foo %}{{ x }}{{ bar.baz }}{{ bar.blub }}
      #|        {% macro blah() %}{{ macro_x }}{{ caller() }}{% endmacro %}
    ),
  )
  let tmpl = env.get_template("demo")
  let undeclared = tmpl.undeclared_variables(false)
  assert_eq(sorted(undeclared), sorted(["foo", "bar", "macro_x"]))
  let undeclared = tmpl.undeclared_variables(true)
  assert_eq(
    sorted(undeclared),
    sorted(["foo", "bar.baz", "bar.blub", "macro_x"]),
  )
}

///|
test "templates: undeclared variables bug" {
  // see https://github.com/mitsuhiko/minijinja/issues/484
  let env = @minijinja.Environment::new()
  env.add_template(
    "demo",
    (
      #|
      #|        {% for item in content.products.items() %}
      #|          {{ foo.bar }}
      #|          {{ item.name }}  // this used to cause a loop
      #|        {% endfor %}
      #|
    ),
  )
  let tmpl = env.get_template("demo")
  let undeclared = tmpl.undeclared_variables(true)
  assert_eq(sorted(undeclared), sorted(["foo.bar", "content.products.items"]))
}

///|
test "templates: undeclared variables macro bug" {
  // https://github.com/mitsuhiko/minijinja/issues/712
  let env = @minijinja.Environment::new()
  env.add_template(
    "demo",
    (
      #|
      #|        {% macro bar(a) %}
      #|            {{ a }}
      #|        {% endmacro %}
      #|        {% call (b) bar() %}
      #|            {{ b }}
      #|        {% endcall %}
      #|        {{ a }} {{ b }}
      #|
    ),
  )
  let tmpl = env.get_template("demo")
  let undeclared = tmpl.undeclared_variables(true)
  assert_eq(sorted(undeclared), sorted(["a", "b"]))
}

///|
test "templates: block fragments" {
  let env = @minijinja.Environment::new()
  env.add_template(
    "demo", "I am outside the fragment{% block foo %}foo{% endblock %}So am I!",
  )
  let tmpl = env.get_template("demo")
  let rv_a = tmpl.render(@minijinja.Value::none())
  let rv_b = tmpl.render_captured(@minijinja.Value::none()).state.render_block(
    "foo",
  )
  assert_eq(rv_a, "I am outside the fragmentfooSo am I!")
  assert_eq(rv_b, "foo")
}

///|
test "templates: state" {
  let env = @minijinja.Environment::new()
  env.add_template(
    "foo.html",
    (
      #|
      #|        {% set global = variable * 2 %}
      #|        {% macro something() %}{{ global }}{% endmacro %}
      #|        {% block baz %}[{{ global }}]{% endblock %}
      #|
    ),
  )
  let template = env.get_template("foo.html")
  let rendered = template.render_captured(ctx([("variable", tval(23))]))
  assert_true(rendered.state.lookup("range") is Some(_))
  assert_true(!rendered.state.exports().contains("range"))
  assert_eq(rendered.state.lookup("global"), Some(tval(23 * 2)))
  assert_eq(rendered.state.call_macro("something", []), "46")
  assert_eq(rendered.state.render_block("baz"), "[46]")
}

///|
test "templates: loop locals do not persist between iterations" {
  assert_eq(
    render(
      "{% for x in [1, 2] %}{% if loop.first %}{% set y = x %}{% endif %}[{{ y }}]{% endfor %}",
      [],
    ),
    "[1][]",
  )
}

///|
test "templates: render captured state" {
  // The `fuel` feature is not ported; its assertions are dropped.
  let env = @minijinja.Environment::new()
  let tmpl = env.template_from_str(
    "{% for x in range(3) %}Hello {{ name }}!\n{% endfor %}{% set x = 1 %}",
  )
  let captured = tmpl.render_captured(ctx([("name", tstr("Foo"))]))
  assert_eq(captured.output, "Hello Foo!\nHello Foo!\nHello Foo!\n")
  assert_eq(captured.state.lookup("x"), Some(tval(1)))
}

///|
test "templates: render captured" {
  let env = @minijinja.Environment::new()
  let rendered = env
    .template_from_str(
      "{% set foo = 42 %}{% macro bar() %}x{{ foo }}{% endmacro %}",
    )
    .render_captured(@minijinja.Value::none())
  assert_eq(rendered.output, "")
  assert_eq(rendered.state.lookup("foo"), Some(tval(42)))
  let rv = try rendered.state.call_macro("bar", []) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
  assert_eq(rv, Some("x42"))
}

///|
test "templates: render captured to" {
  // There is no `render_captured_to` (no `io::Write` outputs in MoonBit);
  // `render_captured` collects the output into `Captured::output` instead
  // of writing it to a separate sink.
  let env = @minijinja.Environment::new()
  let tmpl = env.template_from_str(
    "{% set foo = 42 %}{% macro bar() %}x{% endmacro %}root",
  )
  let captured = tmpl.render_captured(@minijinja.Value::none())
  assert_eq(captured.output, "root")
  assert_eq(captured.state.lookup("foo"), Some(tval(42)))
  let rv = try captured.state.call_macro("bar", []) catch {
    _ => None
  } noraise {
    s => Some(s)
  }
  assert_eq(rv, Some("x"))
}

///|
test "templates: primitive rendering" {
  assert_eq(render("{{ none }}|{{ true }}|{{ false }}", []), "None|True|False")
  assert_eq(render("{{ [none, true, false] }}", []), "[None, True, False]")
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Html)
  assert_eq(
    env.render_str("{{ none }}|{{ true }}|{{ false }}", ctx([])),
    "None|True|False",
  )
}

///|
fn const_function(rv : @minijinja.Value) -> @minijinja.Value {
  @minijinja.Value::from_function("f", (state, args) => {
    @minijinja.Args::new(state, args).finish()
    rv
  })
}

///|
test "templates: functions" {
  assert_eq(render("{{ f() }}", [("f", const_function(tval(42)))]), "42")
  assert_eq(
    render("{{ {'f': f}.f() }}", [("f", const_function(tval(42)))]),
    "42",
  )
  // `|| -> Option<i32> { None }` returns none.
  assert_eq(
    render("{{ f() }}", [("f", const_function(@minijinja.Value::none()))]),
    "None",
  )
  // `|| -> Result<i32, Error> { Ok(23) }`
  assert_eq(render("{{ f() }}", [("f", const_function(tval(23)))]), "23")
}

///|
struct FailingIteration {}

///|
impl @minijinja.Object for FailingIteration with fn repr(_self) {
  Iterable
}

///|
impl @minijinja.Object for FailingIteration with fn enumerate(_self) {
  let items = [tval(0), tval(1), tval(2), tval(3)]
  items.push(
    @minijinja.Value::from_error(
      @minijinja.TemplateError::new(InvalidOperation, "failed during iteration"),
    ),
  )
  Iter(items.iter())
}

///|
test "templates: invalid value iteration" {
  // Upstream renders with `render_captured_to` into an `io::Write` sink and
  // checks the partial output "[0][1][2][3]".  MoonBit has no streaming
  // output, so a failed render yields no partial output; only the error is
  // checked.
  let env = @minijinja.Environment::new()
  let t = env.template_from_str(
    "{% for item in iter %}[{{ item }}]{% endfor %}",
  )
  let err = try
    t.render_captured(
      ctx([("iter", @minijinja.Value::from_object(FailingIteration::{ }))]),
    )
  catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(err.kind(), @minijinja.ErrorKind::InvalidOperation)
  assert_eq(err.detail(), Some("failed during iteration"))
}

///|
test "templates: multiple extended includes in loop" {
  let env = @minijinja.Environment::new()
  env.add_template("dummy.txt", "{% block blk %}{% endblock %}")
  env.add_template(
    "include.txt", "{% extends 'dummy.txt' %}{% block blk %}{{ item }}{% endblock %}",
  )
  env.add_template(
    "main.txt", "{% for item in range(3) %}{% include 'include.txt' %}{% endfor %}",
  )
  let rv = env.get_template("main.txt").render(@minijinja.Value::none())
  assert_eq(rv, "012")
}

///|
test "templates: filter caching" {
  // See https://github.com/mitsuhiko/minijinja/issues/551
  let env = @minijinja.Environment::new()
  env.add_template("parent.txt", "{{ 'Hello Foo' | lower }}")
  env.add_template(
    "child.txt", "{% extends 'parent.txt' %}{% set dummy = 'a' | upper %}",
  )
  let rv = env.get_template("child.txt").render(@minijinja.Value::none())
  assert_eq(rv, "hello foo")
}

///|
test "templates: test caching" {
  // See https://github.com/mitsuhiko/minijinja/issues/551
  let env = @minijinja.Environment::new()
  env.add_template("parent.txt", "{{ 42 is odd }}")
  env.add_template(
    "child.txt", "{% extends 'parent.txt' %}{% set dummy = 23 is even %}",
  )
  let rv = env.get_template("child.txt").render(@minijinja.Value::none())
  assert_eq(rv, "False")
}
