///|
/// For the first `MAX_LOCALS` filters/tests, an ID is returned for faster
/// lookups from the stack.
fn get_local_id(ids : Map[String, Int], name : String) -> Int {
  match ids.get(name) {
    Some(id) => id
    None =>
      if ids.length() >= MAX_LOCALS {
        -1
      } else {
        let next_id = ids.length()
        ids[name] = next_id
        next_id
      }
  }
}

///|
fn compare_op(op : CompareOpKind) -> CompareOp {
  match op {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Lte => Lte
    Gt => Gt
    Gte => Gte
    In => In
    NotIn => NotIn
  }
}

///|
/// Represents an open block of code that does not yet have updated jump
/// targets.
priv enum PendingBlock {
  Branch(Int)
  Loop(Int, Array[Int])
  ScBool(Array[Int])
}

///|
/// Provides a convenient interface to creating instructions for the VM.
priv struct CodeGenerator {
  instructions : Instructions
  blocks : Map[String, Instructions]
  pending_block : Array[PendingBlock]
  mut current_line : Int
  span_stack : Array[Span]
  filter_local_ids : Map[String, Int]
  test_local_ids : Map[String, Int]
  mut raw_template_bytes : Int
}

///|
fn CodeGenerator::new(file : String, source : String) -> CodeGenerator {
  {
    instructions: Instructions::new(file, source),
    blocks: Map([]),
    pending_block: [],
    current_line: 0,
    span_stack: [],
    filter_local_ids: Map([]),
    test_local_ids: Map([]),
    raw_template_bytes: 0,
  }
}

///|
fn CodeGenerator::set_line(self : CodeGenerator, lineno : Int) -> Unit {
  self.current_line = lineno
}

///|
fn CodeGenerator::set_line_from_span(self : CodeGenerator, span : Span) -> Unit {
  self.set_line(span.start_line)
}

///|
fn CodeGenerator::push_span(self : CodeGenerator, span : Span) -> Unit {
  self.span_stack.push(span)
  self.set_line_from_span(span)
}

///|
fn CodeGenerator::pop_span(self : CodeGenerator) -> Unit {
  self.span_stack.pop() |> ignore
}

///|
/// Add a simple instruction with the current location.
fn CodeGenerator::add(self : CodeGenerator, instr : Instruction) -> Int {
  if self.span_stack.last() is Some(span) &&
    span.start_line == self.current_line {
    return self.instructions.add_with_span(instr, span)
  }
  self.instructions.add_with_line(instr, self.current_line)
}

///|
/// Add a simple instruction with other location.
fn CodeGenerator::add_with_span(
  self : CodeGenerator,
  instr : Instruction,
  span : Span,
) -> Int {
  self.instructions.add_with_span(instr, span)
}

///|
fn CodeGenerator::next_instruction(self : CodeGenerator) -> Int {
  self.instructions.len()
}

///|
fn CodeGenerator::patch(self : CodeGenerator, idx : Int, target : Int) -> Unit {
  let instr = self.instructions.instructions[idx]
  self.instructions.instructions[idx] = match instr {
    Iterate(_) => Iterate(target)
    Jump(_) => Jump(target)
    JumpIfFalse(_) => JumpIfFalse(target)
    JumpIfFalseOrPop(_) => JumpIfFalseOrPop(target)
    JumpIfTrueOrPop(_) => JumpIfTrueOrPop(target)
    other => other
  }
}

///|
/// Creates a sub generator.
fn CodeGenerator::new_subgenerator(self : CodeGenerator) -> CodeGenerator {
  let sub = CodeGenerator::new(self.instructions.name, self.instructions.source)
  sub.current_line = self.current_line
  if self.span_stack.last() is Some(span) {
    sub.span_stack.push(span)
  }
  sub
}

///|
/// Finishes a sub generator and syncs it back.
fn CodeGenerator::finish_subgenerator(
  self : CodeGenerator,
  sub : CodeGenerator,
) -> Instructions {
  self.current_line = sub.current_line
  let (instructions, blocks) = sub.finish()
  for name, instr in blocks {
    self.blocks[name] = instr
  }
  instructions
}

