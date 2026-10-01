///|
let max_recursion = 150

///|
let reserved_names : Array[String] = [
  "true", "True", "false", "False", "none", "None", "loop", "self",
]

///|
fn unexpected(unexpected : String, expected : String) -> TemplateError {
  TemplateError::new(
    SyntaxError,
    "unexpected \{unexpected}, expected \{expected}",
  )
}

///|
fn unexpected_eof(expected : String) -> TemplateError {
  unexpected("end of input", expected)
}

///|
fn syntax_error(msg : String) -> TemplateError {
  TemplateError::new(SyntaxError, msg)
}

///|
fn make_const(value : Value, span : Span) -> Expr {
  Const({ value, span, })
}

///|
priv struct TokenStream {
  tokenizer : Tokenizer
  mut current : Result[(Token, Span)?, TemplateError]
  mut last_span : Span
}

///|
fn TokenStream::new(
  source : String,
  filename : String,
  in_expr : Bool,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
) -> TokenStream {
  let tokenizer = Tokenizer::new(
    source, filename, in_expr, syntax_config, ws_config,
  )
  let current = capture(() => tokenizer.next_token())
  { tokenizer, current, last_span: Span::default(), }
}

///|
/// Runs `f` and captures its result or error.
fn[T] capture(f : () -> T raise TemplateError) -> Result[T, TemplateError] {
  try f() catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
}

///|
/// Advance the stream.
fn TokenStream::next(self : TokenStream) -> (Token, Span)? raise TemplateError {
  let rv = self.current
  self.current = try self.tokenizer.next_token() catch {
    err => Err(err)
  } noraise {
    tok => Ok(tok)
  }
  match rv {
    Ok(Some((token, span))) => {
      self.last_span = span
      Some((token, span))
    }
    Ok(None) => None
    Err(err) => raise err
  }
}

///|
/// Look at the current token
fn TokenStream::current(
  self : TokenStream,
) -> (Token, Span)? raise TemplateError {
  match self.current {
    Err(err) => {
      self.current = Ok(None)
      raise err
    }
    Ok(rv) => rv
  }
}

///|
/// Expands the span
fn TokenStream::expand_span(self : TokenStream, span : Span) -> Span {
  {
    ..span,
    end_line: self.last_span.end_line,
    end_col: self.last_span.end_col,
    end_offset: self.last_span.end_offset,
  }
}

///|
/// Returns the current span.
fn TokenStream::current_span(self : TokenStream) -> Span {
  match self.current {
    Ok(Some((_, span))) => span
    _ => self.last_span
  }
}

///|
priv struct Parser {
  stream : TokenStream
  mut in_macro : Bool
  mut in_loop : Bool
  blocks : Set[String]
  mut depth : Int
}

///|
priv enum SetParseResult {
  Set(Expr, Expr)
  SetBlock(Expr, Expr?, Array[Stmt])
}

///|
fn Parser::new(
  source : String,
  filename : String,
  in_expr : Bool,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
) -> Parser {
  {
    stream: TokenStream::new(
      source, filename, in_expr, syntax_config, ws_config,
    ),
    in_macro: false,
    in_loop: false,
    blocks: Set([]),
    depth: 0,
  }
}

///|
/// Expects any token.
fn Parser::expect_any(
  self : Parser,
  expectation : String,
) -> (Token, Span) raise TemplateError {
  match self.stream.next() {
    Some(rv) => rv
    None => raise unexpected_eof(expectation)
  }
}

///|
/// Expects a token matching the predicate.
fn Parser::expect(
  self : Parser,
  pred : (Token) -> Bool,
  expectation : String,
) -> (Token, Span) raise TemplateError {
  match self.stream.next() {
    Some((token, span)) =>
      if pred(token) {
        (token, span)
      } else {
        raise unexpected(token.describe(), expectation)
      }
    None => raise unexpected_eof(expectation)
  }
}

///|
/// Expects an identifier and returns its name.
fn Parser::expect_ident(
  self : Parser,
  expectation : String,
) -> (String, Span) raise TemplateError {
  match self.stream.next() {
    Some((Ident(name), span)) => (name, span)
    Some((token, _)) => raise unexpected(token.describe(), expectation)
    None => raise unexpected_eof(expectation)
  }
}

///|
/// Expects a specific identifier.
fn Parser::expect_keyword(
  self : Parser,
  name : String,
  expectation : String,
) -> Span raise TemplateError {
  match self.stream.next() {
    Some((Ident(id), span)) if id == name => span
    Some((token, _)) => raise unexpected(token.describe(), expectation)
    None => raise unexpected_eof(expectation)
  }
}

///|
fn Parser::matches(
  self : Parser,
  pred : (Token) -> Bool,
) -> Bool raise TemplateError {
  match self.stream.current() {
    Some((token, _)) => pred(token)
    None => false
  }
}

