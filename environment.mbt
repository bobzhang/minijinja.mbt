///|
/// The maximum recursion in the VM.  Normally each stack frame adds one to
/// this counter (eg: every time a frame is added).  However in some cases
/// more depth is pushed if the cost of the stack frame is higher.
let max_vm_recursion = 500

///|
/// A callback that formats a value to the output.
pub type FormatterFunc = (Output, State, Value) -> Unit raise TemplateError

///|
/// The signature of filters, tests and functions.
pub type NativeFunction = (State, Array[Value]) -> Value raise TemplateError

///|
/// An abstraction that holds the engine configuration.
///
/// This object holds the central configuration state for templates.  It is
/// also the container for all loaded templates.
///
/// There are generally two ways to construct an environment:
///
/// * [`Environment::new`] creates an environment preconfigured with sensible
///   defaults.  It will contain all built-in filters, tests and globals as
///   well as a callback for auto escaping based on file extension.
/// * [`Environment::empty`] creates a completely blank environment.
pub struct Environment {
  priv templates : Map[String, CompiledTemplate]
  priv mut loader : ((String) -> String? raise TemplateError)?
  // the builtin maps are shared between environments until modified
  // (copy-on-write, like `Arc::make_mut` upstream)
  priv mut filters : Map[String, Value]
  priv mut tests : Map[String, Value]
  priv mut globals : Map[String, Value]
  priv mut maps_shared : Bool
  priv mut path_join_callback : ((String, String) -> String)?
  priv mut unknown_method_callback : ((State, Value, String, Array[Value]) -> Value raise TemplateError)?
  priv mut undefined_behavior : UndefinedBehavior
  priv mut formatter : FormatterFunc
  priv mut formatter_is_default : Bool
  priv mut debug : Bool
  priv mut fuel : Int64?
  priv mut recursion_limit : Int
  priv mut syntax_config : SyntaxConfig
  priv mut ws_config : WhitespaceConfig
  priv mut auto_escape_callback : (String) -> AutoEscape
}

///|
fn default_formatter(
  out : Output,
  state : State,
  value : Value,
) -> Unit raise TemplateError {
  write_escaped(out, state.auto_escape(), value)
}

///|
/// Creates a new environment with sensible defaults.
///
/// This environment does not yet contain any templates but it will have all
/// the default filters, tests and globals loaded.  If you do not want any
/// default configuration you can use [`Environment::empty`].
pub fn Environment::new() -> Environment {
  let env = Environment::empty()
  env.auto_escape_callback = default_auto_escape_callback
  env.filters = builtin_filters
  env.tests = builtin_tests
  env.globals = builtin_globals
  env.maps_shared = true
  env
}

///|
/// Creates a completely empty environment.
///
/// This environment has no filters, no templates, no globals and no default
/// logic for auto escaping configured.
pub fn Environment::empty() -> Environment {
  {
    templates: Map([]),
    loader: None,
    filters: Map([]),
    tests: Map([]),
    globals: Map([]),
    maps_shared: false,
    path_join_callback: None,
    unknown_method_callback: None,
    undefined_behavior: Lenient,
    formatter: default_formatter,
    formatter_is_default: true,
    debug: true,
    fuel: None,
    recursion_limit: max_vm_recursion,
    syntax_config: SyntaxConfig::default(),
    ws_config: WhitespaceConfig::default(),
    auto_escape_callback: _ => NoEscape,
  }
}

///|
/// Loads a template from a string into the environment.
///
/// The `name` parameter defines the name of the template which identifies
/// it.  To look up a loaded template use the [`get_template`] method.
pub fn Environment::add_template(
  self : Environment,
  name : String,
  source : String,
) -> Unit raise TemplateError {
  self.templates[name] = self.compile(name, source)
}

///|
fn Environment::compile(
  self : Environment,
  name : String,
  source : String,
) -> CompiledTemplate raise TemplateError {
  CompiledTemplate::new(
    name,
    source,
    self.syntax_config,
    self.ws_config,
    (self.auto_escape_callback)(name),
  )
}