///|
/// Starts a for loop
fn CodeGenerator::start_for_loop(
  self : CodeGenerator,
  with_loop_var : Bool,
  recursive : Bool,
) -> Unit {
  let mut flags = 0
  if with_loop_var {
    flags = flags | LOOP_FLAG_WITH_LOOP_VAR
  }
  if recursive {
    flags = flags | LOOP_FLAG_RECURSIVE
  }
  self.add(PushLoop(flags)) |> ignore
  let instr = self.add(Iterate(-1))
  self.pending_block.push(Loop(instr, []))
}

///|
/// Ends the open for loop
fn CodeGenerator::end_for_loop(
  self : CodeGenerator,
  push_did_not_iterate : Bool,
) -> Unit {
  guard self.pending_block.pop() is Some(Loop(iter_instr, jump_instrs)) else {
    abort("unreachable")
  }
  self.add(Jump(iter_instr)) |> ignore
  let loop_end = self.next_instruction()
  if push_did_not_iterate {
    self.add(PushDidNotIterate) |> ignore
  }
  self.add(PopLoopFrame) |> ignore
  for instr in jump_instrs {
    self.patch(instr, loop_end)
  }
  self.patch(iter_instr, loop_end)
}

///|
/// Begins an if conditional
fn CodeGenerator::start_if(self : CodeGenerator) -> Unit {
  let jump_instr = self.add(JumpIfFalse(-1))
  self.pending_block.push(Branch(jump_instr))
}

///|
/// Begins an else conditional
fn CodeGenerator::start_else(self : CodeGenerator) -> Unit {
  let jump_instr = self.add(Jump(-1))
  self.end_condition(jump_instr + 1)
  self.pending_block.push(Branch(jump_instr))
}

///|
/// Closes the current if block.
fn CodeGenerator::end_if(self : CodeGenerator) -> Unit {
  self.end_condition(self.next_instruction())
}

///|
/// Starts a short-circuited bool block.
fn CodeGenerator::start_sc_bool(self : CodeGenerator) -> Unit {
  self.pending_block.push(ScBool([]))
}

///|
/// Emits a short-circuited bool operator.
fn CodeGenerator::sc_bool(self : CodeGenerator, is_and : Bool) -> Unit {
  guard self.pending_block.last() is Some(ScBool(jump_instrs)) else {
    abort("unreachable")
  }
  jump_instrs.push(
    self.instructions.add(
      if is_and {
        JumpIfFalseOrPop(-1)
      } else {
        JumpIfTrueOrPop(-1)
      },
    ),
  )
}

///|
/// Ends a short-circuited bool block.
fn CodeGenerator::end_sc_bool(self : CodeGenerator) -> Unit {
  let end = self.next_instruction()
  if self.pending_block.pop() is Some(ScBool(jump_instrs)) {
    for instr in jump_instrs {
      self.patch(instr, end)
    }
  }
}

///|
fn CodeGenerator::end_condition(
  self : CodeGenerator,
  new_jump_instr : Int,
) -> Unit {
  match self.pending_block.pop() {
    Some(Branch(jump_instr)) => self.patch(jump_instr, new_jump_instr)
    _ => abort("unreachable")
  }
}

