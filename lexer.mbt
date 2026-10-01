///|
priv enum LexerState {
  Template
  Variable
  Block
  LineStatement
}

///|
/// Utility enum that defines a marker.
priv enum StartMarker {
  Variable
  Block
  Comment
  LineStatement
  LineComment
} derive(Eq)

///|
/// What ends this block tokenization?
priv enum BlockSentinel {
  Variable
  Block
  LineStatement
} derive(Eq)

///|
priv enum Whitespace {
  Default
  Preserve
  Remove
} derive(Eq)

///|
fn Whitespace::from_unit(u : Int) -> Whitespace {
  if u == '-'.to_int() {
    Remove
  } else if u == '+'.to_int() {
    Preserve
  } else {
    Default
  }
}

///|
fn Whitespace::len(self : Whitespace) -> Int {
  match self {
    Default => 0
    Preserve | Remove => 1
  }
}

///|
fn is_nl(c : Char) -> Bool {
  c == '\r' || c == '\n'
}

///|
fn find_start_marker_memchr(
  source : String,
  offset : Int,
) -> (Int, StartMarker, Int, Whitespace)? {
  let len = source.length()
  let mut i = offset
  while i < len {
    if source[i] == '{' {
      let marker = match unit_at(source, i + 1) {
        0x7B => Some(StartMarker::Variable) // {
        0x25 => Some(StartMarker::Block) // %
        0x23 => Some(StartMarker::Comment) // #
        _ => None
      }
      if marker is Some(marker) {
        let ws = Whitespace::from_unit(unit_at(source, i + 2))
        return Some((i - offset, marker, 2 + ws.len(), ws))
      }
    }
    i += 1
  }
  None
}

///|
fn find_start_marker(
  source : String,
  offset : Int,
  syntax_config : SyntaxConfig,
) -> (Int, StartMarker, Int, Whitespace)? {
  if syntax_config.is_default {
    return find_start_marker_memchr(source, offset)
  }
  let patterns : Array[(String, StartMarker)] = []
  patterns.push((syntax_config.variable_start, StartMarker::Variable))
  patterns.push((syntax_config.block_start, StartMarker::Block))
  patterns.push((syntax_config.comment_start, StartMarker::Comment))
  if syntax_config.line_statement_prefix != "" {
    patterns.push(
      (syntax_config.line_statement_prefix, StartMarker::LineStatement),
    )
  }
  if syntax_config.line_comment_prefix != "" {
    patterns.push((syntax_config.line_comment_prefix, StartMarker::LineComment))
  }
  let len = source.length()
  for pos in offset..<len {
    let mut best : (Int, StartMarker, Int, Whitespace)? = None
    let mut best_len = -1
    for pattern in patterns {
      let (delim, marker) = pattern
      if !starts_with_at(source, pos, delim) {
        continue
      }
      let ws = if marker == StartMarker::LineStatement {
        // line statements are only valid at the start of a line (after
        // optional spaces and tabs).
        let mut j = pos - 1
        while j >= 0 && (source[j] == ' ' || source[j] == '\t') {
          j -= 1
        }
        if j >= 0 && source[j] != '\r' && source[j] != '\n' {
          continue
        }
        Whitespace::Default
      } else {
        Whitespace::from_unit(unit_at(source, pos + delim.length()))
      }
      if delim.length() > best_len {
        best_len = delim.length()
        best = Some((pos - offset, marker, delim.length() + ws.len(), ws))
      }
    }
    if best is Some(_) {
      return best
    }
  }
  None
}

///|
/// Returns the length (in UTF-16 code units) of the identifier at `offset`.
fn lex_identifier(s : String, offset : Int) -> Int {
  let mut i = offset
  let mut idx = 0
  while char_at(s, i) is Some(c) {
    let cont = if c == '_' {
      true
    } else if idx == 0 {
      @unicode.is_xid_start(c)
    } else {
      @unicode.is_xid_continue(c)
    }
    if !cont {
      break
    }
    i += c.utf16_len()
    idx += 1
  }
  i - offset
}

///|
/// Returns `(was_nl, skip)`.
fn skip_nl(s : String, offset : Int) -> (Bool, Int) {
  let mut skip = 0
  let mut was_nl = false
  if unit_at(s, offset) == '\n'.to_int() {
    skip += 1
    was_nl = true
  }
  if unit_at(s, offset + skip) == '\r'.to_int() {
    skip += 1
    was_nl = true
  }
  (was_nl || offset + skip >= s.length(), skip)
}

