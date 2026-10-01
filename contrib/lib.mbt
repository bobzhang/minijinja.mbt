///|
/// Registers all features of this package with an
/// [`@minijinja.Environment`].
///
/// All the filters that are available will be added (`pluralize`,
/// `filesizeformat`, `truncate`, `striptags`, `wordcount`, `wordwrap` and
/// `random`), same with the global functions (`cycler`, `joiner`, `lipsum`
/// and `randrange`).
///
/// **Note:** the `pycompat` support ([`unknown_method_callback`]) is
/// intentionally not registered with the environment.
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::new()
///   @contrib.add_to_environment(env)
///   inspect(
///     env.render_str(
///       "{{ 3 }} item{{ 3|pluralize }}, {{ 2048|filesizeformat }}",
///       @minijinja.Value::none(),
///     ),
///     content="3 items, 2.0 kB",
///   )
/// }
/// ```
pub fn add_to_environment(env : @minijinja.Environment) -> Unit {
  env.add_filter("pluralize", filter_pluralize)
  env.add_filter("filesizeformat", filter_filesizeformat)
  env.add_filter("truncate", filter_truncate)
  env.add_filter("striptags", filter_striptags)
  env.add_filter("wordcount", filter_wordcount)
  env.add_filter("wordwrap", filter_wordwrap)
  env.add_filter("random", filter_random)
  env.add_function("lipsum", function_lipsum)
  env.add_function("randrange", function_randrange)
  env.add_function("cycler", function_cycler)
  env.add_function("joiner", function_joiner)
}

///|
fn filter_pluralize(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let v = a.value()
  let singular = a.opt_value()
  let plural = a.opt_value()
  a.finish()
  pluralize(v, singular?, plural?)
}

///|
fn filter_filesizeformat(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let value = a.f64()
  let binary = a.opt_bool().unwrap_or(false)
  a.finish()
  @minijinja.Value::from_string(filesizeformat(value, binary~))
}

///|
fn filter_truncate(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.value()
  a.finish()
  truncate(state, value, kwargs)
}

///|
fn filter_striptags(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let s = a.string()
  a.finish()
  @minijinja.Value::from_string(striptags(s))
}

///|
fn filter_wordcount(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let value = a.value()
  a.finish()
  wordcount(value)
}

///|
fn filter_wordwrap(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let kwargs = a.kwargs()
  let value = a.value()
  a.finish()
  wordwrap(value, kwargs)
}

///|
fn filter_random(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let seq = a.value()
  a.finish()
  random(state, seq)
}

///|
fn function_cycler(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  // port of `Vec<Value>` argument conversion: a missing argument is an
  // empty list, otherwise a sequence or iterable is required.
  let items = if a.has_more() {
    let value = a.value()
    match value.as_object() {
      Some(obj) if obj.repr() is (Seq | Iterable) &&
        obj.try_iter() is Some(iter) => iter.to_array()
      _ => raise @minijinja.TemplateError::new(InvalidOperation, "not iterable")
    }
  } else {
    []
  }
  a.finish()
  cycler(items)
}

///|
fn function_joiner(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let sep = a.opt_value()
  a.finish()
  joiner(sep?)
}

///|
fn function_randrange(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let n = a.i64()
  let m = a.opt_i64()
  a.finish()
  @minijinja.Value::from_int64(randrange(state, n, m?))
}

///|
fn function_lipsum(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  let a = @minijinja.Args::new(state, args)
  let kwargs = a.kwargs()
  let n = a.opt_usize()
  a.finish()
  lipsum(state, n?, kwargs)
}