///|
/// Compiles a statement.
fn CodeGenerator::compile_stmt(self : CodeGenerator, stmt : Stmt) -> Unit {
  match stmt {
    Template(t) => {
      self.set_line_from_span(t.span)
      for node in t.children {
        self.compile_stmt(node)
      }
    }
    EmitExpr(expr) => self.compile_emit_expr(expr)
    EmitRaw(raw) => {
      self.set_line_from_span(raw.span)
      self.add(EmitRaw(raw.raw)) |> ignore
      self.raw_template_bytes += raw.raw.length()
    }
    ForLoop(for_loop) => self.compile_for_loop(for_loop)
    IfCond(if_cond) => self.compile_if_stmt(if_cond)
    WithBlock(with_block) => {
      self.set_line_from_span(with_block.span)
      self.add(PushWith) |> ignore
      for pair in with_block.assignments {
        self.compile_expr(pair.1)
        self.compile_assignment(pair.0)
      }
      for node in with_block.body {
        self.compile_stmt(node)
      }
      self.add(PopFrame) |> ignore
    }
    Set(set) => {
      self.set_line_from_span(set.span)
      self.compile_expr(set.expr)
      self.compile_assignment(set.target)
    }
    SetBlock(set_block) => {
      self.set_line_from_span(set_block.span)
      self.add(BeginCapture(Capture)) |> ignore
      for node in set_block.body {
        self.compile_stmt(node)
      }
      self.add(EndCapture) |> ignore
      if set_block.filter is Some(filter) {
        self.compile_expr(filter)
      }
      self.compile_assignment(set_block.target)
    }
    AutoEscape(auto_escape) => {
      self.set_line_from_span(auto_escape.span)
      self.compile_expr(auto_escape.enabled)
      self.add(PushAutoEscape) |> ignore
      for node in auto_escape.body {
        self.compile_stmt(node)
      }
      self.add(PopAutoEscape) |> ignore
    }
    FilterBlock(filter_block) => {
      self.set_line_from_span(filter_block.span)
      self.add(BeginCapture(Capture)) |> ignore
      for node in filter_block.body {
        self.compile_stmt(node)
      }
      self.add(EndCapture) |> ignore
      self.compile_expr(filter_block.filter)
      self.add(Emit) |> ignore
    }
    Block(block) => self.compile_block(block)
    Import(import_) => {
      self.add(BeginCapture(Capture)) |> ignore
      self.add(PushWith) |> ignore
      self.compile_expr(import_.expr)
      self.add_with_span(Include(false), import_.span) |> ignore
      self.add(EndCapture) |> ignore
      self.add(ExportLocals) |> ignore
      self.add(PopFrame) |> ignore
      self.compile_assignment(import_.name)
    }
    FromImport(from_import) => {
      self.add(BeginCapture(Discard)) |> ignore
      self.add(PushWith) |> ignore
      self.compile_expr(from_import.expr)
      self.add_with_span(Include(false), from_import.span) |> ignore
      for pair in from_import.names {
        self.compile_expr(pair.0)
      }
      self.add(PopFrame) |> ignore
      for i = from_import.names.length() - 1; i >= 0; i = i - 1 {
        let (name, alias_name) = from_import.names[i]
        self.compile_assignment(alias_name.unwrap_or(name))
      }
      self.add(EndCapture) |> ignore
    }
    Extends(extends) => {
      self.set_line_from_span(extends.span)
      self.compile_expr(extends.name)
      self.add_with_span(LoadBlocks, extends.span) |> ignore
    }
    Include(include) => {
      self.set_line_from_span(include.span)
      self.compile_expr(include.name)
      self.add_with_span(Include(include.ignore_missing), include.span)
      |> ignore
    }
    Macro(macro_decl) => self.compile_macro(macro_decl)
    CallBlock(call_block) => self.compile_call_block(call_block)
    Continue(span) => {
      self.set_line_from_span(span)
      for i = self.pending_block.length() - 1; i >= 0; i = i - 1 {
        if self.pending_block[i] is Loop(iter_instr, _) {
          self.add(Jump(iter_instr)) |> ignore
          break
        }
      }
    }
    Break(span) => {
      self.set_line_from_span(span)
      let instr = self.add(Jump(0))
      for i = self.pending_block.length() - 1; i >= 0; i = i - 1 {
        if self.pending_block[i] is Loop(_, jump_instrs) {
          jump_instrs.push(instr)
          break
        }
      }
    }
    Do(do_tag) => self.compile_call(do_tag.call, None)
  }
}

///|
fn CodeGenerator::compile_block(
  self : CodeGenerator,
  block : BlockNode,
) -> Unit {
  self.set_line_from_span(block.span)
  let sub = self.new_subgenerator()
  for node in block.body {
    sub.compile_stmt(node)
  }
  sub.instructions.required_block = block.required
  let instructions = self.finish_subgenerator(sub)
  self.blocks[block.name] = instructions
  self.add(CallBlock(block.name)) |> ignore
}

