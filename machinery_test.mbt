///|
test "debug_tokens" {
  inspect(
    @minijinja.debug_tokens("Hello {{ foo }}!").join("\n"),
    content=(
      #|TemplateData("Hello ")
      #|VariableStart
      #|Ident("foo")
      #|VariableEnd
      #|TemplateData("!")
    ),
  )
}

///|
test "debug_ast" {
  inspect(
    @minijinja.debug_ast("{{ x }}", "t.j2"),
    content=(
      #|Template {
      #|    children: [
      #|        EmitExpr {
      #|            expr: Var {
      #|                id: "x",
      #|            } @ 1:3-1:4,
      #|        } @ 1:0-1:4,
      #|    ],
      #|} @ 0:0-1:7
    ),
  )
}

///|
test "debug_instructions" {
  let env = @minijinja.Environment::new()
  let tmpl = env.template_from_named_str(
    "t.j2", "{% block b %}B{% endblock %}{% block a %}{{ x }}{% endblock %}",
  )
  let sb = StringBuilder()
  for block in tmpl.debug_instructions() {
    sb.write_string("\{block.0}: \{block.1.join(", ")}\n")
  }
  inspect(
    sb.to_string(),
    content=(
      #|a: Lookup("x"), Emit
      #|b: EmitRaw("B")
      #|<root>: CallBlock("b"), CallBlock("a")
      #|
    ),
  )
}
