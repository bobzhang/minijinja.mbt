// Test helpers mirroring upstream's `tests/test_basic.rs` harness: temp
// files named `minijinja-testfile--*`, insta_cmd style snapshots and the
// same output filters (`bind_common_filters!`).

///|
priv struct TestDir {
  path : String
  mut counter : Int
}

///|
/// Runs `f` with a fresh temporary directory that is removed afterwards.
async fn with_test_dir(f : async (TestDir) -> Unit) -> Unit {
  let path = @fs.tmpdir(prefix="minijinja-cli-test-")
  let dir = { path, counter: 0, }
  defer (@fs.rmdir(path, recursive=true) catch { _ => () })
  f(dir)
}

///|
/// Creates a temp file with the given contents (and extension) and returns
/// its absolute path.
async fn TestDir::file(
  self : TestDir,
  contents : String,
  ext? : String = "",
) -> String {
  self.counter += 1
  let path = "\{self.path}/minijinja-testfile--\{self.counter}\{ext}"
  @fs.write_file(path, @utf8.encode(contents), create_mode=CreateNew)
  path
}

///|
/// Runs the CLI in the temp directory and returns an insta_cmd style
/// snapshot of the outcome (with the common filters applied).
async fn TestDir::run(
  self : TestDir,
  args : Array[String],
  stdin? : String = "",
  env? : Map[String, String] = Map([]),
) -> String {
  let outcome = @cli.run(args, env_vars=env, cwd=self.path, stdin=() => {
    @utf8.encode(stdin)
  })
  let snapshot = StringBuilder()
  snapshot.write_string("success: \{outcome.exit_code == 0}\n")
  snapshot.write_string("exit_code: \{outcome.exit_code}\n")
  snapshot.write_string("----- stdout -----\n")
  snapshot.write_string(outcome.stdout)
  snapshot.write_string("\n----- stderr -----\n")
  snapshot.write_string(outcome.stderr)
  filter_snapshot(snapshot.to_string())
}

///|
/// Applies the filters of upstream's `bind_common_filters!` and trims
/// trailing whitespace like insta does.
fn filter_snapshot(s : String) -> String {
  let lines = []
  for line in s.split("\n") {
    let line = line.to_owned()
    // (?mis)(^Referenced variables: \{).*\z
    if line.has_prefix("Referenced variables: {") {
      lines.push("Referenced variables: { ... }")
      break
    }
    lines.push(filter_line(line))
  }
  let rv = lines.join("\n")
  rv.trim_end(chars=" \n").to_owned()
}

///|
fn filter_line(line : String) -> String {
  // (?m)(non-existing template).*$
  if line.find("non-existing template") is Some(idx) {
    return line.view(end_offset=idx).to_owned() +
      "non-existing template [FILENAME HERE]"
  }
  // (?m)^-+ (minijinja-testfile--\S+) -+$
  if line.has_prefix("-") &&
    line.has_suffix("-") &&
    line.find(" minijinja-testfile--") is Some(_) {
    return "--- [TEMPLATE] ---"
  }
  // \(in .*minijinja-testfile--.*?:(\d+)\)
  if line.find("(in ") is Some(start) &&
    line.view(start_offset=start).find(")") is Some(len) {
    let inner = line.view(start_offset=start + 4, end_offset=start + len)
    if inner.find("minijinja-testfile--") is Some(_) &&
      inner.rev_find(":") is Some(colon) {
      let lineno = inner.view(start_offset=colon + 1)
      return line.view(end_offset=start).to_owned() +
        "(in [TEMPLATE]:\{lineno})" +
        line.view(start_offset=start + len + 1).to_owned()
    }
  }
  line
}