///|
fn lstrip_block(s : StringView) -> StringView {
  let mut end = s.length()
  while end > 0 {
    let u = s[end - 1].to_int()
    if u >= 0xD800 && u <= 0xDFFF {
      break
    }
    let c = u.unsafe_to_char()
    if is_rust_whitespace(c) && !is_nl(c) {
      end -= 1
    } else {
      break
    }
  }
  let trimmed = s.view(end_offset=end)
  if trimmed.length() == 0 || trimmed[trimmed.length() - 1] == '\n' {
    trimmed
  } else {
    s
  }
}

///|
fn should_lstrip_block(
  flag : Bool,
  marker : StartMarker,
  source : String,
  prefix_end : Int,
) -> Bool {
  if flag && marker != StartMarker::Variable {
    // Only strip if we're at the start of a line
    let mut i = prefix_end - 1
    while i >= 0 {
      let u = source[i].to_int()
      if u >= 0xDC00 && u <= 0xDFFF {
        return false
      }
      let c = u.unsafe_to_char()
      if is_nl(c) {
        return true
      } else if !is_rust_whitespace(c) {
        return false
      }
      i -= 1
    }
    // If we get here, we're at the start of the file
    return true
  }
  marker == StartMarker::LineStatement || marker == StartMarker::LineComment
}

///|
fn skip_basic_tag(
  source : String,
  offset : Int,
  name : String,
  block_end : String,
  skip_ws_control : Bool,
) -> (Int, Whitespace)? {
  let mut ptr = offset
  if skip_ws_control {
    let u = unit_at(source, ptr)
    if u == '-'.to_int() || u == '+'.to_int() {
      ptr += 1
    }
  }
  while is_ascii_ws_unit(unit_at(source, ptr)) {
    ptr += 1
  }
  if !starts_with_at(source, ptr, name) {
    return None
  }
  ptr += name.length()
  while is_ascii_ws_unit(unit_at(source, ptr)) {
    ptr += 1
  }
  let ws = if unit_at(source, ptr) == '-'.to_int() {
    ptr += 1
    Whitespace::Remove
  } else if unit_at(source, ptr) == '+'.to_int() {
    ptr += 1
    Whitespace::Preserve
  } else {
    Whitespace::Default
  }
  if starts_with_at(source, ptr, block_end) {
    Some((ptr + block_end.length() - offset, ws))
  } else {
    None
  }
}

///|
/// Tokenizes jinja templates.
priv struct Tokenizer {
  stack : Array[LexerState]
  source : String
  filename : String
  mut current_line : Int
  mut current_col : Int
  mut current_offset : Int
  mut trim_leading_whitespace : Bool
  mut pending_start_marker : (StartMarker, Int)?
  mut paren_balance : Int
  syntax_config : SyntaxConfig
  ws_config : WhitespaceConfig
}

///|
fn Tokenizer::new(
  input : String,
  filename : String,
  in_expr : Bool,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
) -> Tokenizer {
  let stack = [if in_expr { LexerState::Variable } else { Template }]
  let mut source = input
  if !ws_config.keep_trailing_newline {
    if source.has_suffix("\n") {
      source = source.view(end_offset=source.length() - 1).to_owned()
    }
    if source.has_suffix("\r") {
      source = source.view(end_offset=source.length() - 1).to_owned()
    }
  }
  {
    stack,
    source,
    filename,
    current_line: 1,
    current_col: 0,
    current_offset: 0,
    trim_leading_whitespace: false,
    pending_start_marker: None,
    paren_balance: 0,
    syntax_config,
    ws_config,
  }
}

///|
/// Produces the next token from the tokenizer.
fn Tokenizer::next_token(
  self : Tokenizer,
) -> (Token, Span)? raise TemplateError {
  for ;; {
    if self.current_offset >= self.source.length() {
      // line statements normally close with newlines.  At the end of the
      // file however we need to use the stack to close out the block.
      if self.stack.pop() is Some(LineStatement) {
        return Some(
          (
            BlockEnd,
            self.span_from(
              self.current_line,
              self.current_col,
              self.current_offset,
            ),
          ),
        )
      }
      return None
    }
    let depth = self.stack.length()
    if depth == 0 {
      abort("empty lexer stack")
    }
    let outcome = match self.stack[depth - 1] {
      Template => self.tokenize_root()
      Block => self.tokenize_block_or_var(BlockSentinel::Block)
      LineStatement => self.tokenize_block_or_var(BlockSentinel::LineStatement)
      Variable => self.tokenize_block_or_var(BlockSentinel::Variable)
    }
    if outcome is Some(_) {
      return outcome
    }
  }
}

