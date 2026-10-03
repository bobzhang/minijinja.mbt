///|
fn[T] replaced(xs : Array[T], i : Int, x : T) -> Array[T] {
  let rv = xs.copy()
  rv[i] = x
  rv
}

///|
fn[T] removed(xs : Array[T], i : Int) -> Array[T] {
  let rv = xs.copy()
  rv.remove(i) |> ignore
  rv
}

///|
fn[T] spliced(xs : Array[T], i : Int, ys : Array[T]) -> Array[T] {
  let rv = xs[:i].to_owned()
  rv.append(ys)
  rv.append(xs[i + 1:].to_owned())
  rv
}

///|
/// Smaller variants of each element of `xs`, one element at a time.
fn[T] shrink_each(xs : Array[T], f : (T) -> Array[T]) -> Array[Array[T]] {
  let rv = []
  for i, x in xs {
    for y in f(x) {
      rv.push(replaced(xs, i, y))
    }
  }
  rv
}

///|
fn shrink_exprs(xs : Array[Expr]) -> Array[Array[Expr]] {
  let rv = Array::makei(xs.length(), i => removed(xs, i))
  rv.append(shrink_each(xs, shrink_expr))
  rv
}

///|
fn shrink_kwargs(xs : Array[(String, Expr)]) -> Array[Array[(String, Expr)]] {
  let rv = Array::makei(xs.length(), i => removed(xs, i))
  rv.append(shrink_each(xs, kv => shrink_expr(kv.1).map(e => (kv.0, e))))
  rv
}

///|
fn shrink_string(s : String) -> Array[String] {
  if s.is_empty() {
    return []
  }
  let chars = s.iter().to_array()
  let rv = [""]
  if chars.length() > 1 {
    rv.push(String::from_array(chars[:chars.length() / 2].to_owned()))
    rv.push(String::from_array(chars[chars.length() / 2:].to_owned()))
    for i in 0..<chars.length() {
      rv.push(String::from_array(removed(chars, i)))
    }
  }
  rv
}

///|
fn opt_shrink(e : Expr?) -> Array[Expr?] {
  match e {
    None => []
    Some(e) => [None, ..shrink_expr(e).map(x => Some(x))]
  }
}

///|
fn shrink_expr(e : Expr) -> Array[Expr] {
  let rv : Array[Expr] = []
  // children first: they are the biggest simplification
  match e {
    Lit(s) =>
      if s != "0" && s != "1" {
        rv.push(Lit("1"))
        rv.push(Lit("0"))
      }
    Str(s) => rv.append(shrink_string(s).map(x => Expr::Str(x)))
    Var(_) => ()
    List(items) | Tuple(items) => {
      rv.append(items)
      for xs in shrink_exprs(items) {
        rv.push(if e is List(_) { List(xs) } else { Tuple(xs) })
      }
    }
    Dict(items) => {
      for kv in items {
        rv.push(kv.1)
      }
      for i in 0..<items.length() {
        rv.push(Dict(removed(items, i)))
      }
      for xs in shrink_each(items, kv => shrink_expr(kv.1).map(v => (kv.0, v))) {
        rv.push(Dict(xs))
      }
    }
    Paren(x) => {
      rv.push(x)
      rv.append(shrink_expr(x).map(y => Expr::Paren(y)))
    }
    Bin(op, a, b) => {
      rv.push(a)
      rv.push(b)
      rv.append(shrink_expr(a).map(x => Expr::Bin(op, x, b)))
      rv.append(shrink_expr(b).map(x => Expr::Bin(op, a, x)))
    }
    Unary(op, x) => {
      rv.push(x)
      rv.append(shrink_expr(x).map(y => Expr::Unary(op, y)))
    }
    Filter(x, name, args, kwargs) => {
      rv.push(x)
      rv.append(shrink_expr(x).map(y => Expr::Filter(y, name, args, kwargs)))
      for xs in shrink_exprs(args) {
        rv.push(Filter(x, name, xs, kwargs))
      }
      for kws in shrink_kwargs(kwargs) {
        rv.push(Filter(x, name, args, kws))
      }
    }
    Test(x, negated, name, args) => {
      rv.push(x)
      if negated {
        rv.push(Test(x, false, name, args))
      }
      rv.append(shrink_expr(x).map(y => Expr::Test(y, negated, name, args)))
      for xs in shrink_exprs(args) {
        rv.push(Test(x, negated, name, xs))
      }
    }
    Attr(x, name) => {
      rv.push(x)
      rv.append(shrink_expr(x).map(y => Expr::Attr(y, name)))
    }
    Item(x, idx) => {
      rv.push(x)
      rv.push(idx)
      rv.append(shrink_expr(x).map(y => Expr::Item(y, idx)))
      rv.append(shrink_expr(idx).map(y => Expr::Item(x, y)))
    }
    Slice(x, a, b, c) => {
      rv.push(x)
      rv.append(shrink_expr(x).map(y => Expr::Slice(y, a, b, c)))
      rv.append(opt_shrink(a).map(y => Expr::Slice(x, y, b, c)))
      rv.append(opt_shrink(b).map(y => Expr::Slice(x, a, y, c)))
      rv.append(opt_shrink(c).map(y => Expr::Slice(x, a, b, y)))
    }
    Call(f, args, kwargs) => {
      rv.append(args)
      for xs in shrink_exprs(args) {
        rv.push(Call(f, xs, kwargs))
      }
      for kws in shrink_kwargs(kwargs) {
        rv.push(Call(f, args, kws))
      }
      rv.append(shrink_expr(f).map(y => Expr::Call(y, args, kwargs)))
    }
    Cond(a, c, other) => {
      rv.push(a)
      rv.push(c)
      if other is Some(o) {
        rv.push(o)
        rv.push(Cond(a, c, None))
      }
      rv.append(shrink_expr(a).map(y => Expr::Cond(y, c, other)))
      rv.append(shrink_expr(c).map(y => Expr::Cond(a, y, other)))
      if other is Some(o) {
        rv.append(shrink_expr(o).map(y => Expr::Cond(a, c, Some(y))))
      }
    }
  }
  match e {
    Lit(_) | Str(_) | Var(_) => ()
    _ => {
      rv.push(Lit("1"))
      rv.push(Str("a"))
    }
  }
  rv
}

