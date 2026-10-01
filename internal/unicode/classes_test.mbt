///|
test "character classes" {
  inspect(@unicode.is_alphabetic('ä'), content="true")
  // U+093E DEVANAGARI VOWEL SIGN AA is Other_Alphabetic, but not a letter
  inspect(@unicode.is_alphabetic('\u{93e}'), content="true")
  inspect(@unicode.is_letter('\u{93e}'), content="false")
  inspect(@unicode.is_letter('き'), content="true")
  inspect(@unicode.is_alphabetic('1'), content="false")
  inspect(@unicode.is_numeric('1'), content="true")
  inspect(@unicode.is_numeric('½'), content="true")
  inspect(@unicode.is_numeric('٣'), content="true")
  inspect(@unicode.is_alphanumeric('Ⅷ'), content="true")
  inspect(@unicode.is_alphanumeric('-'), content="false")
  inspect(@unicode.is_whitespace('\u{a0}'), content="true")
  inspect(@unicode.is_whitespace('\u{3000}'), content="true")
  inspect(@unicode.is_whitespace('\u{1c}'), content="false")
  inspect(@unicode.is_whitespace('\u{200b}'), content="false")
}

///|
test "trim" {
  inspect(@unicode.trim("\u{3000} a b \n"), content="a b")
  inspect(@unicode.trim_start("  a "), content="a ")
  inspect(@unicode.trim_end("  a "), content="  a")
}
