///|
fn micro(b : @bench.T, name : String, src : String) -> Unit raise {
  let env = @minijinja.Environment::new()
  env.add_template(name, src)
  let tmpl = env.get_template(name)
  b.bench(name~, () => {
    let rv = tmpl.render(@minijinja.Value::none()) catch {
      _ => abort("failed")
    }
    b.keep(rv)
  })
}

///|
test "micro" (b : @bench.T) {
  micro(b, "empty_loop", "{% for i in range(200) %}{% endfor %}")
  micro(b, "emit_loop", "{% for i in range(200) %}{{ i }}{% endfor %}")
  micro(b, "set_loop", "{% for i in range(200) %}{% set x = i %}{% endfor %}")
  micro(
    b, "add_loop", "{% for i in range(200) %}{% set x = i + 1 %}{% endfor %}",
  )
  micro(
    b, "tuple_loop", "{% for i in range(200) %}{% set x = (i, i) %}{% endfor %}",
  )
}
