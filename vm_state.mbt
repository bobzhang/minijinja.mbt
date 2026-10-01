///|
let state_id_counter : Ref[Int] = { val: 0, }

///|
/// Provides access to the current execution state of the engine.
///
/// A read only reference is passed to filter functions and similar objects
/// to allow limited interfacing with the engine.
pub struct State {
  priv mut ctx : Context
  priv mut current_block : String?
  priv mut auto_escape : AutoEscape
  priv mut instructions : Instructions
  priv temps : Map[String, Value]
  priv mut blocks : Map[String, BlockStack]
  priv mut loaded_templates : Set[String]
  priv id : Int
}

///|
priv struct BlockStack {
  instructions : Array[Instructions]
  mut depth : Int
}

///|
fn BlockStack::new(instructions : Instructions) -> BlockStack {
  { instructions: [instructions], depth: 0, }
}

///|
fn BlockStack::instructions(self : BlockStack) -> Instructions {
  self.instructions[self.depth]
}

///|
fn BlockStack::push(self : BlockStack) -> Bool {
  if self.depth + 1 < self.instructions.length() {
    self.depth += 1
    true
  } else {
    false
  }
}

///|
fn BlockStack::pop(self : BlockStack) -> Unit {
  self.depth -= 1
}

///|
fn prepare_blocks(
  blocks : Map[String, Instructions],
) -> Map[String, BlockStack] {
  let rv = Map::new()
  for name, instr in blocks {
    rv[name] = BlockStack::new(instr)
  }
  rv
}

///|
priv enum BlockState {
  Keep
  Isolate
  Replace(Map[String, BlockStack])
}

///|
fn State::new(
  ctx : Context,
  auto_escape : AutoEscape,
  instructions : Instructions,
  blocks : Map[String, BlockStack],
) -> State {
  state_id_counter.val += 1
  {
    ctx,
    current_block: None,
    auto_escape,
    instructions,
    temps: Map::new(),
    blocks,
    loaded_templates: Set([]),
    id: state_id_counter.val,
  }
}

///|
/// Returns a reference to the current environment.
pub fn State::env(self : State) -> Environment {
  self.ctx.env
}

///|
/// Returns the name of the current template.
pub fn State::name(self : State) -> String {
  self.instructions.name
}

///|
/// Returns the current value of the auto escape flag.
pub fn State::auto_escape(self : State) -> AutoEscape {
  self.auto_escape
}

///|
/// Returns the current undefined behavior.
pub fn State::undefined_behavior(self : State) -> UndefinedBehavior {
  self.ctx.env.undefined_behavior
}

///|
/// Returns the name of the innermost block.
pub fn State::current_block(self : State) -> String? {
  self.current_block
}

///|
/// Looks up a variable by name in the context.
pub fn State::lookup(self : State, name : String) -> Value? {
  self.ctx.load(name)
}

///|
/// Runs `f` with a swapped execution state (instructions, auto escape,
/// current block and blocks) and restores the previous state afterwards,
/// also when `f` raises.
fn[T] State::with_execution_state(
  self : State,
  instructions : Instructions,
  auto_escape : AutoEscape,
  current_block : String?,
  block_state : BlockState,
  f : (State) -> T raise TemplateError,
) -> T raise TemplateError {
  let stack_depth = match block_state {
    Isolate => None
    _ => Some(self.ctx.stack_depth())
  }
  let old_instructions = self.instructions
  let old_auto_escape = self.auto_escape
  let old_current_block = self.current_block
  self.instructions = instructions
  self.auto_escape = auto_escape
  self.current_block = current_block
  let old_loaded = Set::from_iter(self.loaded_templates.iter())
  let checkpoint : Array[(String, Int, Int)] = []
  let mut old_blocks : Map[String, BlockStack]? = None
  match block_state {
    Keep => ()
    Isolate =>
      for name, block in self.blocks {
        checkpoint.push((name, block.instructions.length(), block.depth))
      }
    Replace(blocks) => {
      old_blocks = Some(self.blocks)
      self.blocks = blocks
    }
  }
  let restore = () => {
    if stack_depth is Some(depth) {
      self.ctx.restore_stack_depth(depth)
    }
    self.instructions = old_instructions
    self.auto_escape = old_auto_escape
    self.current_block = old_current_block
    match block_state {
      Keep => ()
      Isolate => {
        let new_blocks = Map::new()
        for entry in checkpoint {
          let (name, count, depth) = entry
          if self.blocks.get(name) is Some(block) {
            block.instructions.truncate(count)
            block.depth = depth
            new_blocks[name] = block
          }
        }
        self.blocks = new_blocks
        self.loaded_templates = old_loaded
      }
      Replace(_) => {
        if old_blocks is Some(blocks) {
          self.blocks = blocks
        }
        self.loaded_templates = old_loaded
      }
    }
  }
  let rv = f(self) catch {
    err => {
      restore()
      raise err
    }
  }
  restore()
  rv
}

