///|
/// A compiled template.
priv struct CompiledTemplate {
  instructions : Instructions
  blocks : Map[String, Instructions]
  buffer_size_hint : Int
  syntax_config : SyntaxConfig
  initial_auto_escape : AutoEscape
}

///|
fn CompiledTemplate::new(
  name : String,
  source : String,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
  initial_auto_escape : AutoEscape,
) -> CompiledTemplate raise TemplateError {
  let ast = parse(source, name, syntax_config, ws_config) catch {
    err => raise attach_basic_debug_info(err, source)
  }
  let g = CodeGenerator::new(name, source)
  g.compile_stmt(ast)
  let buffer_size_hint = g.buffer_size_hint()
  let (instructions, blocks) = g.finish()
  {
    instructions,
    blocks,
    buffer_size_hint,
    syntax_config,
    initial_auto_escape,
  }
}

///|
/// Represents a handle to a template.
///
/// Templates are stored in the [`Environment`] as bytecode instructions.
/// With the [`Environment::get_template`] method that is looked up and
/// returned in form of this handle.  Such a template can be rendered with
/// [`Template::render`].
pub struct Template {
  priv env : Environment
  priv compiled : CompiledTemplate
}

///|
/// Returns the name of the template.
pub fn Template::name(self : Template) -> String {
  self.compiled.instructions.name
}

///|
/// Returns the source code of the template.
pub fn Template::source(self : Template) -> String {
  self.compiled.instructions.source
}

///|
/// Renders the template into a string.
///
/// The provided value is used as the initial context for the template.  It
/// can be any object that implements the object protocol, typically a map
/// created with [`Value::from_pairs`] or [`Value::from_map`].
pub fn Template::render(
  self : Template,
  ctx : Value,
) -> String raise TemplateError {
  let buf = StringBuilder(size_hint=self.compiled.buffer_size_hint)
  self.eval(ctx, Output::new(buf)) |> ignore
  buf.to_string()
}

///|
/// Renders the template and returns the output together with the final
/// state.  The state can be used to render blocks or call macros.
pub fn Template::render_captured(
  self : Template,
  ctx : Value,
) -> Captured raise TemplateError {
  let buf = StringBuilder(size_hint=self.compiled.buffer_size_hint)
  let (_, state) = self.eval(ctx, Output::new(buf))
  { output: buf.to_string(), state, }
}

///|
/// Renders the template, streaming the output into `write`.
///
/// Errors raised by `write` abort rendering with a `WriteFailure` error.
/// The final state is returned (like [`Template::render_captured`]).
pub fn Template::render_to(
  self : Template,
  ctx : Value,
  write : (StringView) -> Unit raise,
) -> State raise TemplateError {
  let (_, state) = self.eval(ctx, Output::with_sink(write))
  state
}

///|
fn Template::eval(
  self : Template,
  root : Value,
  out : Output,
) -> (Value?, State) raise TemplateError {
  vm_eval(
    self.env,
    self.compiled.instructions,
    root,
    self.compiled.blocks,
    out,
    self.compiled.initial_auto_escape,
  )
}

///|
/// Returns a set of all undeclared variables in the template.
///
/// This returns a set of all variables that might be looked up at runtime
/// by the template.  With `nested` set to `true`, attribute lookups on
/// undeclared variables are tracked as dotted paths (`foo.bar`).
pub fn Template::undeclared_variables(
  self : Template,
  nested? : Bool = false,
) -> Array[String] {
  let ast = parse(
    self.compiled.instructions.source,
    self.name(),
    self.compiled.syntax_config,
    WhitespaceConfig::default(),
  ) catch {
    _ => return []
  }
  let rv = find_undeclared(ast, nested).to_array()
  rv.sort_by((a, b) => compare_str(a, b))
  rv
}

///|
/// Creates an empty [`State`] for this template.
pub fn Template::new_state(self : Template) -> State {
  State::new(
    Context::new(self.env),
    self.compiled.initial_auto_escape,
    self.compiled.instructions,
    prepare_blocks(self.compiled.blocks),
  )
}

///|
/// Captured render output together with the state.
pub struct Captured {
  /// The rendered output.
  output : String
  /// The state after rendering.
  state : State
}

///|
/// A handle to a compiled expression.
///
/// An expression is created via the [`Environment::compile_expression`]
/// method.  It provides a method to evaluate the expression and return the
/// result as value object.
pub struct Expression {
  priv env : Environment
  priv instructions : Instructions
}

///|
/// Evaluates the expression with some context.
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::new()
///   let expr = env.compile_expression("number < 42")
///   let ctx = @minijinja.Value::from_pairs([
///     ("number", @minijinja.Value::from_int(23)),
///   ])
///   inspect(expr.eval(ctx).to_string(), content="True")
/// }
/// ```
pub fn Expression::eval(
  self : Expression,
  ctx : Value,
) -> Value raise TemplateError {
  let (rv, _) = vm_eval(
    self.env,
    self.instructions,
    ctx,
    Map::new(),
    Output::null(),
    NoEscape,
  )
  match rv {
    Some(v) => v
    None => abort("expression evaluation did not leave value on stack")
  }
}

///|
/// Returns a set of all undeclared variables in the expression.
pub fn Expression::undeclared_variables(
  self : Expression,
  nested? : Bool = false,
) -> Array[String] {
  let expr = parse_expr(self.instructions.source) catch { _ => return [] }
  let rv = find_undeclared(EmitExpr({ expr, span: Span::default(), }), nested).to_array()
  rv.sort_by((a, b) => compare_str(a, b))
  rv
}
