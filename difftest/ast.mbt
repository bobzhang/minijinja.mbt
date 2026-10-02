///|
/// A generated template expression.  Rendering never adds parentheses on
/// its own (`Paren` does), so precedence handling is exercised as well.
enum Expr {
  /// A literal spelled exactly as in the template (`1`, `1.5e3`, `true`).
  Lit(String)
  Str(String)
  Var(String)
  List(Array[Expr])
  Tuple(Array[Expr])
  Dict(Array[(Expr, Expr)])
  Paren(Expr)
  Bin(String, Expr, Expr)
  Unary(String, Expr)
  Filter(Expr, String, Array[Expr], Array[(String, Expr)])
  Test(Expr, Bool, String, Array[Expr])
  Attr(Expr, String)
  Item(Expr, Expr)
  Slice(Expr, Expr?, Expr?, Expr?)
  Call(Expr, Array[Expr], Array[(String, Expr)])
  Cond(Expr, Expr, Expr?)
} derive(Debug)

///|
/// Whitespace control markers of a tag: `-`, `+` or nothing.
struct Ws {
  left : String
  right : String
} derive(Debug)

///|
enum Stmt {
  Text(String)
  Emit(Ws, Expr)
  Comment(String)
  Raw(String)
  If(Ws, Array[(Expr, Array[Stmt])], Array[Stmt]?)
  For(Ws, Array[String], Expr, Expr?, Array[Stmt], Array[Stmt]?)
  Set(Ws, Array[String], Expr)
  SetBlock(Ws, String, Array[Stmt])
  With(Ws, Array[(String, Expr)], Array[Stmt])
  FilterBlock(Ws, String, Array[Stmt])
  Autoescape(Ws, Expr, Array[Stmt])
  Macro(Ws, String, Array[(String, Expr?)], Array[Stmt])
  CallBlock(Ws, Array[String], Expr, Array[Stmt])
  Break(Ws)
  Continue(Ws)
  Do(Ws, Expr)
} derive(Debug)

///|
/// A JSON value of the render context.  Floats are kept as their literal
/// spelling so both engines parse exactly the same text.
enum JVal {
  JNull
  JBool(Bool)
  JNum(String)
  JStr(String)
  JArr(Array[JVal])
  JObj(Array[(String, JVal)])
} derive(Debug)

///|
struct Case {
  name : String
  body : Array[Stmt]
  ctx : Array[(String, JVal)]
  undefined : String
  trim_blocks : Bool
  lstrip_blocks : Bool
  keep_trailing_newline : Bool
} derive(Debug)

///|
fn quote_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('\'')
  for c in s {
    match c {
      '\\' => sb.write_string("\\\\")
      '\'' => sb.write_string("\\'")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      c => sb.write_char(c)
    }
  }
  sb.write_char('\'')
  sb.to_string()
}

///|
fn write_args(
  sb : StringBuilder,
  args : Array[Expr],
  kwargs : Array[(String, Expr)],
) -> Unit {
  sb.write_char('(')
  let mut first = true
  for a in args {
    if !first {
      sb.write_string(", ")
    }
    first = false
    a.write(sb)
  }
  for kw in kwargs {
    if !first {
      sb.write_string(", ")
    }
    first = false
    sb.write_string(kw.0)
    sb.write_char('=')
    kw.1.write(sb)
  }
  sb.write_char(')')
}

///|
fn Expr::write(self : Expr, sb : StringBuilder) -> Unit {
  match self {
    Lit(s) | Var(s) => sb.write_string(s)
    Str(s) => sb.write_string(quote_str(s))
    List(items) => {
      sb.write_char('[')
      for i, e in items {
        if i > 0 {
          sb.write_string(", ")
        }
        e.write(sb)
      }
      sb.write_char(']')
    }
    Tuple(items) => {
      sb.write_char('(')
      for i, e in items {
        if i > 0 {
          sb.write_string(", ")
        }
        e.write(sb)
      }
      if items.length() == 1 {
        sb.write_char(',')
      }
      sb.write_char(')')
    }
    Dict(items) => {
      sb.write_char('{')
      for i, kv in items {
        if i > 0 {
          sb.write_string(", ")
        }
        kv.0.write(sb)
        sb.write_string(": ")
        kv.1.write(sb)
      }
      sb.write_char('}')
    }
    Paren(e) => {
      sb.write_char('(')
      e.write(sb)
      sb.write_char(')')
    }
    Bin(op, a, b) => {
      a.write(sb)
      sb.write_string(" \{op} ")
      b.write(sb)
    }
    Unary(op, e) => {
      sb.write_string(op)
      if op == "not" {
        sb.write_char(' ')
      }
      e.write(sb)
    }
    Filter(e, name, args, kwargs) => {
      e.write(sb)
      sb.write_char('|')
      sb.write_string(name)
      if !args.is_empty() || !kwargs.is_empty() {
        write_args(sb, args, kwargs)
      }
    }
    Test(e, negated, name, args) => {
      e.write(sb)
      sb.write_string(if negated { " is not " } else { " is " })
      sb.write_string(name)
      if !args.is_empty() {
        write_args(sb, args, [])
      }
    }
    Attr(e, name) => {
      e.write(sb)
      sb.write_char('.')
      sb.write_string(name)
    }
    Item(e, idx) => {
      e.write(sb)
      sb.write_char('[')
      idx.write(sb)
      sb.write_char(']')
    }
    Slice(e, start, stop, step) => {
      e.write(sb)
      sb.write_char('[')
      if start is Some(x) {
        x.write(sb)
      }
      sb.write_char(':')
      if stop is Some(x) {
        x.write(sb)
      }
      if step is Some(x) {
        sb.write_char(':')
        x.write(sb)
      }
      sb.write_char(']')
    }
    Call(f, args, kwargs) => {
      f.write(sb)
      write_args(sb, args, kwargs)
    }
    Cond(a, cond, other) => {
      a.write(sb)
      sb.write_string(" if ")
      cond.write(sb)
      if other is Some(o) {
        sb.write_string(" else ")
        o.write(sb)
      }
    }
  }
}