///|
/// Invokes a macro by name with the given arguments.
pub fn State::call_macro(
  self : State,
  name : String,
  args : Array[Value],
) -> String raise TemplateError {
  guard self.lookup(name) is Some(f) else {
    raise TemplateError::new(UnknownFunction, "macro not found")
  }
  f.call(self, args).to_string()
}

///|
/// Renders a block with the given name into a string.
///
/// This method works like [`Template::render`] but it only renders a
/// specific block in the template.
pub fn State::render_block(
  self : State,
  block : String,
) -> String raise TemplateError {
  let buf = StringBuilder()
  call_block(block, self, Output::new(buf)) |> ignore
  buf.to_string()
}

///|
/// Returns a list of the names of all exports (top-level variables).
pub fn State::exports(self : State) -> Array[String] {
  self.ctx.exports().keys().to_array()
}

///|
/// Returns a list of all known variables.
pub fn State::known_variables(self : State) -> Array[String] {
  self.ctx.known_variables(true).to_array()
}

///|
/// Fetches a template by name with path joining.
pub fn State::get_template(
  self : State,
  name : String,
) -> Template raise TemplateError {
  let env = self.env()
  env.get_template(env.join_template_path(name, self.name()))
}

///|
/// Invokes a filter with some arguments.
pub fn State::apply_filter(
  self : State,
  filter : String,
  args : Array[Value],
) -> Value raise TemplateError {
  match self.env().get_filter(filter) {
    Some(f) => f.call(self, args)
    None => raise TemplateError::from_kind(UnknownFilter)
  }
}

///|
/// Invokes a test function on a value.
pub fn State::perform_test(
  self : State,
  test_name : String,
  args : Array[Value],
) -> Bool raise TemplateError {
  match self.env().get_test(test_name) {
    Some(f) => f.call(self, args).is_true()
    None => raise TemplateError::from_kind(UnknownTest)
  }
}

///|
/// Formats a value to a string using the formatter on the environment.
pub fn State::format(self : State, value : Value) -> String raise TemplateError {
  let buf = StringBuilder()
  self.env().format(value, self, Output::new(buf))
  buf.to_string()
}

///|
/// Looks up a temp and returns it.
pub fn State::get_temp(self : State, name : String) -> Value? {
  self.temps.get(name)
}

///|
/// Inserts a temp and returns the old temp.
pub fn State::set_temp(self : State, name : String, value : Value) -> Value? {
  let old = self.temps.get(name)
  self.temps[name] = value
  old
}

///|
fn State::make_debug_info(
  self : State,
  pc : Int,
  instructions : Instructions,
) -> DebugInfo {
  let referenced_locals = Map::new()
  for name in instructions.get_referenced_names(pc) {
    if self.lookup(name) is Some(v) {
      referenced_locals[name] = v
    }
  }
  { template_source: Some(instructions.source), referenced_locals, }
}

///|
/// Formats the state like MiniJinja's pretty `Debug` output.
fn State::fmt_debug(self : State, f : @rfmt.Formatter) -> Unit {
  f
  .debug_struct("State")
  .field("name", f => f.write_str(@rfmt.str_debug(self.instructions.name)))
  .field("current_block", f => {
    match self.current_block {
      Some(b) =>
        f
        .debug_tuple("Some")
        .field(f => f.write_str(@rfmt.str_debug(b)))
        .finish()
      None => f.write_str("None")
    }
  })
  .field("auto_escape", f => f.write_str(self.auto_escape.debug_name()))
  .field("ctx", f => self.ctx.fmt_debug(f))
  .field("env", f => self.env().fmt_debug(f))
  .finish()
}
