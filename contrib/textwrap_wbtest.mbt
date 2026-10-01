///|
/// `textwrap::wrap(text, width)` with the default options (hyphen
/// splitting, breaking long words, optimal fit).
fn wrap(
  text : String,
  width : Int,
  break_words? : Bool = true,
) -> Array[String] {
  textwrap(text, width~, hyphen_splitter=true, break_words~)
}

///|
test "textwrap upstream unit tests" {
  // ported from textwrap's `wrap.rs` tests
  debug_inspect(wrap("foo", 10), content="[\"foo\"]")
  debug_inspect(
    wrap("foo bar baz", 5),
    content=(
      #|["foo", "bar", "baz"]
    ),
  )
  debug_inspect(
    wrap("foo bar baz", 10),
    content=(
      #|["foo bar", "baz"]
    ),
  )
  debug_inspect(
    wrap("foo", 0),
    content=(
      #|["f", "o", "o"]
    ),
  )
  debug_inspect(
    wrap("foo bar", 0),
    content=(
      #|["f", "o", "o", "b", "a", "r"]
    ),
  )
  debug_inspect(
    wrap("  foo bar", 6),
    content=(
      #|["  foo", "bar"]
    ),
  )
  debug_inspect(
    wrap(" foobar baz", 6),
    content=(
      #|["", "foobar", "baz"]
    ),
  )
  debug_inspect(
    wrap("foo     bar     baz  ", 5),
    content=(
      #|["foo", "bar", "baz"]
    ),
  )
  debug_inspect(
    wrap("aaabbbccc x yyyzzzwww", 9),
    content=(
      #|["aaabbbccc", "x", "yyyzzzwww"]
    ),
  )
  debug_inspect(
    wrap("foo-bar", 5),
    content=(
      #|["foo-", "bar"]
    ),
  )
  debug_inspect(
    wrap("foobar-", 5, break_words=false),
    content=(
      #|["foobar-"]
    ),
  )
  debug_inspect(
    wrap("foo-bar-baz", 5),
    content=(
      #|["foo-", "bar-", "baz"]
    ),
  )
  debug_inspect(
    wrap("The --foo-bar flag.", 5, break_words=false),
    content=(
      #|["The", "--foo-", "bar", "flag."]
    ),
  )
  debug_inspect(
    wrap("foo--bar", 4, break_words=false),
    content=(
      #|["foo--bar"]
    ),
  )
  debug_inspect(
    wrap("Na2-CH4", 5),
    content=(
      #|["Na2-", "CH4"]
    ),
  )
  debug_inspect(
    wrap("Hello, World!", 15),
    content=(
      #|["Hello, World!"]
    ),
  )
  // double width characters (no `unicode-width`: >= U+1100 is 2 columns)
  debug_inspect(
    wrap("Ｈｅｌｌｏ, Ｗｏｒｌｄ!", 15),
    content=(
      #|["Ｈｅｌｌｏ,", "Ｗｏｒｌｄ!"]
    ),
  )
}

///|
test "textwrap ansi escapes" {
  // escape sequences do not count towards the width
  debug_inspect(
    wrap("\u{1b}[31mfoo\u{1b}[0m bar", 7),
    content=(
      #|["\u{1b}[31mfoo\u{1b}[0m bar"]
    ),
  )
}
