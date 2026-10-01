///|
priv struct AssignmentTracker {
  out : Set[String]
  nested_out : Set[String]?
  assigned : Array[Set[String]]
}

///|
fn AssignmentTracker::is_assigned(
  self : AssignmentTracker,
  name : String,
) -> Bool {
  self.assigned.iter().any(x => x.contains(name))
}

///|
fn AssignmentTracker::assign(self : AssignmentTracker, name : String) -> Unit {
  self.assigned[self.assigned.length() - 1].add(name)
}

///|
fn AssignmentTracker::assign_nested(
  self : AssignmentTracker,
  name : String,
) -> Unit {
  if self.nested_out is Some(nested_out) {
    nested_out.add(name)
  }
}

///|
fn AssignmentTracker::push(self : AssignmentTracker) -> Unit {
  self.assigned.push(Set([]))
}

///|
fn AssignmentTracker::pop(self : AssignmentTracker) -> Unit {
  self.assigned.pop() |> ignore
}

///|
/// Finds all variables that need to be captured as closure for a macro.
fn find_macro_closure(m : MacroNode) -> Set[String] {
  let state = { out: Set([]), nested_out: None, assigned: [Set([])], }
  tracker_visit_macro(m, state, false)
  state.out
}

///|
/// Finds all variables that are undeclared in a template.
fn find_undeclared(t : Stmt, track_nested : Bool) -> Set[String] {
  let state = {
    out: Set([]),
    nested_out: if track_nested {
      Some(Set([]))
    } else {
      None
    },
    assigned: [Set([])],
  }
  track_walk(t, state)
  match state.nested_out {
    Some(nested) => nested
    None => state.out
  }
}

///|
fn tracker_visit_expr_opt(expr : Expr?, state : AssignmentTracker) -> Unit {
  if expr is Some(expr) {
    tracker_visit_expr(expr, state)
  }
}

///|
fn tracker_visit_macro(
  m : MacroNode,
  state : AssignmentTracker,
  declare_caller : Bool,
) -> Unit {
  if declare_caller {
    // this is not completely correct as caller is actually only defined if
    // the macro was used in the context of a call block.  However it is
    // impossible to determine this at compile time so we err on the side of
    // assuming caller is there.
    state.assign("caller")
  }
  for arg in m.args {
    track_assign(arg, state)
  }
  for expr in m.defaults {
    tracker_visit_expr(expr, state)
  }
  for node in m.body {
    track_walk(node, state)
  }
}

///|
fn tracker_visit_callarg(arg : CallArg, state : AssignmentTracker) -> Unit {
  match arg {
    Pos(expr) | Kwarg(_, expr) | PosSplat(expr) | KwargSplat(expr) =>
      tracker_visit_expr(expr, state)
  }
}

///|
fn tracker_visit_expr(expr : Expr, state : AssignmentTracker) -> Unit {
  match expr {
    Var(v) =>
      if !state.is_assigned(v.id) {
        state.out.add(v.id)
        // if we are not tracking nested assignments, we can consider a
        // variable to be assigned the first time we perform a lookup.
        if state.nested_out is None {
          state.assign(v.id)
        } else {
          state.assign_nested(v.id)
        }
      }
    Const(_) => ()
    UnaryOp(e) => tracker_visit_expr(e.expr, state)
    BinOp(e) => {
      tracker_visit_expr(e.left, state)
      tracker_visit_expr(e.right, state)
    }
    Compare(e) => {
      tracker_visit_expr(e.expr, state)
      for op in e.ops {
        tracker_visit_expr(op.expr, state)
      }
    }
    IfExpr(e) => {
      tracker_visit_expr(e.test_expr, state)
      tracker_visit_expr(e.true_expr, state)
      tracker_visit_expr_opt(e.false_expr, state)
    }
    Filter(e) => {
      tracker_visit_expr_opt(e.expr, state)
      for x in e.args {
        tracker_visit_callarg(x, state)
      }
    }
    Test(e) => {
      tracker_visit_expr(e.expr, state)
      for x in e.args {
        tracker_visit_callarg(x, state)
      }
    }
    GetAttr(e) => {
      // if we are tracking nested, we check if we have a chain of attribute
      // lookups that terminate in a variable lookup.  In that case we can
      // assign the nested lookup.
      if state.nested_out is Some(_) {
        let attrs = [e.name]
        let mut ptr = e.expr
        for ;; {
          match ptr {
            Var(v) => {
              if !state.is_assigned(v.id) {
                let rv = StringBuilder()
                rv.write_string(v.id)
                for i = attrs.length() - 1; i >= 0; i = i - 1 {
                  rv.write_char('.')
                  rv.write_string(attrs[i])
                }
                state.assign_nested(rv.to_string())
                return
              }
              break
            }
            GetAttr(inner) => {
              attrs.push(inner.name)
              ptr = inner.expr
            }
            _ => break
          }
        }
      }
      tracker_visit_expr(e.expr, state)
    }
    GetItem(e) => {
      tracker_visit_expr(e.expr, state)
      tracker_visit_expr(e.subscript_expr, state)
    }
    Slice(e) => {
      tracker_visit_expr_opt(e.start, state)
      tracker_visit_expr_opt(e.stop, state)
      tracker_visit_expr_opt(e.step, state)
    }
    Call(e) => {
      tracker_visit_expr(e.expr, state)
      for x in e.args {
        tracker_visit_callarg(x, state)
      }
    }
    List(e) =>
      for x in e.items {
        tracker_visit_expr(x, state)
      }
    Tuple(e) =>
      for x in e.items {
        tracker_visit_expr(x, state)
      }
    Map(e) =>
      for i, k in e.keys {
        tracker_visit_expr(k, state)
        tracker_visit_expr(e.values[i], state)
      }
  }
}