///|
fn Tokenizer::rest_len(self : Tokenizer) -> Int {
  self.source.length() - self.current_offset
}

///|
fn Tokenizer::advance(self : Tokenizer, n : Int) -> StringView {
  let start = self.current_offset
  let end = start + n
  let mut i = start
  while i < end {
    let u = self.source[i].to_int()
    if u == '\n'.to_int() {
      // line and column numbers saturate like Rust's u16
      if self.current_line < 65535 {
        self.current_line += 1
      }
      self.current_col = 0
    } else {
      if self.current_col < 65535 {
        self.current_col += 1
      }
      if u >= 0xD800 && u <= 0xDBFF && i + 1 < end {
        let u2 = self.source[i + 1].to_int()
        if u2 >= 0xDC00 && u2 <= 0xDFFF {
          i += 1
        }
      }
    }
    i += 1
  }
  self.current_offset = end
  self.source.view(start_offset=start, end_offset=end)
}

///|
fn Tokenizer::span_from(
  self : Tokenizer,
  start_line : Int,
  start_col : Int,
  start_offset : Int,
) -> Span {
  {
    start_line,
    start_col,
    start_offset,
    end_line: self.current_line,
    end_col: self.current_col,
    end_offset: self.current_offset,
  }
}

///|
fn Tokenizer::syntax_error(self : Tokenizer, msg : String) -> TemplateError {
  let span = self.span_from(
    self.current_line,
    self.current_col,
    self.current_offset,
  )
  let span = if span.start_col == span.end_col {
    { ..span, end_col: span.end_col + 1, end_offset: span.end_offset + 1, }
  } else {
    span
  }
  let err = TemplateError::new(SyntaxError, msg)
  err.set_filename_and_span(self.filename, span)
  err
}

///|
priv enum NumberState {
  RadixInteger
  Integer
  Fraction
  Exponent
  ExponentSign
}

///|
fn is_digit_unit(u : Int) -> Bool {
  u >= '0'.to_int() && u <= '9'.to_int()
}

///|
/// Parses an unsigned integer in the given radix.  Returns `None` on invalid
/// digits or empty input.
fn parse_uint_radix(s : StringView, radix : Int) -> BigInt? {
  if s.length() == 0 {
    return None
  }
  let mut rv = 0N
  let big_radix = BigInt::from_int(radix)
  for c in s {
    let d = hex_value(c)
    if d < 0 || d >= radix {
      return None
    }
    rv = rv * big_radix + BigInt::from_int(d)
  }
  Some(rv)
}

///|
let max_u64_big : BigInt = BigInt::from_uint64(0xFFFFFFFFFFFFFFFFUL)

///|
let max_u128_big : BigInt = (1N << 128) - 1N

