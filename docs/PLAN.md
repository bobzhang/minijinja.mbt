# MiniJinja → MoonBit porting plan

Upstream: <https://github.com/mitsuhiko/minijinja>, pinned in
`scripts/MINIJINJA_COMMIT` and cloned (not committed) at `.repos/minijinja`.
Scope is the `minijinja` crate (~25k lines of Rust).  `minijinja-contrib`,
the CLI and the language bindings come later, if at all.

## Goals

* Faithful port: lexer, parser, AST, code generator, VM, value model,
  filters, tests, functions, macros, `extends` / `include` / `import`,
  loop controls, custom syntax, line statements, auto escaping, undefined
  behaviors, error reporting with spans and debug info.
* The core library is pure MoonBit with no IO, and builds on every backend
  (`native`, `wasm-gc`, `js`).  IO happens only in tests and a future CLI, through
  `moonbitlang/async` (which now supports wasm).
* Upstream's snapshot corpus (`tests/inputs/*.txt` and `tests/snapshots/*.snap`)
  is the conformance oracle.  It is vendored in `testdata/`.

## Out of scope / replaced

| Rust | MoonBit |
|---|---|
| `serde` / `Serde<T>` / deserialization | `Value::from_json(Json)`, `Value::to_json()` |
| `self_cell` vendor, `type_erase!` vtables | a GC'd trait object (`&Object`) |
| `Arc`, lifetimes, `'source` borrowing | GC references; templates own their source `String` |
| `ArgType` / `FunctionArgs` generic magic | an explicit `Args` helper (see below) |
| `fuel`, `stacker` | `fuel` later; no stack growth |
| `std::io::Write` outputs | `StringBuilder` |

## UTF-16 strategy

MoonBit `String` is UTF-16, while Rust works in UTF-8 bytes.

* Lexer offsets are **UTF-16 code unit** offsets (used for slicing the source).
  Line and column numbers are counted in **Unicode scalars**, as Rust does, so
  span debug output (`@ 1:0-1:5`) and error markers match the snapshots.
* Template-level string semantics are per Unicode scalar (Rust `chars()`):
  `length`, indexing, slicing, `reverse`, `center`, `truncate`, `wordcount`,
  and iteration all walk code points, never code units.
* `Value::Bytes` stays a byte sequence; `string` conversion of bytes uses
  lossy UTF-8 decoding.

## Package layout

One public facade package that owns the public types (they are mutually
recursive: `Value` ↔ `State` ↔ `Environment`), plus internal helpers.

```
bobzhang/minijinja            (root) Value, Object, Kwargs, Error, Environment,
                              Template, State, SyntaxConfig, filters, tests,
                              functions, lexer, parser, AST, codegen, VM
bobzhang/minijinja/internal/rfmt   Rust-compatible f64 Display/Debug formatting
bobzhang/minijinja/tests      snapshot conformance runner (async fs, native/wasm)
```

Files in the root package mirror the upstream modules (`lexer.mbt`,
`parser.mbt`, `ast.mbt`, `codegen.mbt`, `instructions.mbt`, `vm.mbt`,
`vm_state.mbt`, `value.mbt`, `value_ops.mbt`, `object.mbt`, `filters.mbt`, …).

## Key designs

### Value

```
enum Value {
  Undefined(UndefinedType)   // Default | Silent
  None
  Bool(Bool)
  U64(UInt64) | I64(Int64) | F64(Double)
  U128(BigInt) | I128(BigInt)   // range-checked BigInt
  Str(String, StringType)       // Normal | Safe
  Bytes(Bytes)
  Invalid(Error)
  Object(DynObject)
}
```

`Value` is an abstract type; users build values with constructors
(`Value::from_int`, `from_string`, `from_array`, `from_map`, `from_object`, …)
and inspect them with accessors (`kind`, `as_str`, `as_i64`, `try_iter`, …).
Arithmetic follows `value/ops.rs` exactly, with i128 semantics emulated by a
fast Int64 path plus a BigInt slow path that checks i128 and u128 bounds.

### Objects

`DynObject` wraps an internal enum: built-in objects (`Seq`, `Map`, `Tuple`,
`Kwargs`, `Namespace`, `Loop`, `Macro`, `Module`, lazy iterables, merged
seqs/maps) plus `Custom(&Object)` for user types.  The internal enum stands
in for Rust's `downcast_ref` (tuples, kwargs, namespace, loop).  The public
`Object` trait mirrors Rust's (`repr`, `get_value`, `enumerate`,
`enumerator_len`, `is_true`, `call`, `call_method`, `custom_cmp`, `render`)
with default methods.  `Enumerator` maps to MoonBit's pull-based `Iter`.

`ValueMap` preserves insertion order (like the `preserve_order` feature).
The JSON test contexts are key-sorted the way `serde_json` sorts them, so
the snapshots still match.

### Callables and arguments

