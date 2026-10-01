///|
/// This loop has the loop var.
const LOOP_FLAG_WITH_LOOP_VAR : Int = 1

///|
/// This loop is recursive.
const LOOP_FLAG_RECURSIVE : Int = 2

///|
/// This macro uses the caller var.
const MACRO_CALLER : Int = 2

///|
/// The maximum number of filters/tests that can be cached.
const MAX_LOCALS : Int = 50

///|
priv enum CaptureMode {
  Capture
  Discard
} derive(Eq)

///|
/// A comparison operation.
priv enum CompareOp {
  Eq
  Ne
  Lt
  Lte
  Gt
  Gte
  In
  NotIn
}

///|
/// Represents an instruction for the VM.
priv enum Instruction {
  /// Emits raw source
  EmitRaw(String)
  /// Stores a variable (only possible in for loops)
  StoreLocal(String)
  /// Load a variable,
  Lookup(String)
  /// Looks up an attribute.
  GetAttr(String)
  /// Sets an attribute.
  SetAttr(String)
  /// Looks up an item.
  GetItem
  /// Performs a slice operation.
  Slice
  /// Loads a constant value.
  LoadConst(Value)
  /// Builds a map of the last n pairs on the stack.
  BuildMap(Int)
  /// Builds a kwargs map of the last n pairs on the stack.
  BuildKwargs(Int)
  /// Merges N kwargs maps on the list into one.
  MergeKwargs(Int)
  /// Builds a list of the last n pairs on the stack.
  BuildList(Int?)
  /// Builds a tuple of the last n pairs on the stack.
  BuildTuple(Int?)
  /// Unpacks a list into N stack items.
  UnpackList(Int)
  /// Unpacks N lists onto the stack and pushes the number of items there
  /// were unpacked.
  UnpackLists(Int)
  Add
  Sub
  Mul
  Div
  IntDiv
  Rem
  Pow
  Neg
  Eq
  Ne
  Gt
  Gte
  Lt
  Lte
  Not
  StringConcat
  In
  /// Performs a comparison and preserves the right operand for chained
  /// comparisons.
  CompareAndPreserve(CompareOp)
  /// Apply a filter.
  ApplyFilter(String, Int?, Int)
  /// Perform a test.
  PerformTest(String, Int?, Int)
  /// Emit the stack top as output
  Emit
  /// Starts a loop.  The argument are loop flags.
  PushLoop(Int)
  /// Starts a with block.
  PushWith
  /// Does a single loop iteration.  The argument is the jump target for
  /// when the loop ends and must point to a `PopLoopFrame` instruction.
  Iterate(Int)
  /// Push a bool that indicates that the loop iterated.
  PushDidNotIterate
  /// Pops the topmost frame
  PopFrame
  /// Pops the topmost frame and runs loop logic
  PopLoopFrame
  /// Jump to a specific instruction
  Jump(Int)
  /// Jump if the stack top evaluates to false
  JumpIfFalse(Int)
  /// Jump if the stack top evaluates to false or pops the value
  JumpIfFalseOrPop(Int)
  /// Jump if the stack top evaluates to true or pops the value
  JumpIfTrueOrPop(Int)
  /// Sets the auto escape flag to the current value.
  PushAutoEscape
  /// Resets the auto escape flag to the previous value.
  PopAutoEscape
  /// Begins capturing of output (false) or discard (true).
  BeginCapture(CaptureMode)
  /// Ends capturing of output.
  EndCapture
  /// Calls a global function
  CallFunction(String, Int?)
  /// Calls a method
  CallMethod(String, Int?)
  /// Calls an object
  CallObject(Int?)
  /// Duplicates the top item
  DupTop
  /// Discards the top item
  DiscardTop
  /// A fast super instruction without intermediate capturing.
  FastSuper
  /// A fast loop recurse instruction without intermediate capturing.
  FastRecurse
  /// Swaps the top two items in the stack.
  Swap
  /// Call into a block.
  CallBlock(String)
  /// Loads block from a template with name on stack ("extends")
  LoadBlocks
  /// Includes another template.
  Include(Bool)
  /// Builds a module
  ExportLocals
  /// Builds a macro on the stack.
  BuildMacro(String, Int, Int)
  /// Breaks from the interpreter loop (exists a function)
  Return
  /// True if the value is undefined
  IsUndefined
  /// Encloses a variable.
  Enclose(String)
  /// Returns the closure of this context level.
  GetClosure
}

