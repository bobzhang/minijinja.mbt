// Port of upstream's `config.rs` (without the TOML config file support).

///|
/// Overrides specific syntax settings.
priv struct SyntaxElements {
  mut block_start : String
  mut block_end : String
  mut variable_start : String
  mut variable_end : String
  mut comment_start : String
  mut comment_end : String
  mut line_statement_prefix : String
  mut line_comment_prefix : String
}

///|
/// Holds in-memory config state for the execution.
priv struct Config {
  mut format : String
  mut autoescape : String
  mut allow_include : Bool
  mut newline : Bool
  mut trim_blocks : Bool
  mut lstrip_blocks : Bool
  mut py_compat : Bool
  mut env : Bool
  mut strict : Bool
  mut safe_paths : Array[String]
  mut expr_out : String
  mut fuel : UInt64
  syntax : SyntaxElements
  defines : Map[String, @minijinja.Value]
}

///|
fn Config::new() -> Config {
  {
    format: "auto",
    autoescape: "auto",
    allow_include: true,
    newline: true,
    trim_blocks: false,
    lstrip_blocks: false,
    py_compat: false,
    env: false,
    strict: false,
    safe_paths: [],
    expr_out: "print",
    fuel: 0,
    syntax: {
      block_start: "{%",
      block_end: "%}",
      variable_start: "{{",
      variable_end: "}}",
      comment_start: "{#",
      comment_end: "#}",
      line_statement_prefix: "",
      line_comment_prefix: "",
    },
    defines: {},
  }
}

///|
fn parse_env_bool(s : String, var_name : String) -> Bool raise CliError {
  match s.to_lower() {
    "0" | "false" | "no" | "off" => false
    "1" | "true" | "yes" | "on" => true
    _ => raise fail_with("Invalid boolean value for \{var_name}: \{s}")
  }
}

///|
/// Parses an unsigned 64 bit integer like Rust's `u64::from_str`.
fn parse_u64(s : String) -> UInt64 raise CliError {
  let digits = if s.has_prefix("+") { s.view(start_offset=1) } else { s[:] }
  if digits.length() == 0 {
    raise fail_with("cannot parse integer from empty string")
  }
  let mut rv : UInt64 = 0
  for c in digits {
    guard c is ('0'..='9') else {
      raise fail_with("invalid digit found in string")
    }
    let d = (c.to_int() - '0'.to_int()).to_uint64()
    if rv > (@uint64.MAX_VALUE - d) / 10 {
      raise fail_with("number too large to fit in target type")
    }
    rv = rv * 10 + d
  }
  rv
}

///|
fn Config::update_from_env(
  self : Config,
  env_vars : Map[String, String],
) -> Unit raise CliError {
  if env_vars.get("MINIJINJA_FORMAT") is Some(v) {
    self.format = v
  }
  if env_vars.get("MINIJINJA_AUTOESCAPE") is Some(v) {
    self.autoescape = v
  }
  if env_vars.get("MINIJINJA_INCLUDE") is Some(v) {
    self.allow_include = parse_env_bool(v, "MINIJINJA_INCLUDE")
  }
  if env_vars.get("MINIJINJA_NEWLINE") is Some(v) {
    self.newline = parse_env_bool(v, "MINIJINJA_NEWLINE")
  }
  if env_vars.get("MINIJINJA_TRIM_BLOCKS") is Some(v) {
    self.trim_blocks = parse_env_bool(v, "MINIJINJA_TRIM_BLOCKS")
  }
  if env_vars.get("MINIJINJA_LSTRIP_BLOCKS") is Some(v) {
    self.lstrip_blocks = parse_env_bool(v, "MINIJINJA_LSTRIP_BLOCKS")
  }
  if env_vars.get("MINIJINJA_PY_COMPAT") is Some(v) {
    self.py_compat = parse_env_bool(v, "MINIJINJA_PY_COMPAT")
  }
  if env_vars.get("MINIJINJA_ENV") is Some(v) {
    self.env = parse_env_bool(v, "MINIJINJA_ENV")
  }
  if env_vars.get("MINIJINJA_STRICT") is Some(v) {
    self.strict = parse_env_bool(v, "MINIJINJA_STRICT")
  }
  if env_vars.get("MINIJINJA_EXPR_OUT") is Some(v) {
    self.expr_out = v
  }
  if env_vars.get("MINIJINJA_FUEL") is Some(v) {
    // invalid values are ignored, like upstream does
    let fuel = parse_u64(v) catch { _ => 0 }
    if fuel > 0 {
      self.fuel = fuel
    }
  }
  if env_vars.get("MINIJINJA_SAFE_PATHS") is Some(v) {
    self.safe_paths = v.split(":").map(x => x.to_owned()).to_array()
  }
  if env_vars.get("MINIJINJA_SYNTAX") is Some(v) {
    let pairs = []
    for part in v.split(" ") {
      for item in part.split("\t") {
        for x in item.split("\n") {
          if x != "" {
            pairs.push(x.to_owned())
          }
        }
      }
    }
    self.update_syntax_from_pairs(pairs)
  }
}