Filters, tests and functions have the type
`(State, Array[Value]) -> Value raise Error`.  An `Args` helper ports the
`ArgType` conversion rules: a trailing kwargs value, `MissingArgument`,
`TooManyArguments`, `Option` = undefined/none, string coercion that
rejects undefined in strict mode, and `Rest`.  The built-in filters use
the same helper.

### VM

Same instruction set as `compiler/instructions.rs`.  Lifetimes go away:
macros hold their `Instructions` and closure map directly.  Block stacks,
`super()`, recursive loops, `loop.changed/cycle`, `previtem/nextitem`, and
the include/import depth costs are ported as written.

### Errors

`suberror` carrying an `Error` record (`kind`, `detail`, `name`, `lineno`,
`span`, `source`, `debug_info`), with Rust-compatible `Display` (`{}` and
`{:#}`) and `Debug` (`{:#?}`) renderers, because the snapshots contain all
three.

### Rust formatting parity

* `f64` Display (`50.0`, `1e100` → `1000…0.0`) and Debug: digits come from
  MoonBit's shortest-roundtrip `Double::to_string` and are re-laid out.
* Python-style string repr used by `Value` Debug, `{:#?}` pretty Debug for
  the AST, and the `format` (printf) filter.

## Test strategy

1. `testdata/` mirrors upstream `tests/{inputs,lexer-inputs,parser-inputs,fragment-inputs,snapshots}`.
2. `tests/` package: an async test reads every input, runs it the same
   way the Rust test harness does (`test_templates.rs`, `test_lexer.rs`,
   `test_parser.rs`), and compares against the `.snap` body.  A checked-in
   `testdata/known_failures.txt` lists cases that don't pass yet, so CI
   catches regressions while the port is in progress.  Each fixed case is
   removed from the list.
3. Unit tests port the targeted Rust tests (`test_value.rs`, `test_filters.rs`,
   `test_environment.rs`, `test_macros.rs`, …) as MoonBit `test` blocks.

## Status

* Milestones 1–12 are done.  All upstream lexer (22), parser (40),
  compiler (4), template (160) and block fragment (6) snapshots pass, as do
  the ported upstream unit tests (`*_test.mbt`, ~250 tests) on the native,
  wasm, wasm-gc and js backends (the corpus runners need file IO and run on
  native and wasm only).
* Two Codex review rounds (`docs/codex-review-*.md`) were addressed.
* `fuel` is ported; `minijinja-contrib` is being ported in `contrib/`
  (without the `datetime` feature which depends on `jiff`).
* Benchmarks mirroring upstream live in `bench/`
  (`moon bench --target native --release bench`).

## Milestones (one or more commits each)

1. Skeleton, vendored fixtures, plan.  ✅
2. Error type, Span, Rust float formatting helper.
3. Lexer + token Debug → lexer snapshots pass.
4. AST + parser + pretty Debug printer → parser snapshots pass.
5. Value model, objects, ops, ordering/equality/hash.
6. Instructions + codegen (+ compiler snapshots).
7. VM core: output/capture, autoescape, undefined behaviors, loops, if,
   set/with, filters/tests/functions dispatch → first template snapshots.
8. Built-in filters, tests, functions (`range`, `dict`, `namespace`, `debug`).
9. Macros, call blocks, closures.
10. Multi-template: loader, `extends`/`block`/`super`, `include`, `import`.
11. Error debug-info rendering, the rest of the error snapshots, custom syntax,
    line statements.
12. `format` filter, `tojson`/`urlencode`, remaining snapshots, docs, README.
13. Optional: `minijinja-contrib`, a CLI built on `moonbitlang/async`.

## Notes adopted from the Codex review (`docs/codex-advice-plan.md`)

* Object identity uses explicit ids (not `physical_equal`, which is only an
  optimization hint) for `sameas` and equality fast paths.
* `.snap` comparison applies insta's normalization (strip leading CR/LF and
  trailing whitespace, CRLF → LF) to both sides; exact-output unit tests
  cover trailing newlines and whitespace control.
* JSON fixtures are decoded by a number-preserving JSON → `Value` parser
  (`4` stays an integer and `4.0` a float), unlike `@json`.
* The `format` filter keeps upstream quirks: padding counts UTF-8 bytes and
  `%c` pads to width one. `round` uses half-even decimal rounding.
* Sorting is stable and reverses the comparator, not the result.
* `Value` Display of floats appends `.0` (`50.0`, `-0.0`); containers use the
  Debug representation (exponent form for large or small magnitudes).
* Deviation: span offsets are UTF-16 code units (MoonBit string indices)
  instead of UTF-8 bytes; lines and columns match Rust exactly.

## Risks

* Float formatting parity (Rust Display and Debug).  Mitigated by a tested
  helper package.
* i128 semantics: overflow errors must trigger exactly at the i128 and u128
  bounds.
* Map ordering differences: the default `BTreeMap` behavior is ignored in
  favor of insertion order.  Snapshot cases that depend on sorted literal
  maps get recorded and resolved one by one.
* Unicode identifiers (`unicode` feature: XID tables).  The first pass is
  ASCII identifiers plus a compact XID table later.