///|
/// Removes a template by name.
pub fn Environment::remove_template(self : Environment, name : String) -> Unit {
  self.templates.remove(name)
}

///|
/// Removes all stored templates.
pub fn Environment::clear_templates(self : Environment) -> Unit {
  self.templates.clear()
}

///|
/// Registers a template loader as source of templates.
///
/// When a template loader is registered, the environment gains the ability
/// to dynamically load templates.  The loader is invoked with the name of
/// the template.  If this template exists `Some(source)` has to be returned,
/// otherwise `None`.  Once a template has been loaded it's stored on the
/// environment.
pub fn Environment::set_loader(
  self : Environment,
  f : (String) -> String? raise TemplateError,
) -> Unit {
  self.loader = Some(f)
}

///|
/// Preserve the trailing newline when rendering templates.
pub fn Environment::set_keep_trailing_newline(
  self : Environment,
  yes : Bool,
) -> Unit {
  self.ws_config = { ..self.ws_config, keep_trailing_newline: yes, }
}

///|
/// Returns the value of the trailing newline preservation flag.
pub fn Environment::keep_trailing_newline(self : Environment) -> Bool {
  self.ws_config.keep_trailing_newline
}

///|
/// Remove the first newline after a block.
pub fn Environment::set_trim_blocks(self : Environment, yes : Bool) -> Unit {
  self.ws_config = { ..self.ws_config, trim_blocks: yes, }
}

///|
/// Returns the value of the trim blocks flag.
pub fn Environment::trim_blocks(self : Environment) -> Bool {
  self.ws_config.trim_blocks
}

///|
/// Remove leading spaces and tabs from the start of a line to a block.
pub fn Environment::set_lstrip_blocks(self : Environment, yes : Bool) -> Unit {
  self.ws_config = { ..self.ws_config, lstrip_blocks: yes, }
}

///|
/// Returns the value of the lstrip blocks flag.
pub fn Environment::lstrip_blocks(self : Environment) -> Bool {
  self.ws_config.lstrip_blocks
}

///|
/// Sets a callback to join template paths (for relative includes).
///
/// The callback is invoked with the name of the template to load and the
/// name of the template that is loading it.
pub fn Environment::set_path_join_callback(
  self : Environment,
  f : (String, String) -> String,
) -> Unit {
  self.path_join_callback = Some(f)
}

///|
/// Sets a callback invoked when an unknown method is called on an object.
pub fn Environment::set_unknown_method_callback(
  self : Environment,
  f : (State, Value, String, Array[Value]) -> Value raise TemplateError,
) -> Unit {
  self.unknown_method_callback = Some(f)
}

///|
/// Fetches a template by name.
///
/// This requires that the template has been loaded with
/// [`add_template`](Environment::add_template) beforehand or that a loader
/// can produce it.
pub fn Environment::get_template(
  self : Environment,
  name : String,
) -> Template raise TemplateError {
  match self.templates.get(name) {
    Some(compiled) => { env: self, compiled, }
    None => {
      let source = match self.loader {
        Some(loader) => loader(name)
        None => None
      }
      match source {
        Some(source) => {
          let compiled = self.compile(name, source)
          self.templates[name] = compiled
          { env: self, compiled, }
        }
        None => raise TemplateError::new_not_found(name)
      }
    }
  }
}

///|
/// Returns the names of all loaded templates.
pub fn Environment::template_names(self : Environment) -> Array[String] {
  self.templates.keys().to_array()
}

///|
/// Loads a template from a string, with name.
///
/// In some cases you really only need a template to be compiled once.  This
/// creates a template that is not stored on the environment.
pub fn Environment::template_from_named_str(
  self : Environment,
  name : String,
  source : String,
) -> Template raise TemplateError {
  { env: self, compiled: self.compile(name, source), }
}

///|
/// Loads a template from a string (named `<string>`).
pub fn Environment::template_from_str(
  self : Environment,
  source : String,
) -> Template raise TemplateError {
  self.template_from_named_str("<string>", source)
}

///|
/// Parses and renders a template from a string in one go with name.
pub fn Environment::render_named_str(
  self : Environment,
  name : String,
  source : String,
  ctx : Value,
) -> String raise TemplateError {
  self.template_from_named_str(name, source).render(ctx)
}

