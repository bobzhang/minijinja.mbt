///|
/// An enum describing the error kind.
pub(all) enum ErrorKind {
  /// A non primitive value was encountered where one was expected.
  NonPrimitive
  /// A value is not valid for a key in a map.
  NonKey
  /// An invalid operation was attempted.
  InvalidOperation
  /// The template has a syntax error
  SyntaxError
  /// A template was not found.
  TemplateNotFound
  /// Too many arguments were passed to a function.
  TooManyArguments
  /// A expected argument was missing
  MissingArgument
  /// A filter is unknown
  UnknownFilter
  /// A test is unknown
  UnknownTest
  /// A function is unknown
  UnknownFunction
  /// Un unknown method was called
  UnknownMethod
  /// A bad escape sequence in a string was encountered.
  BadEscape
  /// An operation on an undefined value was attempted.
  UndefinedError
  /// Not able to serialize this value.
  BadSerialization
  /// Not able to deserialize this value.
  CannotDeserialize
  /// An error happened in an include.
  BadInclude
  /// An error happened in a super block.
  EvalBlock
  /// Unable to unpack a value.
  CannotUnpack
  /// Failed writing output.
  WriteFailure
  /// Engine ran out of fuel
  OutOfFuel
  /// Invalid custom delimiters
  InvalidDelimiter
  /// A block is unknown
  UnknownBlock
} derive(Eq, Hash, Debug)

///|
/// The name of the kind as Rust's `Debug` would print it.
pub fn ErrorKind::name(self : ErrorKind) -> String {
  match self {
    NonPrimitive => "NonPrimitive"
    NonKey => "NonKey"
    InvalidOperation => "InvalidOperation"
    SyntaxError => "SyntaxError"
    TemplateNotFound => "TemplateNotFound"
    TooManyArguments => "TooManyArguments"
    MissingArgument => "MissingArgument"
    UnknownFilter => "UnknownFilter"
    UnknownTest => "UnknownTest"
    UnknownFunction => "UnknownFunction"
    UnknownMethod => "UnknownMethod"
    BadEscape => "BadEscape"
    UndefinedError => "UndefinedError"
    BadSerialization => "BadSerialization"
    CannotDeserialize => "CannotDeserialize"
    BadInclude => "BadInclude"
    EvalBlock => "EvalBlock"
    CannotUnpack => "CannotUnpack"
    WriteFailure => "WriteFailure"
    OutOfFuel => "OutOfFuel"
    InvalidDelimiter => "InvalidDelimiter"
    UnknownBlock => "UnknownBlock"
  }
}

///|
/// A short human readable description of the kind.
pub fn ErrorKind::description(self : ErrorKind) -> String {
  match self {
    NonPrimitive => "not a primitive"
    NonKey => "not a key type"
    InvalidOperation => "invalid operation"
    SyntaxError => "syntax error"
    TemplateNotFound => "template not found"
    TooManyArguments => "too many arguments"
    MissingArgument => "missing argument"
    UnknownFilter => "unknown filter"
    UnknownFunction => "unknown function"
    UnknownTest => "unknown test"
    UnknownMethod => "unknown method"
    BadEscape => "bad string escape"
    UndefinedError => "undefined value"
    BadSerialization => "could not serialize to value"
    BadInclude => "could not render include"
    EvalBlock => "could not render block"
    CannotUnpack => "cannot unpack"
    WriteFailure => "failed to write output"
    CannotDeserialize => "cannot deserialize"
    OutOfFuel => "engine ran out of fuel"
    InvalidDelimiter => "invalid custom delimiters"
    UnknownBlock => "unknown block"
  }
}

///|
pub impl Show for ErrorKind with fn output(self, logger) {
  logger.write_string(self.description())
}

///|
/// Debug information that is attached to errors raised during rendering.
priv struct DebugInfo {
  template_source : String?
  referenced_locals : Map[String, Value]
}

///|
struct ErrorData {
  kind : ErrorKind
  mut detail : String?
  mut name : String?
  mut lineno : Int
  mut span : Span?
  mut source : TemplateError?
  mut debug_info : DebugInfo?
}

///|
/// Represents template errors.
///
/// Errors carry a [`ErrorKind`], an optional detail message, and — once the
/// engine knows about it — the name of the template and the location in it.
pub suberror TemplateError {
  TemplateError(ErrorData)
}

///|
fn TemplateError::data(self : TemplateError) -> ErrorData {
  match self {
    TemplateError(d) => d
  }
}

///|
/// Creates a new error with a kind and a detail message.
pub fn TemplateError::new(kind : ErrorKind, detail : String) -> TemplateError {
  TemplateError({
    kind,
    detail: Some(detail),
    name: None,
    lineno: 0,
    span: None,
    source: None,
    debug_info: None,
  })
}

///|
/// Creates a new error with just a kind.
pub fn TemplateError::from_kind(kind : ErrorKind) -> TemplateError {
  TemplateError({
    kind,
    detail: None,
    name: None,
    lineno: 0,
    span: None,
    source: None,
    debug_info: None,
  })
}

