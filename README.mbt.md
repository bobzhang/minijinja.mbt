# minijinja.mbt

A port of [MiniJinja](https://github.com/mitsuhiko/minijinja) — a powerful
but minimal dependency template engine based on the syntax and behavior of
the Jinja2 template engine for Python — to [MoonBit](https://www.moonbitlang.com).

The port follows the upstream implementation closely: the same lexer, parser,
bytecode compiler and VM, the same value model, filters, tests and functions.
It passes all of upstream's lexer, parser, compiler and template snapshot
tests (see [docs/PLAN.md](docs/PLAN.md) for the details of the port).

The library is pure MoonBit and works on all backends (`native`, `wasm`,
`wasm-gc` and `js`).

## Example

```mbt check
///|
test "hello world" {
  let env = @minijinja.Environment::new()
  env.add_template("hello.txt", "Hello {{ name }}!")
  let tmpl = env.get_template("hello.txt")
  let ctx = @minijinja.Value::from_pairs([
    ("name", @minijinja.Value::from_string("John")),
  ])
  inspect(tmpl.render(ctx), content="Hello John!")
}
```

## Template inheritance, macros and loops

```mbt check
///|
test "inheritance" {
  let env = @minijinja.Environment::new()
  env.add_template(
    "layout.html", "<title>{% block title %}{% endblock %}</title>{% block body %}{% endblock %}",
  )
  env.add_template(
    "index.html",
    (
      #|{% extends "layout.html" %}
      #|{% macro item(x) %}<li>{{ x }}</li>{% endmacro %}
      #|{% block title %}Items{% endblock %}
      #|{% block body %}<ul>{% for x in items %}{{ item(x) }}{% endfor %}</ul>{% endblock %}
    ),
  )
  let ctx = @minijinja.Value::from_pairs([
    (
      "items",
      @minijinja.Value::from_array([
        @minijinja.Value::from_string("<a>"),
        @minijinja.Value::from_int(42),
      ]),
    ),
  ])
  inspect(
    env.get_template("index.html").render(ctx),
    content="<title>Items</title><ul><li>&lt;a&gt;</li><li>42</li></ul>",
  )
}
```

HTML auto escaping is enabled for templates ending in `.html`, `.htm` and
`.xml` (`.json`, `.js` and `.yaml` use JSON escaping).

## Custom filters, tests and functions

Filters, tests and functions are functions taking the render [`State`] and
the arguments.  The [`Args`] helper implements MiniJinja's argument
conversion rules (missing and superfluous arguments, optional values,
keyword arguments):

```mbt check
///|
test "custom filter" {
  let env = @minijinja.Environment::new()
  env.add_filter("repeat", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let kwargs = a.kwargs()
    let value = a.string()
    let times = a.opt_usize().unwrap_or(2)
    let sep = kwargs.get_str("sep").unwrap_or("")
    a.finish()
    kwargs.assert_all_used()
    @minijinja.Value::from_string(Array::make(times, value).join(sep))
  })
  inspect(
    env.render_str(
      "{{ 'ab'|repeat }} {{ 'x'|repeat(3, sep='-') }}",
      @minijinja.Value::none(),
    ),
    content="abab x-x-x",
  )
}
```

Arguments can also be converted with the generic `Args::next`, which works
for every type implementing `FromValue` (`Bool`, `Int`, `Int64`, `Double`,
`String`, `Value`, `Array[T]` and `T?`):

```mbt check
///|
test "typed arguments" {
  let env = @minijinja.Environment::new()
  env.add_function("clamp", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let value : Int = a.next()
    let lo : Int = a.next()
    let hi : Int? = a.next()
    a.finish()
    let hi = hi.unwrap_or(100)
    @minijinja.Value::from_int(
      if value < lo {
        lo
      } else if value > hi {
        hi
      } else {
        value
      },
    )
  })
  inspect(
    env.render_str(
      "{{ clamp(5, 10) }} {{ clamp(500, 1) }}",
      @minijinja.Value::none(),
    ),
    content="10 100",
  )
}
```

## Loaders, captured state and streaming

Templates can be loaded on demand with a loader callback.  Rendering can
stream into a callback, and the final state can be used to render individual
blocks or call macros:

```mbt check
///|
test "loader and blocks" {
  let env = @minijinja.Environment::new()
  let sources = {
    "macros.txt": "{% macro hello(name) %}Hello {{ name }}!{% endmacro %}",
    "page.txt": "{% from 'macros.txt' import hello %}{% block title %}{{ hello(who) }}{% endblock %}",
  }
  env.set_loader(name => sources.get(name))
  let tmpl = env.get_template("page.txt")
  let ctx = @minijinja.Value::from_pairs([
    ("who", @minijinja.Value::from_string("World")),
  ])
  let out = StringBuilder()
  let state = tmpl.render_to(ctx, s => out.write_view(s))
  inspect(out.to_string(), content="Hello World!")
  inspect(state.render_block("title"), content="Hello World!")
  inspect(
    state.call_macro("hello", [@minijinja.Value::from_string("Moon")]),
    content="Hello Moon!",
  )
}
```

## Dynamic objects

Implement the [`Object`] trait to expose your own types to templates:

```mbt check
///|
struct Point {
  x : Int
  y : Int
}

///|
impl @minijinja.Object for Point with fn get_value(self, key) {
  match key.as_str() {
    Some("x") => Some(@minijinja.Value::from_int(self.x))
    Some("y") => Some(@minijinja.Value::from_int(self.y))
    _ => None
  }
}

///|
impl @minijinja.Object for Point with fn enumerate(_self) {
  Str(["x", "y"])
}

///|
test "objects" {
  let env = @minijinja.Environment::new()
  let ctx = @minijinja.Value::from_pairs([
    ("p", @minijinja.Value::from_object(Point::{ x: 1, y: 2, })),
  ])
  inspect(
    env.render_str("{{ p.x }},{{ p.y }} {{ p|list }}", ctx),
    content="1,2 ['x', 'y']",
  )
}
```

## Expressions

```mbt check
///|
test "expressions" {
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("number < 42 and name is defined")
  let ctx = @minijinja.Value::from_pairs([
    ("number", @minijinja.Value::from_int(23)),
    ("name", @minijinja.Value::from_string("x")),
  ])
  inspect(expr.eval(ctx), content="True")
}
```

## Errors

Errors carry the kind, a detail message and the location.  When the debug
mode is enabled (the default), errors raised during rendering also carry the
template source and the referenced variables:

```mbt check
///|
test "errors" {
  let env = @minijinja.Environment::new()
  env.add_template("bad.txt", "{{ [1, 2] + 23 }}")
  let tmpl = env.get_template("bad.txt")
  try tmpl.render(@minijinja.Value::none()) catch {
    err => {
      inspect(err.kind() == InvalidOperation, content="true")
      inspect(
        err,
        content="invalid operation: tried to use + operator on unsupported types sequence and number (in bad.txt:1)",
      )
    }
  } noraise {
    _ => fail("expected an error")
  }
}
```

## Differences to MiniJinja

* Values are built with constructors (`Value::from_string`, `from_int`,
  `from_array`, `from_pairs`, `from_json_str`, ...) instead of `From` and
  `serde`.
* Maps keep their insertion order (like the `preserve_order` feature).
* Spans and `TemplateError::range` use UTF-16 offsets (lines and columns
  match upstream).
* `AutoEscape::None` is called `AutoEscape::NoEscape`, `ValueKind::None` is
  `ValueKind::Null`.
* Not ported: the `datetime` feature of `minijinja-contrib`, and parts of
  the CLI (see below).

## Contrib

The [`contrib`](contrib/) package ports `minijinja-contrib`: Python
compatibility methods (`unknown_method_callback`), extra filters
(`pluralize`, `filesizeformat`, `truncate`, `striptags`, `wordcount`,
`wordwrap`, `random`) and globals (`cycler`, `joiner`, `randrange`,
`lipsum`).  See [contrib/README.mbt.md](contrib/README.mbt.md).

## Command line tool

[`cmd/minijinja`](cmd/minijinja/) ports `minijinja-cli` (the logic lives in
the testable [`cli`](cli/) package, `@cli.run`).  It runs on the `native`
and `wasm` backends and does its I/O through `moonbitlang/async`:

```
moon run cmd/minijinja -- hello.j2 hello.json
moon run cmd/minijinja -- --template='Hello {{ name }}!' -Dname=World
moon run cmd/minijinja -- --expr '1 + 1'
moon run cmd/minijinja -- --help
```

All options of the upstream tool are supported except the ones listed
below, with the same semantics, error messages and exit codes (`2` for usage
errors, `1` for failures, the result for `--expr-out=status`): `-f/--format`,
`-a/--autoescape`, `-D/--define`, `--strict`, `--no-include`, `--safe-path`,
`--fuel`, `-n/--no-newline`, `--trim-blocks`, `--lstrip-blocks`,
`--py-compat`, `-s/--syntax`, `--env`, `-t/--template`, `-E/--expr`,
`--expr-out`, `--dump`, `-o/--output`, `--select`, `--help`, `--long-help`,
`--syntax-help`, `-V/--version` and the `MINIJINJA_*` environment variables.
Contrib filters and globals are always enabled.

Not ported: the `yaml`, `toml`, `cbor`, `ini` and `json5` data formats (only
`json` and `querystring` are available), the TOML config file
(`--config-file`, `--print-config`), `--repl` and `--generate-completion`.
Template paths are normalized lexically instead of being canonicalized.

## License

Apache-2.0, like the original project.  MiniJinja is © Armin Ronacher.