///|
/// Parses and renders a template from a string in one go.
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::new()
///   let ctx = @minijinja.Value::from_pairs([
///     ("name", @minijinja.Value::from_string("World")),
///   ])
///   inspect(env.render_str("Hello {{ name }}!", ctx), content="Hello World!")
/// }
/// ```
pub fn Environment::render_str(
  self : Environment,
  source : String,
  ctx : Value,
) -> String raise TemplateError {
  self.template_from_str(source).render(ctx)
}

///|
/// Sets a new function to select the default auto escaping.
///
/// This function is invoked when templates are loaded into the environment
/// to determine the default auto escaping behavior.  The function is
/// invoked with the name of the template.
pub fn Environment::set_auto_escape_callback(
  self : Environment,
  f : (String) -> AutoEscape,
) -> Unit {
  self.auto_escape_callback = f
}

///|
/// Changes the undefined behavior.
pub fn Environment::set_undefined_behavior(
  self : Environment,
  behavior : UndefinedBehavior,
) -> Unit {
  self.undefined_behavior = behavior
}

///|
/// Returns the current undefined behavior.
pub fn Environment::undefined_behavior(self : Environment) -> UndefinedBehavior {
  self.undefined_behavior
}

///|
/// Sets a different formatter function.
///
/// The formatter is invoked to format the given value into the provided
/// output.  The default formatter escapes values according to the auto
/// escape flag of the state.
pub fn Environment::set_formatter(
  self : Environment,
  f : FormatterFunc,
) -> Unit {
  self.formatter = f
  self.formatter_is_default = false
}

///|
/// Enable or disable the debug mode.
///
/// When the debug mode is enabled the engine will dump out some of the
/// execution state together with the source information of the executing
/// template when an error is created.
pub fn Environment::set_debug(self : Environment, enabled : Bool) -> Unit {
  self.debug = enabled
}

///|
/// Returns the current value of the debug flag.
pub fn Environment::debug(self : Environment) -> Bool {
  self.debug
}

///|
/// Sets the optional fuel of the engine.
///
/// When MiniJinja is compiled with fuel support (always the case in this
/// port), the engine will consume fuel on every instruction it executes.
/// Once the engine runs out of fuel, rendering fails with an `OutOfFuel`
/// error.  This can be used to limit the amount of work a template can do.
pub fn Environment::set_fuel(self : Environment, fuel : Int64?) -> Unit {
  self.fuel = fuel
}

///|
/// Returns the configured fuel.
pub fn Environment::fuel(self : Environment) -> Int64? {
  self.fuel
}

///|
/// Sets the syntax for the environment.
///
/// Note that this only affects templates that are added after the syntax
/// was changed.
pub fn Environment::set_syntax(
  self : Environment,
  syntax : SyntaxConfig,
) -> Unit {
  self.syntax_config = syntax
}

///|
/// Returns the current syntax config.
pub fn Environment::syntax(self : Environment) -> SyntaxConfig {
  self.syntax_config
}

///|
/// Reconfigures the runtime recursion limit (capped at 500).
pub fn Environment::set_recursion_limit(
  self : Environment,
  level : Int,
) -> Unit {
  self.recursion_limit = if level < max_vm_recursion {
    level
  } else {
    max_vm_recursion
  }
}

///|
/// Returns the current max recursion limit.
pub fn Environment::recursion_limit(self : Environment) -> Int {
  self.recursion_limit
}

///|
/// Compiles an expression.
///
/// This lets one compile an expression in the template language and receive
/// the output.  This lets one use the expressions of the language be used
/// as a minimal scripting language.
pub fn Environment::compile_expression(
  self : Environment,
  expr : String,
) -> Expression raise TemplateError {
  let ast = parse_expr(expr) catch {
    err => raise attach_basic_debug_info(err, expr)
  }
  let g = CodeGenerator::new("<expression>", expr)
  g.compile_expr(ast)
  { env: self, instructions: g.finish().0, }
}