///|
fn opt_int_debug(v : Int?) -> String {
  match v {
    Some(n) => "Some(\{n})"
    None => "None"
  }
}

///|
fn Instruction::debug_string(self : Instruction) -> String {
  fn s(x : String) -> String {
    @rfmt.str_debug(x)
  }

  match self {
    EmitRaw(x) => "EmitRaw(\{s(x)})"
    StoreLocal(x) => "StoreLocal(\{s(x)})"
    Lookup(x) => "Lookup(\{s(x)})"
    GetAttr(x) => "GetAttr(\{s(x)})"
    SetAttr(x) => "SetAttr(\{s(x)})"
    GetItem => "GetItem"
    Slice => "Slice"
    LoadConst(v) => "LoadConst(\{v.debug_string()})"
    BuildMap(n) => "BuildMap(\{n})"
    BuildKwargs(n) => "BuildKwargs(\{n})"
    MergeKwargs(n) => "MergeKwargs(\{n})"
    BuildList(n) => "BuildList(\{opt_int_debug(n)})"
    BuildTuple(n) => "BuildTuple(\{opt_int_debug(n)})"
    UnpackList(n) => "UnpackList(\{n})"
    UnpackLists(n) => "UnpackLists(\{n})"
    Add => "Add"
    Sub => "Sub"
    Mul => "Mul"
    Div => "Div"
    IntDiv => "IntDiv"
    Rem => "Rem"
    Pow => "Pow"
    Neg => "Neg"
    Eq => "Eq"
    Ne => "Ne"
    Gt => "Gt"
    Gte => "Gte"
    Lt => "Lt"
    Lte => "Lte"
    Not => "Not"
    StringConcat => "StringConcat"
    In => "In"
    CompareAndPreserve(op) => {
      let name = match op {
        Eq => "Eq"
        Ne => "Ne"
        Lt => "Lt"
        Lte => "Lte"
        Gt => "Gt"
        Gte => "Gte"
        In => "In"
        NotIn => "NotIn"
      }
      "CompareAndPreserve(\{name})"
    }
    ApplyFilter(name, n, id) =>
      "ApplyFilter(\{s(name)}, \{opt_int_debug(n)}, \{id})"
    PerformTest(name, n, id) =>
      "PerformTest(\{s(name)}, \{opt_int_debug(n)}, \{id})"
    Emit => "Emit"
    PushLoop(flags) => "PushLoop(\{flags})"
    PushWith => "PushWith"
    Iterate(t) => "Iterate(\{t})"
    PushDidNotIterate => "PushDidNotIterate"
    PopFrame => "PopFrame"
    PopLoopFrame => "PopLoopFrame"
    Jump(t) => "Jump(\{t})"
    JumpIfFalse(t) => "JumpIfFalse(\{t})"
    JumpIfFalseOrPop(t) => "JumpIfFalseOrPop(\{t})"
    JumpIfTrueOrPop(t) => "JumpIfTrueOrPop(\{t})"
    PushAutoEscape => "PushAutoEscape"
    PopAutoEscape => "PopAutoEscape"
    BeginCapture(mode) =>
      "BeginCapture(\{if mode == Capture { "Capture" } else { "Discard" }})"
    EndCapture => "EndCapture"
    CallFunction(name, n) => "CallFunction(\{s(name)}, \{opt_int_debug(n)})"
    CallMethod(name, n) => "CallMethod(\{s(name)}, \{opt_int_debug(n)})"
    CallObject(n) => "CallObject(\{opt_int_debug(n)})"
    DupTop => "DupTop"
    DiscardTop => "DiscardTop"
    FastSuper => "FastSuper"
    FastRecurse => "FastRecurse"
    Swap => "Swap"
    CallBlock(name) => "CallBlock(\{s(name)})"
    LoadBlocks => "LoadBlocks"
    Include(b) => "Include(\{b})"
    ExportLocals => "ExportLocals"
    BuildMacro(name, offset, flags) =>
      "BuildMacro(\{s(name)}, \{offset}, \{flags})"
    Return => "Return"
    IsUndefined => "IsUndefined"
    Enclose(name) => "Enclose(\{s(name)})"
    GetClosure => "GetClosure"
  }
}

///|
/// Wrapper around instructions to help with location management.
priv struct Instructions {
  instructions : Array[Instruction]
  line_infos : Array[(Int, Int)]
  span_infos : Array[(Int, Span)]
  name : String
  source : String
  mut required_block : Bool
}

