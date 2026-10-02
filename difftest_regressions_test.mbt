///|
/// Divergences from upstream found by differential testing (`difftest/`).
fn dt_render(
  source : String,
  name? : String = "t.txt",
) -> String raise @minijinja.TemplateError {
  let env = @minijinja.Environment::new()
  env.add_template(name, source)
  let ctx = @minijinja.Value::from_pairs([
    ("big", @minijinja.Value::from_json_str("9223372036854775807")),
    (
      "words",
      @minijinja.Value::from_array([@minijinja.Value::from_string("w")]),
    ),
  ])
  env.get_template(name).render(ctx) catch {
    err => {
      let sb = StringBuilder()
      sb.write_string("error: \{err}")
      let mut source = err.source()
      while source is Some(e) {
        sb.write_string(" / caused by: \{e}")
        source = e.source()
      }
      sb.to_string()
    }
  }
}

///|
test "difftest: range takes isize" {
  inspect(
    dt_render("{{ range(1.5) }}"),
    content="error: invalid operation: cannot convert number to isize (in t.txt:1)",
  )
}

///|
test "difftest: map * iterable is an unsupported operation" {
  inspect(
    dt_render("{{ dict() * range(1) }}"),
    content="error: invalid operation: tried to use * operator on unsupported types map and iterator (in t.txt:1)",
  )
}

///|
test "difftest: format errors show the first UTF-8 byte" {
  inspect(
    dt_render("{{ '%é'|format }}"),
    content="error: invalid operation: invalid conversion type 'Ã' in format spec at offset 1 (in t.txt:1)",
  )
}

///|
test "difftest: float parsing follows Rust" {
  inspect(
    dt_render("{{ ''|float }}"),
    content="error: invalid operation: cannot parse float from empty string (in t.txt:1)",
  )
  inspect(
    dt_render("{{ '1e'|float }}"),
    content="error: invalid operation: invalid float literal (in t.txt:1)",
  )
  inspect(
    dt_render("{{ '.5'|float }} {{ '5.'|float }} {{ '+1e2'|float }}"),
    content="0.5 5.0 100.0",
  )
  inspect(dt_render("{{ 'nan'|float }} {{ '-inf'|float }}"), content="NaN -inf")
}

///|
test "difftest: repetition counts are 64 bit" {
  inspect(dt_render("[{{ '' * big }}][{{ [] * big }}]"), content="[][[]]")
  inspect(
    dt_render("{{ 'ab' * big }}"),
    content="error: invalid operation: repeated string is too large (in t.txt:1)",
  )
}

///|
test "difftest: JSON serialization errors carry a plain cause" {
  inspect(
    dt_render("{{ {words: 1} }}", name="t.json"),
    content="error: could not serialize to value: unable to format to JSON (in t.json:1) / caused by: key must be a string",
  )
}

///|
test "difftest: loops over strings have no known length" {
  inspect(
    dt_render(
      "{% for c in 'ab' %}{{ loop }} {{ loop.length is undefined }} {{ loop.last }} {% endfor %}{% for c in '' %}{% else %}empty{% endfor %}",
    ),
    content="<loop 0/?> True False <loop 1/?> True False empty",
  )
}

///|
test "difftest: reverse slices of empty values (upstream panics)" {
  inspect(
    dt_render(
      "[{{ [][::-1] }}][{{ ''[:-10:-1] }}][{{ ()[::-2] }}][{{ [1, 2][5::-1] }}]",
    ),
    content="[[]][][()][[2, 1]]",
  )
}
