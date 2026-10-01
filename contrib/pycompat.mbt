///|
/// An unknown method callback implementing Python methods on primitives.
///
/// This implements a lot of Python methods on basic types so that the
/// compatibility with Jinja2 templates improves.  Register it with
/// [`@minijinja.Environment::set_unknown_method_callback`]:
///
/// ```mbt check
/// test {
///   let env = @minijinja.Environment::new()
///   env.set_unknown_method_callback(@contrib.unknown_method_callback)
///   inspect(
///     env.render_str("{{ 'hello'.upper() }}", @minijinja.Value::none()),
///     content="HELLO",
///   )
/// }
/// ```
///
/// Today the following methods are implemented:
///
/// * `dict.get`
/// * `dict.items`
/// * `dict.keys`
/// * `dict.values`
/// * `list.count`
/// * `str.capitalize`
/// * `str.count`
/// * `str.endswith`
/// * `str.find`
/// * `str.format`
/// * `str.isalnum`
/// * `str.isalpha`
/// * `str.isascii`
/// * `str.isdigit`
/// * `str.islower`
/// * `str.isnumeric`
/// * `str.isspace`
/// * `str.isupper`
/// * `str.join`
/// * `str.lower`
/// * `str.lstrip`
/// * `str.replace`
/// * `str.rfind`
/// * `str.rstrip`
/// * `str.split`
/// * `str.splitlines`
/// * `str.startswith`
/// * `str.strip`
/// * `str.title`
/// * `str.upper`
///
/// Differences to upstream: `str.find` and `str.rfind` return indexes in
/// Unicode scalar values (characters) instead of UTF-8 byte offsets (this is
/// identical for ASCII strings and closer to Python), and `str.count('')`
/// returns the number of characters plus one like Python instead of looping
/// forever.
pub fn unknown_method_callback(
  state : @minijinja.State,
  value : @minijinja.Value,
  name : String,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  match value.kind() {
    String => string_methods(state, value, name, args)
    Map => map_methods(state, value, name, args)
    Seq => seq_methods(state, value, name, args)
    _ => raise @minijinja.TemplateError::from_kind(UnknownMethod)
  }
}

///|
fn unknown_method() -> @minijinja.TemplateError {
  @minijinja.TemplateError::from_kind(UnknownMethod)
}

