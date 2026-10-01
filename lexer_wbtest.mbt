///|
fn json_bool(obj : Map[String, Json], key : String) -> Bool {
  obj.get(key) is Some(True)
}

///|
fn json_str(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Builds the syntax and whitespace config from the test settings used by
/// the upstream test-suite.
fn settings_to_configs(
  settings : Json,
) -> (SyntaxConfig, WhitespaceConfig) raise TemplateError {
  guard settings is Object(obj) else {
    return (SyntaxConfig::default(), WhitespaceConfig::default())
  }
  let ws = {
    keep_trailing_newline: json_bool(obj, "keep_trailing_newline"),
    lstrip_blocks: json_bool(obj, "lstrip_blocks"),
    trim_blocks: json_bool(obj, "trim_blocks"),
  }
  let markers = match obj.get("markers") {
    Some(Array(m)) =>
      Some(
        m.map(x => {
          match x {
            String(s) => s
            _ => ""
          }
        }),
      )
    _ => None
  }
  let syntax = match markers {
    Some(m) =>
      SyntaxConfig::new(
        block_delimiters=(m[0], m[1]),
        variable_delimiters=(m[2], m[3]),
        comment_delimiters=(m[4], m[5]),
        line_statement_prefix=json_str(obj, "line_statement_prefix").unwrap_or(
          "",
        ),
        line_comment_prefix=json_str(obj, "line_comment_prefix").unwrap_or(""),
      )
    None =>
      SyntaxConfig::new(
        line_statement_prefix=json_str(obj, "line_statement_prefix").unwrap_or(
          "",
        ),
        line_comment_prefix=json_str(obj, "line_comment_prefix").unwrap_or(""),
      )
  }
  (syntax, ws)
}

///|
fn stringify_tokens(tokens : Array[(Token, Span)], contents : String) -> String {
  let sb = StringBuilder()
  for item in tokens {
    let (token, span) = item
    let end = if span.end_offset > contents.length() {
      contents.length()
    } else {
      span.end_offset
    }
    let token_source = contents.view(
      start_offset=span.start_offset,
      end_offset=end,
    )
    sb.write_string(token.debug_string())
    sb.write_char('\n')
    sb.write_string("  ")
    sb.write_string(@rfmt.str_debug(token_source))
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
#cfg(any(target="native", target="wasm"))
async test "lexer snapshots" {
  run_snapshot_suite("lexer", "testdata/lexer-inputs", "test_lexer__lexer@", (
    _name,
    contents,
  ) => {
    let (header, template) = split_fixture(contents)
    let settings = @json.parse(header) catch { _ => Json::object({}) }
    let (syntax, ws) = settings_to_configs(settings)
    let tokens = tokenize(template, false, syntax, ws)
    stringify_tokens(tokens, template)
  })
}

///|
test "skip_basic_tag" {
  debug_inspect(
    skip_basic_tag(" raw %}", 0, "raw", "%}", false).map(x => x.0),
    content="Some(7)",
  )
  debug_inspect(
    skip_basic_tag(" raw %}", 0, "endraw", "%}", false).map(x => x.0),
    content="None",
  )
  debug_inspect(
    skip_basic_tag("  raw  %}", 0, "raw", "%}", false).map(x => x.0),
    content="Some(9)",
  )
  assert_true(
    skip_basic_tag("  raw  -%}", 0, "raw", "%}", false) is Some((10, Remove)),
  )
  assert_true(
    skip_basic_tag("  raw  +%}", 0, "raw", "%}", false) is Some((10, Preserve)),
  )
}

///|
test "basic identifiers" {
  fn is_single_ident(s : String) -> Bool {
    let tokens = tokenize(
      s,
      true,
      SyntaxConfig::default(),
      WhitespaceConfig::default(),
    ) catch {
      _ => return false
    }
    tokens is [(Ident(ident), _)] && ident == s
  }

  for
    s in [
      "foo_bar_baz", "_foo_bar_baz", "_42world", "_world42", "world42", "foo", "föö",
      "き", "_", "ᢅ", "ᢆ", "℘", "℮", "a·",
    ] {
    assert_true(is_single_ident(s), msg="expected identifier: \{s}")
  }
  for s in ["42world", "1a", "a-", "🐍a", "a🐍🐍", "·"] {
    assert_true(!is_single_ident(s), msg="expected no identifier: \{s}")
  }
}

///|
test "trim blocks" {
  let input = "{% block foo %}\nbar{% endblock %}"
  let tokens = tokenize(input, false, SyntaxConfig::default(), {
    keep_trailing_newline: false,
    lstrip_blocks: false,
    trim_blocks: true,
  })
  inspect(
    stringify_tokens(tokens, input),
    content=(
      #|BlockStart
      #|  "{%"
      #|Ident("block")
      #|  "block"
      #|Ident("foo")
      #|  "foo"
      #|BlockEnd
      #|  "%}"
      #|TemplateData("bar")
      #|  "bar"
      #|BlockStart
      #|  "{%"
      #|Ident("endblock")
      #|  "endblock"
      #|BlockEnd
      #|  "%}"
      #|
    ),
  )
}

///|
test "overflowing column" {
  let input = " ".repeat(70000) + "{{ x }}"
  let tokens = tokenize(
    input,
    false,
    SyntaxConfig::default(),
    WhitespaceConfig::default(),
  )
  let spans = tokens.map(x => x.1)
  inspect(
    spans
    .map(s => "\{s.start_col} \{s.start_offset} \{s.end_col} \{s.end_offset}")
    .join("|"),
    content="0 0 65535 70000|65535 70000 65535 70002|65535 70003 65535 70004|65535 70005 65535 70007",
  )
}