///|
fn shrink_ws(ws : Ws, f : (Ws) -> Stmt) -> Array[Stmt] {
  if ws.left == "" && ws.right == "" {
    []
  } else {
    [f(ws_none())]
  }
}

///|
/// The nested bodies of a statement (spliced in place when shrinking).
fn Stmt::children(self : Stmt) -> Array[Array[Stmt]] {
  match self {
    If(_, branches, else_body) =>
      branches.map(b => b.1)..append(else_body.map_or([], b => [b]))
    For(_, _, _, _, body, else_body) =>
      [body]..append(else_body.map_or([], b => [b]))
    SetBlock(_, _, body)
    | With(_, _, body)
    | FilterBlock(_, _, body)
    | Autoescape(_, _, body)
    | Macro(_, _, _, body)
    | CallBlock(_, _, _, body)
    | Block(_, _, body) => [body]
    _ => []
  }
}

///|
fn shrink_stmt(s : Stmt) -> Array[Stmt] {
  let rv : Array[Stmt] = []
  match s {
    Text(t) => rv.append(shrink_string(t).map(x => Stmt::Text(x)))
    Emit(ws, e) => {
      rv.append(shrink_ws(ws, ws => Emit(ws, e)))
      rv.append(shrink_expr(e).map(x => Stmt::Emit(ws, x)))
    }
    Comment(_) | Raw(_) | Break(_) | Continue(_) => ()
    If(ws, branches, else_body) => {
      rv.append(shrink_ws(ws, ws => If(ws, branches, else_body)))
      if else_body is Some(_) {
        rv.push(If(ws, branches, None))
      }
      if branches.length() > 1 {
        for i in 0..<branches.length() {
          rv.push(If(ws, removed(branches, i), else_body))
        }
      }
      for bs in shrink_each(branches, b => shrink_expr(b.0).map(c => (c, b.1))) {
        rv.push(If(ws, bs, else_body))
      }
      for
        bs in shrink_each(branches, b => {
          shrink_body(b.1).map(body => (b.0, body))
        }) {
        rv.push(If(ws, bs, else_body))
      }
      if else_body is Some(body) {
        for b in shrink_body(body) {
          rv.push(If(ws, branches, Some(b)))
        }
      }
    }
    For(ws, targets, iter, cond, body, else_body) => {
      rv.append(
        shrink_ws(ws, ws => For(ws, targets, iter, cond, body, else_body)),
      )
      if else_body is Some(_) {
        rv.push(For(ws, targets, iter, cond, body, None))
      }
      if cond is Some(_) {
        rv.push(For(ws, targets, iter, None, body, else_body))
      }
      rv.append(
        shrink_expr(iter).map(x => {
          Stmt::For(ws, targets, x, cond, body, else_body)
        }),
      )
      for b in shrink_body(body) {
        rv.push(For(ws, targets, iter, cond, b, else_body))
      }
    }
    Set(ws, targets, e) => {
      rv.append(shrink_ws(ws, ws => Set(ws, targets, e)))
      rv.append(shrink_expr(e).map(x => Stmt::Set(ws, targets, x)))
    }
    SetBlock(ws, name, body) =>
      for b in shrink_body(body) {
        rv.push(SetBlock(ws, name, b))
      }
    With(ws, assignments, body) => {
      for
        xs in shrink_each(assignments, a => shrink_expr(a.1).map(e => (a.0, e))) {
        rv.push(With(ws, xs, body))
      }
      for b in shrink_body(body) {
        rv.push(With(ws, assignments, b))
      }
    }
    FilterBlock(ws, name, body) =>
      for b in shrink_body(body) {
        rv.push(FilterBlock(ws, name, b))
      }
    Autoescape(ws, e, body) =>
      for b in shrink_body(body) {
        rv.push(Autoescape(ws, e, b))
      }
    Macro(ws, name, params, body) => {
      for i in 0..<params.length() {
        if params[i].1 is Some(_) {
          rv.push(
            Macro(ws, name, replaced(params, i, (params[i].0, None)), body),
          )
        }
      }
      for b in shrink_body(body) {
        rv.push(Macro(ws, name, params, b))
      }
    }
    CallBlock(ws, params, call, body) => {
      rv.append(
        shrink_expr(call).map(x => Stmt::CallBlock(ws, params, x, body)),
      )
      for b in shrink_body(body) {
        rv.push(CallBlock(ws, params, call, b))
      }
    }
    Do(ws, e) => rv.append(shrink_expr(e).map(x => Stmt::Do(ws, x)))
    Include(ws, e, ignore_missing, context) => {
      if ignore_missing {
        rv.push(Include(ws, e, false, context))
      }
      if context != "" {
        rv.push(Include(ws, e, ignore_missing, ""))
      }
      rv.append(
        shrink_expr(e).map(x => Stmt::Include(ws, x, ignore_missing, context)),
      )
    }
    Extends(ws, e) => rv.append(shrink_expr(e).map(x => Stmt::Extends(ws, x)))
    Block(ws, name, body) =>
      for b in shrink_body(body) {
        rv.push(Block(ws, name, b))
      }
    Import(_) => ()
    FromImport(ws, e, names) =>
      if names.length() > 1 {
        for i in 0..<names.length() {
          rv.push(FromImport(ws, e, removed(names, i)))
        }
      }
  }
  rv
}

