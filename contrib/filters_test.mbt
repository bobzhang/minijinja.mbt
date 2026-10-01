///|
test "test_pluralize" {
  for
    case in [
      (0, "You have 0 messages."),
      (1, "You have 1 message."),
      (10, "You have 10 messages."),
    ] {
    assert_eq(
      render(
        "You have {{ num_messages }} message{{ num_messages|pluralize }}.",
        ctx=[("num_messages", @minijinja.Value::from_int(case.0))],
      ),
      case.1,
    )
  }
  for
    case in [
      (0, "You have 0 walruses."),
      (1, "You have 1 walrus."),
      (10, "You have 10 walruses."),
    ] {
    assert_eq(
      render(
        "You have {{ num_walruses }} walrus{{ num_walruses|pluralize(None, \"es\") }}.",
        ctx=[("num_walruses", @minijinja.Value::from_int(case.0))],
      ),
      case.1,
    )
  }
  for
    case in [
      (0, "You have 0 cherries."),
      (1, "You have 1 cherry."),
      (10, "You have 10 cherries."),
    ] {
    assert_eq(
      render(
        "You have {{ num_cherries }} cherr{{ num_cherries|pluralize(\"y\", \"ies\") }}.",
        ctx=[("num_cherries", @minijinja.Value::from_int(case.0))],
      ),
      case.1,
    )
  }
  assert_eq(
    render(
      "You have {{ num_cherries|length }} cherr{{ num_cherries|pluralize(\"y\", \"ies\") }}.",
      ctx=[
        (
          "num_cherries",
          @minijinja.Value::from_array(Array::make(5, @minijinja.Value::none())),
        ),
      ],
    ),
    "You have 5 cherries.",
  )
  assert_eq(
    render(
      "You have {{ num_cherries }} cherr{{ num_cherries|pluralize(\"y\", \"ies\") }}.",
      ctx=[("num_cherries", @minijinja.Value::from_int(5))],
    ),
    "You have 5 cherries.",
  )
  assert_eq(
    render_err(
      "You have {{ num_cherries }} cherr{{ num_cherries|pluralize(\"y\", \"ies\") }}.",
      ctx=[("num_cherries", @minijinja.Value::from_double(0.5))],
    ),
    "invalid operation: Pluralize argument is not an integer, or a sequence / object with a length but of type number (in <string>:1)",
  )
}

///|
test "test_random" {
  assert_eq(render("{% set RAND_SEED = 42 %}{{ [1, 2, 3, 4]|random }}"), "1")
  assert_eq(render("{% set RAND_SEED = 42 %}{{ 'HelloWorld'|random }}"), "H")
  let env = contrib_env()
  let state = env.empty_state()
  let result = @contrib.random(
    state,
    @minijinja.Value::from_safe_string("HelloWorld"),
  )
  assert_true(result.is_safe())
}

///|
test "test_filesizeformat" {
  assert_eq(render("{{ 0.5|filesizeformat }}"), "0.5 Bytes")
  assert_eq(render("{{ 1|filesizeformat }}"), "1 Byte")
  assert_eq(render("{{ -1|filesizeformat }}"), "-1 Bytes")
  assert_eq(render("{{ 1024|filesizeformat }}"), "1.0 kB")
  assert_eq(render("{{ 1024|filesizeformat(true) }}"), "1.0 KiB")
  assert_eq(render("{{ 1000|filesizeformat }}"), "1.0 kB")
  assert_eq(render("{{ 1000|filesizeformat(true) }}"), "1000 Bytes")
  assert_eq(render("{{ (1024 * 1024 * 1024)|filesizeformat }}"), "1.1 GB")
  assert_eq(
    render("{{ (1024 * 1024 * 1024)|filesizeformat(true) }}"),
    "1.0 GiB",
  )
  assert_eq(
    render("{{ (1024 * 1024 * 1024 * 1024 * 1024)|filesizeformat }}"),
    "1.1 PB",
  )
  assert_eq(
    render(
      "{{ (1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024)|filesizeformat }}",
    ),
    "1.2 YB",
  )
  assert_eq(
    render(
      "{{ (1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024 * 1024)|filesizeformat }}",
    ),
    "1267650.6 YB",
  )
}