///|
fn Tokenizer::eat_number(self : Tokenizer) -> (Token, Span) raise TemplateError {
  let old_line = self.current_line
  let old_col = self.current_col
  let old_off = self.current_offset
  let off = self.current_offset
  let u0 = unit_at(self.source, off)
  let u1 = unit_at(self.source, off + 1)
  let radix = if u0 == '0'.to_int() {
    if u1 == 'b'.to_int() || u1 == 'B'.to_int() {
      2
    } else if u1 == 'o'.to_int() || u1 == 'O'.to_int() {
      8
    } else if u1 == 'x'.to_int() || u1 == 'X'.to_int() {
      16
    } else {
      10
    }
  } else {
    10
  }
  let mut state = if radix == 10 {
    NumberState::Integer
  } else {
    self.advance(2) |> ignore
    NumberState::RadixInteger
  }
  let start = self.current_offset
  let mut num_len = 0
  while is_digit_unit(unit_at(self.source, start + num_len)) {
    num_len += 1
  }
  let mut has_underscore = false
  while start + num_len < self.source.length() {
    let c = self.source[start + num_len].to_int()
    let next_state = match (c, state) {
      (0x2E, Integer) => {
        // '.'
        let n1 = unit_at(self.source, start + num_len + 1)
        let n2 = unit_at(self.source, start + num_len + 2)
        let is_exp = (n1 == 'e'.to_int() || n1 == 'E'.to_int()) &&
          (n2 == '+'.to_int() || n2 == '-'.to_int() || is_digit_unit(n2))
        if !is_exp && lex_identifier(self.source, start + num_len + 1) > 0 {
          None
        } else {
          Some(NumberState::Fraction)
        }
      }
      (0x45 | 0x65, Integer | Fraction) => Some(Exponent)
      (0x2B | 0x2D, Exponent) => Some(ExponentSign)
      (0x30..=0x39, Exponent) => Some(ExponentSign)
      (0x30..=0x39, s) => Some(s)
      (0x61..=0x66 | 0x41..=0x46, RadixInteger) if radix == 16 =>
        Some(RadixInteger)
      (0x5F, s) => {
        has_underscore = true
        Some(s)
      }
      _ => None
    }
    match next_state {
      Some(s) => state = s
      None => break
    }
    num_len += 1
  }
  let is_float = !(state is (Integer | RadixInteger))
  let mut num = self.advance(num_len).to_owned()
  if has_underscore {
    if num.has_suffix("_") {
      raise self.syntax_error("'_' may not occur at end of number")
    }
    num = num.replace_all(old="_", new="")
  }
  let token = if is_float {
    let f = parse_rust_float(num) catch {
      _ => raise self.syntax_error("invalid float")
    }
    Token::Float(f)
  } else {
    match parse_uint_radix(num, radix) {
      Some(v) if v <= max_u64_big => Token::Int(v.to_uint64())
      Some(v) if v <= max_u128_big => Token::Int128(v)
      _ => raise self.syntax_error("invalid integer (too large)")
    }
  }
  (token, self.span_from(old_line, old_col, old_off))
}

///|
/// Parses a float like Rust's `str::parse::<f64>` for the inputs the lexer
/// produces (digits, an optional fraction and an optional exponent).
fn parse_rust_float(s : String) -> Double raise {
  if s.contains("_") {
    fail("invalid float")
  }
  if s.has_suffix("e") ||
    s.has_suffix("E") ||
    s.has_suffix("+") ||
    s.has_suffix("-") {
    fail("invalid float")
  }
  // the lexer validated the syntax, so a failure here is an overflow which
  // Rust turns into an infinity
  @string.parse_double(s) catch {
    _ => 1.0 / 0.0
  }
}

///|
fn Tokenizer::eat_identifier(
  self : Tokenizer,
) -> (Token, Span) raise TemplateError {
  let ident_len = lex_identifier(self.source, self.current_offset)
  if ident_len > 0 {
    let old_line = self.current_line
    let old_col = self.current_col
    let old_off = self.current_offset
    let ident = self.advance(ident_len).to_owned()
    (Ident(ident), self.span_from(old_line, old_col, old_off))
  } else {
    raise self.syntax_error("unexpected character")
  }
}

///|
fn Tokenizer::eat_string(
  self : Tokenizer,
  delim : Int,
) -> (Token, Span) raise TemplateError {
  let old_line = self.current_line
  let old_col = self.current_col
  let old_off = self.current_offset
  let off = self.current_offset
  let mut escaped = false
  let mut has_escapes = false
  let mut str_len = 0
  let len = self.source.length()
  while off + 1 + str_len < len {
    let c = self.source[off + 1 + str_len].to_int()
    if escaped {
      escaped = false
    } else if c == '\\'.to_int() {
      escaped = true
      has_escapes = true
    } else if c == delim {
      break
    }
    str_len += 1
  }
  if escaped || unit_at(self.source, off + str_len + 1) != delim {
    self.advance(str_len + 1) |> ignore
    raise self.syntax_error("unexpected end of string")
  }
  let s = self.advance(str_len + 2)
  let inner = s.view(start_offset=1, end_offset=s.length() - 1)
  if has_escapes {
    (OwnedStr(unescape(inner)), self.span_from(old_line, old_col, old_off))
  } else {
    (Str(inner.to_owned()), self.span_from(old_line, old_col, old_off))
  }
}

///|
fn Tokenizer::skip_whitespace(self : Tokenizer) -> Unit {
  let mut i = self.current_offset
  while char_at(self.source, i) is Some(c) && is_rust_whitespace(c) {
    i += c.utf16_len()
  }
  if i > self.current_offset {
    self.advance(i - self.current_offset) |> ignore
  }
}