///|
fn Parser::skip(
  self : Parser,
  pred : (Token) -> Bool,
) -> Bool raise TemplateError {
  match self.stream.current() {
    Some((token, _)) if pred(token) => {
      ignore(self.stream.next())
      true
    }
    _ => false
  }
}

///|
fn is_ident(name : String) -> (Token) -> Bool {
  token => token is Ident(id) && id == name
}

///|
fn Parser::with_recursion_guard(
  self : Parser,
  f : () -> Expr raise TemplateError,
) -> Expr raise TemplateError {
  self.depth += 1
  if self.depth > max_recursion {
    raise syntax_error("template exceeds maximum recursion limits")
  }
  let rv = f()
  self.depth -= 1
  rv
}

///|
/// Parses a template.
fn Parser::parse(self : Parser) -> Stmt raise TemplateError {
  let span = self.stream.last_span
  let children = self.subparse(_ => false) catch {
    err => raise self.attach_location_to_error(err)
  }
  Template({ children, span: self.stream.expand_span(span), })
}

///|
/// Parses an expression and asserts that there is no more input after it.
fn Parser::parse_standalone_expr(self : Parser) -> Expr raise TemplateError {
  let rv = try {
    let result = self.parse_expr()
    if self.stream.next() is Some(_) {
      raise syntax_error("unexpected input after expression")
    }
    result
  } catch {
    err => Err(err)
  } noraise {
    v => Ok(v)
  }
  match rv {
    Ok(v) => v
    Err(err) => raise self.attach_location_to_error(err)
  }
}

///|
fn Parser::filename(self : Parser) -> String {
  self.stream.tokenizer.filename
}