///|
fn track_assign(expr : Expr, state : AssignmentTracker) -> Unit {
  match expr {
    Var(v) => state.assign(v.id)
    List(l) =>
      for x in l.items {
        track_assign(x, state)
      }
    Tuple(t) =>
      for x in t.items {
        track_assign(x, state)
      }
    _ => ()
  }
}

///|
fn track_walk(node : Stmt, state : AssignmentTracker) -> Unit {
  match node {
    Template(stmt) => {
      state.assign("self")
      for x in stmt.children {
        track_walk(x, state)
      }
    }
    EmitExpr(e) => tracker_visit_expr(e.expr, state)
    EmitRaw(_) => ()
    ForLoop(stmt) => {
      state.push()
      state.assign("loop")
      tracker_visit_expr(stmt.iter, state)
      track_assign(stmt.target, state)
      tracker_visit_expr_opt(stmt.filter_expr, state)
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
      state.push()
      for x in stmt.else_body {
        track_walk(x, state)
      }
      state.pop()
    }
    IfCond(stmt) => {
      tracker_visit_expr(stmt.expr, state)
      state.push()
      for x in stmt.true_body {
        track_walk(x, state)
      }
      state.pop()
      state.push()
      for x in stmt.false_body {
        track_walk(x, state)
      }
      state.pop()
    }
    WithBlock(stmt) => {
      state.push()
      for pair in stmt.assignments {
        track_assign(pair.0, state)
        tracker_visit_expr(pair.1, state)
      }
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
    }
    Set(stmt) => {
      track_assign(stmt.target, state)
      tracker_visit_expr(stmt.expr, state)
    }
    AutoEscape(stmt) => {
      state.push()
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
    }
    FilterBlock(stmt) => {
      state.push()
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
    }
    SetBlock(stmt) => {
      track_assign(stmt.target, state)
      state.push()
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
    }
    Block(stmt) => {
      state.push()
      state.assign("super")
      for x in stmt.body {
        track_walk(x, state)
      }
      state.pop()
    }
    Extends(_) | Include(_) => ()
    Import(stmt) => track_assign(stmt.name, state)
    FromImport(stmt) =>
      for pair in stmt.names {
        match pair.1 {
          Some(alias_name) => track_assign(alias_name, state)
          None => track_assign(pair.0, state)
        }
      }
    Macro(stmt) => {
      state.assign(stmt.name)
      state.push()
      tracker_visit_macro(stmt, state, true)
      state.pop()
    }
    CallBlock(stmt) => {
      tracker_visit_expr(stmt.call.expr, state)
      for x in stmt.call.args {
        tracker_visit_callarg(x, state)
      }
      state.push()
      tracker_visit_macro(stmt.macro_decl, state, true)
      state.pop()
    }
    Continue(_) | Break(_) => ()
    Do(stmt) => {
      tracker_visit_expr(stmt.call.expr, state)
      for x in stmt.call.args {
        tracker_visit_callarg(x, state)
      }
    }
  }
}