///|
fn CodeGenerator::compile_macro_expression(
  self : CodeGenerator,
  macro_decl : MacroNode,
) -> Unit {
  self.set_line_from_span(macro_decl.span)
  let instr = self.add(Jump(-1))
  let defaults = macro_decl.defaults
  let mut default_idx = defaults.length() - 1
  for i = macro_decl.args.length() - 1; i >= 0; i = i - 1 {
    let arg = macro_decl.args[i]
    if default_idx >= 0 {
      let default = defaults[default_idx]
      default_idx -= 1
      self.add(DupTop) |> ignore
      self.add(IsUndefined) |> ignore
      self.start_if()
      self.add(DiscardTop) |> ignore
      self.compile_expr(default)
      self.end_if()
    }
    self.compile_assignment(arg)
  }
  for node in macro_decl.body {
    self.compile_stmt(node)
  }
  self.add(Return) |> ignore
  let undeclared = find_macro_closure(macro_decl)
  let caller_reference = undeclared.contains("caller")
  undeclared.remove("caller")
  let macro_instr = self.next_instruction()
  for name in undeclared {
    self.add(Enclose(name)) |> ignore
  }
  self.add(GetClosure) |> ignore
  self.add(
    LoadConst(
      Value::from_array(
        macro_decl.args.map(x => {
          match x {
            Var(v) => Value::from_string(v.id)
            _ => abort("unreachable")
          }
        }),
      ),
    ),
  )
  |> ignore
  let mut flags = 0
  if caller_reference {
    flags = flags | MACRO_CALLER
  }
  self.add(BuildMacro(macro_decl.name, instr + 1, flags)) |> ignore
  self.patch(instr, macro_instr)
}

///|
fn CodeGenerator::compile_macro(
  self : CodeGenerator,
  macro_decl : MacroNode,
) -> Unit {
  self.compile_macro_expression(macro_decl)
  self.add(StoreLocal(macro_decl.name)) |> ignore
}

///|
fn CodeGenerator::compile_call_block(
  self : CodeGenerator,
  call_block : CallBlockNode,
) -> Unit {
  self.compile_call(call_block.call, Some(call_block.macro_decl))
  self.add(Emit) |> ignore
}

///|
fn CodeGenerator::compile_if_stmt(
  self : CodeGenerator,
  if_cond : IfCondNode,
) -> Unit {
  self.set_line_from_span(if_cond.span)
  self.push_span(if_cond.expr.span())
  self.compile_expr(if_cond.expr)
  self.start_if()
  self.pop_span()
  for node in if_cond.true_body {
    self.compile_stmt(node)
  }
  if !if_cond.false_body.is_empty() {
    self.start_else()
    for node in if_cond.false_body {
      self.compile_stmt(node)
    }
  }
  self.end_if()
}

///|
fn CodeGenerator::compile_emit_expr(
  self : CodeGenerator,
  expr : EmitExprNode,
) -> Unit {
  if expr.expr is Call(call) {
    self.set_line_from_span(expr.expr.span())
    match call.identify_call() {
      Function("super") if call.args.is_empty() => {
        self.add_with_span(FastSuper, call.span) |> ignore
        return
      }
      Function("loop") if call.args.length() == 1 => {
        self.compile_call_args([call.args[0]], 0, None) |> ignore
        self.add_with_span(FastRecurse, call.span) |> ignore
        return
      }
      Block(name) => {
        self.add(CallBlock(name)) |> ignore
        return
      }
      _ => ()
    }
  }
  self.push_span(expr.expr.span())
  self.compile_expr(expr.expr)
  self.add(Emit) |> ignore
  self.pop_span()
}