///|
fn Parser::parse_ifexpr(self : Parser) -> Expr raise TemplateError {
  let mut span = self.stream.last_span
  let mut expr = self.parse_or()
  for ;; {
    if self.skip(is_ident("if")) {
      let expr2 = self.parse_or()
      let expr3 = if self.skip(is_ident("else")) {
        Some(self.parse_ifexpr())
      } else {
        None
      }
      expr = IfExpr({
        test_expr: expr2,
        true_expr: expr,
        false_expr: expr3,
        span: self.stream.expand_span(span),
      })
      span = self.stream.last_span
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::binop(
  self : Parser,
  next : (Parser) -> Expr raise TemplateError,
  op_for : (Token) -> BinOpKind?,
) -> Expr raise TemplateError {
  let span = self.stream.current_span()
  let mut left = next(self)
  for ;; {
    let op = match self.stream.current() {
      Some((token, _)) =>
        match op_for(token) {
          Some(op) => op
          None => break
        }
      None => break
    }
    ignore(self.stream.next())
    let right = next(self)
    left = BinOp({ op, left, right, span: self.stream.expand_span(span), })
  }
  left
}

///|
fn Parser::parse_or(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_and, token => {
    if token is Ident("or") {
      Some(ScOr)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_and(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_not, token => {
    if token is Ident("and") {
      Some(ScAnd)
    } else {
      None
    }
  })
}

///|
fn Parser::parse_not(self : Parser) -> Expr raise TemplateError {
  let span = self.stream.current_span()
  match self.stream.current() {
    Some((Ident("not"), _)) => ()
    _ => return self.parse_compare()
  }
  ignore(self.stream.next())
  let expr = self.parse_not()
  UnaryOp({ op: Not, expr, span: self.stream.expand_span(span), })
}

///|
fn Parser::parse_compare(self : Parser) -> Expr raise TemplateError {
  let span = self.stream.last_span
  let expr = self.parse_math1()
  let ops : Array[CompareOperand] = []
  for ;; {
    let op : CompareOpKind = match self.stream.current() {
      Some((Eq, _)) => Eq
      Some((Ne, _)) => Ne
      Some((Lt, _)) => Lt
      Some((Lte, _)) => Lte
      Some((Gt, _)) => Gt
      Some((Gte, _)) => Gte
      Some((Ident("in"), _)) => In
      Some((Ident("not"), _)) => {
        ignore(self.stream.next())
        ignore(self.expect_keyword("in", "in"))
        NotIn
      }
      _ => break
    }
    if !(op is NotIn) {
      ignore(self.stream.next())
    }
    ops.push({ op, expr: self.parse_math1(), })
  }
  match ops.length() {
    0 => expr
    1 => {
      let op = ops[0]
      let (binop, negated) : (BinOpKind, Bool) = match op.op {
        Eq => (Eq, false)
        Ne => (Ne, false)
        Lt => (Lt, false)
        Lte => (Lte, false)
        Gt => (Gt, false)
        Gte => (Gte, false)
        In => (In, false)
        NotIn => (In, true)
      }
      let expr = BinOp({
        op: binop,
        left: expr,
        right: op.expr,
        span: self.stream.expand_span(span),
      })
      if negated {
        UnaryOp({ op: Not, expr, span: self.stream.expand_span(span), })
      } else {
        expr
      }
    }
    _ => Compare({ expr, ops, span: self.stream.expand_span(span), })
  }
}

///|
fn Parser::parse_math1(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_concat, token => {
    match token {
      Plus => Some(Add)
      Minus => Some(Sub)
      _ => None
    }
  })
}

///|
fn Parser::parse_concat(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_math2, token => {
    match token {
      Tilde => Some(Concat)
      _ => None
    }
  })
}

///|
fn Parser::parse_math2(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_pow, token => {
    match token {
      Mul => Some(Mul)
      Div => Some(Div)
      FloorDiv => Some(FloorDiv)
      Mod => Some(Rem)
      _ => None
    }
  })
}

///|
fn Parser::parse_pow(self : Parser) -> Expr raise TemplateError {
  self.binop(Parser::parse_unary, token => {
    match token {
      Pow => Some(Pow)
      _ => None
    }
  })
}

///|
fn Parser::parse_unary_only(self : Parser) -> Expr raise TemplateError {
  let span = self.stream.current_span()
  match self.stream.current() {
    Some((Minus, _)) => ()
    _ => return self.parse_primary()
  }
  ignore(self.stream.next())
  let expr = self.parse_unary_only()
  UnaryOp({ op: Neg, expr, span: self.stream.expand_span(span), })
}

///|
fn Parser::parse_unary(self : Parser) -> Expr raise TemplateError {
  let span = self.stream.current_span()
  let mut expr = self.parse_unary_only()
  expr = self.parse_postfix(expr, span)
  self.parse_filter_expr(expr)
}

///|
fn Parser::parse_postfix(
  self : Parser,
  expr : Expr,
  span : Span,
) -> Expr raise TemplateError {
  let mut expr = expr
  let mut span = span
  for ;; {
    let next_span = self.stream.current_span()
    match self.stream.current() {
      Some((Dot, _)) => {
        ignore(self.stream.next())
        match self.stream.next() {
          Some((Ident(name), _)) =>
            expr = GetAttr({ name, expr, span: self.stream.expand_span(span), })
          Some((Int(idx), idx_span)) =>
            expr = GetItem({
              expr,
              subscript_expr: make_const(Value::from_uint64(idx), idx_span),
              span: self.stream.expand_span(span),
            })
          Some((Int128(idx), idx_span)) =>
            expr = GetItem({
              expr,
              subscript_expr: make_const(Value::U128(idx), idx_span),
              span: self.stream.expand_span(span),
            })
          Some((token, _)) =>
            raise unexpected(token.describe(), "identifier or integer")
          None => raise unexpected_eof("identifier or integer")
        }
      }
      Some((BracketOpen, _)) => {
        ignore(self.stream.next())
        let mut start = None
        let mut stop = None
        let mut step = None
        let mut is_slice = false
        if !self.matches(t => t is Colon) {
          start = Some(self.parse_expr())
        }
        if self.skip(t => t is Colon) {
          is_slice = true
          if !self.matches(t => t is (BracketClose | Colon)) {
            stop = Some(self.parse_expr())
          }
          if self.skip(t => t is Colon) && !self.matches(t => t is BracketClose) {
            step = Some(self.parse_expr())
          }
        }
        ignore(self.expect(t => t is BracketClose, "`]`"))
        if !is_slice {
          guard start is Some(subscript_expr) else {
            raise syntax_error("empty subscript")
          }
          expr = GetItem({
            expr,
            subscript_expr,
            span: self.stream.expand_span(span),
          })
        } else {
          expr = Slice({
            expr,
            start,
            stop,
            step,
            span: self.stream.expand_span(span),
          })
        }
      }
      Some((ParenOpen, _)) => {
        let args = self.parse_args()
        expr = Call({ expr, args, span: self.stream.expand_span(span), })
      }
      _ => break
    }
    span = next_span
  }
  expr
}

///|
fn Parser::parse_filter_test_name(
  self : Parser,
) -> (String, Span) raise TemplateError {
  let (first_segment, span) = self.expect_ident("identifier")
  let start_offset = span.start_offset
  let mut end_offset = span.end_offset
  let mut is_dotted = false
  while self.skip(t => t is Dot) {
    let (_, segment_span) = self.expect_ident("identifier")
    end_offset = segment_span.end_offset
    is_dotted = true
  }
  if is_dotted {
    (
      self.stream.tokenizer.source.view(start_offset~, end_offset~).to_owned(),
      self.stream.expand_span(span),
    )
  } else {
    (first_segment, span)
  }
}

///|
fn Parser::parse_filter_expr(
  self : Parser,
  expr : Expr,
) -> Expr raise TemplateError {
  let mut expr = expr
  for ;; {
    match self.stream.current() {
      Some((Pipe, _)) => {
        ignore(self.stream.next())
        let (name, span) = self.parse_filter_test_name()
        let args = if self.matches(t => t is ParenOpen) {
          self.parse_args()
        } else {
          []
        }
        expr = Filter({
          name,
          expr: Some(expr),
          args,
          span: self.stream.expand_span(span),
        })
      }
      Some((Ident("is"), _)) => {
        ignore(self.stream.next())
        let negated = self.skip(is_ident("not"))
        let (name, span) = self.parse_filter_test_name()
        let args = if self.matches(t => t is ParenOpen) {
          self.parse_args()
        } else if self.matches(t => {
            t
            is (Ident(_)
            | Str(_)
            | OwnedStr(_)
            | Int(_)
            | Int128(_)
            | Float(_)
            | Plus
            | Minus
            | BracketOpen
            | BraceOpen)
          }) &&
          !self.matches(t => {
            t is (Ident("and") | Ident("or") | Ident("else") | Ident("is"))
          }) {
          let span = self.stream.current_span()
          let mut expr = self.parse_unary_only()
          expr = self.parse_postfix(expr, span)
          [CallArg::Pos(expr)]
        } else {
          []
        }
        expr = Test({ name, expr, args, span: self.stream.expand_span(span), })
        if negated {
          expr = UnaryOp({ op: Not, expr, span: self.stream.expand_span(span), })
        }
      }
      _ => break
    }
  }
  expr
}

///|
priv enum ArgType {
  Regular
  Splat
  KwargsSplat
}

///|
fn Parser::parse_args(self : Parser) -> Array[CallArg] raise TemplateError {
  let args : Array[CallArg] = []
  let mut has_kwargs = false
  ignore(self.expect(t => t is ParenOpen, "`(`"))
  for ;; {
    if self.skip(t => t is ParenClose) {
      break
    }
    if !args.is_empty() || has_kwargs {
      ignore(self.expect(t => t is Comma, "`,`"))
      if self.skip(t => t is ParenClose) {
        break
      }
    }
    let arg_type = if self.skip(t => t is Pow) {
      ArgType::KwargsSplat
    } else if self.skip(t => t is Mul) {
      ArgType::Splat
    } else {
      ArgType::Regular
    }
    let expr = self.parse_expr()
    match arg_type {
      Regular =>
        match expr {
          Var(v) if self.skip(t => t is Assign) => {
            has_kwargs = true
            args.push(Kwarg(v.id, self.parse_expr()))
          }
          _ if has_kwargs =>
            raise syntax_error("non-keyword arg after keyword arg")
          _ => args.push(Pos(expr))
        }
      Splat => args.push(PosSplat(expr))
      KwargsSplat => {
        args.push(KwargSplat(expr))
        has_kwargs = true
      }
    }
    // Set an arbitrary limit of max function parameters.
    if args.length() > 2000 {
      raise syntax_error("Too many arguments in function call")
    }
  }
  args
}

///|
fn Parser::parse_primary(self : Parser) -> Expr raise TemplateError {
  self.with_recursion_guard(() => self.parse_primary_impl())
}

///|
fn Parser::parse_primary_impl(self : Parser) -> Expr raise TemplateError {
  let (token, span) = self.expect_any("expression")
  match token {
    Ident("true" | "True") =>
      make_const(Value::from_bool(true), self.stream.expand_span(span))
    Ident("false" | "False") =>
      make_const(Value::from_bool(false), self.stream.expand_span(span))
    Ident("none" | "None") =>
      make_const(Value::none(), self.stream.expand_span(span))
    Ident(name) => Var({ id: name, span, })
    Str(_) | OwnedStr(_) => {
      let buf = StringBuilder()
      match token {
        Str(s) | OwnedStr(s) => buf.write_string(s)
        _ => ()
      }
      for ;; {
        match self.stream.current() {
          Some((Str(s), _)) | Some((OwnedStr(s), _)) => buf.write_string(s)
          _ => break
        }
        ignore(self.stream.next())
      }
      make_const(
        Value::from_string(buf.to_string()),
        self.stream.expand_span(span),
      )
    }
    Int(val) =>
      make_const(Value::from_uint64(val), self.stream.expand_span(span))
    Int128(val) => make_const(Value::U128(val), self.stream.expand_span(span))
    Float(val) =>
      make_const(Value::from_double(val), self.stream.expand_span(span))
    ParenOpen => self.parse_tuple_or_expression(span)
    BracketOpen => self.parse_list_expr(span)
    BraceOpen => self.parse_map_expr(span)
    token => raise syntax_error("unexpected \{token.describe()}")
  }
}

///|
fn Parser::parse_list_expr(
  self : Parser,
  span : Span,
) -> Expr raise TemplateError {
  let items = []
  for ;; {
    if self.skip(t => t is BracketClose) {
      break
    }
    if !items.is_empty() {
      ignore(self.expect(t => t is Comma, "`,`"))
      if self.skip(t => t is BracketClose) {
        break
      }
    }
    items.push(self.parse_expr())
  }
  List({ items, span: self.stream.expand_span(span), })
}

///|
fn Parser::parse_map_expr(
  self : Parser,
  span : Span,
) -> Expr raise TemplateError {
  let keys = []
  let values = []
  for ;; {
    if self.skip(t => t is BraceClose) {
      break
    }
    if !keys.is_empty() {
      ignore(self.expect(t => t is Comma, "`,`"))
      if self.skip(t => t is BraceClose) {
        break
      }
    }
    keys.push(self.parse_expr())
    ignore(self.expect(t => t is Colon, "`:`"))
    values.push(self.parse_expr())
  }
  Map({ keys, values, span: self.stream.expand_span(span), })
}

///|
fn Parser::parse_tuple_or_expression(
  self : Parser,
  span : Span,
) -> Expr raise TemplateError {
  if self.skip(t => t is ParenClose) {
    return Tuple({ items: [], span: self.stream.expand_span(span), })
  }
  let mut expr = self.parse_expr()
  if self.matches(t => t is Comma) {
    let items = [expr]
    for ;; {
      if self.skip(t => t is ParenClose) {
        break
      }
      ignore(self.expect(t => t is Comma, "`,`"))
      if self.skip(t => t is ParenClose) {
        break
      }
      items.push(self.parse_expr())
    }
    expr = Tuple({ items, span: self.stream.expand_span(span), })
  } else {
    ignore(self.expect(t => t is ParenClose, "`)`"))
  }
  expr
}

///|
fn Parser::parse_expr(self : Parser) -> Expr raise TemplateError {
  self.with_recursion_guard(() => self.parse_ifexpr())
}

///|
fn Parser::parse_expr_noif(self : Parser) -> Expr raise TemplateError {
  self.parse_or()
}

///|
fn Parser::parse_stmt(self : Parser) -> Stmt raise TemplateError {
  self.depth += 1
  if self.depth > max_recursion {
    raise syntax_error("template exceeds maximum recursion limits")
  }
  let rv = self.parse_stmt_unprotected()
  self.depth -= 1
  rv
}

///|
fn Parser::parse_stmt_unprotected(self : Parser) -> Stmt raise TemplateError {
  let (token, span) = self.expect_any("block keyword")
  let ident = match token {
    Ident(ident) => ident
    token =>
      raise syntax_error("unknown \{token.describe()}, expected statement")
  }
  match ident {
    "for" => {
      let (target, iter, filter_expr, recursive, body, else_body) = self.parse_for_stmt()
      ForLoop({
        target,
        iter,
        filter_expr,
        recursive,
        body,
        else_body,
        span: self.stream.expand_span(span),
      })
    }
    "if" => {
      let (expr, true_body, false_body) = self.parse_if_cond()
      IfCond({
        expr,
        true_body,
        false_body,
        span: self.stream.expand_span(span),
      })
    }
    "with" => {
      let (assignments, body) = self.parse_with_block()
      WithBlock({ assignments, body, span: self.stream.expand_span(span), })
    }
    "set" =>
      match self.parse_set() {
        Set(target, expr) =>
          Set({ target, expr, span: self.stream.expand_span(span), })
        SetBlock(target, filter, body) =>
          SetBlock({
            target,
            filter,
            body,
            span: self.stream.expand_span(span),
          })
      }
    "autoescape" => {
      let enabled = self.parse_expr()
      ignore(self.expect(t => t is BlockEnd, "end of block"))
      let body = self.subparse(is_ident("endautoescape"))
      ignore(self.stream.next())
      AutoEscape({ enabled, body, span: self.stream.expand_span(span), })
    }
    "filter" => {
      let filter = self.parse_filter_chain()
      ignore(self.expect(t => t is BlockEnd, "end of block"))
      let body = self.subparse(is_ident("endfilter"))
      ignore(self.stream.next())
      FilterBlock({ filter, body, span: self.stream.expand_span(span), })
    }
    "block" => {
      let (name, required, body) = self.parse_block()
      Block({ name, required, body, span: self.stream.expand_span(span), })
    }
    "extends" => {
      let name = self.parse_expr()
      Extends({ name, span: self.stream.expand_span(span), })
    }
    "include" => {
      let (name, ignore_missing) = self.parse_include()
      Include({ name, ignore_missing, span: self.stream.expand_span(span), })
    }
    "import" => {
      let expr = self.parse_expr()
      ignore(self.expect_keyword("as", "as"))
      let name = self.parse_expr()
      ignore(self.skip_context_marker())
      Import({ expr, name, span: self.stream.expand_span(span), })
    }
    "from" => {
      let (expr, names) = self.parse_from_import()
      FromImport({ expr, names, span: self.stream.expand_span(span), })
    }
    "macro" => {
      let m = self.parse_macro()
      Macro({ ..m, span: self.stream.expand_span(span), })
    }
    "call" => {
      let (call, macro_decl) = self.parse_call_block()
      CallBlock({ call, macro_decl, span: self.stream.expand_span(span), })
    }
    "continue" => {
      if !self.in_loop {
        raise syntax_error("'continue' must be placed inside a loop")
      }
      Continue(self.stream.expand_span(span))
    }
    "break" => {
      if !self.in_loop {
        raise syntax_error("'break' must be placed inside a loop")
      }
      Break(self.stream.expand_span(span))
    }
    "do" => {
      let call = self.parse_do()
      Do({ call, span: self.stream.expand_span(span), })
    }
    name => raise syntax_error("unknown statement \{name}")
  }
}

///|
fn Parser::parse_assign_name(
  self : Parser,
  dotted : Bool,
) -> Expr raise TemplateError {
  let (id, span) = self.expect_ident("identifier")
  if reserved_names.contains(id) {
    raise syntax_error("cannot assign to reserved variable name \{id}")
  }
  let mut rv = Var({ id, span, })
  if dotted {
    while self.skip(t => t is Dot) {
      let (attr, span) = self.expect_ident("identifier")
      rv = GetAttr({ expr: rv, name: attr, span, })
    }
  }
  rv
}

///|
fn Parser::parse_assignment(
  self : Parser,
  dotted : Bool,
) -> Expr raise TemplateError {
  let span = self.stream.current_span()
  let items = []
  let mut is_tuple = false
  for ;; {
    if !items.is_empty() {
      ignore(self.expect(t => t is Comma, "`,`"))
    }
    if self.matches(t => {
        t is (ParenClose | VariableEnd | BlockEnd | Ident("in"))
      }) {
      break
    }
    items.push(
      if self.skip(t => t is ParenOpen) {
        let rv = self.parse_assignment(dotted)
        ignore(self.expect(t => t is ParenClose, "`)`"))
        rv
      } else {
        self.parse_assign_name(dotted)
      },
    )
    if self.matches(t => t is Comma) {
      is_tuple = true
    } else {
      break
    }
  }
  if !is_tuple && items.length() == 1 {
    items[0]
  } else {
    List({ items, span: self.stream.expand_span(span), })
  }
}

///|
fn Parser::parse_for_stmt(
  self : Parser,
) -> (Expr, Expr, Expr?, Bool, Array[Stmt], Array[Stmt]) raise TemplateError {
  let old_in_loop = self.in_loop
  self.in_loop = true
  let target = self.parse_assignment(false)
  ignore(self.expect_keyword("in", "in"))
  let iter = self.parse_expr_noif()
  let filter_expr = if self.skip(is_ident("if")) {
    Some(self.parse_expr())
  } else {
    None
  }
  let recursive = self.skip(is_ident("recursive"))
  ignore(self.expect(t => t is BlockEnd, "end of block"))
  let body = self.subparse(t => t is (Ident("endfor") | Ident("else")))
  let else_body = if self.skip(is_ident("else")) {
    ignore(self.expect(t => t is BlockEnd, "end of block"))
    self.subparse(is_ident("endfor"))
  } else {
    []
  }
  ignore(self.stream.next())
  self.in_loop = old_in_loop
  (target, iter, filter_expr, recursive, body, else_body)
}

///|
fn Parser::parse_if_cond(
  self : Parser,
) -> (Expr, Array[Stmt], Array[Stmt]) raise TemplateError {
  let expr = self.parse_expr_noif()
  ignore(self.expect(t => t is BlockEnd, "end of block"))
  let true_body = self.subparse(t => {
    t is (Ident("endif") | Ident("else") | Ident("elif"))
  })
  let false_body = match self.stream.next() {
    Some((Ident("else"), _)) => {
      ignore(self.expect(t => t is BlockEnd, "end of block"))
      let rv = self.subparse(is_ident("endif"))
      ignore(self.stream.next())
      rv
    }
    Some((Ident("elif"), span)) => {
      let (expr, true_body, false_body) = self.parse_if_cond()
      [
        Stmt::IfCond({
          expr,
          true_body,
          false_body,
          span: self.stream.expand_span(span),
        }),
      ]
    }
    _ => []
  }
  (expr, true_body, false_body)
}

///|
fn Parser::parse_with_block(
  self : Parser,
) -> (Array[(Expr, Expr)], Array[Stmt]) raise TemplateError {
  let assignments = []
  while !self.matches(t => t is BlockEnd) {
    if !assignments.is_empty() {
      ignore(self.expect(t => t is Comma, "comma"))
    }
    let target = if self.skip(t => t is ParenOpen) {
      let assign = self.parse_assignment(false)
      ignore(self.expect(t => t is ParenClose, "`)`"))
      assign
    } else {
      self.parse_assign_name(false)
    }
    ignore(self.expect(t => t is Assign, "assignment operator"))
    let expr = self.parse_expr()
    assignments.push((target, expr))
  }
  ignore(self.expect(t => t is BlockEnd, "end of block"))
  let body = self.subparse(is_ident("endwith"))
  ignore(self.stream.next())
  (assignments, body)
}

///|
fn Parser::parse_set(self : Parser) -> SetParseResult raise TemplateError {
  let target = self.parse_assignment(true)
  if self.matches(t => t is (BlockEnd | Pipe)) {
    let filter = if self.skip(t => t is Pipe) {
      Some(self.parse_filter_chain())
    } else {
      None
    }
    ignore(self.expect(t => t is BlockEnd, "end of block"))
    let body = self.subparse(is_ident("endset"))
    ignore(self.stream.next())
    SetBlock(target, filter, body)
  } else {
    ignore(self.expect(t => t is Assign, "assignment operator"))
    // Parse RHS - single expression or comma-separated tuple
    let expr = self.parse_expr()
    let expr = if self.skip(t => t is Comma) {
      let span = self.stream.current_span()
      let items = [expr]
      for ;; {
        if self.matches(t => t is BlockEnd) {
          break
        }
        items.push(self.parse_expr())
        if !self.skip(t => t is Comma) {
          break
        }
      }
      Expr::Tuple({ items, span: self.stream.expand_span(span), })
    } else {
      expr
    }
    Set(target, expr)
  }
}

///|
fn Parser::parse_block(
  self : Parser,
) -> (String, Bool, Array[Stmt]) raise TemplateError {
  if self.in_macro {
    raise syntax_error("block tags in macros are not allowed")
  }
  let old_in_loop = self.in_loop
  self.in_loop = false
  let (name, _) = self.expect_ident("identifier")
  if self.matches(is_ident("scoped")) {
    ignore(self.stream.next())
  }
  let required = if self.matches(is_ident("required")) {
    ignore(self.stream.next())
    true
  } else {
    false
  }
  if self.blocks.contains(name) {
    raise syntax_error("block '\{name}' defined twice")
  }
  self.blocks.add(name)
  ignore(self.expect(t => t is BlockEnd, "end of block"))
  let body = self.subparse(is_ident("endblock"))
  ignore(self.stream.next())
  if required &&
    !body
    .iter()
    .all(stmt => {
      match stmt {
        EmitRaw(raw) => trim_view(raw.raw).length() == 0
        _ => false
      }
    }) {
    raise syntax_error(
      "Required blocks can only contain comments or whitespace",
    )
  }
  if self.stream.current() is Some((Ident(trailing_name), _)) {
    if trailing_name != name {
      raise syntax_error(
        "mismatching name on block. Got `\{trailing_name}`, expected `\{name}`",
      )
    }
    ignore(self.stream.next())
  }
  self.in_loop = old_in_loop
  (name, required, body)
}

///|
fn Parser::parse_filter_chain(self : Parser) -> Expr raise TemplateError {
  let mut filter : Expr? = None
  while !self.matches(t => t is BlockEnd) {
    if filter is Some(_) {
      ignore(self.expect(t => t is Pipe, "`|`"))
    }
    let (name, span) = self.parse_filter_test_name()
    let args = if self.matches(t => t is ParenOpen) {
      self.parse_args()
    } else {
      []
    }
    filter = Some(
      Filter({ name, expr: filter, args, span: self.stream.expand_span(span), }),
    )
  }
  match filter {
    Some(f) => f
    None => raise syntax_error("expected a filter")
  }
}

///|
fn Parser::parse_include(self : Parser) -> (Expr, Bool) raise TemplateError {
  let name = self.parse_expr()
  let skipped_context = self.skip_context_marker()
  let ignore_missing = if self.skip(is_ident("ignore")) {
    ignore(self.expect_keyword("missing", "missing keyword"))
    if !skipped_context {
      ignore(self.skip_context_marker())
    }
    true
  } else {
    false
  }
  (name, ignore_missing)
}

///|
fn Parser::parse_from_import(
  self : Parser,
) -> (Expr, Array[(Expr, Expr?)]) raise TemplateError {
  let expr = self.parse_expr()
  let names = []
  ignore(self.expect_keyword("import", "import"))
  for ;; {
    if self.skip_context_marker() || self.matches(t => t is BlockEnd) {
      break
    }
    if !names.is_empty() {
      ignore(self.expect(t => t is Comma, "`,`"))
    }
    if self.skip_context_marker() || self.matches(t => t is BlockEnd) {
      break
    }
    let name = self.parse_assign_name(false)
    let alias_name = if self.skip(is_ident("as")) {
      Some(self.parse_assign_name(false))
    } else {
      None
    }
    names.push((name, alias_name))
  }
  (expr, names)
}

///|
fn Parser::skip_context_marker(self : Parser) -> Bool raise TemplateError {
  // with/without context is without meaning in MiniJinja, but for syntax
  // compatibility it's supported.
  if self.skip(t => t is (Ident("with") | Ident("without"))) {
    ignore(self.expect_keyword("context", "context"))
    true
  } else {
    false
  }
}

///|
fn Parser::parse_macro_args_and_defaults(
  self : Parser,
  args : Array[Expr],
  defaults : Array[Expr],
) -> Unit raise TemplateError {
  for ;; {
    if self.skip(t => t is ParenClose) {
      break
    }
    if !args.is_empty() {
      ignore(self.expect(t => t is Comma, "`,`"))
      if self.skip(t => t is ParenClose) {
        break
      }
    }
    args.push(self.parse_assign_name(false))
    if self.skip(t => t is Assign) {
      defaults.push(self.parse_expr())
    } else if !defaults.is_empty() {
      ignore(self.expect(t => t is Assign, "`=`"))
    }
  }
}

///|
fn Parser::parse_macro_or_call_block_body(
  self : Parser,
  args : Array[Expr],
  defaults : Array[Expr],
  name : String?,
) -> MacroNode raise TemplateError {
  ignore(self.expect(t => t is BlockEnd, "end of block"))
  let old_in_loop = self.in_loop
  self.in_loop = false
  let old_in_macro = self.in_macro
  self.in_macro = true
  let is_macro = name is Some(_)
  let body = self.subparse(t => {
    match t {
      Ident("endmacro") if is_macro => true
      Ident("endcall") if !is_macro => true
      _ => false
    }
  })
  self.in_macro = old_in_macro
  self.in_loop = old_in_loop
  ignore(self.stream.next())
  {
    name: name.unwrap_or("caller"),
    args,
    defaults,
    body,
    span: Span::default(),
  }
}

///|
fn Parser::parse_macro(self : Parser) -> MacroNode raise TemplateError {
  let (name, _) = self.expect_ident("identifier")
  ignore(self.expect(t => t is ParenOpen, "`(`"))
  let args = []
  let defaults = []
  self.parse_macro_args_and_defaults(args, defaults)
  self.parse_macro_or_call_block_body(args, defaults, Some(name))
}

///|
fn Parser::parse_call_block(
  self : Parser,
) -> (CallNode, MacroNode) raise TemplateError {
  let span = self.stream.last_span
  let args = []
  let defaults = []
  if self.skip(t => t is ParenOpen) {
    self.parse_macro_args_and_defaults(args, defaults)
  }
  let call = match self.parse_expr() {
    Call(call) => call
    expr =>
      raise syntax_error(
        "expected call expression in call block, got \{expr.description()}",
      )
  }
  let macro_decl = self.parse_macro_or_call_block_body(args, defaults, None)
  (call, { ..macro_decl, span: self.stream.expand_span(span), })
}

///|
fn Parser::parse_do(self : Parser) -> CallNode raise TemplateError {
  match self.parse_expr() {
    Call(call) => call
    expr =>
      raise syntax_error(
        "expected call expression in call block, got \{expr.description()}",
      )
  }
}

///|
fn Parser::subparse(
  self : Parser,
  end_check : (Token) -> Bool,
) -> Array[Stmt] raise TemplateError {
  let rv = []
  while self.stream.next() is Some((token, span)) {
    match token {
      TemplateData(raw) => rv.push(Stmt::EmitRaw({ raw, span, }))
      VariableStart => {
        let expr = self.parse_expr()
        rv.push(Stmt::EmitExpr({ expr, span: self.stream.expand_span(span), }))
        ignore(self.expect(t => t is VariableEnd, "end of variable block"))
      }
      BlockStart => {
        let tok = match self.stream.current() {
          Some((tok, _)) => tok
          None =>
            raise syntax_error("unexpected end of input, expected keyword")
        }
        if end_check(tok) {
          return rv
        }
        rv.push(self.parse_stmt())
        ignore(self.expect(t => t is BlockEnd, "end of block"))
      }
      _ => abort("lexer produced garbage")
    }
  }
  rv
}

///|
fn Parser::attach_location_to_error(
  self : Parser,
  err : TemplateError,
) -> TemplateError {
  if err.line() is None {
    err.set_filename_and_span(self.filename(), self.stream.last_span)
  }
  err
}

///|
/// Parses a template.
fn parse(
  source : String,
  filename : String,
  syntax_config : SyntaxConfig,
  ws_config : WhitespaceConfig,
) -> Stmt raise TemplateError {
  Parser::new(source, filename, false, syntax_config, ws_config).parse()
}

///|
/// Parses a standalone expression.
fn parse_expr(source : String) -> Expr raise TemplateError {
  Parser::new(
    source,
    "<expression>",
    true,
    SyntaxConfig::default(),
    WhitespaceConfig::default(),
  ).parse_standalone_expr()
}
