///|
/// A statement node.
priv enum Stmt {
  Template(TemplateNode)
  EmitExpr(EmitExprNode)
  EmitRaw(EmitRawNode)
  ForLoop(ForLoopNode)
  IfCond(IfCondNode)
  WithBlock(WithBlockNode)
  Set(SetNode)
  SetBlock(SetBlockNode)
  AutoEscape(AutoEscapeNode)
  FilterBlock(FilterBlockNode)
  Block(BlockNode)
  Import(ImportNode)
  FromImport(FromImportNode)
  Extends(ExtendsNode)
  Include(IncludeNode)
  Macro(MacroNode)
  CallBlock(CallBlockNode)
  Continue(Span)
  Break(Span)
  Do(DoNode)
}

///|
/// An expression node.
priv enum Expr {
  Var(VarNode)
  Const(ConstNode)
  Slice(SliceNode)
  UnaryOp(UnaryOpNode)
  BinOp(BinOpNode)
  Compare(CompareNode)
  IfExpr(IfExprNode)
  Filter(FilterNode)
  Test(TestNode)
  GetAttr(GetAttrNode)
  GetItem(GetItemNode)
  Call(CallNode)
  List(ListNode)
  Tuple(TupleNode)
  Map(MapNode)
}

///|
priv struct TemplateNode {
  children : Array[Stmt]
  span : Span
}

///|
priv struct ForLoopNode {
  target : Expr
  iter : Expr
  filter_expr : Expr?
  recursive : Bool
  body : Array[Stmt]
  else_body : Array[Stmt]
  span : Span
}

///|
priv struct IfCondNode {
  expr : Expr
  true_body : Array[Stmt]
  false_body : Array[Stmt]
  span : Span
}

///|
priv struct WithBlockNode {
  assignments : Array[(Expr, Expr)]
  body : Array[Stmt]
  span : Span
}

///|
priv struct SetNode {
  target : Expr
  expr : Expr
  span : Span
}

///|
priv struct SetBlockNode {
  target : Expr
  filter : Expr?
  body : Array[Stmt]
  span : Span
}

///|
priv struct BlockNode {
  name : String
  required : Bool
  body : Array[Stmt]
  span : Span
}

///|
priv struct ExtendsNode {
  name : Expr
  span : Span
}

///|
priv struct IncludeNode {
  name : Expr
  ignore_missing : Bool
  span : Span
}

///|
priv struct AutoEscapeNode {
  enabled : Expr
  body : Array[Stmt]
  span : Span
}

///|
priv struct FilterBlockNode {
  filter : Expr
  body : Array[Stmt]
  span : Span
}

///|
priv struct MacroNode {
  name : String
  args : Array[Expr]
  defaults : Array[Expr]
  body : Array[Stmt]
  span : Span
}

///|
priv struct CallBlockNode {
  call : CallNode
  macro_decl : MacroNode
  span : Span
}

///|
priv struct DoNode {
  call : CallNode
  span : Span
}

///|
priv struct FromImportNode {
  expr : Expr
  names : Array[(Expr, Expr?)]
  span : Span
}

///|
priv struct ImportNode {
  expr : Expr
  name : Expr
  span : Span
}

///|
priv struct EmitExprNode {
  expr : Expr
  span : Span
}

///|
priv struct EmitRawNode {
  raw : String
  span : Span
}

///|
priv struct VarNode {
  id : String
  span : Span
}

///|
priv struct ConstNode {
  value : Value
  span : Span
}

///|
priv struct SliceNode {
  expr : Expr
  start : Expr?
  stop : Expr?
  step : Expr?
  span : Span
}

///|
priv enum UnaryOpKind {
  Not
  Neg
}

///|
priv struct UnaryOpNode {
  op : UnaryOpKind
  expr : Expr
  span : Span
}

