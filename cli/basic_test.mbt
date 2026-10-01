// Ports of upstream's `minijinja-cli/tests/test_basic.rs` (the cases that
// apply to the formats supported by this port).  Expected outputs are the
// upstream snapshots.

///|
async test "explicit_format" {
  with_test_dir(dir => {
    let input = dir.file("{\"foo\": \"bar\"}")
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run(["--format=json", tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello bar!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "no_newline" {
  with_test_dir(dir => {
    let input = dir.file("{\"foo\": \"bar\"}")
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run(["--format=json", "--no-newline", tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello bar!
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "json" {
  with_test_dir(dir => {
    let input = dir.file("{\"foo\": \"bar\"}", ext=".json")
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run([tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello bar!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
/// Upstream uses a JSON and a YAML file; this port uses two JSON files.
async test "multiple_data_files" {
  with_test_dir(dir => {
    let json_input = dir.file(
      "{\"name\": \"World\", \"greeting\": \"Hello\"}",
      ext=".json",
    )
    let json_input2 = dir.file("{\"greeting\": \"Hi\"}", ext=".json")
    let tmpl = dir.file("{{ greeting }} {{ name }}!")
    inspect(
      dir.run([tmpl, json_input, json_input2]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hi World!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
/// Upstream uses a JSON and a YAML file; this port uses two JSON files.
async test "select_from_toplevel" {
  with_test_dir(dir => {
    let json_input = dir.file(
      "{\"base\": {\"name\": \"World\", \"greeting\": \"Hello\"}}",
      ext=".json",
    )
    let json_input2 = dir.file(
      "{\"base\": {\"greeting\": \"Hi\"}}",
      ext=".json",
    )
    let tmpl = dir.file("{{ greeting }} {{ name }}!")
    inspect(
      dir.run(["--select=base", tmpl, json_input, json_input2]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hi World!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "querystring" {
  with_test_dir(dir => {
    let input = dir.file("foo=blub+blah%2fx", ext=".qs")
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run([tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello blub blah/x!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "preserve_order_json" {
  with_test_dir(dir => {
    let input = dir.file("{\"x\": {\"c\": 3, \"a\": 1, \"b\": 2}}", ext=".json")
    let tmpl = dir.file(
      "{% for key, value in x|items %}{{ key }}: {{ value }}\n{% endfor %}",
    )
    inspect(
      dir.run([tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|c: 3
        #|a: 1
        #|b: 2
        #|
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "context_stdin" {
  with_test_dir(dir => {
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run([tmpl, "-", "--format=json"], stdin="{\"foo\": \"bar\"}"),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello bar!
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run([tmpl, "-"], stdin=""),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: auto detection does not work with data from stdin
      ),
    )
  })
}

///|
async test "dump" {
  with_test_dir(dir => {
    let tmpl = dir.file("Hello {{ foo }}!")
    inspect(
      dir.run([tmpl, "--dump=tokens"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|TemplateData("Hello ")
        #|VariableStart
        #|Ident("foo")
        #|VariableEnd
        #|TemplateData("!")
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run([tmpl, "--dump=ast"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Template {
        #|    children: [
        #|        EmitRaw {
        #|            raw: "Hello ",
        #|        } @ 1:0-1:6,
        #|        EmitExpr {
        #|            expr: Var {
        #|                id: "foo",
        #|            } @ 1:9-1:12,
        #|        } @ 1:6-1:12,
        #|        EmitRaw {
        #|            raw: "!",
        #|        } @ 1:15-1:16,
        #|    ],
        #|} @ 0:0-1:16
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run([tmpl, "--dump=instructions"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Block: "<root>"
        #|     0: EmitRaw("Hello ")
        #|     1: Lookup("foo")
        #|     2: Emit
        #|     3: EmitRaw("!")
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "include" {
  with_test_dir(dir => {
    let tmpl = dir.file("{% include ENV.OTHER_TEMPLATE %}")
    let other_tmpl = dir.file("Hello!")
    let input = dir.file("{}", ext=".json")
    inspect(
      dir.run([tmpl, input, "--env"], env={ "OTHER_TEMPLATE": other_tmpl }),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "no_include" {
  with_test_dir(dir => {
    let tmpl = dir.file("{% include ENV.OTHER_TEMPLATE %}")
    let other_tmpl = dir.file("Hello!")
    let input = dir.file("{}", ext=".json")
    inspect(
      dir.run([tmpl, input, "--env", "--no-include"], env={
        "OTHER_TEMPLATE": other_tmpl,
      }),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: template not found: tried to include non-existing template [FILENAME HERE]
        #|
        #|--- [TEMPLATE] ---
        #|   1 > {% include ENV.OTHER_TEMPLATE %}
        #|     i    ^^^^^^^^^^^^^^^^^^^^^^^^^^ template not found
        #|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        #|Referenced variables: { ... }
      ),
    )
  })
}

///|
async test "syntax_error" {
  with_test_dir(dir => {
    let tmpl = dir.file("{{ all_good }}\n{% for item in seq")
    let input = dir.file("{}", ext=".json")
    inspect(
      dir.run([tmpl, input]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: syntax error: unexpected end of input, expected end of block (in [TEMPLATE]:2)
        #|
        #|--- [TEMPLATE] ---
        #|   1 | {{ all_good }}
        #|   2 > {% for item in seq
        #|     i                ^^^ syntax error
        #|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        #|No referenced variables
        #|-------------------------------------------------------------------------------
      ),
    )
  })
}

///|
async test "stdin_template" {
  with_test_dir(dir => {
    let input = dir.file("{\"foo\": \"bar\"}", ext=".json")
    inspect(
      dir.run(["-", input], stdin="Hello {{ foo }}!"),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello bar!
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "line_statement" {
  with_test_dir(dir => {
    let tmpl = dir.file("# for item in seq\n  {{ item }}\n# endfor")
    let input = dir.file("{\"seq\": [1, 2, 3]}", ext=".json")
    inspect(
      dir.run(["-sline-statement-prefix=#", "--no-newline", tmpl, input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|  1
        #|  2
        #|  3
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "template_string" {
  with_test_dir(dir => {
    inspect(
      dir.run(["-tHello {{ name }}", "-Dname=Peter", "--no-newline"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello Peter
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "empty_template_name_with_string_template" {
  with_test_dir(dir => {
    let input = dir.file("{\"name\": \"Peter\"}", ext=".json")
    inspect(
      dir.run(["-tHello {{ name }}", "", input, "--no-newline"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|Hello Peter
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "template_name_with_string_template_fails" {
  with_test_dir(dir => {
    let input = dir.file("{\"name\": \"Peter\"}", ext=".json")
    inspect(
      dir.run(["-tHello {{ name }}", "invalid.tmpl", input, "--no-newline"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: When --template is used, a template cannot be passed as argument (only an empty argument is allowed).
      ),
    )
  })
}

///|
async test "empty_template_name_errors" {
  with_test_dir(dir => {
    let input = dir.file("{\"name\": \"Peter\"}", ext=".json")
    inspect(
      dir.run(["", input, "--no-newline"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: Empty template names are only valid with --template.
      ),
    )
  })
}