///|
fn Tokenizer::skip_newline_if_trim_blocks(self : Tokenizer) -> Unit {
  if self.ws_config.trim_blocks {
    if unit_at(self.source, self.current_offset) == '\r'.to_int() {
      self.advance(1) |> ignore
    }
    if unit_at(self.source, self.current_offset) == '\n'.to_int() {
      self.advance(1) |> ignore
    }
  }
}

///|
fn Tokenizer::handle_tail_ws(self : Tokenizer, ws : Whitespace) -> Unit {
  match ws {
    Preserve => ()
    Default => self.skip_newline_if_trim_blocks()
    Remove => self.trim_leading_whitespace = true
  }
}

///|
fn Tokenizer::tokenize_root(
  self : Tokenizer,
) -> (Token, Span)? raise TemplateError {
  if self.pending_start_marker is Some((marker, len)) {
    self.pending_start_marker = None
    return self.handle_start_marker(marker, len)
  }
  if self.trim_leading_whitespace {
    self.trim_leading_whitespace = false
    self.skip_whitespace()
  }
  let old_line = self.current_line
  let old_col = self.current_col
  let old_off = self.current_offset
  let offset = self.current_offset
  let (lead, span) = match
    find_start_marker(self.source, offset, self.syntax_config) {
    Some((start, marker, len, whitespace)) => {
      self.pending_start_marker = Some((marker, len))
      match whitespace {
        Default if should_lstrip_block(
            self.ws_config.lstrip_blocks,
            marker,
            self.source,
            offset + start,
          ) => {
          let peeked = self.source.view(
            start_offset=offset,
            end_offset=offset + start,
          )
          let trimmed = lstrip_block(peeked)
          let lead = self.advance(trimmed.length())
          let span = self.span_from(old_line, old_col, old_off)
          self.advance(peeked.length() - trimmed.length()) |> ignore
          (lead, span)
        }
        Default | Preserve => {
          let lead = self.advance(start)
          (lead, self.span_from(old_line, old_col, old_off))
        }
        Remove => {
          let peeked = self.source.view(
            start_offset=offset,
            end_offset=offset + start,
          )
          let trimmed = trim_end_view(peeked)
          let lead = self.advance(trimmed.length())
          let span = self.span_from(old_line, old_col, old_off)
          self.advance(peeked.length() - trimmed.length()) |> ignore
          (lead, span)
        }
      }
    }
    None => {
      let lead = self.advance(self.rest_len())
      (lead, self.span_from(old_line, old_col, old_off))
    }
  }
  if lead.length() == 0 {
    None
  } else {
    Some((TemplateData(lead.to_owned()), span))
  }
}

///|
fn Tokenizer::handle_start_marker(
  self : Tokenizer,
  marker : StartMarker,
  skip : Int,
) -> (Token, Span)? raise TemplateError {
  match marker {
    Comment => {
      let comment_end = self.syntax_config.comment_end
      match find_from(self.source, self.current_offset + skip, comment_end) {
        Some(end) => {
          let ws_idx = (if end > 0 { end - 1 } else { 0 }) + skip
          let ws = Whitespace::from_unit(
            unit_at(self.source, self.current_offset + ws_idx),
          )
          self.advance(end + skip + comment_end.length()) |> ignore
          self.handle_tail_ws(ws)
          None
        }
        None => {
          self.advance(self.rest_len()) |> ignore
          raise self.syntax_error("unexpected end of comment")
        }
      }
    }
    Variable => {
      let old_line = self.current_line
      let old_col = self.current_col
      let old_off = self.current_offset
      self.advance(skip) |> ignore
      self.stack.push(LexerState::Variable)
      Some((VariableStart, self.span_from(old_line, old_col, old_off)))
    }
    Block =>
      // raw blocks require some special handling.  If we are at the
      // beginning of a raw block we want to skip everything until
      // {% endraw %} completely ignoring interior syntax and emit the entire
      // raw block as TemplateData.
      match
        skip_basic_tag(
          self.source,
          self.current_offset + skip,
          "raw",
          self.syntax_config.block_end,
          false,
        ) {
        Some((raw, ws_start)) => {
          self.advance(raw + skip) |> ignore
          self.handle_raw_tag(ws_start)
        }
        None => {
          let old_line = self.current_line
          let old_col = self.current_col
          let old_off = self.current_offset
          self.advance(skip) |> ignore
          self.stack.push(LexerState::Block)
          Some((BlockStart, self.span_from(old_line, old_col, old_off)))
        }
      }
    LineStatement => {
      let old_line = self.current_line
      let old_col = self.current_col
      let old_off = self.current_offset
      self.advance(skip) |> ignore
      self.stack.push(LexerState::LineStatement)
      Some((BlockStart, self.span_from(old_line, old_col, old_off)))
    }
    LineComment => {
      let base = self.current_offset + skip
      let mut comment_skip = 0
      while base + comment_skip < self.source.length() {
        let c = self.source[base + comment_skip]
        if c == '\r' || c == '\n' {
          break
        }
        comment_skip += 1
      }
      let (_, nl_skip) = skip_nl(self.source, base + comment_skip)
      self.advance(skip + comment_skip + nl_skip) |> ignore
      None
    }
  }
}

