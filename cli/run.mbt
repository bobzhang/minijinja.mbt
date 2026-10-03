// Port of upstream's `cli.rs`: the main execution logic.

///|
/// The version printed by `--version`.
pub let version : String = "0.1.1"

///|
/// The name of stdin / stdout in file arguments.
let stdin_stdout : String = "-"

///|
/// The result of running the command line tool.
pub(all) struct Outcome {
  /// The process exit code.
  exit_code : Int
  /// Everything written to stdout.
  stdout : String
  /// Everything written to stderr.
  stderr : String
} derive(Debug, Eq)

///|
/// Per-invocation I/O state.
priv struct Io {
  env_vars : Map[String, String]
  cwd : String
  read_stdin : async () -> Bytes
  mut stdin_cache : Bytes?
  stdout : StringBuilder
}

///|
async fn Io::stdin(self : Io) -> Bytes {
  match self.stdin_cache {
    Some(b) => b
    None => {
      let b = (self.read_stdin)()
      self.stdin_cache = Some(b)
      b
    }
  }
}

///|
/// Runs the command line tool.
///
/// * `args` are the command line arguments without the program name.
/// * `env_vars` are the environment variables (used for `MINIJINJA_*`
///   configuration and `--env`), defaulting to the process environment.
/// * `cwd` is the directory relative paths are resolved against, defaulting
///   to the process working directory.
/// * `stdin` reads all of stdin (only invoked when `-` is used as template
///   or data file), defaulting to reading the process stdin.
///
/// Output files (`-o`) are written directly; everything that goes to stdout
/// and stderr is returned in the `Outcome`.
pub async fn run(
  args : ArrayView[String],
  env_vars? : Map[String, String],
  cwd? : String,
  stdin? : async () -> Bytes,
) -> Outcome {
  let env_vars = match env_vars {
    Some(m) => m
    None => @env.get_env_vars()
  }
  let cwd = match cwd {
    Some(cwd) => cwd
    None =>
      match @env.current_dir() {
        Some(cwd) => cwd
        None => @fs.realpath(".") catch { _ => "." }
      }
  }
  let read_stdin : async () -> Bytes = match stdin {
    Some(f) => f
    None => () => @stdio.stdin.read_all().binary()
  }
  let io = {
    env_vars,
    cwd,
    read_stdin,
    stdin_cache: None,
    stdout: StringBuilder(),
  }
  let (exit_code, stderr) = try execute(io, args) catch {
    UsageError(msg) => (2, msg)
    err => (1, format_error(err))
  } noraise {
    code => (code, "")
  }
  { exit_code, stdout: io.stdout.to_string(), stderr, }
}

///|
async fn execute(io : Io, args : ArrayView[String]) -> Int {
  let matches = match parse_args(args) {
    Run(matches) => matches
    ShortHelp => {
      io.stdout.write_string(short_help)
      return 0
    }
    LongHelp => {
      io.stdout.write_string(long_help)
      return 0
    }
    Version => {
      io.stdout.write_string("minijinja-cli \{version}\n")
      return 0
    }
  }
  let config = Config::new()
  config.update_from_env(io.env_vars)
  config.update_from_matches(matches)
  if matches.get_flag("syntax-help") {
    io.stdout.write_string(syntax_help)
    io.stdout.write_char('\n')
    return 0
  }
  let positionals = matches.positionals
  let data_files = if positionals.length() > 1 {
    positionals[1:].to_owned()
  } else {
    []
  }
  let mut stdin_used = false
  let base_ctx = if data_files.is_empty() {
    @minijinja.Value::from_pairs([])
  } else {
    let contexts = []
    let select = matches.get_one("select")
    for data_file in data_files {
      let (ctx, stdin_used_here) = load_data(
        io,
        config.format,
        data_file,
        select,
      )
      contexts.push(ctx)
      stdin_used = stdin_used || stdin_used_here
    }
    @minijinja.merge_maps(contexts)
  }
  // defines take precedence over the data files
  let ctx = @minijinja.merge_maps([base_ctx, config.defines_value()])
  let template_file = match positionals.get(0) {
    Some(name) => Some(name)
    None =>
      if matches.get_one("template") is Some(_) {
        None
      } else {
        Some("-")
      }
  }
  let (template_name, template_source) = match
    (matches.get_one("template"), template_file) {
    (None, Some("-")) => (stdin_stdout, None)
    (None, Some("")) =>
      raise fail_with("Empty template names are only valid with --template.")
    (None, Some(rel_name)) => (path_join(io.cwd, rel_name), None)
    (Some(source), None | Some("")) => ("<string>", Some(source))
    _ =>
      raise fail_with(
        "When --template is used, a template cannot be passed as argument (only an empty argument is allowed).",
      )
  }
  let output = matches.get_one("output").unwrap_or(stdin_stdout)
  let loader = FileLoader::new(
    config, template_name, template_source, stdin_used,
  )
  let env = create_env(config, io, loader)
  let out = StringBuilder()
  let mut exit_code = 0
  if matches.get_one("expr") is Some(expr) {
    let rv = loader.run(io, () => env.compile_expression(expr).eval(ctx))
    exit_code = print_expr_out(rv, config, out)
  } else if matches.get_one("dump") is Some(dump) {
    let text = loader.run(io, () => dump_info(dump, env, template_name, config))
    out.write_string(text)
  } else {
    let result = loader.run(io, () => {
      env.get_template(template_name).render(ctx)
    })
    out.write_string(result)
    if config.newline {
      out.write_char('\n')
    }
  }
  write_output(io, output, out.to_string())
  exit_code
}