///|
fn Expr::to_source(self : Expr) -> String {
  let sb = StringBuilder()
  self.write(sb)
  sb.to_string()
}

///|
fn ws_none() -> Ws {
  { left: "", right: "", }
}

///|
fn write_tag(sb : StringBuilder, ws : Ws, body : String) -> Unit {
  sb.write_string("{%\{ws.left} \{body} \{ws.right}%}")
}

///|
fn write_body(sb : StringBuilder, body : Array[Stmt]) -> Unit {
  for s in body {
    s.write(sb)
  }
}

///|
fn Stmt::write(self : Stmt, sb : StringBuilder) -> Unit {
  match self {
    Text(s) => sb.write_string(s)
    Emit(ws, e) =>
      sb.write_string("{{\{ws.left} \{e.to_source()} \{ws.right}}}")
    Comment(s) => sb.write_string("{# \{s} #}")
    Raw(s) => sb.write_string("{% raw %}\{s}{% endraw %}")
    If(ws, branches, else_body) =>
      for i, branch in branches {
        write_tag(
          sb,
          ws,
          (if i == 0 { "if " } else { "elif " }) + branch.0.to_source(),
        )
        write_body(sb, branch.1)
      } nobreak {
        if else_body is Some(body) {
          write_tag(sb, ws, "else")
          write_body(sb, body)
        }
        write_tag(sb, ws, "endif")
      }
    For(ws, targets, iter, cond, body, else_body) => {
      let head = StringBuilder()
      head.write_string("for \{targets.join(", ")} in \{iter.to_source()}")
      if cond is Some(c) {
        head.write_string(" if \{c.to_source()}")
      }
      write_tag(sb, ws, head.to_string())
      write_body(sb, body)
      if else_body is Some(body) {
        write_tag(sb, ws, "else")
        write_body(sb, body)
      }
      write_tag(sb, ws, "endfor")
    }
    Set(ws, targets, e) =>
      write_tag(sb, ws, "set \{targets.join(", ")} = \{e.to_source()}")
    SetBlock(ws, name, body) => {
      write_tag(sb, ws, "set \{name}")
      write_body(sb, body)
      write_tag(sb, ws, "endset")
    }
    With(ws, assignments, body) => {
      let parts = assignments.map(a => "\{a.0} = \{a.1.to_source()}")
      write_tag(sb, ws, "with \{parts.join(", ")}")
      write_body(sb, body)
      write_tag(sb, ws, "endwith")
    }
    FilterBlock(ws, name, body) => {
      write_tag(sb, ws, "filter \{name}")
      write_body(sb, body)
      write_tag(sb, ws, "endfilter")
    }
    Autoescape(ws, e, body) => {
      write_tag(sb, ws, "autoescape \{e.to_source()}")
      write_body(sb, body)
      write_tag(sb, ws, "endautoescape")
    }
    Macro(ws, name, params, body) => {
      let ps = params.map(p => {
        match p.1 {
          Some(d) => "\{p.0}=\{d.to_source()}"
          None => p.0
        }
      })
      write_tag(sb, ws, "macro \{name}(\{ps.join(", ")})")
      write_body(sb, body)
      write_tag(sb, ws, "endmacro")
    }
    CallBlock(ws, params, call, body) => {
      let head = if params.is_empty() {
        "call \{call.to_source()}"
      } else {
        "call(\{params.join(", ")}) \{call.to_source()}"
      }
      write_tag(sb, ws, head)
      write_body(sb, body)
      write_tag(sb, ws, "endcall")
    }
    Break(ws) => write_tag(sb, ws, "break")
    Continue(ws) => write_tag(sb, ws, "continue")
    Do(ws, e) => write_tag(sb, ws, "do \{e.to_source()}")
  }
}

///|
fn Case::source(self : Case) -> String {
  let sb = StringBuilder()
  write_body(sb, self.body)
  sb.to_string()
}

///|
fn JVal::write(self : JVal, sb : StringBuilder) -> Unit {
  match self {
    JNull => sb.write_string("null")
    JBool(b) => sb.write_string(if b { "true" } else { "false" })
    JNum(s) => sb.write_string(s)
    JStr(s) => sb.write_string(Json::string(s).stringify())
    JArr(items) => {
      sb.write_char('[')
      for i, x in items {
        if i > 0 {
          sb.write_char(',')
        }
        x.write(sb)
      }
      sb.write_char(']')
    }
    JObj(items) => {
      sb.write_char('{')
      for i, kv in items {
        if i > 0 {
          sb.write_char(',')
        }
        sb.write_string(Json::string(kv.0).stringify())
        sb.write_char(':')
        kv.1.write(sb)
      }
      sb.write_char('}')
    }
  }
}

///|
fn Case::ctx_json(self : Case) -> String {
  let sb = StringBuilder()
  JVal::JObj(self.ctx).write(sb)
  sb.to_string()
}
