///|
#borrow(path)
extern "C" fn oracle_start_ffi(path : Bytes) -> Int = "difftest_oracle_start"

///|
#borrow(req)
extern "C" fn oracle_query_ffi(req : Bytes) -> Bytes = "difftest_oracle_query"

///|
#borrow(path, data)
extern "C" fn write_file_ffi(path : Bytes, data : Bytes) -> Unit = "difftest_write_file"

///|
fn c_str(s : String) -> Bytes {
  let b = @utf8.encode(s)
  let rv = FixedArray::make(b.length() + 1, b'\x00')
  for i in 0..<b.length() {
    rv[i] = b[i]
  }
  Bytes::from_array(rv)
}

///|
enum Outcome {
  Rendered(String)
  Failed(String)
  Crashed(String)
} derive(Eq, Debug)

///|
fn format_err(err : @minijinja.TemplateError) -> String {
  let sb = StringBuilder()
  sb.write_string(err.to_string())
  let mut source = err.source()
  while source is Some(e) {
    sb.write_string("\ncaused by: ")
    sb.write_string(e.to_string())
    source = e.source()
  }
  sb.to_string()
}

///|
fn render_ours(c : Case) -> Outcome {
  let env = @minijinja.Environment::new()
  env.set_undefined_behavior(
    match c.undefined {
      "strict" => Strict
      "semi_strict" => SemiStrict
      "chainable" => Chainable
      _ => Lenient
    },
  )
  env.set_trim_blocks(c.trim_blocks)
  env.set_lstrip_blocks(c.lstrip_blocks)
  env.set_keep_trailing_newline(c.keep_trailing_newline)
  env.set_recursion_limit(100)
  try {
    let ctx = @minijinja.Value::from_json_str(c.ctx_json())
    for t in c.extra {
      env.add_template(t.0, body_source(t.1))
    }
    env.add_template(c.name, c.source())
    Rendered(env.get_template(c.name).render(ctx))
  } catch {
    err => Failed(format_err(err))
  }
}

///|
fn Case::request(self : Case) -> String {
  let j : Json = {
    "name": self.name.to_json(),
    "source": self.source().to_json(),
    "templates": Json::array(
      self.extra.map(t => {
        Json::array([t.0.to_json(), body_source(t.1).to_json()])
      }),
    ),
    "ctx": self.ctx_json().to_json(),
    "undefined": self.undefined.to_json(),
    "trim_blocks": self.trim_blocks.to_json(),
    "lstrip_blocks": self.lstrip_blocks.to_json(),
    "keep_trailing_newline": self.keep_trailing_newline.to_json(),
  }
  j.stringify()
}

///|
let oracle_path : Ref[String] = { val: "", }

///|
fn render_oracle(c : Case) -> Outcome {
  let line = @utf8.decode_lossy(oracle_query_ffi(@utf8.encode(c.request())))
  if line.is_empty() {
    // the oracle aborted (for instance on an allocation failure)
    write_file_ffi(
      c_str("_build/difftest_oracle_crash.txt"),
      @utf8.encode(c.describe()),
    )
    if oracle_start_ffi(c_str(oracle_path.val)) != 0 {
      abort("cannot restart the oracle")
    }
    return Crashed("oracle process died")
  }
  let parsed = @json.parse(line) catch {
    _ => return Crashed("oracle died or sent garbage: \{line}")
  }
  match parsed {
    { "ok": String(s), .. } => Rendered(s)
    { "err": String(s), .. } => Failed(s)
    { "panic": String(s), .. } => Crashed("rust panic: \{s}")
    _ => Crashed("unexpected oracle response: \{line}")
  }
}

///|
let last_case_path : Bytes = c_str("_build/difftest_last_case.txt")

///|
fn Case::describe(self : Case) -> String {
  "name=\{self.name} undefined=\{self.undefined} trim_blocks=\{self.trim_blocks} " +
  "lstrip_blocks=\{self.lstrip_blocks} keep_trailing_newline=\{self.keep_trailing_newline}\n" +
  "ctx=\{self.ctx_json()}\n" +
  self.extra.map(t => "--- \{t.0}\n\{body_source(t.1)}\n").join("") +
  "--- source\n\{self.source()}\n---"
}

///|
/// Runs both engines; returns `None` if they agree.
fn compare(c : Case) -> (Outcome, Outcome)? {
  write_file_ffi(last_case_path, @utf8.encode(c.describe()))
  let theirs = render_oracle(c)
  // A Rust panic is an upstream bug, not a porting divergence.
  if theirs is Crashed(_) {
    return None
  }
  let ours = render_ours(c)
  if ours == theirs {
    None
  } else {
    Some((ours, theirs))
  }
}

///|
fn Outcome::show(self : Outcome) -> String {
  match self {
    Rendered(s) => "rendered: \{s.escape()}"
    Failed(s) => "error: \{s.escape()}"
    Crashed(s) => "crash: \{s}"
  }
}

///|
fn report_mismatch(c : Case) -> String {
  match compare(c) {
    Some((ours, theirs)) =>
      "\{c.describe()}\n  rust: \{theirs.show()}\n  ours: \{ours.show()}"
    None => "(no longer fails)\n\{c.describe()}"
  }
}

///|
/// Greedy shrinking: keep taking the first smaller case that still fails.
fn shrink_failure(c : Case, max_steps : Int) -> Case {
  shrink_while(c, max_steps, x => compare(x) is Some(_))
}

