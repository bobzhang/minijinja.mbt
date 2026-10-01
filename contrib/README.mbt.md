# minijinja/contrib

A port of [`minijinja-contrib`](https://github.com/mitsuhiko/minijinja/tree/main/minijinja-contrib):
utilities that are too specific for the MiniJinja core.

* Filters: `pluralize`, `filesizeformat`, `truncate`, `striptags`,
  `wordcount`, `wordwrap` and `random`.
* Global functions: `cycler`, `joiner`, `randrange` and `lipsum`.
* Python compatibility: `unknown_method_callback` implements common Python
  methods on strings, maps and lists (`'x'.upper()`, `d.items()`, ...).

`add_to_environment` registers all filters and functions (but not the
`pycompat` callback, like upstream):

```mbt check
///|
test "contrib" {
  let env = @minijinja.Environment::new()
  @contrib.add_to_environment(env)
  env.set_unknown_method_callback(@contrib.unknown_method_callback)
  let ctx = @minijinja.Value::from_pairs([
    (
      "users",
      @minijinja.Value::from_array([@minijinja.Value::from_string("a")]),
    ),
    ("size", @minijinja.Value::from_int(123456)),
  ])
  inspect(
    env.render_str(
      "{{ users|length }} user{{ users|pluralize }}, {{ size|filesizeformat }}, " +
      "{{ '<b>Hi</b> &amp; bye'|striptags }}, {{ 'a long sentence'|truncate(length=10, leeway=0) }}, " +
      "{{ 'hello world'.title() }}",
      ctx,
    ),
    content="1 user, 123.5 kB, Hi & bye, a long..., Hello World",
  )
  // random functions can be seeded with the `RAND_SEED` variable
  inspect(
    env.render_str(
      "{% set RAND_SEED = 42 %}{{ randrange(10) }} {{ [1, 2, 3]|random }}",
      @minijinja.Value::none(),
    ),
    content="0 2",
  )
}
```

## Differences to upstream

* The `datetime` feature (`datetimeformat`, `dateformat`, `timeformat`
  filters and the `now()` function) is not ported: it depends on the `jiff`
  crate.
* `striptags` only knows the default entities (`&amp;`, `&lt;`, `&gt;`,
  `&quot;` and numeric references); the full HTML5 entity table of the
  `html_entities` feature is not included.
* `wordwrap` implements the non unicode aware `wordwrap` feature (characters
  up to U+10FF are one column wide, everything else two), not
  `unicode_wordwrap`.
* All features of upstream (`rand`, `wordcount`, `wordwrap`) are always
  enabled.
* `str.find` / `str.rfind` return indexes in Unicode scalar values
  (characters) instead of UTF-8 byte offsets, which is identical for ASCII
  strings.  `str.count('')` returns the number of characters plus one (like
  Python) where upstream would not terminate.
* The random number generator (the same xorshift generator as upstream) is
  kept per render in a state temp instead of a typed state extension.
  Without `RAND_SEED` it is seeded from the platform entropy source (or the
  current time where no entropy source is available).
* `cycler` takes the items as a single sequence, exactly like upstream:
  `cycler(["odd", "even"])`.
