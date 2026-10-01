// Ported from minijinja/tests/test_vm.rs.
//
// The Rust tests use the `unstable_machinery` feature (`CodeGenerator`,
// `Instruction`, `eval`).  Those are private in the MoonBit port, so this is
// a whitebox test.

///|
fn simple_eval(
  instructions : Instructions,
  ctx : Value,
) -> String raise TemplateError {
  let env = Environment::new()
  let empty_blocks : Map[String, Instructions] = Map([])
  let rv = StringBuilder()
  let output = Output::new(rv)
  vm_eval(env, instructions, ctx, empty_blocks, output, NoEscape) |> ignore
  rv.to_string()
}

///|
test "vm: loop" {
  let ctx = Value::from_pairs([
    ("items", Value::from_array(Array::makei(9, i => Value::from_int(i + 1)))),
  ])
  let c = CodeGenerator::new("<unknown>", "")
  c.add(Lookup("items")) |> ignore
  c.start_for_loop(false, false)
  c.add(Emit) |> ignore
  c.end_for_loop(false)
  c.add(EmitRaw("!")) |> ignore
  let output = simple_eval(c.finish().0, ctx)
  assert_eq(output, "123456789!")
}

///|
test "vm: if" {
  for item in [(true, "true"), (false, "false")] {
    let (val, expectation) = item
    let ctx = Value::from_pairs([("cond", Value::from_bool(val))])
    let c = CodeGenerator::new("<unknown>", "")
    c.add(Lookup("cond")) |> ignore
    c.start_if()
    c.add(EmitRaw("true")) |> ignore
    c.start_else()
    c.add(EmitRaw("false")) |> ignore
    c.end_if()
    let output = simple_eval(c.finish().0, ctx)
    assert_eq(output, expectation)
  }
}

///|
test "vm: if branches" {
  let ctx = Value::from_pairs([
    ("false", Value::from_bool(false)),
    ("nil", Value::none()),
  ])
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
  let output = simple_eval(c.finish().0, ctx)
  assert_eq(output, "yes")
}

///|
test "vm: basic" {
  let user = Value::from_pairs([("name", Value::from_string("Peter"))])
  let ctx = Value::from_pairs([
    ("user", user),
    ("a", Value::from_int(42)),
    ("b", Value::from_int(23)),
  ])
  let i = Instructions::new("", "")
  i.add(EmitRaw("Hello ")) |> ignore
  i.add(Lookup("user")) |> ignore
  i.add(GetAttr("name")) |> ignore
  i.add(Emit) |> ignore
  i.add(Lookup("a")) |> ignore
  i.add(Lookup("b")) |> ignore
  i.add(Add) |> ignore
  i.add(Neg) |> ignore
  i.add(Emit) |> ignore
  let output = simple_eval(i, ctx)
  assert_eq(output, "Hello Peter-65")
}

///|
test "vm: error info" {
  let c = CodeGenerator::new("hello.html", "")
  c.set_line(1)
  c.add(EmitRaw("<h1>Hello</h1>\n")) |> ignore
  c.set_line(2)
  c.add(Lookup("a_string")) |> ignore
  c.add(Lookup("an_int")) |> ignore
  c.add(Add) |> ignore
  let ctx = Value::from_pairs([
    ("a_string", Value::from_string("foo")),
    ("an_int", Value::from_int(42)),
  ])
  let err = try simple_eval(c.finish().0, ctx) catch {
    err => err
  } noraise {
    _ => fail("expected an error")
  }
  assert_eq(err.name(), Some("hello.html"))
  assert_eq(err.line(), Some(2))
}

///|
fn run_binop_instr(
  lhs : Value,
  rhs : Value,
  op : Instruction,
  file? : String = "<unknown>",
) -> String raise TemplateError {
  let c = CodeGenerator::new(file, "")
  c.add(LoadConst(lhs)) |> ignore
  c.add(LoadConst(rhs)) |> ignore
  c.add(op) |> ignore
  c.add(Emit) |> ignore
  simple_eval(c.finish().0, Value::none())
}

///|
test "vm: op eq" {
  assert_eq(
    run_binop_instr(
      Value::from_int(1),
      Value::from_int(1),
      Instruction::Eq,
      file="hello.html",
    ),
    "True",
  )
  assert_eq(
    run_binop_instr(
      Value::from_int(1),
      Value::from_int(2),
      Instruction::Eq,
      file="hello.html",
    ),
    "False",
  )
}

