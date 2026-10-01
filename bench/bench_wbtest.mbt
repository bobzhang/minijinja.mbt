// Mirrors upstream benchmarks/benches/templates.rs.
// Run with `moon bench --target native --release bench`.

///|
fn create_real_env() -> @minijinja.Environment raise {
  let env = @minijinja.Environment::new()
  env.add_template("footer.html", footer_src)
  env.add_template("all_elements.html", all_elements_src)
  env.add_template("map_items.jinja", map_items_src)
  env.add_filter("asset_url", (state, args) => {
    let a = @minijinja.Args::new(state, args)
    let v = a.string()
    a.finish()
    @minijinja.Value::from_string(v)
  })
  env.add_function("current_year", (_state, _args) => {
    @minijinja.Value::from_int(2022)
  })
  env
}

///|
fn render_ctx() -> @minijinja.Value {
  fn nav(url : String, active : Bool, title : String) -> @minijinja.Value {
    @minijinja.Value::from_pairs([
      ("url", @minijinja.Value::from_string(url)),
      ("is_active", @minijinja.Value::from_bool(active)),
      ("title", @minijinja.Value::from_string(title)),
    ])
  }

  @minijinja.Value::from_pairs([
    ("DEBUG", @minijinja.Value::from_bool(false)),
    (
      "site",
      @minijinja.Value::from_pairs([
        (
          "nav",
          @minijinja.Value::from_array([
            nav("/", true, "Index"),
            nav("/doc", false, "Docs"),
            nav("/help", false, "Help"),
          ]),
        ),
      ]),
    ),
    (
      "items",
      @minijinja.Value::from_array(
        Array::makei(197, i => @minijinja.Value::from_int(i + 3)),
      ),
    ),
  ])
}

///|
test "bench: parse and compile" (b : @bench.T) {
  b.bench(name="compile", () => {
    let env = @minijinja.Environment::new()
    env.add_template("all_elements.html", all_elements_src) catch {
      _ => abort("failed")
    }
  })
}

///|
test "bench: render" (b : @bench.T) {
  let env = create_real_env()
  let tmpl = env.get_template("all_elements.html")
  let ctx = render_ctx()
  b.bench(name="render", () => {
    let rv = tmpl.render(ctx) catch { _ => abort("failed") }
    b.keep(rv)
  })
}

///|
test "bench: loop map items" (b : @bench.T) {
  let env = create_real_env()
  let tmpl = env.get_template("map_items.jinja")
  let m : Map[@minijinja.Value, @minijinja.Value] = Map::new()
  for i in 0..<10000 {
    m[@minijinja.Value::from_int(i)] = @minijinja.Value::from_string(
      "Person\{i}",
    )
  }
  let ctx = @minijinja.Value::from_pairs([
    ("employees", @minijinja.Value::from_map(m)),
  ])
  b.bench(name="loop_map_items", () => {
    let rv = tmpl.render(ctx) catch { _ => abort("failed") }
    b.keep(rv)
  })
}

///|
test "bench: tuple ops" (b : @bench.T) {
  let env = @minijinja.Environment::new()
  env.add_template(
    "tuple_ops", "{% for i in range(200) %}{% set pair = (i, i + 1) %}{{ pair[0] }}{% endfor %}",
  )
  let tmpl = env.get_template("tuple_ops")
  b.bench(name="tuple_ops", () => {
    let rv = tmpl.render(@minijinja.Value::none()) catch {
      _ => abort("failed")
    }
    b.keep(rv)
  })
}