///|
priv enum CompareOpKind {
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
priv enum BinOpKind {
  Eq
  Ne
  Lt
  Lte
  Gt
  Gte
  ScAnd
  ScOr
  Add
  Sub
  Mul
  Div
  FloorDiv
  Rem
  Pow
  Concat
  In
}

///|
priv struct BinOpNode {
  op : BinOpKind
  left : Expr
  right : Expr
  span : Span
}

///|
priv struct CompareOp {
  op : CompareOpKind
  expr : Expr
}

///|
priv struct CompareNode {
  expr : Expr
  ops : Array[CompareOp]
  span : Span
}

///|
priv struct IfExprNode {
  test_expr : Expr
  true_expr : Expr
  false_expr : Expr?
  span : Span
}

///|
priv struct FilterNode {
  name : String
  expr : Expr?
  args : Array[CallArg]
  span : Span
}

///|
priv struct TestNode {
  name : String
  expr : Expr
  args : Array[CallArg]
  span : Span
}

///|
priv struct GetAttrNode {
  expr : Expr
  name : String
  span : Span
}

///|
priv struct GetItemNode {
  expr : Expr
  subscript_expr : Expr
  span : Span
}

///|
priv struct CallNode {
  expr : Expr
  args : Array[CallArg]
  span : Span
}

///|
priv enum CallArg {
  Pos(Expr)
  Kwarg(String, Expr)
  PosSplat(Expr)
  KwargSplat(Expr)
}

///|
priv struct ListNode {
  items : Array[Expr]
  span : Span
}

///|
priv struct TupleNode {
  items : Array[Expr]
  span : Span
}

///|
priv struct MapNode {
  keys : Array[Expr]
  values : Array[Expr]
  span : Span
}

///|
fn Expr::description(self : Expr) -> String {
  match self {
    Var(_) => "variable"
    Const(_) => "constant"
    Slice(_)
    | UnaryOp(_)
    | BinOp(_)
    | Compare(_)
    | IfExpr(_)
    | GetAttr(_)
    | GetItem(_) => "expression"
    Call(_) => "call"
    List(_) => "list literal"
    Tuple(_) => "tuple literal"
    Map(_) => "map literal"
    Test(_) => "test expression"
    Filter(_) => "filter expression"
  }
}

///|
fn Expr::span(self : Expr) -> Span {
  match self {
    Var(n) => n.span
    Const(n) => n.span
    Slice(n) => n.span
    UnaryOp(n) => n.span
    BinOp(n) => n.span
    Compare(n) => n.span
    IfExpr(n) => n.span
    Filter(n) => n.span
    Test(n) => n.span
    GetAttr(n) => n.span
    GetItem(n) => n.span
    Call(n) => n.span
    List(n) => n.span
    Tuple(n) => n.span
    Map(n) => n.span
  }
}

///|
fn const_values(items : Array[Expr]) -> Array[Value]? {
  let rv = []
  for item in items {
    match item {
      Const(c) => rv.push(c.value)
      _ => return None
    }
  }
  Some(rv)
}

///|
/// Returns the constant value of an expression if it can be determined at
/// compile time (used for constant folding).
fn Expr::as_const(self : Expr) -> Value? {
  match self {
    Const(c) => Some(c.value)
    List(l) => const_values(l.items).map(Value::from_array)
    Tuple(t) => const_values(t.items).map(Value::from_tuple)
    Map(m) => {
      let rv : Map[Value, Value] = Map([])
      for i, key in m.keys {
        match (key, m.values[i]) {
          (Const(k), Const(v)) => rv[k.value] = v.value
          _ => return None
        }
      }
      Some(Value::from_map(rv))
    }
    UnaryOp(c) =>
      match c.op {
        Not =>
          match c.expr.as_const() {
            Some(v) => Some(Value::from_bool(!v.is_true()))
            None => None
          }
        Neg =>
          match c.expr.as_const() {
            Some(v) =>
              try value_neg(v) catch {
                _ => None
              } noraise {
                v => Some(v)
              }
            None => None
          }
      }
    BinOp(c) =>
      match (c.left.as_const(), c.right.as_const()) {
        (Some(left), Some(right)) => eval_binop(c.op, left, right)
        _ => None
      }
    Compare(c) => {
      guard c.expr.as_const() is Some(left) else { return None }
      let mut left = left
      for op in c.ops {
        guard op.expr.as_const() is Some(right) else { return None }
        match eval_compare(op.op, left, right) {
          Some(v) => if !v.is_true() { return Some(Value::from_bool(false)) }
          None => return None
        }
        left = right
      }
      Some(Value::from_bool(true))
    }
    _ => None
  }
}

///|
fn eval_binop(op : BinOpKind, left : Value, right : Value) -> Value? {
  fn ok(f : () -> Value raise TemplateError) -> Value? {
    try f() catch {
      _ => None
    } noraise {
      v => Some(v)
    }
  }

  match op {
    Add => ok(() => value_add(left, right))
    Sub => ok(() => value_sub(left, right))
    Mul => ok(() => value_mul(left, right))
    Div => ok(() => value_div(left, right))
    FloorDiv => ok(() => value_int_div(left, right))
    Rem => ok(() => value_rem(left, right))
    Pow => ok(() => value_pow(left, right))
    Concat => Some(string_concat(left, right))
    Eq => Some(Value::from_bool(left == right))
    Ne => Some(Value::from_bool(left != right))
    Lt => Some(Value::from_bool(left.cmp(right) < 0))
    Lte => Some(Value::from_bool(left.cmp(right) <= 0))
    Gt => Some(Value::from_bool(left.cmp(right) > 0))
    Gte => Some(Value::from_bool(left.cmp(right) >= 0))
    In => ok(() => value_contains(right, left))
    ScAnd => Some(if left.is_true() { right } else { left })
    ScOr => Some(if left.is_true() { left } else { right })
  }
}

///|
fn eval_compare(op : CompareOpKind, left : Value, right : Value) -> Value? {
  match op {
    Eq => Some(Value::from_bool(left == right))
    Ne => Some(Value::from_bool(left != right))
    Lt => Some(Value::from_bool(left.cmp(right) < 0))
    Lte => Some(Value::from_bool(left.cmp(right) <= 0))
    Gt => Some(Value::from_bool(left.cmp(right) > 0))
    Gte => Some(Value::from_bool(left.cmp(right) >= 0))
    In =>
      try value_contains(right, left) catch {
        _ => None
      } noraise {
        v => Some(v)
      }
    NotIn =>
      try value_contains(right, left) catch {
        _ => None
      } noraise {
        v => Some(Value::from_bool(!v.is_true()))
      }
  }
}

///|
/// Defines the specific type of call.
priv enum CallType {
  Function(String)
  Method(Expr, String)
  Block(String)
  Object(Expr)
}

///|
/// Try to isolate a method call.
///
/// name + call and attribute lookup + call are really method calls which
/// are easier to handle for the compiler as a separate thing.
fn CallNode::identify_call(self : CallNode) -> CallType {
  match self.expr {
    Var(v) => Function(v.id)
    GetAttr(attr) =>
      match attr.expr {
        Var(v) if v.id == "self" => Block(attr.name)
        _ => Method(attr.expr, attr.name)
      }
    _ => Object(self.expr)
  }
}

// ---------------------------------------------------------------------------
// Debug printing (matches the upstream `internal_debug` output)

///|

///|
fn dbg_str(f : @rfmt.Formatter, s : String) -> Unit {
  f.write_str(@rfmt.str_debug(s))
}

///|
fn dbg_bool(f : @rfmt.Formatter, b : Bool) -> Unit {
  f.write_str(if b { "true" } else { "false" })
}

///|
fn dbg_stmts(f : @rfmt.Formatter, stmts : Array[Stmt]) -> Unit {
  let l = f.debug_list()
  for s in stmts {
    l.entry(f => s.fmt_debug(f)) |> ignore
  }
  l.finish()
}

///|
fn dbg_exprs(f : @rfmt.Formatter, exprs : Array[Expr]) -> Unit {
  let l = f.debug_list()
  for e in exprs {
    l.entry(f => e.fmt_debug(f)) |> ignore
  }
  l.finish()
}

///|
fn dbg_opt_expr(f : @rfmt.Formatter, expr : Expr?) -> Unit {
  match expr {
    None => f.write_str("None")
    Some(e) => f.debug_tuple("Some").field(f => e.fmt_debug(f)).finish()
  }
}

///|
fn dbg_args(f : @rfmt.Formatter, args : Array[CallArg]) -> Unit {
  let l = f.debug_list()
  for arg in args {
    l.entry(f => {
      match arg {
        Pos(e) => f.debug_tuple("Pos").field(f => e.fmt_debug(f)).finish()
        Kwarg(name, e) =>
          f
          .debug_tuple("Kwarg")
          .field(f => dbg_str(f, name))
          .field(f => e.fmt_debug(f))
          .finish()
        PosSplat(e) =>
          f.debug_tuple("PosSplat").field(f => e.fmt_debug(f)).finish()
        KwargSplat(e) =>
          f.debug_tuple("KwargSplat").field(f => e.fmt_debug(f)).finish()
      }
    })
    |> ignore
  }
  l.finish()
}

///|
fn dbg_span(f : @rfmt.Formatter, span : Span) -> Unit {
  f.write_str(span.to_string())
}

///|
fn dbg_macro(f : @rfmt.Formatter, m : MacroNode) -> Unit {
  f
  .debug_struct("Macro")
  .field("name", f => dbg_str(f, m.name))
  .field("args", f => dbg_exprs(f, m.args))
  .field("defaults", f => dbg_exprs(f, m.defaults))
  .field("body", f => dbg_stmts(f, m.body))
  .finish()
  dbg_span(f, m.span)
}

///|
fn dbg_call(f : @rfmt.Formatter, c : CallNode) -> Unit {
  f
  .debug_struct("Call")
  .field("expr", f => c.expr.fmt_debug(f))
  .field("args", f => dbg_args(f, c.args))
  .finish()
  dbg_span(f, c.span)
}

///|
fn Stmt::fmt_debug(self : Stmt, f : @rfmt.Formatter) -> Unit {
  match self {
    Template(n) => {
      f
      .debug_struct("Template")
      .field("children", f => dbg_stmts(f, n.children))
      .finish()
      dbg_span(f, n.span)
    }
    EmitExpr(n) => {
      f
      .debug_struct("EmitExpr")
      .field("expr", f => n.expr.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    EmitRaw(n) => {
      f.debug_struct("EmitRaw").field("raw", f => dbg_str(f, n.raw)).finish()
      dbg_span(f, n.span)
    }
    ForLoop(n) => {
      f
      .debug_struct("ForLoop")
      .field("target", f => n.target.fmt_debug(f))
      .field("iter", f => n.iter.fmt_debug(f))
      .field("filter_expr", f => dbg_opt_expr(f, n.filter_expr))
      .field("recursive", f => dbg_bool(f, n.recursive))
      .field("body", f => dbg_stmts(f, n.body))
      .field("else_body", f => dbg_stmts(f, n.else_body))
      .finish()
      dbg_span(f, n.span)
    }
    IfCond(n) => {
      f
      .debug_struct("IfCond")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("true_body", f => dbg_stmts(f, n.true_body))
      .field("false_body", f => dbg_stmts(f, n.false_body))
      .finish()
      dbg_span(f, n.span)
    }
    WithBlock(n) => {
      f
      .debug_struct("WithBlock")
      .field("assignments", f => {
        let l = f.debug_list()
        for pair in n.assignments {
          l.entry(f => {
            f
            .debug_tuple("")
            .field(f => pair.0.fmt_debug(f))
            .field(f => pair.1.fmt_debug(f))
            .finish()
          })
          |> ignore
        }
        l.finish()
      })
      .field("body", f => dbg_stmts(f, n.body))
      .finish()
      dbg_span(f, n.span)
    }
    Set(n) => {
      f
      .debug_struct("Set")
      .field("target", f => n.target.fmt_debug(f))
      .field("expr", f => n.expr.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    SetBlock(n) => {
      f
      .debug_struct("SetBlock")
      .field("target", f => n.target.fmt_debug(f))
      .field("filter", f => dbg_opt_expr(f, n.filter))
      .field("body", f => dbg_stmts(f, n.body))
      .finish()
      dbg_span(f, n.span)
    }
    AutoEscape(n) => {
      f
      .debug_struct("AutoEscape")
      .field("enabled", f => n.enabled.fmt_debug(f))
      .field("body", f => dbg_stmts(f, n.body))
      .finish()
      dbg_span(f, n.span)
    }
    FilterBlock(n) => {
      f
      .debug_struct("FilterBlock")
      .field("filter", f => n.filter.fmt_debug(f))
      .field("body", f => dbg_stmts(f, n.body))
      .finish()
      dbg_span(f, n.span)
    }
    Block(n) => {
      f
      .debug_struct("Block")
      .field("name", f => dbg_str(f, n.name))
      .field("required", f => dbg_bool(f, n.required))
      .field("body", f => dbg_stmts(f, n.body))
      .finish()
      dbg_span(f, n.span)
    }
    Import(n) => {
      f
      .debug_struct("Import")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("name", f => n.name.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    FromImport(n) => {
      f
      .debug_struct("FromImport")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("names", f => {
        let l = f.debug_list()
        for pair in n.names {
          l.entry(f => {
            f
            .debug_tuple("")
            .field(f => pair.0.fmt_debug(f))
            .field(f => dbg_opt_expr(f, pair.1))
            .finish()
          })
          |> ignore
        }
        l.finish()
      })
      .finish()
      dbg_span(f, n.span)
    }
    Extends(n) => {
      f.debug_struct("Extends").field("name", f => n.name.fmt_debug(f)).finish()
      dbg_span(f, n.span)
    }
    Include(n) => {
      f
      .debug_struct("Include")
      .field("name", f => n.name.fmt_debug(f))
      .field("ignore_missing", f => dbg_bool(f, n.ignore_missing))
      .finish()
      dbg_span(f, n.span)
    }
    Macro(n) => dbg_macro(f, n)
    CallBlock(n) => {
      f
      .debug_struct("CallBlock")
      .field("call", f => dbg_call(f, n.call))
      .field("macro_decl", f => dbg_macro(f, n.macro_decl))
      .finish()
      dbg_span(f, n.span)
    }
    Continue(span) => {
      f.write_str("Continue")
      dbg_span(f, span)
    }
    Break(span) => {
      f.write_str("Break")
      dbg_span(f, span)
    }
    Do(n) => {
      f.debug_struct("Do").field("call", f => dbg_call(f, n.call)).finish()
      dbg_span(f, n.span)
    }
  }
}

///|
fn UnaryOpKind::name(self : UnaryOpKind) -> String {
  match self {
    Not => "Not"
    Neg => "Neg"
  }
}

///|
fn BinOpKind::name(self : BinOpKind) -> String {
  match self {
    Eq => "Eq"
    Ne => "Ne"
    Lt => "Lt"
    Lte => "Lte"
    Gt => "Gt"
    Gte => "Gte"
    ScAnd => "ScAnd"
    ScOr => "ScOr"
    Add => "Add"
    Sub => "Sub"
    Mul => "Mul"
    Div => "Div"
    FloorDiv => "FloorDiv"
    Rem => "Rem"
    Pow => "Pow"
    Concat => "Concat"
    In => "In"
  }
}

///|
fn CompareOpKind::name(self : CompareOpKind) -> String {
  match self {
    Eq => "Eq"
    Ne => "Ne"
    Lt => "Lt"
    Lte => "Lte"
    Gt => "Gt"
    Gte => "Gte"
    In => "In"
    NotIn => "NotIn"
  }
}

///|
fn Expr::fmt_debug(self : Expr, f : @rfmt.Formatter) -> Unit {
  match self {
    Var(n) => {
      f.debug_struct("Var").field("id", f => dbg_str(f, n.id)).finish()
      dbg_span(f, n.span)
    }
    Const(n) => {
      f.debug_struct("Const").field("value", f => n.value.fmt_debug(f)).finish()
      dbg_span(f, n.span)
    }
    Slice(n) => {
      f
      .debug_struct("Slice")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("start", f => dbg_opt_expr(f, n.start))
      .field("stop", f => dbg_opt_expr(f, n.stop))
      .field("step", f => dbg_opt_expr(f, n.step))
      .finish()
      dbg_span(f, n.span)
    }
    UnaryOp(n) => {
      f
      .debug_struct("UnaryOp")
      .field("op", f => f.write_str(n.op.name()))
      .field("expr", f => n.expr.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    BinOp(n) => {
      f
      .debug_struct("BinOp")
      .field("op", f => f.write_str(n.op.name()))
      .field("left", f => n.left.fmt_debug(f))
      .field("right", f => n.right.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    Compare(n) => {
      f
      .debug_struct("Compare")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("ops", f => {
        let l = f.debug_list()
        for op in n.ops {
          l.entry(f => {
            f
            .debug_struct("CompareOp")
            .field("op", f => f.write_str(op.op.name()))
            .field("expr", f => op.expr.fmt_debug(f))
            .finish()
          })
          |> ignore
        }
        l.finish()
      })
      .finish()
      dbg_span(f, n.span)
    }
    IfExpr(n) => {
      f
      .debug_struct("IfExpr")
      .field("test_expr", f => n.test_expr.fmt_debug(f))
      .field("true_expr", f => n.true_expr.fmt_debug(f))
      .field("false_expr", f => dbg_opt_expr(f, n.false_expr))
      .finish()
      dbg_span(f, n.span)
    }
    Filter(n) => {
      f
      .debug_struct("Filter")
      .field("name", f => dbg_str(f, n.name))
      .field("expr", f => dbg_opt_expr(f, n.expr))
      .field("args", f => dbg_args(f, n.args))
      .finish()
      dbg_span(f, n.span)
    }
    Test(n) => {
      f
      .debug_struct("Test")
      .field("name", f => dbg_str(f, n.name))
      .field("expr", f => n.expr.fmt_debug(f))
      .field("args", f => dbg_args(f, n.args))
      .finish()
      dbg_span(f, n.span)
    }
    GetAttr(n) => {
      f
      .debug_struct("GetAttr")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("name", f => dbg_str(f, n.name))
      .finish()
      dbg_span(f, n.span)
    }
    GetItem(n) => {
      f
      .debug_struct("GetItem")
      .field("expr", f => n.expr.fmt_debug(f))
      .field("subscript_expr", f => n.subscript_expr.fmt_debug(f))
      .finish()
      dbg_span(f, n.span)
    }
    Call(n) => dbg_call(f, n)
    List(n) => {
      f.debug_struct("List").field("items", f => dbg_exprs(f, n.items)).finish()
      dbg_span(f, n.span)
    }
    Tuple(n) => {
      f
      .debug_struct("Tuple")
      .field("items", f => dbg_exprs(f, n.items))
      .finish()
      dbg_span(f, n.span)
    }
    Map(n) => {
      f
      .debug_struct("Map")
      .field("keys", f => dbg_exprs(f, n.keys))
      .field("values", f => dbg_exprs(f, n.values))
      .finish()
      dbg_span(f, n.span)
    }
  }
}
