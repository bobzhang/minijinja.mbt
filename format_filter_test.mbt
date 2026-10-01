// Ported from minijinja/tests/test_format_filter.rs by
// scripts/port_format_tests.py.

///|
fn fv(val : @minijinja.Value, spec : String) -> String raise {
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("'%\{spec}' | format(val)")
  expr.eval(@minijinja.Value::from_pairs([("val", val)])).to_string()
}

///|
fn ee(expr : String) -> String raise {
  let env = @minijinja.Environment::new()
  env
  .compile_expression(expr)
  .eval(@minijinja.Value::from_pairs([]))
  .to_string()
}

///|
fn eerr(expr : String) -> String raise {
  let env = @minijinja.Environment::new()
  let e = env.compile_expression(expr)
  try e.eval(@minijinja.Value::from_pairs([])) catch {
    err => return err.to_string()
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "format filter: integer_in_decimal" {
  assert_eq(ee("'%10d' | format(1234)"), "      1234")
  assert_eq(ee("'%010d' | format(1234)"), "0000001234")
  assert_eq(ee("'horses: %03d' | format(123)"), "horses: 123")
  assert_eq(ee("'%02d rabbits' | format(123)"), "123 rabbits")
  assert_eq(ee("'%4.5d' | format(123)"), " 123")
  assert_eq(fv(@minijinja.Value::from_int(123), "+d"), "+123")
  assert_eq(fv(@minijinja.Value::from_int(123), "+05d"), "+0123")
  assert_eq(fv(@minijinja.Value::from_int(-123), "04d"), "-123")
  assert_eq(fv(@minijinja.Value::from_int(-123), "05d"), "-0123")
  assert_eq(fv(@minijinja.Value::from_int(-123), "+05d"), "-0123")
  assert_eq(fv(@minijinja.Value::from_int(123), " d"), " 123")
  assert_eq(fv(@minijinja.Value::from_int(-123), " d"), "-123")
  assert_eq(fv(@minijinja.Value::from_int(123), " +d"), "+123")
  assert_eq(fv(@minijinja.Value::from_int(-123), " +d"), "-123")
  assert_eq(fv(@minijinja.Value::from_int(123), "-5d"), "123  ")
  assert_eq(fv(@minijinja.Value::from_int(123), "-05d"), "123  ")
  assert_eq(fv(@minijinja.Value::from_int(123), "0d"), "123")
  assert_eq(fv(@minijinja.Value::from_int(123), "-0d"), "123")
  assert_eq(
    fv(@minijinja.Value::from_int64(0x7FFFFFFFFFFFFFFFL), "+d"),
    "+9223372036854775807",
  )
  assert_eq(
    fv(@minijinja.Value::from_int64(-0x7FFFFFFFFFFFFFFFL - 1L), "+d"),
    "-9223372036854775808",
  )
  assert_eq(
    fv(@minijinja.Value::from_bigint(-9223372036854775809N), "+d"),
    "-9223372036854775809",
  )
  assert_eq(
    fv(@minijinja.Value::from_uint64(0xFFFFFFFFFFFFFFFFUL), "+d"),
    "+18446744073709551615",
  )
  assert_eq(
    fv(@minijinja.Value::from_bigint(18446744073709551616N), "+d"),
    "+18446744073709551616",
  )
  assert_eq(ee("'horses: %i' | format(123)"), "horses: 123")
  assert_eq(ee("'%ld, %0hi, %Ld' | format(1,2,3)"), "1, 2, 3")
}

///|
test "format filter: integer_as_string" {
  assert_eq(fv(@minijinja.Value::from_int(123), "s"), "123")
  assert_eq(fv(@minijinja.Value::from_int(-123), "s"), "-123")
  assert_eq(fv(@minijinja.Value::from_int(123), "+s"), "123")
  assert_eq(fv(@minijinja.Value::from_int(-123), "+s"), "-123")
}

///|
test "format filter: integer_in_octal" {
  assert_eq(fv(@minijinja.Value::from_int(57), "o"), "71")
  assert_eq(fv(@minijinja.Value::from_int(57), "#o"), "0o71")
  assert_eq(fv(@minijinja.Value::from_int(57), "#06o"), "0o0071")
  assert_eq(fv(@minijinja.Value::from_int(57), "#6o"), "  0o71")
  assert_eq(fv(@minijinja.Value::from_int(511), "+#o"), "+0o777")
  assert_eq(fv(@minijinja.Value::from_int(-57), "+#o"), "-0o71")
  assert_eq(fv(@minijinja.Value::from_int(7), "-3o"), "7  ")
  assert_eq(fv(@minijinja.Value::from_int(7), "-#5o"), "0o7  ")
}

///|
test "format filter: integer_in_hex" {
  assert_eq(fv(@minijinja.Value::from_int(255), "x"), "ff")
  assert_eq(fv(@minijinja.Value::from_int(255), "#X"), "0XFF")
  assert_eq(fv(@minijinja.Value::from_int(127), "#x"), "0x7f")
  assert_eq(fv(@minijinja.Value::from_int(127), "+#x"), "+0x7f")
  assert_eq(fv(@minijinja.Value::from_int(-127), "#x"), "-0x7f")
  assert_eq(fv(@minijinja.Value::from_int(-127), "05x"), "-007f")
  assert_eq(fv(@minijinja.Value::from_int(2147483647), "05x"), "7fffffff")
  assert_eq(fv(@minijinja.Value::from_int(2147483646), "-#12x"), "0x7ffffffe  ")
  assert_eq(
    fv(
      @minijinja.Value::from_bigint(170141183460469231731687303715884105727N),
      "#x",
    ),
    "0x7fffffffffffffffffffffffffffffff",
  )
  assert_eq(fv(@minijinja.Value::from_bigint(0N), "#x"), "0x0")
}

///|
test "format filter: integer_as_float" {
  assert_eq(fv(@minijinja.Value::from_int(42), "f"), "42.000000")
  assert_eq(fv(@minijinja.Value::from_int(42), "F"), "42.000000")
  assert_eq(fv(@minijinja.Value::from_int(42), "e"), "4.200000e+01")
  assert_eq(fv(@minijinja.Value::from_int(42), "E"), "4.200000E+01")
  assert_eq(fv(@minijinja.Value::from_int(42), ".3f"), "42.000")
  assert_eq(fv(@minijinja.Value::from_int(42), ".2e"), "4.20e+01")
  assert_eq(fv(@minijinja.Value::from_int(420), ".2e"), "4.20e+02")
  assert_eq(
    fv(@minijinja.Value::from_uint64(0xFFFFFFFFFFFFFFFFUL), ".2e"),
    "1.84e+19",
  )
  assert_eq(fv(@minijinja.Value::from_int(-42), ".2f"), "-42.00")
  assert_eq(fv(@minijinja.Value::from_int(42), ".0f"), "42")
  assert_eq(fv(@minijinja.Value::from_int(42), "#.0f"), "42.")
  assert_eq(fv(@minijinja.Value::from_int(42), ".0e"), "4e+01")
  assert_eq(fv(@minijinja.Value::from_int(42), "#.0e"), "4.e+01")
  assert_eq(fv(@minijinja.Value::from_int(42), ".0E"), "4E+01")
  assert_eq(fv(@minijinja.Value::from_int(42), "#.0E"), "4.E+01")
}

///|
test "format filter: float" {
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "f"),
    "3.141593",
  )
  assert_eq(fv(@minijinja.Value::from_double(3.141592653589793), ".2f"), "3.14")
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "e"),
    "3.141593e+00",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), ".2E"),
    "3.14E+00",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "010.4f"),
    "00003.1416",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "012.4e"),
    "003.1416e+00",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "6.2f"),
    "  3.14",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "-6.2f"),
    "3.14  ",
  )
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 5.0), "f"), "0.200000")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 3.0), ".3f"), "0.333")
  assert_eq(fv(@minijinja.Value::from_double(3.141592653589793), ".0f"), "3")
  assert_eq(fv(@minijinja.Value::from_double(3.141592653589793), "#.0f"), "3.")
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), ".0e"),
    "3e+00",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.141592653589793), "#.0e"),
    "3.e+00",
  )
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "f"), "inf")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "+f"), "+inf")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "e"), "inf")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "06e"), "000inf")
  assert_eq(fv(@minijinja.Value::from_double(-1.0 / 0.0), "+f"), "-inf")
  assert_eq(fv(@minijinja.Value::from_double(-1.0 / 0.0), "f"), "-inf")
  assert_eq(fv(@minijinja.Value::from_double(-1.0 / 0.0), "06f"), "-00inf")
  assert_eq(fv(@minijinja.Value::from_double(0.0), "f"), "0.000000")
  assert_eq(fv(@minijinja.Value::from_double(0.0), "+f"), "+0.000000")
  assert_eq(fv(@minijinja.Value::from_double(-0.0), "+f"), "-0.000000")
  assert_eq(fv(@minijinja.Value::from_double(-0.0), "+05.1f"), "-00.0")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "f"), "nan")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "F"), "NAN")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "e"), "nan")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "E"), "NAN")
  assert_eq(
    fv(@minijinja.Value::from_double(-1.7976931348623157e308), ".4e"),
    "-1.7977e+308",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(2.2250738585072014e-308), ".4e"),
    "2.2251e-308",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(1.7976931348623157e308), ".2e"),
    "1.80e+308",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(-3.4028234663852886e38), ".5E"),
    "-3.40282E+38",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(1.1754943508222875e-38), ".4E"),
    "1.1755E-38",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(3.4028234663852886e38), ".2E"),
    "3.40E+38",
  )
}

