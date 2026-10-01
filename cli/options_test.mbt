// Tests for options that upstream's test-suite does not cover.

///|
async test "help and version" {
  with_test_dir(dir => {
    let short = dir.run(["--help"])
    assert_true(short.has_prefix("success: true\nexit_code: 0\n"))
    assert_true(
      short.contains(
        "Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...",
      ),
    )
    assert_true(short.contains("--expr-out <MODE>"))
    let long = dir.run(["--long-help"])
    assert_true(long.contains("Sets the expression output mode for --expr."))
    let syntax = dir.run(["--syntax-help"])
    assert_true(syntax.contains("Syntax Reference"))
    inspect(
      dir.run(["-V"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|minijinja-cli 0.1.0
        #|
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "usage errors" {
  with_test_dir(dir => {
    inspect(
      dir.run(["--foo"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: unexpected argument '--foo' found
        #|
        #|  tip: to pass '--foo' as a value, use '-- --foo'
        #|
        #|Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--format", "yaml"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: invalid value 'yaml' for '--format <FORMAT>'
        #|  [possible values: auto, json, querystring]
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--fuel=lots"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: invalid value 'lots' for '--fuel <AMOUNT>': invalid digit found in string
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--expr-out=json"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: the following required arguments were not provided:
        #|  --expr <EXPR>
        #|
        #|Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--no-include", "--safe-path", "/tmp"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: the argument '--safe-path <PATH>...' cannot be used with '--no-include'
        #|
        #|Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["-E", "1", "--expr", "2"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: the argument '--expr <EXPR>' cannot be used multiple times
        #|
        #|Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--dump"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: a value is required for '--dump <KIND>' but none was supplied
        #|  [possible values: instructions, ast, tokens]
        #|
        #|For more information, try '--help'.
      ),
    )
    inspect(
      dir.run(["--strict=yes"]),
      content=(
        #|success: false
        #|exit_code: 2
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: unexpected value 'yes' for '--strict' found; no more were expected
        #|
        #|Usage: minijinja-cli [OPTIONS] [TEMPLATE_FILE] [DATA_FILE]...
        #|
        #|For more information, try '--help'.
      ),
    )
  })
}

///|
async test "expr" {
  with_test_dir(dir => {
    let input = dir.file("{\"items\": [1, 2, 3]}", ext=".json")
    inspect(
      dir.run(["-E", "items|sum", "-", input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|6
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run([
        "--expr", "{'a': items, 'b': none}", "--expr-out=json", "-", input,
      ]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|{"a":[1,2,3],"b":null}
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run(["-E", "{'a': [1]}", "--expr-out", "json-pretty"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|{
        #|  "a": [
        #|    1
        #|  ]
        #|}
        #|
        #|----- stderr -----
      ),
    )
    // status: integers are the exit code, other values their truthiness
    let status = (expr : String) => dir.run(["-E", expr, "--expr-out=status"])
    assert_true(status("42").has_prefix("success: false\nexit_code: 42\n"))
    assert_true(status("1 < 10").has_prefix("success: false\nexit_code: 1\n"))
    assert_true(status("'yes'").has_prefix("success: true\nexit_code: 0\n"))
    assert_true(status("''").has_prefix("success: false\nexit_code: 1\n"))
    inspect(
      dir.run(["-E", "1 +"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: syntax error: unexpected end of input, expected expression (in <expression>:1)
        #|
        #|-------------------------------- <expression> ---------------------------------
        #|   1 > 1 +
        #|     i   ^ syntax error
        #|~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        #|No referenced variables
        #|-------------------------------------------------------------------------------
      ),
    )
  })
}

///|
async test "defines" {
  with_test_dir(dir => {
    let input = dir.file(
      "{\"a\": \"from data\", \"b\": \"from data\"}",
      ext=".json",
    )
    inspect(
      dir.run([
        "-t", "{{ a }}|{{ b }}|{{ flag }}|{{ n + 1 }}|{{ seq|length }}", "", input,
        "-Da=from define", "-Dflag", "-Dn:=41", "-D", "seq:=[1, 2, true]",
      ]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|from define|from data|True|42|3
        #|
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run(["-t", "x", "-Dx:={"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: invalid raw value '{' (not valid JSON)
        #|
        #|caused by: cannot deserialize: invalid JSON at offset 1: expected string
      ),
    )
  })
}

///|
async test "output file" {
  with_test_dir(dir => {
    let out = "\{dir.path}/out.txt"
    inspect(
      dir.run(["-t", "Hello {{ name }}", "-Dname=World", "-o", "out.txt"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|
        #|----- stderr -----
      ),
    )
    inspect(@utf8.decode(@fs.read_file(out).binary()), content="Hello World\n")
    // a failing render leaves the original file alone
    let rv = dir.run(["-t", "{{ fail(", "-o", out])
    assert_true(rv.has_prefix("success: false\nexit_code: 1\n"))
    inspect(@utf8.decode(@fs.read_file(out).binary()), content="Hello World\n")
    // no temporary files are left behind
    assert_true(@fs.readdir(dir.path, include_hidden=true) == ["out.txt"])
  })
}

///|
async test "autoescape" {
  with_test_dir(dir => {
    let html = dir.file("{{ x }}", ext=".html")
    let html_j2 = dir.file("{{ x }}", ext=".html.j2")
    let json = dir.file("{{ x }}", ext=".json.j2")
    let txt = dir.file("{{ x }}", ext=".txt")
    let x = "-Dx=<a href=\"x\">"
    let render = (args : Array[String]) => dir.run(args + [x, "-n"])
    inspect(
      [
        render([html]),
        render([html_j2]),
        render([json]),
        render([txt]),
        render(["-a", "html", txt]),
        render(["--autoescape=json", txt]),
        render(["-anone", html]),
      ]
      .map(s => s.split("\n").to_array()[3].to_owned())
      .join("\n"),
      content=(
        #|&lt;a href=&quot;x&quot;&gt;
        #|&lt;a href=&quot;x&quot;&gt;
        #|"<a href=\"x\">"
        #|<a href="x">
        #|&lt;a href=&quot;x&quot;&gt;
        #|"<a href=\"x\">"
        #|<a href="x">
      ),
    )
  })
}

///|
async test "behavior flags" {
  with_test_dir(dir => {
    // contrib filters and globals are always available
    inspect(
      dir.run(["-t", "{{ 3|pluralize }} {{ 'a b c'|wordcount }}", "-n"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|s 3
        #|----- stderr -----
      ),
    )
    // python compatible methods need --py-compat
    let rv = dir.run(["-t", "{{ 'abc'.upper() }}", "-n"])
    assert_true(
      rv.contains("error: unknown method: string has no method named upper"),
    )
    inspect(
      dir.run(["-t", "{{ 'abc'.upper() }}", "-n", "--py-compat"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|ABC
        #|----- stderr -----
      ),
    )
    // strict undefined handling
    inspect(
      dir.run(["-t", "[{{ missing }}]", "-n"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|[]
        #|----- stderr -----
      ),
    )
    let rv = dir.run(["-t", "[{{ missing }}]", "-n", "--strict"])
    assert_true(rv.contains("error: undefined value (in <string>:1)"))
    // trim-blocks and lstrip-blocks
    let tmpl = "<\n  {% if true %}\n  x\n  {% endif %}\n>"
    inspect(
      dir.run(["-t", tmpl, "-n", "--trim-blocks", "--lstrip-blocks"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|<
        #|  x
        #|>
        #|----- stderr -----
      ),
    )
    // fuel
    let rv = dir.run([
      "-t", "{% for x in range(100) %}{{ x }}{% endfor %}", "--fuel", "50",
    ])
    assert_true(rv.contains("error: engine ran out of fuel"))
  })
}

///|
async test "syntax" {
  with_test_dir(dir => {
    inspect(
      dir.run([
        "-t", "${ name } {{ name }}", "-svariable-start=${", "-s", "variable-end=}",
        "-Dname=x", "-n",
      ]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|x {{ name }}
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run(["-t", "x", "-sfoo"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: syntax feature needs to be a key=value pair
      ),
    )
    inspect(
      dir.run(["-t", "x", "-sfoo=bar"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: unknown syntax feature 'foo'
      ),
    )
    inspect(
      dir.run(["-t", "x", "-sblock-start="]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: could not configure syntax
        #|
        #|caused by: invalid custom delimiters
      ),
    )
  })
}

///|
async test "environment configuration" {
  with_test_dir(dir => {
    inspect(
      dir.run(["-t", "{{ x }}{% if true %}\n!{% endif %}", "-Dx=<>"], env={
        "MINIJINJA_NEWLINE": "false",
        "MINIJINJA_AUTOESCAPE": "html",
        "MINIJINJA_TRIM_BLOCKS": "on",
      }),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|&lt;&gt;!
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run(["-t", "x"], env={ "MINIJINJA_STRICT": "maybe" }),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: Invalid boolean value for MINIJINJA_STRICT: maybe
      ),
    )
    let input = dir.file("{}", ext=".json")
    inspect(
      dir.run(["-t", "x", "", input], env={ "MINIJINJA_FORMAT": "yaml" }),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: Unknown format 'yaml'
      ),
    )
    inspect(
      dir.run(["-t", "{{ ENV.GREETING }}", "-n"], env={
        "GREETING": "hi",
        "MINIJINJA_ENV": "1",
      }),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|hi
        #|----- stderr -----
      ),
    )
  })
}

///|
async test "includes and safe paths" {
  with_test_dir(dir => {
    @fs.mkdir("\{dir.path}/sub")
    @fs.write_file(
      "\{dir.path}/sub/layout.j2",
      "[{% block body %}{% endblock %}]",
    )
    @fs.write_file("\{dir.path}/sub/part.j2", "part")
    @fs.write_file(
      "\{dir.path}/sub/page.j2",
      "{% extends 'layout.j2' %}{% block body %}{% include 'part.j2' %}|{% include '../top.j2' %}{% endblock %}",
    )
    @fs.write_file("\{dir.path}/top.j2", "top")
    inspect(
      dir.run(["sub/page.j2", "-n"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|[part|top]
        #|----- stderr -----
      ),
    )
    // ignore missing / choices see the files once they are loaded
    @fs.write_file(
      "\{dir.path}/choice.j2",
      "{% include ['sub/missing.j2', 'top.j2'] %}|{% include 'nope.j2' ignore missing %}|{% include ['top.j2', 'sub/part.j2'] %}",
    )
    inspect(
      dir.run(["choice.j2", "-n"]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|top||top
        #|----- stderr -----
      ),
    )
    let rv = dir.run(["sub/page.j2", "-n", "--safe-path", "\{dir.path}/sub"])
    assert_true(
      rv.contains(
        "error: invalid operation: Cannot include template from non-trusted path",
      ),
    )
    inspect(
      dir.run([
        "sub/page.j2",
        "-n",
        "--safe-path",
        "\{dir.path}/sub",
        "--safe-path",
        dir.path,
      ]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|[part|top]
        #|----- stderr -----
      ),
    )
    let rv = dir.run(["missing.j2"])
    assert_true(rv.contains("error: template not found: template "))
  })
}

///|
async test "data errors" {
  with_test_dir(dir => {
    inspect(
      dir.run(["-t", "x", "", "missing.json"]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: unable to read data file 'missing.json'
        #|
        #|caused by: No such file or directory (os error 2)
      ),
    )
    let txt = dir.file("{}", ext=".txt")
    let rv = dir.run(["-t", "x", "", txt])
    assert_true(rv.contains("error: cannot auto detect format from extension"))
    let list = dir.file("[1, 2]", ext=".json")
    inspect(
      dir.run(["-t", "x", "", list]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: failed to interpret input data as object
        #|
        #|caused by: invalid type: sequence, expected a map
      ),
    )
    let nested = dir.file("{\"a\": [{\"b\": {\"c\": 1}}]}", ext=".json")
    inspect(
      dir.run(["-t", "{{ c }}", "-n", "--select=a.0.b", "", nested]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|1
        #|----- stderr -----
      ),
    )
    inspect(
      dir.run(["-t", "x", "--select=a.5", "", nested]),
      content=(
        #|success: false
        #|exit_code: 1
        #|----- stdout -----
        #|
        #|----- stderr -----
        #|error: failed to interpret input data as object
        #|
        #|caused by: invalid type: undefined, expected a map
      ),
    )
    // stdin can only be used once
    let rv = dir.run(["-", "-", "--format=json"], stdin="{}")
    assert_true(
      rv.contains(
        "error: invalid operation: cannot load template from stdin when data is from stdin",
      ),
    )
  })
}

///|
async test "querystring nesting" {
  with_test_dir(dir => {
    let input = dir.file(
      "user[name]=Peter&user[tags][first]=a%20b&empty&x=1&x=2",
      ext=".qs",
    )
    inspect(
      dir.run(["-E", "[user.name, user.tags.first, empty, x]", "-", input]),
      content=(
        #|success: true
        #|exit_code: 0
        #|----- stdout -----
        #|['Peter', 'a b', '', '2']
        #|
        #|----- stderr -----
      ),
    )
  })
}