///|
async fn Config::update_from_matches(self : Config, matches : Matches) -> Unit {
  if matches.get_one("format") is Some(v) {
    self.format = v
  }
  if matches.get_one("autoescape") is Some(v) {
    self.autoescape = v
  }
  if matches.get_one("expr-out") is Some(v) {
    self.expr_out = v
  }
  if matches.get_flag("no-include") {
    self.allow_include = false
  }
  if matches.get_flag("no-newline") {
    self.newline = false
  }
  if matches.get_flag("trim-blocks") {
    self.trim_blocks = true
  }
  if matches.get_flag("lstrip-blocks") {
    self.lstrip_blocks = true
  }
  if matches.get_flag("py-compat") {
    self.py_compat = true
  }
  if matches.get_flag("env") {
    self.env = true
  }
  if matches.get_flag("strict") {
    self.strict = true
  }
  if matches.get_one("fuel") is Some(v) {
    let fuel = parse_u64(v) catch {
      Failure(msg, _) =>
        raise usage_error(
          "invalid value '\{v}' for '--fuel <AMOUNT>': \{msg}",
          with_usage=false,
        )
      err => raise err
    }
    if fuel > 0 {
      self.fuel = fuel
    }
  }
  for path in matches.get_many("safe-path") {
    let canonical = @fs.realpath(path) catch { _ => path }
    self.safe_paths.push(canonical)
    // Template paths are only normalized lexically (symlinks are not
    // resolved), so the path as given is accepted as well.
    if canonical != path {
      self.safe_paths.push(path)
    }
  }
  self.update_syntax_from_pairs(matches.get_many("syntax"))
  self.add_defines(matches.get_many("define"))
}

///|
fn split_once(s : String, sep : String) -> (String, String)? {
  match s.find(sep) {
    Some(idx) =>
      Some(
        (
          s.view(end_offset=idx).to_owned(),
          s.view(start_offset=idx + sep.length()).to_owned(),
        ),
      )
    None => None
  }
}

///|
fn Config::update_syntax_from_pairs(
  self : Config,
  pairs : Array[String],
) -> Unit raise CliError {
  let s = self.syntax
  for pair in pairs {
    guard split_once(pair, "=") is Some((key, value)) else {
      raise fail_with("syntax feature needs to be a key=value pair")
    }
    match key {
      "block-start" => s.block_start = value
      "block-end" => s.block_end = value
      "variable-start" => s.variable_start = value
      "variable-end" => s.variable_end = value
      "comment-start" => s.comment_start = value
      "comment-end" => s.comment_end = value
      "line-statement-prefix" => s.line_statement_prefix = value
      "line-comment-prefix" => s.line_comment_prefix = value
      _ => raise fail_with("unknown syntax feature '\{key}'")
    }
  }
}