///|
let long_text = "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum."

///|
let short_text = "Fifteen chars !"

///|
let special_text = "Hello 👋 World"

///|
test "test_truncate" {
  assert_eq(
    render("{{ text|truncate }}", ctx=[("text", str(short_text))]),
    "Fifteen chars !",
  )
  assert_eq(
    render("{{ text|truncate }}", ctx=[("text", str(long_text))]),
    "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It...",
  )
  assert_eq(
    render("{{ text|truncate(length=10) }}", ctx=[("text", str(long_text))]),
    "Lorem...",
  )
  assert_eq(
    render("{{ text|truncate(length=10, killwords=true) }}", ctx=[
      ("text", str(long_text)),
    ]),
    "Lorem I...",
  )
  assert_eq(
    render("{{ text|truncate(length=10, end='***') }}", ctx=[
      ("text", str(long_text)),
    ]),
    "Lorem***",
  )
  assert_eq(
    render("{{ text|truncate(length=10, killwords=true, end='') }}", ctx=[
      ("text", str(long_text)),
    ]),
    "Lorem Ipsu",
  )
  assert_eq(
    render("{{ text|truncate(length=10, leeway=5) }}", ctx=[
      ("text", str(short_text)),
    ]),
    "Fifteen chars !",
  )
  assert_eq(
    render("{{ text|truncate(length=10, leeway=0) }}", ctx=[
      ("text", str(short_text)),
    ]),
    "Fifteen...",
  )
  assert_eq(
    render("{{ text|truncate(length=7, leeway=0, end='') }}", ctx=[
      ("text", str(special_text)),
    ]),
    "Hello",
  )
  assert_eq(
    render("{{ text|truncate(length=7, leeway=0, end='', killwords=true) }}", ctx=[
      ("text", str(special_text)),
    ]),
    "Hello 👋",
  )
  assert_eq(
    render("{{ text|truncate(length=8, leeway=0, end='') }}", ctx=[
      ("text", str(special_text)),
    ]),
    "Hello 👋",
  )
  assert_eq(
    render_err("{{ 'hello'|truncate(length=1) }}"),
    "invalid operation: expected length >= 3, got 1 (in <string>:1)",
  )
}

///|
test "test_truncate_preserves_and_composes_safety" {
  let env = @minijinja.Environment::new()
  env.set_auto_escape_callback(_ => Html)
  let template = env.template_from_str("")
  let state = template.new_state()
  let result = @contrib.truncate(
    state,
    @minijinja.Value::from_safe_string("Hello <b>World</b>"),
    @minijinja.Kwargs::from_pairs([
      ("length", @minijinja.Value::from_int(12)),
      ("killwords", @minijinja.Value::from_bool(true)),
      ("end", str("<i>")),
      ("leeway", @minijinja.Value::from_int(0)),
    ]),
  )
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("Hello <b>&lt;i&gt;"))
  let result = @contrib.truncate(
    state,
    str("<b>Hello World</b>"),
    @minijinja.Kwargs::from_pairs([
      ("length", @minijinja.Value::from_int(10)),
      ("killwords", @minijinja.Value::from_bool(true)),
      ("end", @minijinja.Value::from_safe_string("<i>")),
      ("leeway", @minijinja.Value::from_int(0)),
    ]),
  )
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("&lt;b&gt;Hell<i>"))
  let result = @contrib.truncate(
    state,
    @minijinja.Value::from_safe_string("short"),
    @minijinja.Kwargs::from_pairs([]),
  )
  assert_true(result.is_safe())
  assert_eq(result.as_str(), Some("short"))
}