///|
/// Port of `let () = from_args(args)?;`.
fn no_args(
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> Unit raise @minijinja.TemplateError {
  @minijinja.Args::new(state, args).finish()
}

///|
/// Calls one of the core filters directly (upstream calls into
/// `minijinja::filters::*`).
fn call_builtin_filter(
  name : String,
  state : @minijinja.State,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  match @minijinja.builtin_filter(name) {
    Some(filter) => filter.call(state, args)
    None => raise @minijinja.TemplateError::from_kind(UnknownFilter)
  }
}

///|
fn all_chars(s : String, pred : (Char) -> Bool) -> @minijinja.Value {
  @minijinja.Value::from_bool(s.iter().all(pred))
}

///|
fn string_methods(
  state : @minijinja.State,
  value : @minijinja.Value,
  name : String,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  guard value.as_str() is Some(s) else { raise unknown_method() }
  match name {
    "upper" => {
      no_args(state, args)
      @minijinja.Value::from_string(@unicode.to_upper(s))
    }
    "lower" => {
      no_args(state, args)
      @minijinja.Value::from_string(@unicode.to_lower(s))
    }
    "islower" => {
      no_args(state, args)
      all_chars(s, @unicode.is_lowercase)
    }
    "isupper" => {
      no_args(state, args)
      all_chars(s, @unicode.is_uppercase)
    }
    "isspace" => {
      no_args(state, args)
      all_chars(s, @unicode.is_whitespace)
    }
    // this is not a perfect mapping to what Python does, but close enough
    // for most uses in templates.
    "isdigit" | "isnumeric" => {
      no_args(state, args)
      all_chars(s, @unicode.is_numeric)
    }
    "isalnum" => {
      no_args(state, args)
      all_chars(s, @unicode.is_alphanumeric)
    }
    "isalpha" => {
      no_args(state, args)
      all_chars(s, @unicode.is_alphabetic)
    }
    "isascii" => {
      no_args(state, args)
      all_chars(s, c => c.to_int() < 0x80)
    }
    "strip" | "lstrip" | "rstrip" => {
      let a = @minijinja.Args::new(state, args)
      let chars = a.opt_str()
      a.finish()
      let left = name != "rstrip"
      let right = name != "lstrip"
      let rv = match chars {
        Some(chars) => {
          let set = chars.iter().to_array()
          trim_matches(s, c => set.contains(c), left~, right~)
        }
        None => trim_matches(s, @unicode.is_whitespace, left~, right~)
      }
      @minijinja.Value::from_string(rv.to_owned())
    }
    "replace" => {
      let a = @minijinja.Args::new(state, args)
      let old = a.str()
      let new = a.str()
      let count = a.opt_i32()
      a.finish()
      let count = count.unwrap_or(-1)
      @minijinja.Value::from_string(
        rust_replacen(s, old, new, if count < 0 { None } else { Some(count) }),
      )
    }
    "title" => {
      no_args(state, args)
      // one shall not call into these filters.  However we consider
      // ourselves privileged.
      call_builtin_filter("title", state, [@minijinja.Value::from_string(s)])
    }
    "split" => {
      // argument checking (`sep`, `maxsplits`) is done by the filter
      let rv = call_builtin_filter("split", state, [value, ..args])
      @minijinja.Value::from_array(rv.try_iter().to_array())
    }
    "splitlines" => {
      let a = @minijinja.Args::new(state, args)
      let keepends = a.opt_bool()
      a.finish()
      if !keepends.unwrap_or(false) {
        @minijinja.Value::from_array(
          rust_lines(s).map(@minijinja.Value::from_string),
        )
      } else {
        let rv = []
        let mut rest = s[:]
        while rest.find("\n") is Some(offset) {
          rv.push(@minijinja.Value::from_string(rest[:offset + 1].to_owned()))
          rest = rest[offset + 1:]
        }
        if !rest.is_empty() {
          rv.push(@minijinja.Value::from_string(rest.to_owned()))
        }
        @minijinja.Value::from_array(rv)
      }
    }
    "capitalize" => {
      no_args(state, args)
      call_builtin_filter("capitalize", state, [value])
    }
    "count" => {
      let a = @minijinja.Args::new(state, args)
      let what = a.str()
      a.finish()
      if what.is_empty() {
        // Python semantics (upstream would loop forever here)
        return @minijinja.Value::from_int(s.char_length() + 1)
      }
      let mut c = 0
      let mut rest = s[:]
      while rest.find(what) is Some(offset) {
        c += 1
        rest = rest[offset + what.length():]
      }
      @minijinja.Value::from_int(c)
    }
    "find" | "rfind" => {
      let a = @minijinja.Args::new(state, args)
      let what = a.str()
      a.finish()
      let found = if name == "find" { s.find(what) } else { s.rev_find(what) }
      @minijinja.Value::from_int(
        match found {
          Some(offset) => s.char_length(end_offset=offset)
          None => -1
        },
      )
    }
    "format" =>
      @minijinja.Value::from_string(
        @minijinja.format_string(StrFormat, s, args),
      )
    "startswith" | "endswith" => {
      let a = @minijinja.Args::new(state, args)
      let arg = a.value()
      a.finish()
      let check = (x : String) => {
        if name == "startswith" {
          s.has_prefix(x)
        } else {
          s.has_suffix(x)
        }
      }
      match arg.as_str() {
        Some(x) => @minijinja.Value::from_bool(check(x))
        None =>
          match arg.kind() {
            Iterable | Seq => {
              for item in arg.try_iter() {
                guard item.as_str() is Some(x) else {
                  raise @minijinja.TemplateError::new(
                    InvalidOperation,
                    "tuple for \{name} must contain only strings, not \{item.kind()}",
                  )
                }
                if check(x) {
                  return @minijinja.Value::from_bool(true)
                }
              }
              @minijinja.Value::from_bool(false)
            }
            kind =>
              raise @minijinja.TemplateError::new(
                InvalidOperation,
                "\{name} argument must be string or a tuple of strings, not \{kind}",
              )
          }
      }
    }
    "join" => {
      let a = @minijinja.Args::new(state, args)
      let values = a.value()
      a.finish()
      let rv = StringBuilder()
      for idx, item in values.try_iter().to_array() {
        if idx > 0 {
          rv.write_string(s)
        }
        rv.write_string(item.to_string())
      }
      @minijinja.Value::from_string(rv.to_string())
    }
    _ => raise unknown_method()
  }
}

///|
fn map_methods(
  state : @minijinja.State,
  value : @minijinja.Value,
  name : String,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  guard value.as_object() is Some(obj) else { raise unknown_method() }
  match name {
    "keys" => {
      no_args(state, args)
      @minijinja.Value::make_iterable(() => obj.try_iter().unwrap_or([||]))
    }
    "values" => {
      no_args(state, args)
      @minijinja.Value::make_iterable(() => {
        match obj.try_iter_pairs() {
          Some(iter) => iter.map(pair => pair.1)
          None => [||]
        }
      })
    }
    "items" => {
      no_args(state, args)
      @minijinja.Value::make_iterable(() => {
        match obj.try_iter_pairs() {
          Some(iter) =>
            iter.map(pair => @minijinja.Value::from_tuple([pair.0, pair.1]))
          None => [||]
        }
      })
    }
    "get" => {
      let a = @minijinja.Args::new(state, args)
      let key = a.value()
      let default = a.opt_value()
      a.finish()
      match obj.get_value(key) {
        Some(value) => value
        None => default.unwrap_or(@minijinja.Value::none())
      }
    }
    _ => raise unknown_method()
  }
}

///|
fn seq_methods(
  state : @minijinja.State,
  value : @minijinja.Value,
  name : String,
  args : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  guard value.as_object() is Some(obj) else { raise unknown_method() }
  match name {
    "count" => {
      let a = @minijinja.Args::new(state, args)
      let what = a.value()
      a.finish()
      let count = match obj.try_iter() {
        Some(iter) => iter.filter(x => x == what).count()
        None => 0
      }
      @minijinja.Value::from_int(count)
    }
    _ => raise unknown_method()
  }
}

///|
/// Port of `str::trim_matches` / `trim_start_matches` / `trim_end_matches`
/// with a character predicate.
fn trim_matches(
  s : String,
  pred : (Char) -> Bool,
  left~ : Bool,
  right~ : Bool,
) -> StringView {
  let mut view = s[:]
  if left {
    while view is [c, .. rest] && pred(c) {
      view = rest
    }
  }
  if right {
    while view is [.. rest, c] && pred(c) {
      view = rest
    }
  }
  view
}

///|
/// Port of Rust's `str::replacen` (`limit = None` is `str::replace`).  An
/// empty pattern matches at every character boundary.
fn rust_replacen(
  s : String,
  old : String,
  new : String,
  limit : Int?,
) -> String {
  let limit = limit.unwrap_or(0x7FFFFFFF)
  let rv = StringBuilder()
  let mut replaced = 0
  if old.is_empty() {
    for c in s {
      if replaced < limit {
        rv.write_string(new)
        replaced += 1
      }
      rv.write_char(c)
    }
    if replaced < limit {
      rv.write_string(new)
    }
    return rv.to_string()
  }
  let mut rest = s[:]
  while replaced < limit && rest.find(old) is Some(offset) {
    rv.write_view(rest[:offset])
    rv.write_string(new)
    rest = rest[offset + old.length():]
    replaced += 1
  }
  rv.write_view(rest)
  rv.to_string()
}

///|
/// Port of Rust's `str::lines`: splits on `\n`, strips a trailing `\r` from
/// every line and does not yield a final empty line.
fn rust_lines(s : StringView) -> Array[String] {
  let rv = []
  let mut rest = s
  while !rest.is_empty() {
    match rest.find("\n") {
      Some(offset) => {
        let line = rest[:offset]
        let line = if line is [.. head, '\r'] { head } else { line }
        rv.push(line.to_owned())
        rest = rest[offset + 1:]
      }
      None => {
        rv.push(rest.to_owned())
        break
      }
    }
  }
  rv
}
