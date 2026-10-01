// Generated from upstream benchmarks/inputs (see scripts in the commit).

///|
let bench_all_elements_src : String =
  #|<!doctype html>
  #|<meta charset="utf-8">
  #|<title>{% block title %}{% endblock %} | Hello</title>
  #|<link rel="stylesheet" href="{{ 'styles/index.css'|asset_url }}">
  #|{# this is a comment #}
  #|<body>
  #|{% block html_body %}
  #|  <header>
  #|    <h1>Hello</h1>
  #|    <nav>
  #|      <ul class="nav">
  #|        {% for item in site.nav %}
  #|          <li><a href="{{ item.url }}"{% if item.is_active %} class="active"{% endif %}>{{ item.title|upper }}</a>
  #|        {% endfor %}
  #|      </ul>
  #|    </nav>
  #|  </header>
  #|  <main>
  #|    {% block body %}
  #|      <ul>
  #|      {% for item in items %}
  #|        <li>{{ loop.index }}: {{ item|upper }}</li>
  #|      {% endfor %}
  #|      </ul>
  #|    {% endblock %}
  #|  </main>
  #|  <footer>
  #|    {% block footer %}
  #|      {% with copyright=current_year() %}
  #|        {% include "footer.html" %}
  #|      {% endwith %}
  #|    {% endblock %}
  #|  </footer>
  #|  {% if DEBUG %}
  #|    <pre class="debug">{{ debug() }}</pre>
  #|  {% endif %}
  #|{% endblock html_body %}
  #|</body>
  #|

///|
let bench_footer_src : String =
  #|Copyright {{ copyright }}!

///|
let bench_map_items_src : String =
  #|ID,NAME
  #|
  #|{% for id, name in employees | items %}
  #|{{id}},{{name}}
  #|{% endfor %}
  #|

///|
test "bench: compile phases" (b : @bench.T) {
  let src = bench_all_elements_src
  b.bench(name="lex", () => {
    let toks = tokenize(
      src,
      false,
      SyntaxConfig::default(),
      WhitespaceConfig::default(),
    ) catch {
      _ => abort("x")
    }
    b.keep(toks)
  })
  b.bench(name="parse", () => {
    let ast = parse(
      src,
      "x",
      SyntaxConfig::default(),
      WhitespaceConfig::default(),
    ) catch {
      _ => abort("x")
    }
    b.keep(ast)
  })
  let ast = parse(
    src,
    "x",
    SyntaxConfig::default(),
    WhitespaceConfig::default(),
  )
  b.bench(name="codegen", () => {
    let g = CodeGenerator::new("x", src)
    g.compile_stmt(ast)
    b.keep(g.finish())
  })
}