///|
fn Instructions::new(name : String, source : String) -> Instructions {
  {
    instructions: [],
    line_infos: [],
    span_infos: [],
    name,
    source,
    required_block: false,
  }
}

///|
fn Instructions::get(self : Instructions, idx : Int) -> Instruction? {
  self.instructions.get(idx)
}

///|
fn Instructions::add(self : Instructions, instr : Instruction) -> Int {
  let rv = self.instructions.length()
  self.instructions.push(instr)
  rv
}

///|
fn Instructions::len(self : Instructions) -> Int {
  self.instructions.length()
}

///|
fn Instructions::add_line_record(
  self : Instructions,
  instr : Int,
  line : Int,
) -> Unit {
  let same_loc = match self.line_infos.last() {
    Some((_, last_line)) => last_line == line
    None => false
  }
  if !same_loc {
    self.line_infos.push((instr, line))
  }
}

///|
/// Adds a new instruction with line number.
fn Instructions::add_with_line(
  self : Instructions,
  instr : Instruction,
  line : Int,
) -> Int {
  let rv = self.add(instr)
  self.add_line_record(rv, line)
  // if we follow up to a valid span with no more span, clear it out
  if self.span_infos.last() is Some((_, span)) && span != Span::default() {
    self.span_infos.push((rv, Span::default()))
  }
  rv
}

///|
/// Adds a new instruction with span.
fn Instructions::add_with_span(
  self : Instructions,
  instr : Instruction,
  span : Span,
) -> Int {
  let rv = self.add(instr)
  let same_loc = match self.span_infos.last() {
    Some((_, last_span)) => last_span == span
    None => false
  }
  if !same_loc {
    self.span_infos.push((rv, span))
  }
  self.add_line_record(rv, span.start_line)
  rv
}

///|
/// Binary search for the last record whose first instruction is `<= idx`.
fn[T] lookup_record(records : Array[(Int, T)], idx : Int) -> T? {
  let mut lo = 0
  let mut hi = records.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if records[mid].0 <= idx {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo == 0 {
    None
  } else {
    Some(records[lo - 1].1)
  }
}

///|
/// Looks up the line for an instruction
fn Instructions::get_line(self : Instructions, idx : Int) -> Int? {
  lookup_record(self.line_infos, idx)
}

///|
/// Looks up a span for an instruction.
fn Instructions::get_span(self : Instructions, idx : Int) -> Span? {
  match lookup_record(self.span_infos, idx) {
    Some(span) if span != Span::default() => Some(span)
    _ => None
  }
}

///|
/// Returns a list of all names referenced in the current block backwards
/// from the given pc.
fn Instructions::get_referenced_names(
  self : Instructions,
  idx : Int,
) -> Array[String] {
  let rv : Array[String] = []
  if self.instructions.is_empty() {
    return rv
  }
  let idx = if idx < self.instructions.length() - 1 {
    idx
  } else {
    self.instructions.length() - 1
  }
  for i = idx; i >= 0; i = i - 1 {
    let name = match self.instructions[i] {
      Lookup(name) | StoreLocal(name) | CallFunction(name, _) => name
      PushLoop(flags) if (flags & LOOP_FLAG_WITH_LOOP_VAR) != 0 => "loop"
      PushLoop(_) | PushWith => break
      _ => continue
    }
    if !rv.contains(name) {
      rv.push(name)
    }
  }
  rv
}

///|
fn Instructions::debug_string(self : Instructions) -> String {
  let f = @rfmt.Formatter::new(alternate=true)
  self.fmt_debug(f)
  f.to_string()
}

///|
fn Instructions::fmt_debug(self : Instructions, f : @rfmt.Formatter) -> Unit {
  let l = f.debug_list()
  let mut last_line : Int? = None
  for idx, instr in self.instructions {
    let line = self.get_line(idx)
    let idx_str = idx.to_string()
    let padded = "0".repeat(
        if idx_str.length() < 5 {
          5 - idx_str.length()
        } else {
          0
        },
      ) +
      idx_str
    let mut entry = "\{padded} | \{instr.debug_string()}"
    if line != last_line && line is Some(line) {
      entry = entry + "  [line \{line}]"
    }
    l.entry(f => f.write_str(entry)) |> ignore
    last_line = line
  }
  l.finish()
}