///|
test "vm: op ne" {
  assert_eq(
    run_binop_instr(
      Value::from_int(1),
      Value::from_string("foo"),
      Instruction::Ne,
    ),
    "True",
  )
  assert_eq(
    run_binop_instr(
      Value::from_string("foo"),
      Value::from_string("foo"),
      Instruction::Ne,
    ),
    "False",
  )
}

///|
test "vm: op lt" {
  assert_eq(
    run_binop_instr(Value::from_int(1), Value::from_int(2), Instruction::Lt),
    "True",
  )
  assert_eq(
    run_binop_instr(Value::from_int(2), Value::from_int(1), Instruction::Lt),
    "False",
  )
}

///|
test "vm: op gt" {
  assert_eq(
    run_binop_instr(Value::from_int(1), Value::from_int(2), Instruction::Gt),
    "False",
  )
  assert_eq(
    run_binop_instr(Value::from_int(2), Value::from_int(1), Instruction::Gt),
    "True",
  )
}

///|
test "vm: op lte" {
  assert_eq(
    run_binop_instr(Value::from_int(1), Value::from_int(1), Instruction::Lte),
    "True",
  )
  assert_eq(
    run_binop_instr(Value::from_int(2), Value::from_int(1), Instruction::Lte),
    "False",
  )
}

///|
test "vm: op gte" {
  assert_eq(
    run_binop_instr(Value::from_int(1), Value::from_int(2), Instruction::Gte),
    "False",
  )
  assert_eq(
    run_binop_instr(Value::from_int(1), Value::from_int(1), Instruction::Gte),
    "True",
  )
}

///|
test "vm: op not" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(LoadConst(Value::from_int(0))) |> ignore
  c.add(Not) |> ignore
  c.add(Emit) |> ignore
  let output = simple_eval(c.finish().0, Value::none())
  assert_eq(output, "True")
  let c = CodeGenerator::new("<unknown>", "")
  c.add(LoadConst(Value::from_bool(true))) |> ignore
  c.add(Not) |> ignore
  c.add(Emit) |> ignore
  let output = simple_eval(c.finish().0, Value::none())
  assert_eq(output, "False")
}

///|
test "vm: string concat" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(LoadConst(Value::from_string("foo"))) |> ignore
  c.add(LoadConst(Value::from_int(42))) |> ignore
  c.add(StringConcat) |> ignore
  c.add(Emit) |> ignore
  let output = simple_eval(c.finish().0, Value::none())
  assert_eq(output, "foo42")
}

///|
test "vm: unpacking" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(
    LoadConst(
      Value::from_array([Value::from_string("bar"), Value::from_string("foo")]),
    ),
  )
  |> ignore
  c.add(UnpackList(2)) |> ignore
  c.add(StringConcat) |> ignore
  c.add(Emit) |> ignore
  let output = simple_eval(c.finish().0, Value::none())
  assert_eq(output, "foobar")
}

///|
test "vm: call object" {
  let c = CodeGenerator::new("<unknown>", "")
  c.add(
    LoadConst(
      Value::from_function("f", (state, args) => {
        let a = Args::new(state, args)
        let v = a.i64()
        a.finish()
        Value::from_int64(42L + v)
      }),
    ),
  )
  |> ignore
  c.add(LoadConst(Value::from_int(23))) |> ignore
  c.add(CallObject(Some(2))) |> ignore
  c.add(Emit) |> ignore
  let output = simple_eval(c.finish().0, Value::none())
  assert_eq(output, "65")
}

///|
test "vm: deep recursion" {
  // Upstream is gated on the `stacker` feature (stack growth) and uses a
  // limit of 10000.  Without `stacker` the recursion limit is capped at 500
  // (as in Rust), so the depth is scaled down to fit under that cap.
  let env = Environment::new()
  let limit = 70
  env.set_recursion_limit(limit * 7)
  let tmpl = env.template_from_str(
    (
      #|
      #|        {%- macro foo(i) -%}
      #|            {%- if i < limit %}{{ i }}|{{ foo(i + 1) }}{%- endif -%}
      #|        {%- endmacro -%}
      #|        {{- foo(0) -}}
      #|
    ),
  )
  let rv = tmpl.render(Value::from_pairs([("limit", Value::from_int(limit))]))
  let pieces : Array[Int] = []
  for x in rv.split("|") {
    try @string.parse_int(x) catch {
      _ => ()
    } noraise {
      n => pieces.push(n)
    }
  }
  assert_eq(pieces, Array::makei(limit, i => i))
}
