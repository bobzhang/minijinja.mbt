// Additional filter and global tests (not ported from upstream).

///|
test "striptags entities" {
  assert_eq(@contrib.striptags("&#65;&#x42;&#X43;&#+68;"), "ABCD")
  assert_eq(@contrib.striptags("&#xD800; &#1114112;"), "&#xD800; &#1114112;")
  assert_eq(@contrib.striptags("&quot;a&lt;b&quot;"), "\"a<b\"")
  assert_eq(@contrib.striptags("a&#32;&#32;b"), "a b")
  assert_eq(@contrib.striptags("a\u{3000}\n b"), "a b")
  assert_eq(render("{{ '<p>x</p>  y'|striptags }}"), "x y")
  assert_eq(render("{{ 42|striptags }}"), "42")
}

///|
test "truncate extras" {
  assert_eq(render("{{ none|truncate }}"), "")
  assert_eq(render("{{ undefined_var|truncate }}"), "")
  assert_eq(
    render_err("{{ 42|truncate }}"),
    "invalid operation: expected string, got number (in <string>:1)",
  )
  assert_eq(
    render_err("{{ 'x'|truncate(foo=1) }}"),
    "too many arguments: unknown keyword argument 'foo' (in <string>:1)",
  )
  // the leeway defaults to TRUNCATE_LEEWAY
  assert_eq(
    render("{{ 'Fifteen chars !'|truncate(length=10) }}", ctx=[
      ("TRUNCATE_LEEWAY", @minijinja.Value::from_int(0)),
    ]),
    "Fifteen...",
  )
}

///|
test "wordwrap extras" {
  assert_eq(render("{{ ''|wordwrap }}"), "")
  assert_eq(render("{{ '  \\n '|wordwrap }}"), "")
  assert_eq(render("{{ 'a b c'|wordwrap(width=3) }}"), "a b\nc")
  assert_eq(render("{{ 'a\\r\\nb'|wordwrap(width=3) }}"), "a\nb")
  assert_eq(
    render("{{ 'aaa bbb ccc'|wordwrap(width=7, wrapstring='|') }}"),
    "aaa bbb|ccc",
  )
  assert_eq(
    render_err("{{ 'x'|wordwrap(foo=1) }}"),
    "too many arguments: unknown keyword argument 'foo' (in <string>:1)",
  )
}

///|
test "filesizeformat extras" {
  assert_eq(@contrib.filesizeformat(1.0), "1 Byte")
  assert_eq(@contrib.filesizeformat(-2048.0), "-2.0 kB")
  assert_eq(@contrib.filesizeformat(3.0e6, binary=true), "2.9 MiB")
  assert_eq(render("{{ 1048576|filesizeformat(false) }}"), "1.0 MB")
}

///|
test "pluralize extras" {
  assert_eq(render("{{ 'x'|pluralize }}"), "")
  assert_eq(render("{{ 'xs'|pluralize }}"), "s")
  assert_eq(render("{{ {'a': 1}|pluralize('y', 'ies') }}"), "y")
  assert_eq(render("{{ true|pluralize }}"), "")
  assert_eq(render("{{ 1.0|pluralize }}"), "")
}

///|
test "globals extras" {
  assert_eq(
    render_err("{{ cycler([]) }}"),
    "invalid operation: at least one value required (in <string>:1)",
  )
  assert_eq(
    render_err("{{ cycler() }}"),
    "invalid operation: at least one value required (in <string>:1)",
  )
  assert_eq(
    render_err("{{ cycler(1) }}"),
    "invalid operation: not iterable (in <string>:1)",
  )
  assert_eq(
    render(
      "{% set c = cycler(range(3)) %}{{ c.next() }}{{ c.next() }}{{ c.next() }}{{ c.next() }}",
    ),
    "0120",
  )
  assert_eq(
    render_err("{% set j = joiner() %}{{ j(1) }}"),
    "too many arguments (in <string>:1)",
  )
  assert_eq(
    render(
      "{% set j = joiner(' / ') %}{% for x in [1, 2, 3] %}{{ j() }}{{ x }}{% endfor %}",
    ),
    "1 / 2 / 3",
  )
}
