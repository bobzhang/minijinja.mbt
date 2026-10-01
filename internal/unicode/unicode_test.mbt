///|
test "identifiers" {
  inspect(@unicode.is_xid_start('ö'), content="true")
  inspect(@unicode.is_xid_start('き'), content="true")
  inspect(@unicode.is_xid_start('℘'), content="true")
  inspect(@unicode.is_xid_start('🐍'), content="false")
  inspect(@unicode.is_xid_start('·'), content="false")
  inspect(@unicode.is_xid_continue('·'), content="true")
}

///|
test "case mapping" {
  inspect(@unicode.to_upper("straße ǆ"), content="STRASSE Ǆ")
  inspect(@unicode.to_lower("ὈΔΥΣΣΕΎΣ"), content="ὀδυσσεύς")
  inspect(@unicode.to_lower("Σ"), content="σ")
  inspect(@unicode.case_fold("Straße"), content="strasse")
  inspect(@unicode.is_uppercase('Ä'), content="true")
  inspect(@unicode.is_lowercase('ß'), content="true")
}

///|
test "final sigma" {
  inspect(@unicode.to_lower("ǅΣ"), content="ǆς")
  inspect(@unicode.to_lower("A\u{200D}Σ"), content="a\u{200D}ς")
  inspect(@unicode.to_lower("ΣA"), content="σa")
}