///|
test "test_wordcount" {
  let wordcount = (text : String) => {
    render("{{ text|wordcount }}", ctx=[("text", str(text))])
  }
  assert_eq(wordcount("Hello world! How are you?"), "5")
  // Test empty string
  assert_eq(wordcount(""), "0")
  // Test multiple whitespace
  assert_eq(wordcount("Hello    world!   Test"), "3")
  // Test other word separators
  assert_eq(wordcount("hello-again@world! It's_me!"), "5")
  // Test multiple other word separators
  assert_eq(wordcount("hello--again@-!world"), "3")
  // Test unicode marks
  assert_eq(wordcount("helloाworld"), "2")
}

///|
test "test_wordwrap" {
  // Test basic wrapping
  assert_eq(
    render("{{ text|wordwrap(width=20) }}", ctx=[
      (
        "text",
        str(
          "This is a long piece of text that should be wrapped at a specific width.",
        ),
      ),
    ]),
    "This is a long piece\nof text that should\nbe wrapped at a\nspecific width.",
  )
  // Test custom wrap string
  assert_eq(
    render("{{ text|wordwrap(width=10, wrapstring=' <br> ') }}", ctx=[
      ("text", str("This is a test of custom wrap strings.")),
    ]),
    "This is <br> a test <br> of custom <br> wrap <br> strings.",
  )
  // Test preserving newlines
  assert_eq(
    render("{{ text|wordwrap(width=20) }}", ctx=[
      ("text", str("First paragraph.\n\nSecond paragraph.")),
    ]),
    "First paragraph.\n\nSecond paragraph.",
  )
  // Test breaking long words
  assert_eq(
    render("{{ text|wordwrap(width=10, break_long_words=true) }}", ctx=[
      ("text", str("ThisIsAVeryLongWordThatShouldBeBroken")),
    ]),
    "ThisIsAVer\nyLongWordT\nhatShouldB\neBroken",
  )
  // Test not breaking long words
  assert_eq(
    render("{{ text|wordwrap(width=10, break_long_words=false) }}", ctx=[
      ("text", str("ThisIsAVeryLongWordThatShouldBeBroken")),
    ]),
    "ThisIsAVeryLongWordThatShouldBeBroken",
  )
  // Test breaking on hyphens
  assert_eq(
    render("{{ text|wordwrap(width=10, break_on_hyphens=true) }}", ctx=[
      ("text", str("This-is-a-hyphenated-word")),
    ]),
    "This-is-a-\nhyphenated\n-word",
  )
  // Test NOT breaking on hyphens
  assert_eq(
    render("{{ text|wordwrap(width=10, break_on_hyphens=false) }}", ctx=[
      ("text", str("This-is-a-hyphenated-word")),
    ]),
    "This-is-a-hyphenated-word",
  )
}

///|
test "test_striptags" {
  assert_eq(@contrib.striptags("   <a> Hello </a>   "), "Hello")
  assert_eq(@contrib.striptags("Hello &amp World!&gt;"), "Hello & World!>")
  assert_eq(@contrib.striptags("Hello &amp; World!&gt;"), "Hello & World!>")
  assert_eq(@contrib.striptags("Hello &amp< World!&gt;"), "Hello &")
  assert_eq(@contrib.striptags("<!-- <a href='x'>blah</a> -->haha"), "haha")
  assert_eq(@contrib.striptags("This is &amp&amp&amp; x"), "This is &&& x")
  assert_eq(@contrib.striptags("This is &unknown<a>b"), "This is &unknownb")
  assert_eq(@contrib.striptags("This is &unknown"), "This is &unknown")
  assert_eq(@contrib.striptags("This is &unknown;"), "This is &unknown;")
  assert_eq(@contrib.striptags("This is &unknown x"), "This is &unknown x")
  assert_eq(@contrib.striptags("This is &unknown; x"), "This is &unknown; x")
}