///|
test "format filter: general" {
  assert_eq(fv(@minijinja.Value::from_double(123.456), "g"), "123.456")
  assert_eq(fv(@minijinja.Value::from_double(123.000), "g"), "123")
  assert_eq(fv(@minijinja.Value::from_double(120.0), "g"), "120")
  assert_eq(fv(@minijinja.Value::from_double(1234.012), "g"), "1234.01")
  assert_eq(fv(@minijinja.Value::from_double(12345.1234), "g"), "12345.1")
  assert_eq(fv(@minijinja.Value::from_double(123456.1234), "g"), "123456")
  assert_eq(fv(@minijinja.Value::from_double(1234564.1234), "g"), "1.23456e+06")
  assert_eq(
    fv(@minijinja.Value::from_double(12345678.1234), "g"),
    "1.23457e+07",
  )
  assert_eq(fv(@minijinja.Value::from_double(12345000.00), "g"), "1.2345e+07")
  assert_eq(fv(@minijinja.Value::from_double(12345000.00), "G"), "1.2345E+07")
  assert_eq(fv(@minijinja.Value::from_double(0.123456), "g"), "0.123456")
  assert_eq(fv(@minijinja.Value::from_double(0.0123456), "g"), "0.0123456")
  assert_eq(fv(@minijinja.Value::from_double(0.00123456), "g"), "0.00123456")
  assert_eq(fv(@minijinja.Value::from_double(0.000123456), "g"), "0.000123456")
  assert_eq(fv(@minijinja.Value::from_double(0.000123), "g"), "0.000123")
  assert_eq(fv(@minijinja.Value::from_double(0.0000123456), "g"), "1.23456e-05")
  assert_eq(fv(@minijinja.Value::from_double(0.0000123), "g"), "1.23e-05")
  assert_eq(
    fv(@minijinja.Value::from_double(0.0000123456789), "g"),
    "1.23457e-05",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(0.0000000456789), "g"),
    "4.56789e-08",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(0.0000000456780), "g"),
    "4.5678e-08",
  )
  assert_eq(fv(@minijinja.Value::from_double(0.00000004), "g"), "4e-08")
  assert_eq(fv(@minijinja.Value::from_double(0.00000004), "#g"), "4.00000e-08")
  assert_eq(fv(@minijinja.Value::from_double(123.456), ".2g"), "1.2e+02")
  assert_eq(fv(@minijinja.Value::from_double(123.456), ".2g"), "1.2e+02")
  assert_eq(fv(@minijinja.Value::from_int(1000), ".4g"), "1000")
  assert_eq(fv(@minijinja.Value::from_int(1000), ".3g"), "1e+03")
  assert_eq(fv(@minijinja.Value::from_double(1000.00), ".4g"), "1000")
  assert_eq(fv(@minijinja.Value::from_double(1000.10), ".5g"), "1000.1")
  assert_eq(fv(@minijinja.Value::from_double(1000.10), ".6g"), "1000.1")
  assert_eq(
    fv(@minijinja.Value::from_double(123456789.1234), ".6g"),
    "1.23457e+08",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(123456789.1234), ".10g"),
    "123456789.1",
  )
  assert_eq(fv(@minijinja.Value::from_double(0.123456), ".2g"), "0.12")
  assert_eq(fv(@minijinja.Value::from_double(0.00012345), ".4g"), "0.0001234")
  assert_eq(fv(@minijinja.Value::from_double(0.000012345), ".4g"), "1.234e-05")
  assert_eq(fv(@minijinja.Value::from_double(123.456), ".0g"), "1e+02")
  assert_eq(fv(@minijinja.Value::from_double(0.456), ".0g"), "0.5")
  assert_eq(fv(@minijinja.Value::from_double(-123.456), "g"), "-123.456")
  assert_eq(fv(@minijinja.Value::from_double(-123.456), ".2g"), "-1.2e+02")
  assert_eq(fv(@minijinja.Value::from_int(-1000), ".4g"), "-1000")
  assert_eq(fv(@minijinja.Value::from_double(-100.100), ".4g"), "-100.1")
  assert_eq(
    fv(@minijinja.Value::from_double(-123456789.1234), "15g"),
    "   -1.23457e+08",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(-123456789.1234), "015g"),
    "-0001.23457e+08",
  )
  assert_eq(fv(@minijinja.Value::from_double(-0.123456), "g"), "-0.123456")
  assert_eq(
    fv(@minijinja.Value::from_double(-0.0000123456), "g"),
    "-1.23456e-05",
  )
  assert_eq(
    fv(@minijinja.Value::from_double(-0.0000123456), "09.2g"),
    "-01.2e-05",
  )
  assert_eq(fv(@minijinja.Value::from_double(0.0), "g"), "0")
  assert_eq(fv(@minijinja.Value::from_double(-0.0), "g"), "-0")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "g"), "nan")
  assert_eq(fv(@minijinja.Value::from_double(0.0 / 0.0), "G"), "NAN")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "g"), "inf")
  assert_eq(fv(@minijinja.Value::from_double(1.0 / 0.0), "G"), "INF")
  assert_eq(fv(@minijinja.Value::from_double(-1.0 / 0.0), "g"), "-inf")
  assert_eq(fv(@minijinja.Value::from_double(-1.0 / 0.0), "G"), "-INF")
}

