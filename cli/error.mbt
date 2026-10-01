///|
/// Errors raised by the CLI itself (template errors are raised as
/// `@minijinja.TemplateError` and reported with their debug info).
priv suberror CliError {
  /// A command line usage error; the payload is the full clap style message
  /// and the process exits with status 2.
  UsageError(String)
  /// A runtime failure (like an `anyhow` error with context): the message
  /// and an optional underlying cause.
  Failure(String, Error?)
}

///|
fn fail_with(msg : String, cause? : Error) -> CliError {
  Failure(msg, cause)
}

///|
/// Formats an error the way upstream's `print_error` does: the error, its
/// template debug info (when the error refers to a named template) and the
/// chain of causes.
fn format_error(err : Error) -> String {
  let sb = StringBuilder()
  let (msg, cause) = describe_error(err)
  sb.write_string("error: \{msg}\n")
  write_debug_info(sb, err)
  let mut next = cause
  while next is Some(source) {
    let (msg, cause) = describe_error(source)
    sb.write_string("\ncaused by: \{msg}\n")
    write_debug_info(sb, source)
    next = cause
  }
  sb.to_string()
}

///|
fn write_debug_info(sb : StringBuilder, err : Error) -> Unit {
  match err {
    @minijinja.TemplateError(_) as terr if terr.name() is Some(_) => {
      sb.write_string(terr.display_debug_info())
      sb.write_char('\n')
    }
    _ => ()
  }
}

///|
/// Returns the display message and the cause of an error.
fn describe_error(err : Error) -> (String, Error?) {
  match err {
    Failure(msg, cause) => (msg, cause)
    UsageError(msg) => (msg, None)
    @minijinja.TemplateError(_) as terr =>
      (terr.to_string(), terr.source().map(source => source))
    @os_error.OSError(_) as err => (os_error_message(err), None)
    @utf8.Malformed(_) => ("stream did not contain valid UTF-8", None)
    other => (other.to_string(), None)
  }
}

///|
/// Formats an OS error like Rust's `io::Error` (`<strerror> (os error N)`).
fn os_error_message(err : @os_error.OSError) -> String {
  let @os_error.OSError(errno, ..) = err
  // `Show` renders as `OSError("<context>: <strerror>")`; keep the strerror
  let s = err.to_string()
  let s = if s.has_suffix("\")") {
    s.view(end_offset=s.length() - 2).to_owned()
  } else {
    s
  }
  let msg = match s.rev_find(": ") {
    Some(idx) => s.view(start_offset=idx + 2).to_owned()
    None => s
  }
  "\{msg} (os error \{errno})"
}
