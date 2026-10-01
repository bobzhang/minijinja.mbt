///|
async fn read_text(path : String) -> String {
  let data = @fs.read_file(path)
  @utf8.decode_lossy(data.binary())
}

///|
/// Normalizes snapshot contents like insta does: leading newlines and
/// trailing whitespace are removed and CRLF is normalized to LF.
fn normalize_snapshot(s : String) -> String {
  let s = s.replace_all(old="\r\n", new="\n")
  let mut start = 0
  while start < s.length() && (s[start] == '\n' || s[start] == '\r') {
    start += 1
  }
  let mut end = s.length()
  while end > start &&
        (
          s[end - 1] == ' ' ||
          s[end - 1] == '\n' ||
          s[end - 1] == '\r' ||
          s[end - 1] == '\t'
        ) {
    end -= 1
  }
  s.view(start_offset=start, end_offset=end).to_owned()
}

///|
/// Extracts the body of an insta `.snap` file (everything after the YAML
/// front matter).
fn snapshot_body(contents : String) -> String {
  let lines = contents.split("\n").to_array()
  let mut dashes = 0
  let body = StringBuilder()
  let mut first = true
  for line in lines {
    if dashes < 2 {
      if line == "---" {
        dashes += 1
      }
      continue
    }
    if !first {
      body.write_char('\n')
    }
    first = false
    body.write_view(line)
  }
  body.to_string()
}

///|
/// Splits a fixture into its header (settings or context) and the template.
fn split_fixture(contents : String) -> (String, String) {
  match contents.find("\n---\n") {
    Some(idx) =>
      (
        contents.view(end_offset=idx).to_owned(),
        contents.view(start_offset=idx + 5).to_owned(),
      )
    None => (contents, "")
  }
}

///|
/// Runs `render` for every file in `dir` and compares the output with the
/// snapshot `snapshots/<prefix><name>.snap`.  Cases listed in
/// `testdata/known_failures.txt` (as `<suite>/<name>`) may fail.
async fn run_snapshot_suite(
  suite : String,
  dir : String,
  snap_prefix : String,
  render : async (String, String) -> String,
) -> Unit {
  let known = read_text("testdata/known_failures.txt")
    .split("\n")
    .map(x => x.trim().to_owned())
    .filter(x => x != "" && !x.has_prefix("#"))
    .to_array()
  let names = @fs.readdir(dir, sort=true)
  let unexpected = []
  let fixed = []
  let mut passed = 0
  let mut total = 0
  for name in names {
    if !(name.has_suffix(".txt") || name.has_suffix(".html")) {
      continue
    }
    let path = "\{dir}/\{name}"
    if @fs.kind(path) != Regular {
      continue
    }
    total += 1
    let contents = read_text(path)
    let snap_path = "testdata/snapshots/\{snap_prefix}\{name}.snap"
    let expected = normalize_snapshot(snapshot_body(read_text(snap_path)))
    let actual = normalize_snapshot(render(name, contents)) catch {
      err => "<<raised \{err}>>"
    }
    let key = "\{suite}/\{name}"
    let is_known = known.contains(key)
    if actual == expected {
      passed += 1
      if is_known {
        fixed.push(key)
      }
    } else if !is_known {
      unexpected.push((key, expected, actual))
    }
  }
  println("\{suite}: \{passed}/\{total} snapshots pass")
  for f in fixed {
    println("  now passing (remove from known_failures.txt): \{f}")
  }
  for item in unexpected {
    let (key, expected, actual) = item
    println(
      "=== FAIL \{key}\n--- expected\n\{expected}\n--- actual\n\{actual}\n",
    )
  }
  if !unexpected.is_empty() || !fixed.is_empty() {
    fail(
      "\{suite}: \{unexpected.length()} unexpected failures, \{fixed.length()} fixed",
    )
  }
}