///|
test "format filter: bool" {
  assert_eq(fv(@minijinja.Value::from_bool(false), "s"), "False")
  assert_eq(fv(@minijinja.Value::from_bool(true), "s"), "True")
  assert_eq(fv(@minijinja.Value::from_bool(true), ".2d"), "1")
  assert_eq(fv(@minijinja.Value::from_bool(true), "-5d"), "1    ")
  assert_eq(fv(@minijinja.Value::from_bool(false), "5d"), "    0")
  assert_eq(fv(@minijinja.Value::from_bool(true), "d"), "1")
  assert_eq(fv(@minijinja.Value::from_bool(true), "#x"), "0x1")
  assert_eq(fv(@minijinja.Value::from_bool(false), "#o"), "0o0")
  assert_eq(fv(@minijinja.Value::from_bool(true), "04d"), "0001")
}

///|
test "format filter: char" {
  assert_eq(fv(@minijinja.Value::from_int(65), "c"), "A")
  assert_eq(fv(@minijinja.Value::from_int(97), "c"), "a")
  assert_eq(fv(@minijinja.Value::from_int(128512), "c"), "😀")
  assert_eq(fv(@minijinja.Value::from_string("a"), "c"), "a")
  assert_eq(fv(@minijinja.Value::from_int(97), "5c"), "    a")
  assert_eq(fv(@minijinja.Value::from_int(97), "05c"), "    a")
  assert_eq(fv(@minijinja.Value::from_int(97), "-5c"), "a    ")
  assert_eq(fv(@minijinja.Value::from_int(97), "-05c"), "a    ")
  assert_eq(fv(@minijinja.Value::from_int(128512), "5c"), "    😀")
  assert_eq(fv(@minijinja.Value::from_bool(true), "c"), "\u{1}")
  assert_eq(fv(@minijinja.Value::from_bool(false), "c"), "\u{0}")
}

