///|
fn render_error(prefix : String, err : TemplateError) -> String {
  let sb = StringBuilder()
  sb.write_string(prefix)
  sb.write_string("\n\n")
  sb.write_string(err.debug_string(pretty=true))
  sb.write_string("\n\n")
  sb.write_string(err.display_with_debug_info())
  sb.write_char('\n')
  sb.to_string()
}

///|
fn render_error_chain(err : TemplateError) -> String {
  let sb = StringBuilder()
  sb.write_string(render_error("!!!ERROR!!!", err))
  let mut cur = err.source()
  while cur is Some(next_err) {
    sb.write_string("\ncaused by: ")
    sb.write_string(next_err.display_with_debug_info())
    sb.write_char('\n')
    cur = next_err.source()
  }
  sb.to_string()
}

///|
fn apply_template_settings(
  env : Environment,
  ctx : Value,
) -> Unit raise TemplateError {
  let settings = ctx.get_attr("$settings") catch { _ => Value::undefined() }
  if settings.is_undefined() {
    return
  }
  let get_bool = (key : String) => {
    (settings.get_attr(key) catch { _ => Value::undefined() }).is_true()
  }
  let get_str = (key : String) => {
    (settings.get_attr(key) catch { _ => Value::undefined() }).as_str()
  }
  match get_str("undefined") {
    Some("strict") => env.set_undefined_behavior(Strict)
    Some("semi_strict") => env.set_undefined_behavior(SemiStrict)
    Some("chainable") => env.set_undefined_behavior(Chainable)
    _ => env.set_undefined_behavior(Lenient)
  }
  env.set_keep_trailing_newline(get_bool("keep_trailing_newline"))
  env.set_trim_blocks(get_bool("trim_blocks"))
  env.set_lstrip_blocks(get_bool("lstrip_blocks"))
  let markers = settings.get_attr("markers") catch { _ => Value::undefined() }
  let ls = get_str("line_statement_prefix").unwrap_or("")
  let lc = get_str("line_comment_prefix").unwrap_or("")
  let syntax = if markers.is_undefined() {
    SyntaxConfig::new(line_statement_prefix=ls, line_comment_prefix=lc)
  } else {
    let m = markers.try_iter().map(x => x.to_string()).to_array()
    SyntaxConfig::new(
      block_delimiters=(m[0], m[1]),
      variable_delimiters=(m[2], m[3]),
      comment_delimiters=(m[4], m[5]),
      line_statement_prefix=ls,
      line_comment_prefix=lc,
    )
  }
  env.set_syntax(syntax)
}

///|
async fn load_refs(dir : String) -> Array[(String, String)] {
  let rv = []
  for name in @fs.readdir(dir, sort=true) {
    if name.has_suffix(".txt") || name.has_suffix(".html") {
      rv.push((name, read_text("\{dir}/\{name}")))
    }
  }
  rv
}

///|
async test "template snapshots" {
  let refs = load_refs("testdata/inputs/refs")
  run_snapshot_suite("templates", "testdata/inputs", "test_templates__vm@", (
    name,
    contents,
  ) => {
    let (header, content) = split_fixture(contents)
    let env = Environment::new()
    env.add_global(
      "get_args",
      Value::from_function(
        "test_templates::test_vm::{{closure}}::{{closure}}",
        (state, args) => {
          Value::from_array(Args::new(state, args).rest_with_kwargs())
        },
      ),
    )
    let ctx = Value::from_json_str(header, sort_keys=true)
    apply_template_settings(env, ctx)
    for item in refs {
      env.add_template(item.0, item.1)
    }
    env.add_template(name, content) catch {
      err => return render_error("!!!SYNTAX ERROR!!!", err)
    }
    let template = env.get_template(name)
    let actual_context = merge_maps([
      ctx,
      Value::from_pairs([
        (
          "one_shot_iterator",
          Value::make_one_shot_iterator(
            [Value::from_int(0), Value::from_int(1), Value::from_int(2)].iter(),
          ),
        ),
      ]),
    ])
    try template.render(actual_context) catch {
      err => render_error_chain(err)
    } noraise {
      rendered => rendered + "\n"
    }
  })
}
