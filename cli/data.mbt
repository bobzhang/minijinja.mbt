// Loading of the template context from data files.

///|
fn detect_format_from_path(path : String) -> String raise CliError {
  if path_extension(path) is Some(ext) {
    let ext = ext.to_lower()
    for item in supported_formats {
      let (fmt, _, exts) = item
      if exts.contains(ext) {
        return fmt
      }
    }
  }
  raise fail_with("cannot auto detect format from extension")
}

///|
fn decode_utf8(bytes : Bytes) -> String raise CliError {
  @utf8.decode(bytes) catch {
    err => raise fail_with("invalid utf-8", cause=err)
  }
}

///|
/// Parses the raw data of a data file in the given format.
fn parse_data(
  format : String,
  contents : Bytes,
) -> @minijinja.Value raise CliError {
  match format {
    "json" => {
      let text = decode_utf8(contents)
      @minijinja.Value::from_json_str(text) catch {
        @minijinja.TemplateError(_) as err =>
          raise fail_with(err.detail().unwrap_or(err.to_string()))
      }
    }
    "querystring" => parse_querystring(@utf8.decode_lossy(contents))
    other => raise fail_with("Unknown format '\{other}'")
  }
}

///|
/// Applies a `--select` path expression (eg: `values.0.box`).
fn select_data(
  data : @minijinja.Value,
  selector : String,
) -> @minijinja.Value raise CliError {
  let mut data = data
  for part in selector.split(".") {
    let part = part.to_owned()
    let next = try {
      match parse_index(part) {
        Some(idx) => data.get_item_by_index(idx)
        None => data.get_attr(part)
      }
    } catch {
      err =>
        raise fail_with(
          "unable to select \{@rfmt.str_debug(part)} in \{@rfmt.str_debug(selector)} (value was \{data.kind()})",
          cause=err,
        )
    }
    data = next
  }
  data
}

///|
/// Parses a `usize` like Rust's `str::parse::<usize>`.
fn parse_index(s : String) -> Int? {
  let digits = if s.has_prefix("+") { s.view(start_offset=1) } else { s[:] }
  if digits.length() == 0 || digits.length() > 9 {
    return None
  }
  let mut rv = 0
  for c in digits {
    guard c is ('0'..='9') else { return None }
    rv = rv * 10 + (c.to_int() - '0'.to_int())
  }
  Some(rv)
}

///|
/// Converts the loaded data into the top-level context map (with sorted
/// keys, as upstream deserializes into a `BTreeMap<String, Value>`).
fn data_to_context(data : @minijinja.Value) -> @minijinja.Value raise CliError {
  guard data.kind() is Map else {
    raise fail_with(
      "failed to interpret input data as object",
      cause=fail_with("invalid type: \{data.kind()}, expected a map"),
    )
  }
  let m : Map[String, @minijinja.Value] = Map([])
  let keys = data.try_iter() catch {
    err =>
      raise fail_with("failed to interpret input data as object", cause=err)
  }
  for key in keys {
    let value = data.get_item(key) catch {
      err =>
        raise fail_with("failed to interpret input data as object", cause=err)
    }
    m[key.to_string()] = value
  }
  sorted_map_value(m)
}