///|
/// Writes the result to stdout or (atomically) to the output file.
async fn write_output(io : Io, output : String, contents : String) -> Unit {
  if output == stdin_stdout {
    io.stdout.write_string(contents)
    return
  }
  let target = path_join(io.cwd, output)
  let parent = path_parent(target)
  if parent == "" {
    raise fail_with("cannot write to root")
  }
  let tmp = path_join(parent, ".\{path_file_name(target)}.\{@env.now()}.tmp")
  @fs.write_file(tmp, @utf8.encode(contents), create_mode=CreateOrTruncate) catch {
    err => raise fail_with("unable to write output file '\{target}'", cause=err)
  }
  @fs.rename(tmp, target, replace=true) catch {
    err => {
      @fs.remove(tmp) catch {
        _ => ()
      }
      raise fail_with("unable to write output file '\{target}'", cause=err)
    }
  }
}

///|
async fn load_data(
  io : Io,
  format : String,
  path : String,
  selector : String?,
) -> (@minijinja.Value, Bool) {
  let (contents, stdin_used) = if path == stdin_stdout {
    let contents = io.stdin() catch {
      err => raise fail_with("unable to read data from stdin", cause=err)
    }
    (contents, true)
  } else {
    let contents = @fs.read_file(path_join(io.cwd, path)).binary() catch {
      err => raise fail_with("unable to read data file '\{path}'", cause=err)
    }
    (contents, false)
  }
  let format = if format == "auto" {
    if stdin_used {
      raise fail_with("auto detection does not work with data from stdin")
    }
    detect_format_from_path(path)
  } else {
    format
  }
  let mut data = parse_data(format, contents)
  if selector is Some(selector) {
    data = select_data(data, selector)
  }
  (data_to_context(data), stdin_used)
}

///|
fn create_env(
  config : Config,
  io : Io,
  loader : FileLoader,
) -> @minijinja.Environment raise CliError {
  let env = @minijinja.Environment::new()
  env.set_debug(true)
  config.apply_to_env(env, io.env_vars)
  let cwd = io.cwd
  env.set_path_join_callback((name, parent) => {
    let p = if parent == stdin_stdout {
      path_join(cwd, name)
    } else {
      path_join(path_parent(parent), name)
    }
    // upstream canonicalizes the path; this port normalizes it lexically
    normalize_path(path_join(cwd, p))
  })
  env.set_loader(name => loader.load(name))
  env
}

///|
fn dump_info(
  dump : String,
  env : @minijinja.Environment,
  template : String,
  config : Config,
) -> String raise {
  let sb = StringBuilder()
  match dump {
    "ast" => {
      let tmpl = env.get_template(template)
      sb.write_string(@minijinja.debug_ast(tmpl.source(), tmpl.name()))
      sb.write_char('\n')
    }
    "tokens" => {
      let tmpl = env.get_template(template)
      let tokens = @minijinja.debug_tokens(
        tmpl.source(),
        trim_blocks=config.trim_blocks,
        lstrip_blocks=config.lstrip_blocks,
      )
      for token in tokens {
        sb.write_string(token)
        sb.write_char('\n')
      }
    }
    "instructions" => {
      let tmpl = env.get_template(template)
      for block in tmpl.debug_instructions() {
        let (block_name, instructions) = block
        sb.write_string("Block: \{@rfmt.str_debug(block_name)}\n")
        for idx, instr in instructions {
          let idx_str = idx.to_string()
          let pad = " ".repeat(@cmp.maximum(0, 4 - idx_str.length()))
          sb.write_string("  \{pad}\{idx_str}: \{instr}\n")
        }
      }
    }
    other => raise fail_with("unknown dump kind '\{other}'")
  }
  sb.to_string()
}

///|
fn print_expr_out(
  rv : @minijinja.Value,
  config : Config,
  out : StringBuilder,
) -> Int raise {
  match config.expr_out {
    "print" => out.write_string("\{rv}\n")
    "json" => out.write_string("\{rv.to_json_string()}\n")
    "json-pretty" => out.write_string("\{rv.to_json_string(indent=2)}\n")
    "status" => {
      let n : Int? = Some(rv.convert()) catch { _ => None }
      return match n {
        Some(n) => n
        None => if rv.is_true() { 0 } else { 1 }
      }
    }
    other => raise fail_with("unknown expr-out '\{other}'")
  }
  0
}