///|
test "format filter: char_error" {
  assert_true(
    eerr("'%c' | format('abc')").contains(
      "character format ('c') requires integer or char",
    ),
  )
  assert_true(
    eerr("'%c' | format('')").contains(
      "character format ('c') requires integer or char",
    ),
  )
  assert_true(
    eerr("'%c' | format(97.0)").contains(
      "'float' cannot be formatted in character format ('c')",
    ),
  )
  assert_true(
    eerr("'%c' | format(2000000)").contains(
      "character format ('c') arg not in range(0x110000)",
    ),
  )
  assert_true(
    eerr("'%c' | format(-1)").contains(
      "character format ('c') arg not in range(0x110000)",
    ),
  )
}

///|
test "format filter: str" {
  assert_eq(
    fv(@minijinja.Value::from_string("Hello world!"), "s"),
    "Hello world!",
  )
  assert_eq(fv(@minijinja.Value::from_string("Hello"), "9s"), "    Hello")
  assert_eq(fv(@minijinja.Value::from_string("Hello"), "-9s"), "Hello    ")
  assert_eq(fv(@minijinja.Value::from_string("Hello"), ".2s"), "He")
  assert_eq(fv(@minijinja.Value::from_string("Hello"), "4.2s"), "  He")
  assert_eq(
    ee("'Hello %s and %s!'|format('Bob','Alice')"),
    "Hello Bob and Alice!",
  )
}