///|
fn Config::add_defines(
  self : Config,
  items : Array[String],
) -> Unit raise CliError {
  for item in items {
    if split_once(item, ":=") is Some((key, raw_value)) {
      self.defines[key] = interpret_raw_value(raw_value)
    } else if split_once(item, "=") is Some((key, value)) {
      self.defines[key] = @minijinja.Value::from_string(value)
    } else {
      self.defines[item] = @minijinja.Value::from_bool(true)
    }
  }
}

///|
fn interpret_raw_value(s : String) -> @minijinja.Value raise CliError {
  @minijinja.Value::from_json_str(s) catch {
    err =>
      raise fail_with("invalid raw value '\{s}' (not valid JSON)", cause=err)
  }
}

///|
/// The defines as a (key sorted) map value.
fn Config::defines_value(self : Config) -> @minijinja.Value {
  sorted_map_value(self.defines)
}

///|
/// Builds a map value with sorted keys (like a Rust `BTreeMap`).
fn sorted_map_value(m : Map[String, @minijinja.Value]) -> @minijinja.Value {
  let keys = m.keys().to_array()
  keys.sort()
  @minijinja.Value::from_pairs(keys.map(k => (k, m[k])))
}

///|
fn Config::make_syntax(self : Config) -> @minijinja.SyntaxConfig raise CliError {
  let s = self.syntax
  @minijinja.SyntaxConfig::new(
    block_delimiters=(s.block_start, s.block_end),
    variable_delimiters=(s.variable_start, s.variable_end),
    comment_delimiters=(s.comment_start, s.comment_end),
    line_statement_prefix=s.line_statement_prefix,
    line_comment_prefix=s.line_comment_prefix,
  ) catch {
    err => raise fail_with("could not configure syntax", cause=err)
  }
}

///|
/// Picks the auto escape mode for a template name in `auto` mode.
fn auto_escape_for_name(name : String) -> @minijinja.AutoEscape {
  let name = if name.has_suffix(".j2") {
    name.view(end_offset=name.length() - 3).to_owned()
  } else {
    name
  }
  let ext = match name.rev_find(".") {
    Some(idx) => name.view(start_offset=idx + 1).to_owned()
    None => name
  }
  match ext {
    "htm" | "html" | "xml" | "xhtml" => Html
    "json" | "json5" | "yml" | "yaml" => Json
    _ => NoEscape
  }
}

///|
fn Config::apply_to_env(
  self : Config,
  env : @minijinja.Environment,
  env_vars : Map[String, String],
) -> Unit raise CliError {
  if self.env {
    env.add_global(
      "ENV",
      @minijinja.Value::from_pairs(
        env_vars
        .iter()
        .map(kv => (kv.0, @minijinja.Value::from_string(kv.1)))
        .to_array(),
      ),
    )
  }
  env.set_trim_blocks(self.trim_blocks)
  env.set_lstrip_blocks(self.lstrip_blocks)
  if self.fuel > 0 {
    let max = @int64.MAX_VALUE.reinterpret_as_uint64()
    env.set_fuel(
      Some(
        (if self.fuel > max { max } else { self.fuel }).reinterpret_as_int64(),
      ),
    )
  }
  @contrib.add_to_environment(env)
  if self.py_compat {
    env.set_unknown_method_callback(@contrib.unknown_method_callback)
  }
  let callback : (String) -> @minijinja.AutoEscape = match self.autoescape {
    "none" => _ => NoEscape
    "html" => _ => Html
    "json" => _ => Json
    "auto" => auto_escape_for_name
    other => raise fail_with("unknown autoescape mode '\{other}'")
  }
  env.set_auto_escape_callback(callback)
  env.set_undefined_behavior(if self.strict { Strict } else { Lenient })
  env.set_syntax(self.make_syntax())
}
