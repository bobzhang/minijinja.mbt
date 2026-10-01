///|
fn finish_debug(c : CodeGenerator) -> String {
  let (instructions, blocks) = c.finish()
  let f = @rfmt.Formatter::new(alternate=true)
  f
  .debug_tuple("")
  .field(f => instructions.fmt_debug(f))
  .field(f => {
    let m = f.debug_map()
    for name, instr in blocks {
      m.entry(f => f.write_str(@rfmt.str_debug(name)), f => instr.fmt_debug(f))
      |> ignore
    }
    m.finish()
  })
  .finish()
  f.to_string()
}

///|
#cfg(any(target="native", target="wasm"))
async fn assert_compiler_snapshot(name : String, actual : String) -> Unit {
  let expected = normalize_snapshot(
    snapshot_body(read_text("testdata/snapshots/test_compiler__\{name}.snap")),
  )
  assert_eq(normalize_snapshot(actual), expected)
}

///|
#cfg(any(target="native", target="wasm"))
async test "compiler: for loop" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(Lookup("items")) |> ignore
  c.start_for_loop(true, false)
  c.add(Emit) |> ignore
  c.end_for_loop(false)
  c.add(EmitRaw("!")) |> ignore
  assert_compiler_snapshot("for_loop", finish_debug(c))
}

///|
#cfg(any(target="native", target="wasm"))
async test "compiler: if branches" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(Lookup("false")) |> ignore
  c.start_if()
  c.add(EmitRaw("nope1")) |> ignore
  c.start_else()
  c.add(Lookup("nil")) |> ignore
  c.start_if()
  c.add(EmitRaw("nope1")) |> ignore
  c.start_else()
  c.add(EmitRaw("yes")) |> ignore
  c.end_if()
  c.end_if()
  assert_compiler_snapshot("if_branches", finish_debug(c))
}

///|
#cfg(any(target="native", target="wasm"))
async test "compiler: bool ops" {
  let c = CodeGenerator::new("<unknown>", "")
  c.start_sc_bool()
  c.add(Lookup("first")) |> ignore
  c.sc_bool(true)
  c.add(Lookup("second")) |> ignore
  c.sc_bool(false)
  c.add(Lookup("third")) |> ignore
  c.end_sc_bool()
  assert_compiler_snapshot("bool_ops", finish_debug(c))
}

///|
#cfg(any(target="native", target="wasm"))
async test "compiler: const" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(LoadConst(Value::from_string("a"))) |> ignore
  c.add(LoadConst(Value::from_int(42))) |> ignore
  c.add(StringConcat) |> ignore
  assert_compiler_snapshot("const", finish_debug(c))
}

///|
test "compiler: referenced names on empty instructions" {
  let c = CodeGenerator::new("<unknown>", "")
  let (instructions, _) = c.finish()
  assert_true(instructions.get_referenced_names(0).is_empty())
}

///|
test "compiler: const folding" {
  let span = Span::default()
  fn c(v : Value) -> Expr {
    Const({ value: v, span: Span::default(), })
  }

  assert_eq(c(Value::from_int(42)).as_const(), Some(Value::from_int(42)))
  let list_expr = Expr::List({
    items: [c(Value::from_int(1)), c(Value::from_int(2))],
    span,
  })
  assert_eq(
    list_expr.as_const(),
    Some(Value::from_array([Value::from_int(1), Value::from_int(2)])),
  )
  let map_expr = Expr::Map({
    keys: [c(Value::from_string("a"))],
    values: [c(Value::from_int(1))],
    span,
  })
  assert_eq(
    map_expr.as_const(),
    Some(Value::from_pairs([("a", Value::from_int(1))])),
  )
  let binop_expr = Expr::BinOp({
    op: Add,
    left: c(Value::from_int(1)),
    right: c(Value::from_int(2)),
    span,
  })
  assert_eq(binop_expr.as_const(), Some(Value::from_int(3)))
  let unary_expr = Expr::UnaryOp({
    op: Not,
    expr: c(Value::from_bool(false)),
    span,
  })
  assert_eq(unary_expr.as_const(), Some(Value::from_bool(true)))
  let list_with_var = Expr::List({
    items: [c(Value::from_int(1)), Var({ id: "foo", span, })],
    span,
  })
  assert_eq(list_with_var.as_const(), None)
}