///|
fn CodeGenerator::compile_for_loop(
  self : CodeGenerator,
  for_loop : ForLoopNode,
) -> Unit {
  self.set_line_from_span(for_loop.span)

  // filter expressions work like a nested for loop without the special loop
  // variable. in one loop, the condition is checked and passing items
  // accumulated into a list. in the second, that list is iterated over
  // normally
  match for_loop.filter_expr {
    Some(filter_expr) => {
      self.add(LoadConst(Value::from_int(0))) |> ignore
      self.push_span(filter_expr.span())
      self.compile_expr(for_loop.iter)
      self.start_for_loop(false, false)
      self.add(DupTop) |> ignore
      self.compile_assignment(for_loop.target)
      self.compile_expr(filter_expr)
      self.start_if()
      self.add(Swap) |> ignore
      self.add(LoadConst(Value::from_int(1))) |> ignore
      self.add(Add) |> ignore
      self.start_else()
      self.add(DiscardTop) |> ignore
      self.end_if()
      self.pop_span()
      self.end_for_loop(false)
      self.add(BuildList(None)) |> ignore
      self.start_for_loop(true, for_loop.recursive)
    }
    None => {
      self.push_span(for_loop.iter.span())
      self.compile_expr(for_loop.iter)
      self.start_for_loop(true, for_loop.recursive)
      self.pop_span()
    }
  }
  self.compile_assignment(for_loop.target)
  for node in for_loop.body {
    self.compile_stmt(node)
  }
  self.end_for_loop(!for_loop.else_body.is_empty())
  if !for_loop.else_body.is_empty() {
    self.start_if()
    for node in for_loop.else_body {
      self.compile_stmt(node)
    }
    self.end_if()
  }
}

///|
/// Compiles an assignment expression.
fn CodeGenerator::compile_assignment(self : CodeGenerator, expr : Expr) -> Unit {
  match expr {
    Var(v) => self.add(StoreLocal(v.id)) |> ignore
    List(list) => {
      self.push_span(list.span)
      self.add(UnpackList(list.items.length())) |> ignore
      for item in list.items {
        self.compile_assignment(item)
      }
      self.pop_span()
    }
    GetAttr(attr) => {
      self.push_span(attr.span)
      self.compile_expr(attr.expr)
      self.add(SetAttr(attr.name)) |> ignore
    }
    _ => abort("unreachable")
  }
}

///|
/// Compiles an expression.
fn CodeGenerator::compile_expr(self : CodeGenerator, expr : Expr) -> Unit {
  // try to do constant folding
  if expr.as_const() is Some(v) {
    self.set_line_from_span(expr.span())
    self.add(LoadConst(v)) |> ignore
    return
  }
  match expr {
    Var(v) => {
      self.set_line_from_span(v.span)
      self.add(Lookup(v.id)) |> ignore
    }
    Const(_) => abort("unreachable") // handled by constant folding
    Slice(s) => {
      self.push_span(s.span)
      self.compile_expr(s.expr)
      for part in [s.start, s.stop, s.step] {
        match part {
          Some(e) => self.compile_expr(e)
          None => self.add(LoadConst(Value::none())) |> ignore
        }
      }
      self.add(Slice) |> ignore
      self.pop_span()
    }
    UnaryOp(c) => {
      self.set_line_from_span(c.span)
      match c.op {
        Not => {
          self.compile_expr(c.expr)
          self.add(Not) |> ignore
        }
        Neg => {
          // common case: negative numbers.  In that case we directly negate
          // them if this is possible without an error.
          if c.expr is Const(cnst) {
            let negated = value_neg(cnst.value) catch {
              _ => Value::undefined()
            }
            if !negated.is_undefined() {
              self.add(LoadConst(negated)) |> ignore
              return
            }
          }
          self.compile_expr(c.expr)
          self.add_with_span(Neg, c.span) |> ignore
        }
      }
    }
    BinOp(c) => self.compile_bin_op(c)
    Compare(c) => self.compile_compare(c)
    IfExpr(i) => {
      self.set_line_from_span(i.span)
      self.compile_expr(i.test_expr)
      self.start_if()
      self.compile_expr(i.true_expr)
      self.start_else()
      match i.false_expr {
        Some(false_expr) => self.compile_expr(false_expr)
        // special behavior: missing false block have a silent undefined to
        // permit special casing.  This is for compatibility also with what
        // Jinja2 does.
        None => self.add(LoadConst(Value::silent_undefined())) |> ignore
      }
      self.end_if()
    }
    Filter(f) => {
      self.push_span(f.span)
      if f.expr is Some(e) {
        self.compile_expr(e)
      }
      let arg_count = self.compile_call_args(f.args, 1, None)
      let local_id = get_local_id(self.filter_local_ids, f.name)
      self.add(ApplyFilter(f.name, arg_count, local_id)) |> ignore
      self.pop_span()
    }
    Test(f) => {
      self.push_span(f.span)
      self.compile_expr(f.expr)
      let arg_count = self.compile_call_args(f.args, 1, None)
      let local_id = get_local_id(self.test_local_ids, f.name)
      self.add(PerformTest(f.name, arg_count, local_id)) |> ignore
      self.pop_span()
    }
    GetAttr(g) => {
      self.push_span(g.span)
      self.compile_expr(g.expr)
      self.add(GetAttr(g.name)) |> ignore
      self.pop_span()
    }
    GetItem(g) => {
      self.push_span(g.span)
      self.compile_expr(g.expr)
      self.compile_expr(g.subscript_expr)
      self.add(GetItem) |> ignore
      self.pop_span()
    }
    Call(c) => self.compile_call(c, None)
    List(l) => {
      self.set_line_from_span(l.span)
      for item in l.items {
        self.compile_expr(item)
      }
      self.add(BuildList(Some(l.items.length()))) |> ignore
    }
    Tuple(t) => {
      self.set_line_from_span(t.span)
      for item in t.items {
        self.compile_expr(item)
      }
      self.add(BuildTuple(Some(t.items.length()))) |> ignore
    }
    Map(m) => {
      self.set_line_from_span(m.span)
      for i, key in m.keys {
        self.compile_expr(key)
        self.compile_expr(m.values[i])
      }
      self.add(BuildMap(m.keys.length())) |> ignore
    }
  }
}

