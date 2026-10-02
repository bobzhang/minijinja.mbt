#!/usr/bin/env python3
"""Generates internal/unicode/tables.mbt from the Unicode Character Database.

The tables follow the Unicode version used by Rust's standard library (and
the `unicode-ident` crate) that upstream MiniJinja is built with, so that
the port matches Rust's behavior:

* XID_Start / XID_Continue (`unicode-ident`), Uppercase / Lowercase / Cased /
  Case_Ignorable / Alphabetic / Grapheme_Extend from DerivedCoreProperties.txt
* White_Space from PropList.txt (`char::is_whitespace`)
* general categories from UnicodeData.txt (letters, numbers and the
  "printable" set of `char::escape_debug`)
* full case mappings (`str::to_uppercase` / `str::to_lowercase`) from
  UnicodeData.txt and the unconditional entries of SpecialCasing.txt
* full case folding (C + F) from CaseFolding.txt

The UCD files are read from `$UCD_DIR` when set and otherwise downloaded from
unicode.org into `_build/ucd/<version>/`.
"""
import os
import sys
import urllib.request

UNICODE_VERSION = os.environ.get("UCD_VERSION", "16.0.0")
MAX = 0x110000
FILES = [
    "UnicodeData.txt",
    "SpecialCasing.txt",
    "CaseFolding.txt",
    "DerivedCoreProperties.txt",
    "PropList.txt",
]


def ucd_dir():
    d = os.environ.get("UCD_DIR") or os.path.join("_build", "ucd", UNICODE_VERSION)
    os.makedirs(d, exist_ok=True)
    for name in FILES:
        path = os.path.join(d, name)
        if not os.path.exists(path):
            url = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/{name}"
            print(f"downloading {url}", file=sys.stderr)
            with urllib.request.urlopen(url) as f:
                data = f.read()
            with open(path, "wb") as f:
                f.write(data)
    return d


