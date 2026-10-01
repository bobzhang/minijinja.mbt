#!/usr/bin/env python3
"""Translates tests/test_format_filter.rs into MoonBit tests (one-off helper)."""
import re
import sys

SRC = ".repos/minijinja/minijinja/tests/test_format_filter.rs"
src = open(SRC).read()

VALUES = {
    "PI": "Value::from_double(3.141592653589793)",
    "f64::NAN": "Value::from_double(0.0 / 0.0)",
    "f64::INFINITY": "Value::from_double(1.0 / 0.0)",
    "f64::NEG_INFINITY": "Value::from_double(-1.0 / 0.0)",
    "f64::MIN": "Value::from_double(-1.7976931348623157e308)",
    "f64::MAX": "Value::from_double(1.7976931348623157e308)",
    "f64::MIN_POSITIVE": "Value::from_double(2.2250738585072014e-308)",
    "f32::MIN": "Value::from_double(-3.4028234663852886e38)",
    "f32::MAX": "Value::from_double(3.4028234663852886e38)",
    "f32::MIN_POSITIVE": "Value::from_double(1.1754943508222875e-38)",
    "u64::MAX": "Value::from_uint64(0xFFFFFFFFFFFFFFFFUL)",
    "u64::MAX as u128 + 1": "Value::from_bigint(18446744073709551616N)",
    "i64::MAX": "Value::from_int64(0x7FFFFFFFFFFFFFFFL)",
    "i64::MIN": "Value::from_int64(-0x7FFFFFFFFFFFFFFFL - 1L)",
    "i64::MIN as i128 - 1": "Value::from_bigint(-9223372036854775809N)",
    "i32::MAX": "Value::from_int(2147483647)",
    "i32::MAX - 1": "Value::from_int(2147483646)",
    "i128::MAX": "Value::from_bigint(170141183460469231731687303715884105727N)",
    "u128::MIN": "Value::from_bigint(0N)",
    "true": "Value::from_bool(true)",
    "false": "Value::from_bool(false)",
    "1.0 / 5.0": "Value::from_double(1.0 / 5.0)",
    "1.0 / 3.0": "Value::from_double(1.0 / 3.0)",
}


def conv_value(v):
    v = v.strip()
    if v in VALUES:
        return VALUES[v]
    if v.startswith('"'):
        return f"Value::from_string({v})"
    v2 = v.replace("_f64", "").replace("_u8", "").replace("_i8", "")
    if re.fullmatch(r"-?0o[0-7]+", v2):
        neg = v2.startswith("-")
        n = int(v2.lstrip("-")[2:], 8)
        return f"Value::from_int({'-' if neg else ''}{n})"
    if re.fullmatch(r"-?0x[0-9a-f]+", v2):
        neg = v2.startswith("-")
        n = int(v2.lstrip("-")[2:], 16)
        return f"Value::from_int({'-' if neg else ''}{n})"
    if re.fullmatch(r"-?\d+", v2):
        return f"Value::from_int({v2})"
    if re.fullmatch(r"-?\d+\.\d*", v2):
        if v2.endswith("."):
            v2 += "0"
        return f"Value::from_double({v2})"
    raise ValueError(v)


def mbt_str(s):
    # Rust string literal -> MoonBit string literal
    s = s.replace("\\x01", "\\u{1}").replace("\\x00", "\\u{0}")
    return s


out = []
for m in re.finditer(r"fn (test_\w+)\(\) \{(.*?)\n\}", src, re.S):
    name, body = m.group(1), m.group(2)
    lines = []
    for a in re.finditer(r"assert_eq!\(\s*(.*?),\s*(\"(?:[^\"\\]|\\.)*\")\s*\);", body, re.S):
        call, expected = a.group(1), a.group(2)
        fv = re.fullmatch(r"format_val\(&env,\s*(.*),\s*(\"[^\"]*\")\)", call.strip(), re.S)
        ee = re.fullmatch(r"eval_expr\(&env,\s*(\"(?:[^\"\\]|\\.)*\")\)", call.strip(), re.S)
        if fv:
            try:
                val = conv_value(fv.group(1))
            except ValueError:
                print(f"skip {name}: {call}", file=sys.stderr)
                continue
            lines.append(f"  assert_eq(fv({val}, {fv.group(2)}), {mbt_str(expected)})")
        elif ee:
            lines.append(f"  assert_eq(ee({mbt_str(ee.group(1))}), {mbt_str(expected)})")
        else:
            print(f"skip {name}: {call}", file=sys.stderr)
    for a in re.finditer(
        r"assert!\(\s*eval_err_expr\((\"(?:[^\"\\]|\\.)*\")\)\s*\.contains\((\"(?:[^\"\\]|\\.)*\")\)\s*\);",
        body,
        re.S,
    ):
        lines.append(f"  assert_true(eerr({a.group(1)}).contains({a.group(2)}))")
    if lines:
        out.append("///|")
        out.append(f'test "format filter: {name[len("test_format_"):]}" {{')
        out.extend(lines)
        out.append("}")
        out.append("")

header = '''// Ported from minijinja/tests/test_format_filter.rs by
// scripts/port_format_tests.py.

///|
fn fv(val : @minijinja.Value, spec : String) -> String raise {
  let env = @minijinja.Environment::new()
  let expr = env.compile_expression("'%\\{spec}' | format(val)")
  expr.eval(@minijinja.Value::from_pairs([("val", val)])).to_string()
}

///|
fn ee(expr : String) -> String raise {
  let env = @minijinja.Environment::new()
  env.compile_expression(expr).eval(@minijinja.Value::from_pairs([])).to_string()
}

///|
fn eerr(expr : String) -> String raise {
  let env = @minijinja.Environment::new()
  let e = env.compile_expression(expr)
  e.eval(@minijinja.Value::from_pairs([])) catch {
    err => return err.to_string()
  } noraise {
    _ => fail("expected an error")
  }
}

'''
body = "\n".join(out).replace("Value::", "@minijinja.Value::")
open("format_filter_test.mbt", "w").write(header + body)