///|
fn CodeGenerator::compile_call(
  self : CodeGenerator,
  c : CallNode,
  caller : MacroNode?,
) -> Unit {
  self.push_span(c.span)
  match c.identify_call() {
    Function(name) => {
      let arg_count = self.compile_call_args(c.args, 0, caller)
      self.add(CallFunction(name, arg_count)) |> ignore
    }
    Block(name) => {
      self.add(BeginCapture(Capture)) |> ignore
      self.add(CallBlock(name)) |> ignore
      self.add(EndCapture) |> ignore
    }
    Method(expr, name) => {
      self.compile_expr(expr)
      let arg_count = self.compile_call_args(c.args, 1, caller)
      self.add(CallMethod(name, arg_count)) |> ignore
    }
    Object(expr) => {
      self.compile_expr(expr)
      let arg_count = self.compile_call_args(c.args, 1, caller)
      self.add(CallObject(arg_count)) |> ignore
    }
  }
  self.pop_span()
}

///|
fn CodeGenerator::compile_call_args(
  self : CodeGenerator,
  args : Array[CallArg],
  extra_args : Int,
  caller : MacroNode?,
) -> Int? {
  let mut pending_args = extra_args
  let mut num_args_batches = 0
  let mut has_kwargs = caller is Some(_)
  let mut static_kwargs = caller is None
  for arg in args {
    match arg {
      Pos(expr) => {
        self.compile_expr(expr)
        pending_args += 1
      }
      PosSplat(expr) => {
        if pending_args > 0 {
          self.add(BuildList(Some(pending_args))) |> ignore
          pending_args = 0
          num_args_batches += 1
        }
        self.compile_expr(expr)
        num_args_batches += 1
      }
      Kwarg(_, expr) => {
        if !(expr is Const(_)) {
          static_kwargs = false
        }
        has_kwargs = true
      }
      KwargSplat(_) => {
        static_kwargs = false
        has_kwargs = true
      }
    }
  }
  if has_kwargs {
    let mut pending_kwargs = 0
    let mut num_kwargs_batches = 0
    let collected_kwargs : Map[Value, Value] = Map([])
    for arg in args {
      match arg {
        Kwarg(key, value) =>
          if static_kwargs {
            match value {
              Const(c) => collected_kwargs[Value::from_string(key)] = c.value
              _ => abort("unreachable")
            }
          } else {
            self.add(LoadConst(Value::from_string(key))) |> ignore
            self.compile_expr(value)
            pending_kwargs += 1
          }
        KwargSplat(expr) => {
          if pending_kwargs > 0 {
            self.add(BuildKwargs(pending_kwargs)) |> ignore
            num_kwargs_batches += 1
            pending_kwargs = 0
          }
          self.compile_expr(expr)
          num_kwargs_batches += 1
        }
        Pos(_) | PosSplat(_) => ()
      }
    }
    if !collected_kwargs.is_empty() {
      self.add(LoadConst(Value::from_kwargs_map(collected_kwargs))) |> ignore
    } else {
      // The conditions above guarantee that if we collect static kwargs we
      // cannot enter this block (single kwargs batch, no caller).
      if caller is Some(caller) {
        self.add(LoadConst(Value::from_string("caller"))) |> ignore
        self.compile_macro_expression(caller)
        pending_kwargs += 1
      }
      if num_kwargs_batches > 0 {
        if pending_kwargs > 0 {
          self.add(BuildKwargs(pending_kwargs)) |> ignore
          num_kwargs_batches += 1
        }
        self.add(MergeKwargs(num_kwargs_batches)) |> ignore
      } else {
        self.add(BuildKwargs(pending_kwargs)) |> ignore
      }
    }
    pending_args += 1
  }
  if num_args_batches > 0 {
    if pending_args > 0 {
      self.add(BuildList(Some(pending_args))) |> ignore
      num_args_batches += 1
    }
    self.add(UnpackLists(num_args_batches)) |> ignore
    None
  } else {
    Some(pending_args)
  }
}

