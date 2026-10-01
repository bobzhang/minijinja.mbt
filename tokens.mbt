///|
/// Token span information.
///
/// Lines start at 1 and columns at 0; both are counted in Unicode scalar
/// values like in MiniJinja.  Offsets are UTF-16 code unit offsets into the
/// template source.
pub(all) struct Span {
  start_line : Int
  start_col : Int
  start_offset : Int
  end_line : Int
  end_col : Int
  end_offset : Int
} derive(Eq, Default)

///|
/// Formats the span like MiniJinja's `Debug` for `Span` (` @ 1:0-1:5`).
pub fn Span::to_string(self : Span) -> String {
  " @ \{self.start_line}:\{self.start_col}-\{self.end_line}:\{self.end_col}"
}

///|
pub impl Show for Span with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Represents a token in the stream.
enum Token {
  /// Raw template data.
  TemplateData(String)
  /// Variable block start.
  VariableStart
  /// Variable block end
  VariableEnd
  /// Statement block start
  BlockStart
  /// Statement block end
  BlockEnd
  /// An identifier.
  Ident(String)
  /// A string without escapes.
  Str(String)
  /// A string that had escapes.
  OwnedStr(String)
  /// An integer (limited to u64)
  Int(UInt64)
  /// A large integer (u128)
  Int128(BigInt)
  /// A float
  Float(Double)
  Plus
  Minus
  Mul
  Div
  FloorDiv
  Pow
  Mod
  Dot
  Comma
  Colon
  Tilde
  Assign
  Pipe
  Eq
  Ne
  Gt
  Gte
  Lt
  Lte
  BracketOpen
  BracketClose
  ParenOpen
  ParenClose
  BraceOpen
  BraceClose
}

///|
/// Human readable description used in syntax errors.
fn Token::describe(self : Token) -> String {
  match self {
    TemplateData(_) => "template-data"
    VariableStart => "start of variable block"
    VariableEnd => "end of variable block"
    BlockStart => "start of block"
    BlockEnd => "end of block"
    Ident(_) => "identifier"
    Str(_) | OwnedStr(_) => "string"
    Int(_) | Int128(_) => "integer"
    Float(_) => "float"
    Plus => "`+`"
    Minus => "`-`"
    Mul => "`*`"
    Div => "`/`"
    FloorDiv => "`//`"
    Pow => "`**`"
    Mod => "`%`"
    Dot => "`.`"
    Comma => "`,`"
    Colon => "`:`"
    Tilde => "`~`"
    Assign => "`=`"
    Pipe => "`|`"
    Eq => "`==`"
    Ne => "`!=`"
    Gt => "`>`"
    Gte => "`>=`"
    Lt => "`<`"
    Lte => "`<=`"
    BracketOpen => "`[`"
    BracketClose => "`]`"
    ParenOpen => "`(`"
    ParenClose => "`)`"
    BraceOpen => "`{`"
    BraceClose => "`}`"
  }
}

///|
/// Formats the token like Rust's derived `Debug`.
fn Token::debug_string(self : Token) -> String {
  match self {
    TemplateData(s) => "TemplateData(\{@rfmt.str_debug(s)})"
    VariableStart => "VariableStart"
    VariableEnd => "VariableEnd"
    BlockStart => "BlockStart"
    BlockEnd => "BlockEnd"
    Ident(s) => "Ident(\{@rfmt.str_debug(s)})"
    Str(s) => "Str(\{@rfmt.str_debug(s)})"
    OwnedStr(s) => "String(\{@rfmt.str_debug(s)})"
    Int(i) => "Int(\{i})"
    Int128(i) => "Int128(\{i})"
    Float(f) => "Float(\{@rfmt.f64_debug(f)})"
    Plus => "Plus"
    Minus => "Minus"
    Mul => "Mul"
    Div => "Div"
    FloorDiv => "FloorDiv"
    Pow => "Pow"
    Mod => "Mod"
    Dot => "Dot"
    Comma => "Comma"
    Colon => "Colon"
    Tilde => "Tilde"
    Assign => "Assign"
    Pipe => "Pipe"
    Eq => "Eq"
    Ne => "Ne"
    Gt => "Gt"
    Gte => "Gte"
    Lt => "Lt"
    Lte => "Lte"
    BracketOpen => "BracketOpen"
    BracketClose => "BracketClose"
    ParenOpen => "ParenOpen"
    ParenClose => "ParenClose"
    BraceOpen => "BraceOpen"
    BraceClose => "BraceClose"
  }
}