///|
/// Adds a new filter function.
///
/// Filter functions are functions that can be applied to values in
/// templates.  The first argument is the value the filter is applied to.
pub fn Environment::add_filter(
  self : Environment,
  name : String,
  f : NativeFunction,
) -> Unit {
  self.unshare_maps()
  self.filters[name] = Value::from_function(name, f)
}

///|
/// Removes a filter by name.
pub fn Environment::remove_filter(self : Environment, name : String) -> Unit {
  self.unshare_maps()
  self.filters.remove(name)
}

///|
/// Adds a new test function.
///
/// Test functions are similar to filters but perform a check on a value
/// where the return value is always considered a boolean.
pub fn Environment::add_test(
  self : Environment,
  name : String,
  f : NativeFunction,
) -> Unit {
  self.unshare_maps()
  self.tests[name] = Value::from_function(name, f)
}

///|
/// Removes a test by name.
pub fn Environment::remove_test(self : Environment, name : String) -> Unit {
  self.unshare_maps()
  self.tests.remove(name)
}

///|
/// Adds a new global function.
pub fn Environment::add_function(
  self : Environment,
  name : String,
  f : NativeFunction,
) -> Unit {
  self.add_global(name, Value::from_function(name, f))
}

///|
/// Adds a global variable.
pub fn Environment::add_global(
  self : Environment,
  name : String,
  value : Value,
) -> Unit {
  self.unshare_maps()
  self.globals[name] = value
}

///|
/// Removes a global function or variable by name.
pub fn Environment::remove_global(self : Environment, name : String) -> Unit {
  self.unshare_maps()
  self.globals.remove(name)
}

///|
/// Returns all globals as name/value pairs (sorted by name).
pub fn Environment::globals(self : Environment) -> Array[(String, Value)] {
  sorted_keys(self.globals).map(k => (k, self.globals[k]))
}

///|
/// Creates a copy of the environment.  Templates, filters, tests and
/// globals added to the copy do not affect the original and vice versa.
pub fn Environment::clone(self : Environment) -> Environment {
  // both environments now share the maps until one of them modifies them
  self.maps_shared = true
  {
    ..self,
    templates: Map::from_iter(self.templates.iter()),
    maps_shared: true,
  }
}

///|
/// Returns an empty [`State`] for testing purposes and similar.
pub fn Environment::empty_state(self : Environment) -> State {
  State::new(
    Context::new(self),
    NoEscape,
    Instructions::new("<unknown>", ""),
    Map([]),
  )
}

///|
fn Environment::get_global(self : Environment, name : String) -> Value? {
  self.globals.get(name)
}

///|
fn Environment::get_filter(self : Environment, name : String) -> Value? {
  self.filters.get(name)
}

///|
fn Environment::get_test(self : Environment, name : String) -> Value? {
  self.tests.get(name)
}

///|
fn Environment::format(
  self : Environment,
  value : Value,
  state : State,
  out : Output,
) -> Unit raise TemplateError {
  match (self.undefined_behavior, value) {
    // this intentionally does not check for SilentUndefined.
    (Strict | SemiStrict, Undefined(Default)) =>
      raise TemplateError::from_kind(UndefinedError)
    _ =>
      if self.formatter_is_default {
        write_escaped(out, state.auto_escape(), value)
      } else {
        (self.formatter)(out, state, value)
      }
  }
}

///|
fn Environment::join_template_path(
  self : Environment,
  name : String,
  parent : String,
) -> String {
  match self.path_join_callback {
    Some(cb) => cb(name, parent)
    None => name
  }
}

///|
fn sorted_keys(m : Map[String, Value]) -> Array[String] {
  let keys = m.keys().to_array()
  keys.sort_by((a, b) => compare_str(a, b))
  keys
}

