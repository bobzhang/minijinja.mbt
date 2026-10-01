///|
/// An abstraction over output targets with support for capturing.
///
/// Captures nest: `begin_capture` starts a new capture (or a discarding
/// capture) and `end_capture` returns what was captured as a value.
pub struct Output {
  priv target : StringBuilder
  /// An optional sink that receives the (non captured) output instead of
  /// `target` when rendering in streaming mode.
  priv sink : ((StringView) -> Unit raise)?
  priv capture_stack : Array[StringBuilder?]
}

///|
fn Output::new(target : StringBuilder) -> Output {
  { target, sink: None, capture_stack: [], }
}

///|
fn Output::with_sink(sink : (StringView) -> Unit raise) -> Output {
  { target: StringBuilder(), sink: Some(sink), capture_stack: [], }
}

///|
fn Output::write_to_root(
  self : Output,
  s : StringView,
) -> Unit raise TemplateError {
  match self.sink {
    None => self.target.write_view(s)
    Some(sink) =>
      sink(s) catch {
        err =>
          raise TemplateError::new(
            WriteFailure,
            "error during rendering: \{err}",
          )
      }
  }
}

///|
/// An output that discards everything.
fn Output::null() -> Output {
  { target: StringBuilder(), sink: None, capture_stack: [None], }
}

///|
fn Output::begin_capture(self : Output, mode : CaptureMode) -> Unit {
  self.capture_stack.push(
    match mode {
      Capture => Some(StringBuilder())
      Discard => None
    },
  )
}

///|
fn Output::end_capture(self : Output, auto_escape : AutoEscape) -> Value {
  match self.capture_stack.pop() {
    Some(Some(captured)) =>
      if auto_escape is NoEscape {
        Value::from_string(captured.to_string())
      } else {
        Value::from_safe_string(captured.to_string())
      }
    _ => Value::undefined()
  }
}

///|
fn Output::is_discarding(self : Output) -> Bool {
  self.capture_stack.last() is Some(None)
}

///|
/// Writes a string to the output.
pub fn Output::write_str(
  self : Output,
  s : StringView,
) -> Unit raise TemplateError {
  match self.capture_stack.last() {
    Some(Some(sb)) => sb.write_view(s)
    Some(None) => ()
    None => self.write_to_root(s)
  }
}

///|
/// Writes a character to the output.
pub fn Output::write_char(self : Output, c : Char) -> Unit raise TemplateError {
  match self.capture_stack.last() {
    Some(Some(sb)) => sb.write_char(c)
    Some(None) => ()
    None => self.write_to_root(c.to_string())
  }
}
