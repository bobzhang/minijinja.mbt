///|
/// Generator state: randomness, a node budget and the names in scope.
priv struct G {
  rs : @splitmix.RandomState
  mut budget : Int
  mut vars : Array[String]
  macros : Array[String]
  mut loop_depth : Int
  mut in_macro : Bool
  mut counter : Int
}

///|
fn G::pick(self : G, n : Int) -> Int {
  self.rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn G::chance(self : G, pct : Int) -> Bool {
  self.pick(100) < pct
}

///|
fn[T] G::choose(self : G, xs : Array[T]) -> T {
  xs[self.pick(xs.length())]
}

///|
/// Picks an index according to the weights.
fn G::weighted(self : G, weights : Array[Int]) -> Int {
  let total = weights.fold(init=0, (a, b) => a + b)
  let mut r = self.pick(total)
  for i, w in weights {
    if r < w {
      return i
    }
    r -= w
  }
  weights.length() - 1
}

///|
fn G::fresh(self : G, prefix : String) -> String {
  self.counter += 1
  "\{prefix}\{self.counter}"
}

///|
let small_ints : Array[String] = [
  "0", "1", "2", "3", "-1", "4", "5", "7", "10", "42", "-3", "100",
]

///|
let edge_ints : Array[String] = [
  "9223372036854775807", "9223372036854775808", "-9223372036854775808", "18446744073709551615",
  "18446744073709551616", "170141183460469231731687303715884105727", "170141183460469231731687303715884105728",
  "340282366920938463463374607431768211455", "340282366920938463463374607431768211456",
  "1_000", "0b101", "0o17", "0x1F", "0xff", "007", "4294967296", "-2147483649",
]

///|
let float_lits : Array[String] = [
  "0.5", "1.5", "-2.5", "1.0", "0.1", "3.14", "1e3", "1e-3", "2.5e10", "1e308", "1e400",
  "1E2", "0.0", "-0.0", "100.0", "1.5e-7", "123456789.123", "2.675", "0.125", "1e16",
  "1e21", "1e-7", "9007199254740993.0", "1.7976931348623157e308",
]

///|
let string_pool : Array[String] = [
  "", "a", "foo", "bar", "Hello World", "hello world foo", "  pad  ", "a,b,c", "<b>bold</b>",
  "&amp;", "ǅungla", "ΣΑΣ", "ὈΔΥΣΣΕΎΣ", "straße", "İstanbul", "ﬁre",
  "x\ny\nz", "%s and %d", "{} {}", "{0}-{1}", "1,2", "42", "3.5", "-7", " 12 ", "0x1A",
  "true", "None", "😀 emoji", "中文字符", "e\u{301}", "tab\there", "it's",
  "say \"hi\"", "back\\slash", "a-b_c d", "UPPER lower", "mIxEd CaSe", "line1\r\nline2",
  "   ", "\n", "%", "%5.2f", "%-5s|", "%x", "%r", "%(a)s",
  // numeric edge cases for the int / float filters
   "1e", ".", ".5", "5.", "+1", "-0", "1_0", "0x10", "1e5", " 1", "1 ", "inf", "-inf",
  "NaN", "nan", "-nan", "infinity", "+inf", "1.5e+3", "e5", "1e+", "--1", "1..2",
  "١٢", "99999999999999999999999999999999999999999", "-170141183460469231731687303715884105729",
  "1e400", "-1e-400", "0.1e1", "+.5", "-.e1", "12abc", "0b11", "0o7", "2.5E-3", "INF",
]

///|
let string_chars : Array[Char] = [
  'a', 'b', 'z', 'A', 'Z', ' ', '<', '>', '&', '"', '\'', '\\', '\n', '\t', 'é',
  'ß', 'İ', 'ı', 'ǅ', 'Σ', 'ς', '😀', '中', '\u{301}', 'ﬁ', '%', '{',
  '}', '#', '-', '0', '9', '.', ',', '_', 'ŉ', 'ǰ', 'ﬀ', 'Ω', 'ω',
]

///|
let attr_names : Array[String] = [
  "a", "name", "age", "length", "0", "items", "x", "upper", "real", "first", "values",
  "keys", "foo", "s", "index", "length",
]

///|
let filter_names : Array[String] = [
  "safe", "escape", "e", "lower", "upper", "title", "capitalize", "replace", "length",
  "count", "dictsort", "items", "reverse", "trim", "join", "split", "lines", "default",
  "d", "round", "abs", "int", "float", "attr", "first", "last", "min", "max", "sort",
  "list", "string", "bool", "batch", "slice", "sum", "indent", "select", "reject",
  "selectattr", "rejectattr", "map", "groupby", "unique", "chain", "zip", "pprint",
  "format", "tojson", "urlencode",
]

///|
let test_names : Array[String] = [
  "undefined", "defined", "none", "safe", "escaped", "boolean", "odd", "even", "divisibleby",
  "number", "integer", "int", "float", "string", "sequence", "iterable", "mapping",
  "startingwith", "endingwith", "lower", "upper", "in", "true", "false", "filter",
  "test", "eq", "ne", "lt", "gt", "le", "ge", "equalto", "sameas",
]

///|
let bin_ops : Array[String] = [
  "+", "-", "*", "/", "//", "%", "**", "~", "==", "!=", "<", "<=", ">", ">=", "and",
  "or", "in", "not in",
]

///|
let context_names : Array[String] = [
  "a", "b", "s", "items", "words", "d", "users", "flag", "nothing", "html", "big",
  "nested",
]

///|
fn G::gen_string(self : G) -> String {
  if self.chance(60) {
    self.choose(string_pool)
  } else {
    let sb = StringBuilder()
    for _ in 0..<self.pick(7) {
      sb.write_char(self.choose(string_chars))
    }
    sb.to_string()
  }
}

///|
fn G::gen_number(self : G) -> String {
  match self.weighted([70, 10, 20]) {
    0 => self.choose(small_ints)
    1 => self.choose(edge_ints)
    _ => self.choose(float_lits)
  }
}

///|
fn G::gen_var(self : G) -> Expr {
  if self.chance(4) {
    Var(self.choose(["undefined_thing", "missing", "x_y"]))
  } else if !self.vars.is_empty() && self.chance(60) {
    Var(self.choose(self.vars))
  } else {
    Var(self.choose(context_names))
  }
}

///|
fn G::gen_atom(self : G) -> Expr {
  match self.weighted([30, 25, 35, 6, 4]) {
    0 => Lit(self.gen_number())
    1 => Str(self.gen_string())
    2 => self.gen_var()
    3 => Lit(self.choose(["true", "false", "none", "True", "False", "None"]))
    _ =>
      List(
        Array::makei(self.pick(4), _ => {
          if self.chance(50) {
            Lit(self.choose(small_ints))
          } else {
            Str(self.choose(string_pool))
          }
        }),
      )
  }
}

///|
fn G::gen_exprs(self : G, n : Int, depth : Int) -> Array[Expr] {
  Array::makei(n, _ => self.gen_expr(depth))
}

///|
fn G::small_arg(self : G) -> Expr {
  match self.weighted([50, 30, 20]) {
    0 => Lit(self.choose(small_ints))
    1 => Str(self.choose(attr_names))
    _ => self.gen_atom()
  }
}

///|
/// `f()` with the given probability, else nothing.
fn[T] G::maybe(self : G, pct : Int, f : () -> Array[T]) -> Array[T] {
  if self.chance(pct) {
    f()
  } else {
    []
  }
}

///|
fn[T] cat(parts : Array[Array[T]]) -> Array[T] {
  let rv = []
  for p in parts {
    rv.append(p)
  }
  rv
}

///|
/// Arguments for a filter: mostly plausible ones, sometimes random.
fn G::filter_args(
  self : G,
  name : String,
  depth : Int,
) -> (Array[Expr], Array[(String, Expr)]) {
  if self.chance(15) {
    return (self.gen_exprs(self.pick(3), depth - 1), [])
  }
  let bool_lit = () => Expr::Lit(self.choose(["true", "false"]))
  let attr = () => {
    Expr::Str(
      self.choose(["name", "age", "a", "0", "1", "missing", "name.0", "x.y"]),
    )
  }
  let lit = (xs : Array[String]) => Expr::Lit(self.choose(xs))
  let str = (xs : Array[String]) => Expr::Str(self.choose(xs))
  match name {
    "replace" =>
      (
        cat([
          [str(["a", "o", "", "l", "Σ"]), Str(self.gen_string())],
          self.maybe(30, () => [lit(small_ints)]),
        ]),
        [],
      )
    "join" =>
      (
        self.maybe(70, () => [str([", ", "-", "", "<br>"])]),
        self.maybe(20, () => [("attribute", attr())]),
      )
    "split" | "trim" =>
      (
        cat([
          self.maybe(50, () => [str([" ", ",", "a", "", "  ", "ll"])]),
          if name == "split" {
            self.maybe(30, () => [lit(["0", "1", "2", "-1"])])
          } else {
            []
          },
        ]),
        [],
      )
    "default" | "d" =>
      (
        cat([
          self.maybe(80, () => [self.gen_atom()]),
          self.maybe(30, () => [bool_lit()]),
        ]),
        [],
      )
    "round" =>
      (
        self.maybe(50, () => [lit(["0", "1", "2", "3", "-1", "20"])]),
        self.maybe(30, () => {
          [("method", str(["common", "ceil", "floor", "bad"]))]
        }),
      )
    "int" | "float" =>
      (
        self.maybe(30, () => [self.gen_atom()]),
        if name == "int" {
          self.maybe(20, () => [("base", lit(["2", "8", "16", "36", "1"]))])
        } else {
          []
        },
      )
    "attr" => ([attr()], [])
    "dictsort" =>
      (
        [],
        Array::makei(self.pick(3), i => {
          match i {
            0 => ("case_sensitive", bool_lit())
            1 => ("by", str(["key", "value", "bad"]))
            _ => ("reverse", bool_lit())
          }
        }),
      )
    "sort" | "unique" | "min" | "max" =>
      (
        [],
        Array::makei(self.pick(3), i => {
          match i {
            0 => ("attribute", attr())
            1 => ("case_sensitive", bool_lit())
            _ => ("reverse", bool_lit())
          }
        }),
      )
    "batch" | "slice" =>
      (
        cat([
          [lit(["1", "2", "3", "0", "-1"])],
          self.maybe(30, () => [Expr::Str("x")]),
        ]),
        [],
      )
    "sum" =>
      (
        [],
        cat([
          self.maybe(40, () => [("attribute", attr())]),
          self.maybe(20, () => [("start", lit(["1", "1.5", "-2"]))]),
        ]),
      )
    "indent" =>
      (
        [lit(["2", "4", "0"]), Expr::Str("> ")][:self.pick(2) + 1].to_owned(),
        self.maybe(40, () => [(self.choose(["first", "blank"]), bool_lit())]),
      )
    "select" | "reject" =>
      (
        self.maybe(80, () => {
          cat([
            [
              str([
                "odd", "even", "none", "defined", "string", "number", "divisibleby",
                "bogus",
              ]),
            ],
            self.maybe(30, () => [lit(["2", "3"])]),
          ])
        }),
        [],
      )
    "selectattr" | "rejectattr" =>
      (
        cat([
          [attr()],
          self.maybe(60, () => {
            [str(["odd", "even", "none", "defined", "eq", "gt", "string"])]
          }),
          self.maybe(30, () => [self.small_arg()]),
        ]),
        [],
      )
    "map" =>
      if self.chance(50) {
        (
          [],
          cat([
            [("attribute", attr())],
            self.maybe(30, () => [("default", self.gen_atom())]),
          ]),
        )
      } else {
        ([str(["upper", "int", "string", "length", "abs", "bogus"])], [])
      }
    "groupby" =>
      (
        self.maybe(70, () => [attr()]),
        self.maybe(30, () => {
          [
            (
              self.choose(["default", "case_sensitive", "attribute"]),
              self.gen_atom(),
            ),
          ]
        }),
      )
    "chain" | "zip" | "format" => (self.gen_exprs(self.pick(3), depth - 1), [])
    "tojson" =>
      ([], self.maybe(30, () => [("indent", lit(["2", "0", "true"]))]))
    _ => ([], [])
  }
}

///|
fn G::test_args(self : G, name : String) -> Array[Expr] {
  match name {
    "divisibleby" => [Lit(self.choose(["2", "3", "0", "1.5", "-2"]))]
    "startingwith" | "endingwith" =>
      [Str(self.choose(["a", "H", "", "foo", "Σ", "é"]))]
    "in" => [self.gen_atom()]
    "filter" | "test" =>
      [Str(self.choose(["upper", "odd", "bogus", "default"]))]
    "eq" | "ne" | "lt" | "gt" | "le" | "ge" | "equalto" | "sameas" =>
      [self.gen_atom()]
    _ => []
  }
}

///|
fn G::gen_call(self : G, depth : Int) -> Expr {
  let choices = [30, 10, 10, 5, 0, 0, 6]
  if self.loop_depth > 0 {
    choices[4] = 10
  }
  if !self.macros.is_empty() {
    choices[5] = 25
  }
  match self.weighted(choices) {
    0 =>
      Call(
        Var("range"),
        Array::makei(self.pick(3) + 1, _ => {
          Lit(self.choose(["0", "1", "2", "3", "5", "-1", "-2", "10", "1.5"]))
        }),
        [],
      )
    1 =>
      Call(
        Var("dict"),
        if self.chance(30) {
          [self.gen_atom()]
        } else {
          []
        },
        Array::makei(self.pick(3), i => {
          (["a", "b", "c"][i], self.gen_expr(depth - 1))
        }),
      )
    2 =>
      Call(
        Var("namespace"),
        [],
        Array::makei(self.pick(3), i => (["a", "b", "c"][i], self.gen_atom())),
      )
    3 =>
      Call(
        Attr(self.gen_var(), self.choose(["items", "upper", "keys", "bogus"])),
        [],
        [],
      )
    4 =>
      match self.pick(3) {
        0 =>
          Call(
            Attr(Var("loop"), "cycle"),
            self.gen_exprs(self.pick(3) + 1, 0),
            [],
          )
        1 => Call(Attr(Var("loop"), "changed"), [self.gen_var()], [])
        _ => Call(Var("loop"), [self.gen_var()], [])
      }
    5 => {
      let args = self.gen_exprs(self.pick(3), depth - 1)
      Call(
        Var(self.choose(self.macros)),
        args,
        if self.chance(20) {
          [(self.choose(["p0", "p1", "x"]), self.gen_atom())]
        } else {
          []
        },
      )
    }
    _ => Call(Var(self.choose(["caller", "nope", "debug_missing"])), [], [])
  }
}

///|
fn G::gen_expr(self : G, depth : Int) -> Expr {
  self.budget -= 1
  if depth <= 0 || self.budget <= 0 {
    return self.gen_atom()
  }
  match self.weighted([25, 14, 4, 16, 6, 6, 5, 3, 7, 4, 5, 5]) {
    0 => self.gen_atom()
    1 =>
      Bin(
        self.choose(bin_ops),
        self.gen_expr(depth - 1),
        self.gen_expr(depth - 1),
      )
    2 => Unary(self.choose(["not", "not", "-"]), self.gen_expr(depth - 1))
    3 => {
      let name = if self.chance(97) {
        self.choose(filter_names)
      } else {
        "nonexistent"
      }
      let (args, kwargs) = self.filter_args(name, depth)
      Filter(self.gen_expr(depth - 1), name, args, kwargs)
    }
    4 => {
      let name = self.choose(test_names)
      Test(
        self.gen_expr(depth - 1),
        self.chance(30),
        name,
        self.test_args(name),
      )
    }
    5 => {
      let name = if self.loop_depth > 0 && self.chance(50) {
        return Attr(
          Var("loop"),
          self.choose([
            "index", "index0", "first", "last", "length", "revindex", "revindex0",
            "previtem", "nextitem", "depth", "depth0",
          ]),
        )
      } else {
        self.choose(attr_names)
      }
      Attr(self.gen_expr(depth - 1), name)
    }
    6 => {
      let idx = match self.pick(4) {
        0 => Lit(self.choose(["0", "1", "-1", "2", "10", "-10"]))
        1 => Str(self.choose(attr_names))
        _ => self.gen_expr(depth - 1)
      }
      Item(self.gen_expr(depth - 1), idx)
    }
    7 => {
      let part = () => {
        if self.chance(50) {
          Some(
            Lit(self.choose(["0", "1", "-1", "2", "-2", "10", "-10", "none"])),
          )
        } else {
          None
        }
      }
      Slice(self.gen_expr(depth - 1), part(), part(), part())
    }
    8 => self.gen_call(depth)
    9 =>
      Cond(
        self.gen_expr(depth - 1),
        self.gen_expr(depth - 1),
        if self.chance(70) {
          Some(self.gen_expr(depth - 1))
        } else {
          None
        },
      )
    10 =>
      match self.pick(3) {
        0 => List(self.gen_exprs(self.pick(4), depth - 1))
        1 => Tuple(self.gen_exprs(self.pick(3) + 1, depth - 1))
        _ =>
          Dict(
            Array::makei(self.pick(4), _ => {
              (
                if self.chance(80) {
                  Str(self.choose(["a", "b", "c", "name", "1"]))
                } else {
                  self.gen_atom()
                },
                self.gen_expr(depth - 1),
              )
            }),
          )
      }
    _ => Paren(self.gen_expr(depth - 1))
  }
}

///|
fn G::gen_ws(self : G) -> Ws {
  let marker = () => {
    match self.weighted([80, 15, 5]) {
      0 => ""
      1 => "-"
      _ => "+"
    }
  }
  { left: marker(), right: marker(), }
}

///|
let text_pool : Array[String] = [
  "", " ", "\n", "  \n", "x", "Hello ", "\n\n", "\t", "a b", "<p>", "&", "}", " {",
  "# ", "% ", "  ", "\n  ", "text\n", " - ", "é", "\r\n", "x\n", " \n ", "<b>",
]

///|
fn G::with_scope(
  self : G,
  names : Array[String],
  f : () -> Array[Stmt],
) -> Array[Stmt] {
  let old = self.vars
  self.vars = old.copy()..append(names)
  let rv = f()
  self.vars = old
  rv
}

///|
fn G::gen_body(self : G, depth : Int) -> Array[Stmt] {
  let n = if self.budget <= 0 { 1 } else { self.pick(4) + 1 }
  Array::makei(n, _ => self.gen_stmt(depth))
}

///|
fn G::gen_stmt(self : G, depth : Int) -> Stmt {
  self.budget -= 1
  let weights = [18, 32, 8, 10, 8, 3, 3, 3, 2, 4, 2, 2, 1, 0, 2]
  if depth <= 0 || self.budget <= 0 {
    for i in 2..<weights.length() {
      if i != 4 && i != 12 && i != 14 {
        weights[i] = 0
      }
    }
  }
  if self.loop_depth > 0 {
    weights[13] = 3
  }
  if self.macros.is_empty() {
    weights[10] = 0
  }
  let ws = self.gen_ws()
  match self.weighted(weights) {
    0 => Text(self.choose(text_pool))
    1 => {
      // `+` is only valid on block tags (`{%+`), not on variable blocks
      let ws : Ws = {
        left: ws.left.replace_all(old="+", new=""),
        right: ws.right.replace_all(old="+", new=""),
      }
      Emit(ws, self.gen_expr(3))
    }
    2 => {
      let branches = Array::makei(self.pick(2) + 1, _ => {
        (self.gen_expr(2), self.gen_body(depth - 1))
      })
      If(
        ws,
        branches,
        if self.chance(40) {
          Some(self.gen_body(depth - 1))
        } else {
          None
        },
      )
    }
    3 => {
      let targets = if self.chance(25) {
        [self.fresh("k"), self.fresh("v")]
      } else {
        [self.fresh("x")]
      }
      let iter = match self.pick(5) {
        0 =>
          Call(Var("range"), [Lit(self.choose(["0", "1", "2", "3", "4"]))], [])
        1 => Filter(self.gen_var(), "items", [], [])
        _ => self.gen_expr(2)
      }
      let cond = if self.chance(15) { Some(self.gen_expr(1)) } else { None }
      self.loop_depth += 1
      let body = self.with_scope(targets, () => self.gen_body(depth - 1))
      self.loop_depth -= 1
      let else_body = if self.chance(20) {
        Some(self.gen_body(depth - 1))
      } else {
        None
      }
      For(ws, targets, iter, cond, body, else_body)
    }
    4 => {
      let targets = if self.chance(15) {
        [self.fresh("u"), self.fresh("w")]
      } else if self.chance(15) && !self.vars.is_empty() {
        [self.choose(self.vars)]
      } else {
        [self.fresh("v")]
      }
      let e = self.gen_expr(3)
      self.vars.append(targets)
      Set(ws, targets, e)
    }
    5 => {
      let name = self.fresh("v")
      let body = self.gen_body(depth - 1)
      self.vars.push(name)
      SetBlock(ws, name, body)
    }
    6 => {
      let names = Array::makei(self.pick(2) + 1, _ => self.fresh("w"))
      let assignments = names.map(n => (n, self.gen_expr(2)))
      With(
        ws,
        assignments,
        self.with_scope(names, () => self.gen_body(depth - 1)),
      )
    }
    7 =>
      FilterBlock(
        ws,
        self.choose([
          "upper", "lower", "trim", "title", "e", "safe", "indent(2)", "replace('a', 'b')",
          "capitalize", "nonexistent",
        ]),
        self.gen_body(depth - 1),
      )
    8 =>
      Autoescape(
        ws,
        Lit(
          self.choose(["true", "false", "'html'", "'json'", "'none'", "'bogus'"]),
        ),
        self.gen_body(depth - 1),
      )
    9 => {
      let name = self.fresh("m")
      let params = Array::makei(self.pick(3), i => {
        (
          "p\{i}",
          if i > 0 && self.chance(40) {
            Some(self.gen_atom())
          } else {
            None
          },
        )
      })
      let old_loop = self.loop_depth
      let old_in_macro = self.in_macro
      self.loop_depth = 0
      self.in_macro = true
      let body = self.with_scope(
        params.map(p => p.0)..append(["varargs", "kwargs", "caller"]),
        () => self.gen_body(depth - 1),
      )
      self.loop_depth = old_loop
      self.in_macro = old_in_macro
      self.macros.push(name)
      Macro(ws, name, params, body)
    }
    10 => {
      let params = if self.chance(30) { ["y"] } else { [] }
      let call = Call(
        Var(self.choose(self.macros)),
        self.gen_exprs(self.pick(2), 1),
        [],
      )
      CallBlock(
        ws,
        params,
        call,
        self.with_scope(params, () => self.gen_body(depth - 1)),
      )
    }
    11 => Comment(self.choose(["c", "", "{{ x }}", "multi\nline"]))
    12 => Raw(self.choose(["{{ x }}", "{% if %}", "plain", ""]))
    13 => if self.chance(50) { Break(ws) } else { Continue(ws) }
    _ => Do(ws, self.gen_call(2))
  }
}

///|
fn G::gen_json(self : G, depth : Int) -> JVal {
  match
    self.weighted([
      25,
      15,
      25,
      6,
      4,
      if depth > 0 {
        12
      } else {
        0
      },
      if depth > 0 {
        10
      } else {
        0
      },
    ]) {
    0 => JNum(self.choose(small_ints))
    1 =>
      JNum(
        self.choose([
          "0.5", "1.5", "-2.25", "100.125", "3.0", "1e3", "2.5e-3", "9223372036854775807",
          "18446744073709551615", "-9223372036854775808",
        ]),
      )
    2 => JStr(self.gen_string())
    3 => JBool(self.chance(50))
    4 => JNull
    5 => JArr(Array::makei(self.pick(4), _ => self.gen_json(depth - 1)))
    _ =>
      JObj(
        Array::makei(self.pick(4), i => {
          (["name", "age", "a", "b"][i], self.gen_json(depth - 1))
        }),
      )
  }
}

///|
fn G::gen_context(self : G) -> Array[(String, JVal)] {
  let rv = []
  for name in context_names {
    if self.chance(15) {
      continue
    }
    let value : JVal = if self.chance(25) {
      self.gen_json(2)
    } else {
      match name {
        "a" => JNum(self.choose(small_ints))
        "b" => JNum(self.choose(["0.5", "1.5", "-2.25", "3.0"]))
        "s" | "html" => JStr(self.gen_string())
        "items" =>
          JArr(Array::makei(self.pick(5), _ => JNum(self.choose(small_ints))))
        "words" =>
          JArr(Array::makei(self.pick(5), _ => JStr(self.gen_string())))
        "d" =>
          JObj(
            Array::makei(self.pick(4), i => {
              (["b", "a", "c", "B"][i], JNum(self.choose(small_ints)))
            }),
          )
        "users" =>
          JArr(
            Array::makei(self.pick(4), _ => {
              JObj([
                (
                  "name",
                  JStr(self.choose(["alice", "Bob", "carol", "Alice", ""])),
                ),
                ("age", JNum(self.choose(["30", "25", "41", "30"]))),
              ])
            }),
          )
        "flag" => JBool(self.chance(50))
        "nothing" => JNull
        "big" =>
          JNum(
            self.choose([
              "9223372036854775807", "18446744073709551615", "-9223372036854775808",
            ]),
          )
        _ => self.gen_json(2)
      }
    }
    rv.push((name, value))
  }
  rv
}

///|
/// The name of an extra template, sometimes wrong or indirect.
fn G::template_ref(self : G, name : String, ext : String) -> Expr {
  match self.weighted([82, 7, 6, 5]) {
    0 => Str(name)
    1 => Str("missing" + ext)
    2 => List([Str("missing" + ext), Str(name)])
    _ => self.gen_var()
  }
}

///|
/// Generates a main template together with a base layout, an include
/// partial and a macro library.
fn G::gen_multi(
  self : G,
  ext : String,
  depth : Int,
) -> (Array[Stmt], Array[(String, Array[Stmt])]) {
  let base = "base" + ext
  let inc = "inc" + ext
  let lib = "lib" + ext
  // the macro library
  let old_macros = self.macros.copy()
  let lib_body : Array[Stmt] = [
    Macro(
      ws_none(),
      "lm0",
      [("p0", None), ("p1", Some(Lit("1")))],
      self.with_scope(["p0", "p1", "varargs", "kwargs", "caller"], () => {
        self.gen_body(depth - 1)
      }),
    ),
    Set(ws_none(), ["lv"], self.gen_expr(2)),
    Text(self.choose(text_pool)),
  ]
  if self.chance(50) {
    lib_body.push(Macro(ws_none(), "lm1", [], self.gen_body(depth - 1)))
  }
  self.macros.clear()
  self.macros.append(old_macros)
  // the partial
  let inc_body = self.gen_body(depth - 1)
  // the layout
  let base_body : Array[Stmt] = [
    Text(self.choose(text_pool)),
    Block(self.gen_ws(), "b0", self.gen_body(depth - 1)),
    Text(self.choose(["|", "\n", " - ", ""])),
    Block(self.gen_ws(), "b1", self.gen_body(depth - 1)),
  ]
  if self.chance(30) {
    base_body.push(Emit(ws_none(), Call(Attr(Var("self"), "b0"), [], [])))
  }
  if self.chance(30) {
    base_body.push(
      Include(ws_none(), self.template_ref(inc, ext), self.chance(30), ""),
    )
  }
  let extra = [(base, base_body), (inc, inc_body), (lib, lib_body)]
  let main : Array[Stmt] = []
  if self.chance(45) {
    main.push(Extends(self.gen_ws(), self.template_ref(base, ext)))
    if self.chance(30) {
      main.push(Set(ws_none(), [self.fresh("v")], self.gen_expr(2)))
    }
    for name in ["b0", "b1"] {
      if self.chance(70) {
        let body = self.gen_body(depth - 1)
        if self.chance(50) {
          body.insert(
            self.pick(body.length() + 1),
            Emit(ws_none(), Call(Var("super"), [], [])),
          )
        }
        main.push(Block(self.gen_ws(), name, body))
      }
    }
    if self.chance(20) {
      main.push(Text("ignored outside of blocks"))
    }
  } else {
    let n = self.pick(4) + 1
    for _ in 0..<n {
      match self.weighted([30, 25, 20, 25]) {
        0 =>
          main.push(
            Include(
              self.gen_ws(),
              self.template_ref(inc, ext),
              self.chance(30),
              self.choose(["", "", " with context", " without context"]),
            ),
          )
        1 => {
          main.push(Import(self.gen_ws(), self.template_ref(lib, ext), "lib"))
          main.push(
            Emit(
              ws_none(),
              if self.chance(70) {
                Call(
                  Attr(Var("lib"), self.choose(["lm0", "lm1", "lv", "nope"])),
                  self.gen_exprs(self.pick(3), 1),
                  [],
                )
              } else {
                Attr(Var("lib"), self.choose(["lv", "lm0", "nope"]))
              },
            ),
          )
        }
        2 => {
          let names = if self.chance(50) {
            [("lm0", None)]
          } else {
            [("lm0", Some("aliased")), ("lv", None)]
          }
          main.push(
            FromImport(self.gen_ws(), self.template_ref(lib, ext), names),
          )
          let callee = match names[0].1 {
            Some(as_name) => as_name
            None => "lm0"
          }
          main.push(
            Emit(
              ws_none(),
              Call(Var(callee), self.gen_exprs(self.pick(3), 1), []),
            ),
          )
        }
        _ => main.append(self.gen_body(depth - 1))
      }
    }
  }
  (main, extra)
}

///|
fn gen_case(size : Int, rs : @splitmix.RandomState) -> Case {
  let g : G = {
    rs,
    budget: 4 + size / 3,
    vars: [],
    macros: [],
    loop_depth: 0,
    in_macro: false,
    counter: 0,
  }
  let ctx = g.gen_context()
  let depth = 2 + size / 40
  let name = g.choose([
    "t.txt", "t.txt", "t.html", "t.html", "t.json", "t.yaml", "t.xml",
  ])
  let ext = name.view(start_offset=1).to_owned()
  let (body, extra) = if g.chance(30) {
    g.gen_multi(ext, depth)
  } else {
    (Array::makei(g.pick(4) + 1, _ => g.gen_stmt(depth)), [])
  }
  {
    name,
    body,
    extra,
    ctx,
    undefined: g.choose([
      "lenient", "lenient", "lenient", "strict", "semi_strict", "chainable",
    ]),
    trim_blocks: g.chance(25),
    lstrip_blocks: g.chance(25),
    keep_trailing_newline: g.chance(25),
  }
}

///|
impl @quickcheck.Arbitrary for Case with fn arbitrary(size, rs) {
  gen_case(size, rs)
}