///|
fn Environment::fmt_debug(self : Environment, f : @rfmt.Formatter) -> Unit {
  f
  .debug_struct("Environment")
  .field("globals", f => {
    let m = f.debug_map()
    for key in sorted_keys(self.globals) {
      let value = self.globals[key]
      m.entry(f => f.write_str(@rfmt.str_debug(key)), f => value.fmt_debug(f))
      |> ignore
    }
    m.finish()
  })
  .field("tests", f => {
    let l = f.debug_list()
    for key in sorted_keys(self.tests) {
      l.entry(f => f.write_str(@rfmt.str_debug(key))) |> ignore
    }
    l.finish()
  })
  .field("filters", f => {
    let l = f.debug_list()
    for key in sorted_keys(self.filters) {
      l.entry(f => f.write_str(@rfmt.str_debug(key))) |> ignore
    }
    l.finish()
  })
  .field("templates", f => {
    let l = f.debug_list()
    for key in sorted_keys_of(self.templates) {
      l.entry(f => f.write_str(@rfmt.str_debug(key))) |> ignore
    }
    l.finish()
  })
  .finish()
}

///|
fn[V] sorted_keys_of(m : Map[String, V]) -> Array[String] {
  let keys = m.keys().to_array()
  keys.sort_by((a, b) => compare_str(a, b))
  keys
}

///|
/// The default logic for auto escaping based on file extension.
///
/// * `Html`: `.html`, `.htm`, `.xml`
/// * `Json`: `.json`, `.json5`, `.js`, `.yaml`, `.yml`
/// * `NoEscape`: all others
///
/// Additionally `.j2`, `.jinja2` and `.jinja` are stripped first.
pub fn default_auto_escape_callback(name : String) -> AutoEscape {
  let mut name = name
  for ext in [".j2", ".jinja2", ".jinja"] {
    if name.has_suffix(ext) {
      name = name.view(end_offset=name.length() - ext.length()).to_owned()
      break
    }
  }
  let ext = match name.rev_find(".") {
    Some(idx) => name.view(start_offset=idx + 1).to_owned()
    None => name
  }
  match ext {
    "html" | "htm" | "xml" => Html
    "json" | "json5" | "js" | "yaml" | "yml" => Json
    _ => NoEscape
  }
}

///|
fn attach_basic_debug_info(
  err : TemplateError,
  source : String,
) -> TemplateError {
  err.attach_debug_info({
    template_source: Some(source),
    referenced_locals: Map([]),
  })
  err
}

///|
let builtin_filters : Map[String, Value] = {
  let rv : Map[String, Value] = Map([])
  register_builtin_filters(rv)
  rv
}

///|
let builtin_tests : Map[String, Value] = {
  let rv : Map[String, Value] = Map([])
  register_builtin_tests(rv)
  rv
}

///|
let builtin_globals : Map[String, Value] = {
  let rv : Map[String, Value] = Map([])
  register_builtin_globals(rv)
  rv
}

///|
/// Returns one of the built-in filters by name (independent of any
/// environment).  The returned value is callable with `Value::call`; the
/// first argument is the value the filter is applied to.
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::empty()
///   let state = env.empty_state()
///   guard @minijinja.builtin_filter("upper") is Some(upper) else {
///     fail("missing")
///   }
///   inspect(
///     upper.call(state, [@minijinja.Value::from_string("hi")]),
///     content="HI",
///   )
/// }
/// ```
pub fn builtin_filter(name : String) -> Value? {
  builtin_filters.get(name)
}

///|
/// Returns one of the built-in tests by name (independent of any
/// environment).
pub fn builtin_test(name : String) -> Value? {
  builtin_tests.get(name)
}

///|
/// Returns one of the built-in global functions (`range`, `dict`, `debug`,
/// `namespace`) by name.
pub fn builtin_function(name : String) -> Value? {
  builtin_globals.get(name)
}

///|
/// Copies the (shared) filter, test and global maps before modifying them.
fn Environment::unshare_maps(self : Environment) -> Unit {
  if self.maps_shared {
    self.filters = Map::from_iter(self.filters.iter())
    self.tests = Map::from_iter(self.tests.iter())
    self.globals = Map::from_iter(self.globals.iter())
    self.maps_shared = false
  }
}

///|
/// Returns all loaded templates (sorted by name).
pub fn Environment::templates(self : Environment) -> Array[(String, Template)] {
  sorted_keys_of(self.templates).map(name => {
    (name, { env: self, compiled: self.templates[name], })
  })
}