///|
fn TemplateError::new_not_found(name : String) -> TemplateError {
  TemplateError::new(
    TemplateNotFound,
    "template \{@rfmt.str_debug(name)} does not exist",
  )
}

///|
/// Returns a copy of the error that does not share mutable state.
fn TemplateError::internal_clone(self : TemplateError) -> TemplateError {
  let d = self.data()
  TemplateError({
    kind: d.kind,
    detail: d.detail,
    name: d.name,
    lineno: d.lineno,
    span: d.span,
    source: d.source,
    debug_info: d.debug_info,
  })
}

///|
/// Attaches another error as source to this error.
pub fn TemplateError::with_source(
  self : TemplateError,
  source : TemplateError,
) -> TemplateError {
  self.data().source = Some(source)
  self
}

///|
/// Returns the error kind.
pub fn TemplateError::kind(self : TemplateError) -> ErrorKind {
  self.data().kind
}

///|
/// Returns the error detail.
pub fn TemplateError::detail(self : TemplateError) -> String? {
  self.data().detail
}

///|
fn TemplateError::set_detail(self : TemplateError, detail : String) -> Unit {
  self.data().detail = Some(detail)
}

///|
/// Returns the filename of the template that caused the error.
pub fn TemplateError::name(self : TemplateError) -> String? {
  self.data().name
}

///|
/// Returns the line number where the error occurred.
pub fn TemplateError::line(self : TemplateError) -> Int? {
  let lineno = self.data().lineno
  if lineno > 0 {
    Some(lineno)
  } else {
    None
  }
}

///|
/// Returns the source error if there is one.
pub fn TemplateError::source(self : TemplateError) -> TemplateError? {
  self.data().source
}

///|
/// Returns the span of the error in the template source, if known.
pub fn TemplateError::span(self : TemplateError) -> Span? {
  self.data().span
}

///|
/// Returns the byte range of where the error occurred if available.  In
/// MoonBit the offsets are UTF-16 code unit offsets into the source.
pub fn TemplateError::range(self : TemplateError) -> (Int, Int)? {
  match self.data().span {
    Some(span) => Some((span.start_offset, span.end_offset))
    None => None
  }
}

///|
fn TemplateError::set_filename_and_line(
  self : TemplateError,
  filename : String,
  lineno : Int,
) -> Unit {
  let d = self.data()
  d.name = Some(filename)
  d.lineno = lineno
}

///|
fn TemplateError::set_filename_and_span(
  self : TemplateError,
  filename : String,
  span : Span,
) -> Unit {
  let d = self.data()
  d.name = Some(filename)
  d.span = Some(span)
  d.lineno = span.start_line
}

///|
fn TemplateError::debug_info(self : TemplateError) -> DebugInfo? {
  self.data().debug_info
}

///|
fn TemplateError::attach_debug_info(
  self : TemplateError,
  info : DebugInfo,
) -> Unit {
  self.data().debug_info = Some(info)
}

///|
/// Returns the template source if available.
pub fn TemplateError::template_source(self : TemplateError) -> String? {
  match self.data().debug_info {
    Some(info) => info.template_source
    None => None
  }
}

///|
/// Formats the error like Rust's `Display` (`{}`).
pub fn TemplateError::to_string(self : TemplateError) -> String {
  let sb = StringBuilder()
  self.write_display(sb, false)
  sb.to_string()
}

///|
/// Formats the error like Rust's alternate `Display` (`{:#}`) which includes
/// the debug info (template source excerpt and referenced variables).
pub fn TemplateError::display_with_debug_info(self : TemplateError) -> String {
  let sb = StringBuilder()
  self.write_display(sb, true)
  sb.to_string()
}

///|
fn TemplateError::write_display(
  self : TemplateError,
  sb : StringBuilder,
  alternate : Bool,
) -> Unit {
  let d = self.data()
  match d.detail {
    Some(detail) => {
      sb.write_string(d.kind.description())
      sb.write_string(": ")
      sb.write_string(detail)
    }
    None => sb.write_string(d.kind.description())
  }
  if d.name is Some(name) {
    sb.write_string(" (in \{name}:\{self.line().unwrap_or(0)})")
  }
  if alternate && d.debug_info is Some(info) {
    sb.write_string(self.render_debug_info(info))
  }
}

///|
/// Renders only the debug info section of the error.
pub fn TemplateError::display_debug_info(self : TemplateError) -> String {
  match self.data().debug_info {
    Some(info) => self.render_debug_info(info)
    None => ""
  }
}

///|
pub impl Show for TemplateError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Formats the error like Rust's `Debug` (`{:?}` or `{:#?}` when `pretty`
/// is set).  This does not include the debug info.
pub fn TemplateError::debug_string(
  self : TemplateError,
  pretty? : Bool = false,
) -> String {
  let f = @rfmt.Formatter::new(alternate=pretty)
  self.fmt_debug(f)
  f.to_string()
}