///|
fn shrink_while(c : Case, max_steps : Int, fails : (Case) -> Bool) -> Case {
  let mut current = c
  for _ in 0..<max_steps {
    let next = @quickcheck.Shrink::shrink(current).find_first(fails)
    match next {
      Some(x) => current = x
      None => break
    }
  }
  current
}

///|
/// A short key identifying the kind of mismatch, for deduplication.
fn mismatch_key(ours : Outcome, theirs : Outcome) -> String {
  let kind = (o : Outcome) => {
    match o {
      Rendered(_) => "ok"
      Failed(s) => s.split(":").next().map_or("err", x => x.to_owned())
      Crashed(_) => "crash"
    }
  }
  "\{kind(theirs)} vs \{kind(ours)}"
}

///|
fn survey(
  count : Int,
  seed : UInt64,
  max_size : Int,
  max_reports : Int,
) -> Unit {
  let rs = @splitmix.new(seed~)
  let seen : Map[String, Int] = Map([])
  let mut mismatches = 0
  let mut crashes = 0
  let mut rendered = 0
  let mut multi = 0
  let errors : Map[String, Int] = Map([])
  let mut reported = 0
  for i in 0..<count {
    let size = i % max_size
    let c = gen_case(size, rs)
    if !c.extra.is_empty() {
      multi += 1
    }
    match render_oracle(c) {
      Rendered(_) => rendered += 1
      Failed(msg) => {
        let kind = if msg.has_prefix("syntax error") {
          msg.split("(in").next().map_or("?", x => x.to_owned())
        } else {
          msg.split(":").next().map_or("?", x => x.to_owned())
        }
        errors[kind] = errors.get(kind).unwrap_or(0) + 1
      }
      Crashed(_) => ()
    }
    if render_oracle(c) is Crashed(msg) {
      crashes += 1
      let small = shrink_while(c, 200, x => render_oracle(x) is Crashed(_))
      println(
        "=== upstream crash (case \{i}): \{msg}\n\{small.describe()}\n  ours: \{render_ours(small).show()}\n",
      )
      continue
    }
    guard compare(c) is Some(_) else { continue }
    mismatches += 1
    let small = shrink_failure(c, 200)
    guard compare(small) is Some((ours, theirs)) else { continue }
    let key = mismatch_key(ours, theirs) + "|" + small.source()
    if seen.contains(key) {
      seen[key] = seen[key] + 1
      continue
    }
    seen[key] = 1
    if reported < max_reports {
      reported += 1
      println("=== mismatch #\{reported} (case \{i})")
      println(report_mismatch(small))
      println("")
    }
  }
  let top = errors.to_array()
  top.sort_by((a, b) => b.1 - a.1)
  println(
    "outcomes: \{rendered} rendered (\{multi} cases with several templates); errors: " +
    top[:@cmp.minimum(25, top.length())].map(e => "\{e.0} \{e.1}").join(", "),
  )
  println(
    "survey: \{count} cases, \{mismatches} mismatches, \{seen.length()} distinct after shrinking, \{crashes} upstream crashes",
  )
}

///|
fn run_check(count : Int, seed : UInt64, max_size : Int) -> Unit {
  try
    @quickcheck.check(
      (c : Case) => compare(c) is None,
      count=count.reinterpret_as_uint(),
      max_size=max_size.reinterpret_as_uint(),
      seed~,
      counterexample_context=report_mismatch,
    )
  catch {
    err => println("quickcheck failed:\n\{err}")
  } noraise {
    _ => println("quickcheck: \{count} cases passed")
  }
}

///|
fn main {
  let args = @env.args()
  let arg = (i : Int, default : String) => args.get(i).unwrap_or(default)
  let mode = arg(1, "survey")
  let count = @string.parse_int(arg(2, "1000")) catch { _ => 1000 }
  let seed = @string.parse_int64(arg(3, "1")).reinterpret_as_uint64() catch {
    _ => 1UL
  }
  let max_size = @string.parse_int(arg(4, "100")) catch { _ => 100 }
  let oracle = @env.get_env_var("MINIJINJA_ORACLE").unwrap_or(
    "difftest/oracle/target/release/minijinja-oracle",
  )
  oracle_path.val = oracle
  if oracle_start_ffi(c_str(oracle)) != 0 {
    println("failed to start oracle \{oracle}")
    return
  }
  match mode {
    "check" => run_check(count, seed, max_size)
    "syntax" => {
      // shortest generated example per syntax error message (ours only)
      let rs = @splitmix.new(seed~)
      let examples : Map[String, String] = Map([])
      for i in 0..<count {
        let c = gen_case(i % max_size, rs)
        if render_ours(c) is Failed(msg) && msg.has_prefix("syntax error") {
          let key = msg.split("(in").next().map_or("?", x => x.to_owned())
          // show the template the error is about
          let src = match c.extra.search_by(t => msg.contains("(in \{t.0}:")) {
            Some(i) => "[\{c.extra[i].0}] " + body_source(c.extra[i].1)
            None => c.source()
          }
          match examples.get(key) {
            Some(old) if old.length() <= src.length() => ()
            _ => examples[key] = src
          }
        }
      }
      for k, v in examples {
        println("== \{k}\n\{v}")
      }
    }
    "show" => {
      let rs = @splitmix.new(seed~)
      for i in 0..<count {
        println("--- case \{i}\n\{gen_case(i % max_size, rs).source()}")
      }
    }
    _ => survey(count, seed, max_size, 20)
  }
}
