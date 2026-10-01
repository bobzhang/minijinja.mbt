///|
/// An environment with the pycompat unknown method callback.
fn pycompat_env() -> @minijinja.Environment {
  let env = @minijinja.Environment::new()
  env.set_unknown_method_callback(@contrib.unknown_method_callback)
  env
}

///|
fn eval_expr(expr : String) -> @minijinja.Value raise {
  pycompat_env().compile_expression(expr).eval(@minijinja.Value::none())
}

///|
fn eval_err_expr(expr : String) -> String raise {
  let compiled = pycompat_env().compile_expression(expr)
  try compiled.eval(@minijinja.Value::none()) catch {
    err => err.to_string()
  } noraise {
    v => fail("expected an error, got \{v}")
  }
}

///|
/// An environment with all contrib filters and functions.
fn contrib_env() -> @minijinja.Environment {
  let env = @minijinja.Environment::new()
  @contrib.add_to_environment(env)
  env
}

///|
/// Renders a template string with all contrib filters and functions.
fn render(
  source : String,
  ctx? : Array[(String, @minijinja.Value)] = [],
) -> String raise {
  contrib_env().render_str(source, @minijinja.Value::from_pairs(ctx))
}

///|
/// Renders a template string and returns the error message.
fn render_err(
  source : String,
  ctx? : Array[(String, @minijinja.Value)] = [],
) -> String raise {
  try
    contrib_env().render_str(source, @minijinja.Value::from_pairs(ctx))
  catch {
    err => err.to_string()
  } noraise {
    v => fail("expected an error, got \{v}")
  }
}

///|
fn str(s : String) -> @minijinja.Value {
  @minijinja.Value::from_string(s)
}