///|
fn shrink_body(body : Array[Stmt]) -> Array[Array[Stmt]] {
  let rv = Array::makei(body.length(), i => removed(body, i))
  for i, s in body {
    for child in s.children() {
      rv.push(spliced(body, i, child))
    }
  }
  rv.append(shrink_each(body, shrink_stmt))
  rv
}

///|
fn shrink_json(v : JVal) -> Array[JVal] {
  match v {
    JArr(items) =>
      Array::makei(items.length(), i => JVal::JArr(removed(items, i)))..append(
        items,
      )
    JObj(items) =>
      Array::makei(items.length(), i => JVal::JObj(removed(items, i)))..append(
        items.map(kv => kv.1),
      )
    JStr(s) => shrink_string(s).map(x => JVal::JStr(x))
    JNull => []
    _ => [JNull]
  }
}

///|
impl @quickcheck.Shrink for Case with fn shrink(self) {
  let rv : Array[Case] = []
  for body in shrink_body(self.body) {
    rv.push({ ..self, body, })
  }
  for i in 0..<self.extra.length() {
    rv.push({ ..self, extra: removed(self.extra, i), })
  }
  for extra in shrink_each(self.extra, t => shrink_body(t.1).map(b => (t.0, b))) {
    rv.push({ ..self, extra, })
  }
  for i in 0..<self.ctx.length() {
    // the seed keeps contrib's random functions deterministic
    if self.ctx[i].0 != "RAND_SEED" {
      rv.push({ ..self, ctx: removed(self.ctx, i), })
    }
  }
  for ctx in shrink_each(self.ctx, kv => shrink_json(kv.1).map(v => (kv.0, v))) {
    rv.push({ ..self, ctx, })
  }
  if self.undefined != "lenient" {
    rv.push({ ..self, undefined: "lenient", })
  }
  if self.trim_blocks {
    rv.push({ ..self, trim_blocks: false, })
  }
  if self.lstrip_blocks {
    rv.push({ ..self, lstrip_blocks: false, })
  }
  if self.keep_trailing_newline {
    rv.push({ ..self, keep_trailing_newline: false, })
  }
  if self.contrib {
    rv.push({ ..self, contrib: false, })
  }
  if self.name != "t.txt" {
    rv.push({ ..self, name: "t.txt", })
  }
  rv.iter()
}
