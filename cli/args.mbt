// Hand written command line parser that mirrors the subset of clap's
// behavior (and error messages) that upstream's `make_command` relies on.

///|
let usage_line : String = "Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]..."

///|
/// Description of a single command line option.
priv struct OptSpec {
  long : String
  short : Char?
  /// `None` for boolean flags.
  value_name : String?
  /// `<X>...`: consumes all following values that do not look like flags.
  greedy : Bool
  /// The option may be supplied multiple times.
  append : Bool
  possible_values : Array[String]
}

///|
fn opt(
  long : String,
  short? : Char,
  value? : String,
  greedy? : Bool = false,
  append? : Bool = false,
  possible_values? : Array[String] = [],
) -> OptSpec {
  { long, short, value_name: value, greedy, append, possible_values, }
}

///|
/// The supported formats (name, title, file extensions).
let supported_formats : Array[(String, String, Array[String])] = [
  ("json", "JSON", ["json"]),
  ("querystring", "Query String / Form Encoded", ["qs"]),
]

///|
let option_specs : Array[OptSpec] = [
  opt("format", short='f', value="FORMAT", possible_values=[
    "auto", "json", "querystring",
  ]),
  opt("autoescape", short='a', value="MODE", possible_values=[
    "auto", "html", "json", "none",
  ]),
  opt("define", short='D', value="EXPR", append=true),
  opt("strict"),
  opt("no-include"),
  opt("safe-path", value="PATH", greedy=true, append=true),
  opt("fuel", value="AMOUNT"),
  opt("no-newline", short='n'),
  opt("trim-blocks"),
  opt("lstrip-blocks"),
  opt("py-compat"),
  opt("syntax", short='s', value="PAIR", greedy=true, append=true),
  opt("env"),
  opt("template", short='t', value="TEMPLATE_STRING"),
  opt("expr", short='E', value="EXPR"),
  opt("expr-out", value="MODE", possible_values=[
    "print", "json", "json-pretty", "status",
  ]),
  opt("dump", value="KIND", possible_values=["instructions", "ast", "tokens"]),
  opt("output", short='o', value="FILENAME"),
  opt("select", value="SELECTOR"),
  opt("help", short='h'),
  opt("long-help"),
  opt("syntax-help"),
  opt("version", short='V'),
]

///|
fn OptSpec::display(self : OptSpec) -> String {
  match self.value_name {
    Some(v) => "--\{self.long} <\{v}>" + (if self.greedy { "..." } else { "" })
    None => "--\{self.long}"
  }
}

///|
/// The result of parsing the command line.
priv struct Matches {
  values : Map[String, Array[String]]
  flags : Map[String, Bool]
  positionals : Array[String]
}

///|
fn Matches::get_one(self : Matches, name : String) -> String? {
  match self.values.get(name) {
    Some(values) => values.last()
    None => None
  }
}

///|
fn Matches::get_many(self : Matches, name : String) -> Array[String] {
  self.values.get(name).unwrap_or([])
}

///|
fn Matches::get_flag(self : Matches, name : String) -> Bool {
  self.flags.get(name).unwrap_or(false)
}

///|
/// What parsing the command line resulted in.
priv enum ParseOutcome {
  Run(Matches)
  ShortHelp
  LongHelp
  Version
}

///|
/// Formats a clap style usage error.
fn usage_error(msg : String, with_usage? : Bool = true) -> CliError {
  let sb = StringBuilder()
  sb.write_string("error: \{msg}\n\n")
  if with_usage {
    sb.write_string("\{usage_line}\n\n")
  }
  sb.write_string("For more information, try '--help'.\n")
  UsageError(sb.to_string())
}

///|
fn possible_values_hint(spec : OptSpec) -> String {
  if spec.possible_values.is_empty() {
    ""
  } else {
    "\n  [possible values: \{spec.possible_values.join(", ")}]"
  }
}

///|
fn looks_like_flag(arg : String) -> Bool {
  arg.length() > 1 && arg.has_prefix("-")
}

///|
fn find_long(name : String) -> OptSpec? {
  for spec in option_specs {
    if spec.long == name {
      return Some(spec)
    }
  }
  None
}

///|
fn find_short(c : Char) -> OptSpec? {
  for spec in option_specs {
    if spec.short == Some(c) {
      return Some(spec)
    }
  }
  None
}