///|
fn CodeGenerator::compile_compare(
  self : CodeGenerator,
  c : CompareNode,
) -> Unit {
  self.push_span(c.span)
  self.compile_expr(c.expr)
  let cleanup_jumps = []
  for idx, op in c.ops {
    self.compile_expr(op.expr)
    if idx + 1 == c.ops.length() {
      self.emit_compare(op.op)
    } else {
      self.add(CompareAndPreserve(compare_op(op.op))) |> ignore
      cleanup_jumps.push(self.add(JumpIfFalseOrPop(-1)))
    }
  }
  if !cleanup_jumps.is_empty() {
    let jump_end = self.add(Jump(-1))
    let cleanup_start = self.next_instruction()
    self.add(Swap) |> ignore
    self.add(DiscardTop) |> ignore
    let end = self.next_instruction()
    for instr in cleanup_jumps {
      self.patch(instr, cleanup_start)
    }
    self.patch(jump_end, end)
  }
  self.pop_span()
}

///|
fn CodeGenerator::emit_compare(
  self : CodeGenerator,
  op : CompareOpKind,
) -> Unit {
  self.add(
    match op {
      Eq => Eq
      Ne => Ne
      Lt => Lt
      Lte => Lte
      Gt => Gt
      Gte => Gte
      In | NotIn => In
    },
  )
  |> ignore
  if op is NotIn {
    self.add(Not) |> ignore
  }
}

///|
fn CodeGenerator::compile_bin_op(self : CodeGenerator, c : BinOpNode) -> Unit {
  self.push_span(c.span)
  let instr : Instruction = match c.op {
    Eq => Eq
    Ne => Ne
    Lt => Lt
    Lte => Lte
    Gt => Gt
    Gte => Gte
    ScAnd | ScOr => {
      self.start_sc_bool()
      self.compile_expr(c.left)
      self.sc_bool(c.op is ScAnd)
      self.compile_expr(c.right)
      self.end_sc_bool()
      self.pop_span()
      return
    }
    Add => Add
    Sub => Sub
    Mul => Mul
    Div => Div
    FloorDiv => IntDiv
    Rem => Rem
    Pow => Pow
    Concat => StringConcat
    In => In
  }
  self.compile_expr(c.left)
  self.compile_expr(c.right)
  self.add(instr) |> ignore
  self.pop_span()
}

///|
/// Returns the size hint for buffers.
fn CodeGenerator::buffer_size_hint(self : CodeGenerator) -> Int {
  self.raw_template_bytes * 2
}

///|
/// Converts the compiler into the instructions.
fn CodeGenerator::finish(
  self : CodeGenerator,
) -> (Instructions, Map[String, Instructions]) {
  (self.instructions, self.blocks)
}