///|
fn Tokenizer::handle_raw_tag(
  self : Tokenizer,
  ws_start : Whitespace,
) -> (Token, Span)? raise TemplateError {
  let old_line = self.current_line
  let old_col = self.current_col
  let old_off = self.current_offset
  let block_start = self.syntax_config.block_start
  let block_end = self.syntax_config.block_end
  let offset = self.current_offset
  let mut ptr = 0
  while find_from(self.source, offset + ptr, block_start) is Some(block) {
    ptr += block + block_start.length()
    if skip_basic_tag(self.source, offset + ptr, "endraw", block_end, true)
      is Some((endraw, ws_next)) {
      let ws = Whitespace::from_unit(unit_at(self.source, offset + ptr))
      let end = ptr - block_start.length()
      let mut result = self.source.view(
        start_offset=offset,
        end_offset=offset + end,
      )
      self.advance(end) |> ignore
      let span = self.span_from(old_line, old_col, old_off)
      self.advance(block_start.length() + endraw) |> ignore
      match ws_start {
        Default if self.ws_config.trim_blocks => {
          if result.length() > 0 && result[0] == '\r' {
            result = result.view(start_offset=1)
          }
          if result.length() > 0 && result[0] == '\n' {
            result = result.view(start_offset=1)
          }
        }
        Remove => result = trim_start_view(result)
        _ => ()
      }
      result = match ws {
        Default if self.ws_config.lstrip_blocks => lstrip_block(result)
        Remove => trim_end_view(result)
        _ => result
      }
      self.handle_tail_ws(ws_next)
      return Some((TemplateData(result.to_owned()), span))
    }
  }
  self.advance(self.rest_len()) |> ignore
  raise self.syntax_error("unexpected end of raw block")
}