///|
fn TemplateError::fmt_debug(self : TemplateError, f : @rfmt.Formatter) -> Unit {
  let d = self.data()
  let s = f.debug_struct("Error")
  s.field("kind", f => f.write_str(d.kind.name())) |> ignore
  if d.detail is Some(detail) {
    s.field("detail", f => f.write_str(@rfmt.str_debug(detail))) |> ignore
  }
  if d.name is Some(name) {
    s.field("name", f => f.write_str(@rfmt.str_debug(name))) |> ignore
  }
  if self.line() is Some(line) {
    s.field("line", f => f.write_str(line.to_string())) |> ignore
  }
  if d.source is Some(source) {
    s.field("source", f => source.fmt_debug(f)) |> ignore
  }
  s.finish()
}

///|
fn TemplateError::render_debug_info(
  self : TemplateError,
  info : DebugInfo,
) -> String {
  let d = self.data()
  let sb = StringBuilder()
  if info.template_source is Some(source) {
    let name = d.name.unwrap_or("")
    let base = match name.rev_find("/") {
      Some(idx) => name.view(start_offset=idx + 1).to_owned()
      None => name
    }
    let base = match base.rev_find("\\") {
      Some(idx) => base.view(start_offset=idx + 1).to_owned()
      None => base
    }
    let title = " \{base} "
    sb.write_char('\n')
    sb.write_string(center_pad(title, 79, '-'))
    sb.write_char('\n')
    let lines = rust_lines(source)
    let idx = {
      let l = self.line().unwrap_or(1) - 1
      if l < 0 {
        0
      } else {
        l
      }
    }
    let skip = if idx - 3 < 0 { 0 } else { idx - 3 }
    let pre_count = if idx < 3 { idx } else { 3 }
    for i in skip..<(skip + pre_count) {
      if i < lines.length() {
        sb.write_string(
          "\{right_align((i + 1).to_string(), 4)} | \{lines[i]}\n",
        )
      }
    }
    if idx < lines.length() {
      sb.write_string(
        "\{right_align((idx + 1).to_string(), 4)} > \{lines[idx]}\n",
      )
    }
    if d.span is Some(span) && span.start_line == span.end_line {
      sb.write_string("     i ")
      for _ in 0..<span.start_col {
        sb.write_char(' ')
      }
      for _ in 0..<(span.end_col - span.start_col) {
        sb.write_char('^')
      }
      sb.write_string(" \{d.kind}\n")
    }
    for i in (idx + 1)..<(idx + 4) {
      if i < lines.length() {
        sb.write_string(
          "\{right_align((i + 1).to_string(), 4)} | \{lines[i]}\n",
        )
      }
    }
    sb.write_string(center_pad("", 79, '~'))
  }
  sb.write_char('\n')
  let f = @rfmt.Formatter::new(alternate=true)
  let vars = info.referenced_locals
  if vars.is_empty() {
    f.write_str("No referenced variables")
  } else {
    let keys = vars.keys().to_array()
    keys.sort_by((a, b) => compare_str(a, b))
    let s = f.debug_struct("Referenced variables:")
    for key in keys {
      s.field(key, f => vars[key].fmt_debug(f)) |> ignore
    }
    s.finish()
  }
  sb.write_string(f.to_string())
  sb.write_char('\n')
  sb.write_string(center_pad("", 79, '-'))
  sb.to_string()
}

///|
/// Port of Rust's `{:^width$}` with a fill character.
fn center_pad(s : String, width : Int, fill : Char) -> String {
  let len = s.char_length()
  if len >= width {
    return s
  }
  let total = width - len
  let left = total / 2
  let right = total - left
  let sb = StringBuilder()
  for _ in 0..<left {
    sb.write_char(fill)
  }
  sb.write_string(s)
  for _ in 0..<right {
    sb.write_char(fill)
  }
  sb.to_string()
}

///|
/// Port of Rust's `{:>width$}`.
fn right_align(s : String, width : Int) -> String {
  let len = s.char_length()
  if len >= width {
    return s
  }
  let sb = StringBuilder()
  for _ in 0..<(width - len) {
    sb.write_char(' ')
  }
  sb.write_string(s)
  sb.to_string()
}

///|
/// Port of Rust's `str::lines` (splits on `\n`, strips a trailing `\r`, and
/// does not yield a final empty line).
fn rust_lines(s : String) -> Array[String] {
  let rv = []
  let mut start = 0
  let len = s.length()
  while start < len {
    let mut end = start
    while end < len && s[end] != '\n' {
      end += 1
    }
    let mut line_end = end
    if line_end > start && s[line_end - 1] == '\r' {
      line_end -= 1
    }
    rv.push(s.view(start_offset=start, end_offset=line_end).to_owned())
    start = end + 1
  }
  rv
}

///|
pub impl @debug.Debug for TemplateError with fn to_repr(self) {
  @debug.Repr::Repr(self.debug_string())
}