///|
fn unexpected_argument(arg : String) -> CliError {
  usage_error(
    "unexpected argument '\{arg}' found\n\n  tip: to pass '\{arg}' as a value, use '-- \{arg}'",
  )
}

///|
/// Parses the command line arguments (without the program name).
fn parse_args(args : ArrayView[String]) -> ParseOutcome raise CliError {
  let values : Map[String, Array[String]] = Map([])
  let flags : Map[String, Bool] = Map([])
  let positionals = []
  let seen : Map[String, Bool] = Map([])
  fn record(spec : OptSpec) raise CliError {
    if seen.contains(spec.long) && !spec.append {
      raise usage_error(
        "the argument '\{spec.display()}' cannot be used multiple times",
      )
    }
    seen[spec.long] = true
  }

  fn add_value(spec : OptSpec, value : String) raise CliError {
    if !spec.possible_values.is_empty() && !spec.possible_values.contains(value) {
      raise usage_error(
        "invalid value '\{value}' for '\{spec.display()}'\{possible_values_hint(spec)}",
        with_usage=false,
      )
    }
    match values.get(spec.long) {
      Some(arr) => arr.push(value)
      None => values[spec.long] = [value]
    }
  }

  fn missing_value(spec : OptSpec) -> CliError {
    usage_error(
      "a value is required for '\{spec.display()}' but none was supplied\{possible_values_hint(spec)}",
      with_usage=false,
    )
  }

  // Consumes the value(s) for `spec` starting at index `i` (the argument
  // after the option) and returns the index of the next unprocessed argument.
  fn take_values(spec : OptSpec, i : Int) -> Int raise CliError {
    guard i < args.length() && !looks_like_flag(args[i]) else {
      raise missing_value(spec)
    }
    add_value(spec, args[i])
    let mut j = i + 1
    if spec.greedy {
      while j < args.length() && !looks_like_flag(args[j]) {
        add_value(spec, args[j])
        j += 1
      }
    }
    j
  }

  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      for rest in args[i:] {
        positionals.push(rest)
      }
      break
    } else if arg.has_prefix("--") {
      let body = arg.view(start_offset=2)
      let (name, inline_value) = match body.find("=") {
        Some(idx) =>
          (
            body.view(end_offset=idx).to_owned(),
            Some(body.view(start_offset=idx + 1).to_owned()),
          )
        None => (body.to_owned(), None)
      }
      guard find_long(name) is Some(spec) else {
        raise unexpected_argument("--\{name}")
      }
      record(spec)
      match (spec.value_name, inline_value) {
        (None, Some(v)) =>
          raise usage_error(
            "unexpected value '\{v}' for '\{spec.display()}' found; no more were expected",
          )
        (None, None) =>
          match spec.long {
            "help" => return ShortHelp
            "long-help" => return LongHelp
            "version" => return Version
            _ => flags[spec.long] = true
          }
        (Some(_), Some(v)) => add_value(spec, v)
        (Some(_), None) => i = take_values(spec, i)
      }
    } else if looks_like_flag(arg) {
      // a cluster of short flags, the last of which may take a value
      let chars = arg.view(start_offset=1).to_array()
      let mut k = 0
      while k < chars.length() {
        let c = chars[k]
        k += 1
        guard find_short(c) is Some(spec) else {
          raise unexpected_argument("-\{c}")
        }
        record(spec)
        if spec.value_name is None {
          match spec.long {
            "help" => return ShortHelp
            "version" => return Version
            _ => flags[spec.long] = true
          }
          continue
        }
        let mut rest = String::from_array(chars[k:])
        if rest.has_prefix("=") {
          rest = rest.view(start_offset=1).to_owned()
        }
        if rest != "" || k < chars.length() {
          add_value(spec, rest)
        } else {
          i = take_values(spec, i)
        }
        break
      }
    } else {
      positionals.push(arg)
    }
  }
  let matches = { values, flags, positionals, }
  if matches.get_flag("no-include") && values.contains("safe-path") {
    raise usage_error(
      "the argument '--safe-path <PATH>...' cannot be used with '--no-include'",
    )
  }
  if values.contains("expr-out") && !values.contains("expr") {
    raise usage_error(
      "the following required arguments were not provided:\n  --expr <EXPR>",
    )
  }
  Run(matches)
}