///|
fn Tokenizer::tokenize_block_or_var(
  self : Tokenizer,
  sentinel : BlockSentinel,
) -> (Token, Span)? raise TemplateError {
  let old_line = self.current_line
  let old_col = self.current_col
  let old_off = self.current_offset
  let off = self.current_offset
  let source = self.source

  // special case for looking for the end of a line statements if there are
  // no open parens, braces etc.
  if sentinel == BlockSentinel::LineStatement &&
    self.paren_balance == 0 &&
    self.syntax_config.line_statement_prefix != "" {
    let mut skip = 0
    while char_at(source, off + skip) is Some(c) &&
          is_rust_whitespace(c) &&
          !is_nl(c) {
      skip += c.utf16_len()
    }
    let (was_nl, nl_skip) = skip_nl(source, off + skip)
    if was_nl {
      self.advance(skip + nl_skip) |> ignore
      self.stack.pop() |> ignore
      return Some((BlockEnd, self.span_from(old_line, old_col, old_off)))
    }
  }

  // in blocks whitespace is generally ignored, skip it.
  let mut ws = 0
  while off + ws < source.length() &&
        is_ascii_ws_unit(source[off + ws].to_int()) {
    ws += 1
  }
  if ws > 0 {
    self.advance(ws) |> ignore
    return None
  }

  // look out for the end of blocks
  if self.paren_balance == 0 {
    match sentinel {
      Block => {
        let block_end = self.syntax_config.block_end
        let c0 = unit_at(source, off)
        if (c0 == '-'.to_int() || c0 == '+'.to_int()) &&
          starts_with_at(source, off + 1, block_end) {
          self.stack.pop() |> ignore
          let was_minus = c0 == '-'.to_int()
          self.advance(block_end.length() + 1) |> ignore
          let span = self.span_from(old_line, old_col, old_off)
          if was_minus {
            self.trim_leading_whitespace = true
          }
          return Some((BlockEnd, span))
        }
        if starts_with_at(source, off, block_end) {
          self.stack.pop() |> ignore
          self.advance(block_end.length()) |> ignore
          let span = self.span_from(old_line, old_col, old_off)
          self.skip_newline_if_trim_blocks()
          return Some((BlockEnd, span))
        }
      }
      Variable => {
        let variable_end = self.syntax_config.variable_end
        let c0 = unit_at(source, off)
        if (c0 == '-'.to_int() || c0 == '+'.to_int()) &&
          starts_with_at(source, off + 1, variable_end) {
          self.stack.pop() |> ignore
          let was_minus = c0 == '-'.to_int()
          self.advance(variable_end.length() + 1) |> ignore
          let span = self.span_from(old_line, old_col, old_off)
          if was_minus {
            self.trim_leading_whitespace = true
          }
          return Some((VariableEnd, span))
        }
        if starts_with_at(source, off, variable_end) {
          self.stack.pop() |> ignore
          self.advance(variable_end.length()) |> ignore
          return Some((VariableEnd, self.span_from(old_line, old_col, old_off)))
        }
      }
      // line statements are handled above
      LineStatement => ()
    }
  }

  // two character operators
  let c0 = unit_at(source, off)
  let c1 = unit_at(source, off + 1)
  let two : Token? = if c1 == 0x3D {
    // `=` as the second character
    match c0 {
      0x3D => Some(Token::Eq) // ==
      0x21 => Some(Token::Ne) // !=
      0x3E => Some(Token::Gte) // >=
      0x3C => Some(Token::Lte) // <=
      _ => None
    }
  } else if c0 == 0x2F && c1 == 0x2F {
    Some(Token::FloorDiv) // //
  } else if c0 == 0x2A && c1 == 0x2A {
    Some(Token::Pow) // **
  } else {
    None
  }
  if two is Some(op) {
    self.advance(2) |> ignore
    return Some((op, self.span_from(old_line, old_col, old_off)))
  }

  // single character operators (and strings)
  let op = match c0 {
    0x2B => Some(Token::Plus)
    0x2D => Some(Token::Minus)
    0x2A => Some(Token::Mul)
    0x2F => Some(Token::Div)
    0x25 => Some(Token::Mod)
    0x2E => Some(Token::Dot)
    0x2C => Some(Token::Comma)
    0x3A => Some(Token::Colon)
    0x7E => Some(Token::Tilde)
    0x7C => Some(Token::Pipe)
    0x3D => Some(Token::Assign)
    0x3E => Some(Token::Gt)
    0x3C => Some(Token::Lt)
    0x28 => {
      self.paren_balance += 1
      Some(Token::ParenOpen)
    }
    0x29 => {
      self.paren_balance -= 1
      Some(Token::ParenClose)
    }
    0x5B => {
      self.paren_balance += 1
      Some(Token::BracketOpen)
    }
    0x5D => {
      self.paren_balance -= 1
      Some(Token::BracketClose)
    }
    0x7B => {
      self.paren_balance += 1
      Some(Token::BraceOpen)
    }
    0x7D => {
      self.paren_balance -= 1
      Some(Token::BraceClose)
    }
    0x27 => return Some(self.eat_string(0x27))
    0x22 => return Some(self.eat_string(0x22))
    c if is_digit_unit(c) => return Some(self.eat_number())
    _ => None
  }
  match op {
    Some(op) => {
      self.advance(1) |> ignore
      Some((op, self.span_from(old_line, old_col, old_off)))
    }
    None => Some(self.eat_identifier())
  }
}

///|
/// Tokenizes a full source into tokens (used by tests and tooling).
fn tokenize(
  input : String,
  in_expr : Bool,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
) -> Array[(Token, Span)] raise TemplateError {
  let tokenizer = Tokenizer::new(
    input, "<string>", in_expr, syntax_config, ws_config,
  )
  let rv = []
  while tokenizer.next_token() is Some(tok) {
    rv.push(tok)
  }
  rv
}