def read_lines(d, name):
    with open(os.path.join(d, name), encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                yield [x.strip() for x in line.split(";")]


def parse_range(s):
    if ".." in s:
        a, b = s.split("..")
        return range(int(a, 16), int(b, 16) + 1)
    return range(int(s, 16), int(s, 16) + 1)


def properties(d, name):
    props = {}
    for fields in read_lines(d, name):
        props.setdefault(fields[1], set()).update(parse_range(fields[0]))
    return props


def unicode_data(d):
    """General category and simple case mappings of every code point."""
    category = {}
    upper = {}
    lower = {}
    first = None
    with open(os.path.join(d, "UnicodeData.txt"), encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split(";")
            cp = int(fields[0], 16)
            name, cat = fields[1], fields[2]
            if name.endswith(", First>"):
                first = cp
                continue
            if name.endswith(", Last>"):
                for x in range(first, cp + 1):
                    category[x] = cat
                continue
            category[cp] = cat
            if fields[12]:
                upper[cp] = [int(fields[12], 16)]
            if fields[13]:
                lower[cp] = [int(fields[13], 16)]
    return category, upper, lower


def special_casing(d, upper, lower):
    """Applies the unconditional full mappings of SpecialCasing.txt."""
    for fields in read_lines(d, "SpecialCasing.txt"):
        # fields: code; lower; title; upper; (condition_list;)
        if len(fields) > 4 and fields[4]:
            continue  # conditional (language or context sensitive)
        cp = int(fields[0], 16)
        lo = [int(x, 16) for x in fields[1].split()]
        up = [int(x, 16) for x in fields[3].split()]
        if lo != [cp]:
            lower[cp] = lo
        else:
            lower.pop(cp, None)
        if up != [cp]:
            upper[cp] = up
        else:
            upper.pop(cp, None)


def case_folding(d):
    fold = {}
    for fields in read_lines(d, "CaseFolding.txt"):
        status = fields[1]
        if status in ("C", "F"):
            fold[int(fields[0], 16)] = [int(x, 16) for x in fields[2].split()]
    return fold


def ranges(cps):
    out = []
    start = None
    prev = None
    for cp in sorted(cps):
        if 0xD800 <= cp <= 0xDFFF:
            continue
        if start is None:
            start = prev = cp
        elif cp == prev + 1:
            prev = cp
        else:
            out.append((start, prev))
            start = prev = cp
    if start is not None:
        out.append((start, prev))
    return out


def emit_ranges(out, name, cps):
    out.append("///|")
    out.append(f"let {name} : FixedArray[Int] = [")
    for a, b in ranges(cps):
        out.append(f"  0x{a:x}, 0x{b:x},")
    out.append("]")
    out.append("")


def emit_mapping(out, name, mapping):
    single = []
    multi = []
    for cp in sorted(mapping):
        m = mapping[cp]
        if m == [cp]:
            continue
        if len(m) == 1:
            single.append((cp, m[0]))
        else:
            multi.append((cp, m))
    out.append("///|")
    out.append(f"let {name}_single : FixedArray[Int] = [")
    for a, b in single:
        out.append(f"  0x{a:x}, 0x{b:x},")
    out.append("]")
    out.append("")
    out.append("///|")
    out.append(f"let {name}_multi_keys : FixedArray[Int] = [")
    for a, _ in multi:
        out.append(f"  0x{a:x},")
    out.append("]")
    out.append("")
    out.append("///|")
    out.append(f"let {name}_multi_values : FixedArray[String] = [")
    for _, m in multi:
        esc = "".join(f"\\u{{{x:x}}}" for x in m)
        out.append(f'  "{esc}",')
    out.append("]")
    out.append("")


def main():
    d = ucd_dir()
    category, upper, lower = unicode_data(d)
    special_casing(d, upper, lower)
    fold = case_folding(d)
    derived = properties(d, "DerivedCoreProperties.txt")
    proplist = properties(d, "PropList.txt")

    def by_category(cats):
        return {cp for cp, cat in category.items() if cat in cats}

    # Rust's `core::unicode::printable`: everything except these categories
    # (unassigned code points are Cn) is printable, plus the space.
    non_printable_cats = {"Cc", "Cf", "Cs", "Co", "Zl", "Zp", "Zs"}
    printable = {
        cp
        for cp in range(MAX)
        if cp in category and category[cp] not in non_printable_cats
    }
    printable.add(0x20)

    out = [
        "// Code generated by scripts/gen_unicode_tables.py; DO NOT EDIT.",
        f"// Unicode version: {UNICODE_VERSION}",
        "",
    ]
    emit_ranges(out, "xid_start_table", derived["XID_Start"])
    emit_ranges(out, "xid_continue_table", derived["XID_Continue"])
    emit_ranges(out, "uppercase_table", derived["Uppercase"])
    emit_ranges(out, "lowercase_table", derived["Lowercase"])
    emit_ranges(out, "cased_table", derived["Cased"])
    emit_ranges(out, "case_ignorable_table", derived["Case_Ignorable"])
    emit_ranges(out, "alphabetic_table", derived["Alphabetic"])
    emit_ranges(out, "grapheme_extend_table", derived["Grapheme_Extend"])
    # unicode_categories' `is_letter`: general category L*
    emit_ranges(out, "letter_table", by_category({"Lu", "Ll", "Lt", "Lm", "Lo"}))
    # Rust's `char::is_numeric`: general category Nd, Nl or No
    emit_ranges(out, "numeric_table", by_category({"Nd", "Nl", "No"}))
    emit_ranges(out, "white_space_table", proplist["White_Space"])
    emit_ranges(out, "printable_table", printable)
    emit_mapping(out, "upper", upper)
    # U+0130 lowercases to "i̇" like Rust; final sigma is handled by the caller
    emit_mapping(out, "lower", lower)
    emit_mapping(out, "fold", fold)
    path = sys.argv[1] if len(sys.argv) > 1 else "internal/unicode/tables.mbt"
    with open(path, "w") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