///|
test "format filter: escaping" {
  assert_eq(ee("'%% %d'|format(42)"), "% 42")
  assert_eq(ee("'%%%d'|format(42)"), "%42")
  assert_eq(
    ee("'first %% second %% consecutive %%%% %d'|format(42)"),
    "first % second % consecutive %% 42",
  )
}

///|
test "format filter: error" {
  assert_true(
    eerr("'missing type: %04' | format('arg')").contains(
      "missing conversion type",
    ),
  )
  assert_true(
    eerr("'missing type: %a' | format('arg')").contains(
      "invalid conversion type 'a' in format spec",
    ),
  )
  assert_true(
    eerr("'% %s' | format('arg')").contains(
      "invalid conversion type '%' in format spec",
    ),
  )
}

///|
test "format filter: with_mapping_arg" {
  let mapping = "{ 'key' : 42, '1' : 'magic' }"
  assert_eq(
    ee("'read from mapping: %(key)d' | format(\{mapping})"),
    "read from mapping: 42",
  )
  assert_eq(
    ee("'%(key)d is %(1)s number' | format(\{mapping})"),
    "42 is magic number",
  )
  assert_true(
    eerr("'%(key)d must be in mapping' | format(42)").contains(
      "format argument must be a mapping",
    ),
  )
  assert_true(
    eerr("'%(bad-key)d must be in mapping' | format(\{mapping})").contains(
      "missing an argument for format spec",
    ),
  )
}

///|
test "format filter: large_precision" {
  let rv = ee("'%.65536f' | format(1.0)")
  assert_eq(rv.length(), 65538)
  assert_true(rv.has_prefix("1.000"))
  assert_true(rv.has_suffix("00000"))
}
