Found **six remaining divergences** after reviewing the fixes through `2cf9c04`. Findings 1, 3, 4, and 6 were reproduced using existing JavaScript build artifacts; JSON parsing findings are source-based. Rust expectations come from the supplied checkout. No files were changed or builds run.

For **A**, most important first:

1. **[P1] Scientific-format rounding can panic instead of rendering.**

   MoonBit: [internal/rfmt/exact.mbt:144](internal/rfmt/exact.mbt:144), reached from `formatting.mbt`. Rust: [formatting.rs:294](.repos/minijinja/minijinja/src/formatting.rs:294).

   ```jinja
   {{ '%.1e'|format(9.99) }}
   ```

   Rust renders `1.0e+01`. MoonBit aborts outside the `TemplateError` mechanism. Rounding produces digits `"100"`, so padding calls `"0".repeat(2 - 3)`. `%.1g` with the same value also panics.

   **Fix:** Normalize the mantissa after rounding carry, or clamp padding to zero before taking the required digits. Preserve the adjusted exponent.

2. **[P2] `from_json_str` accepts invalid JSON numbers and strings.**

   MoonBit: [json.mbt:185](json.mbt:185), [json.mbt:173](json.mbt:173), and line 178. Rust: [value/deserialize.rs:12](.repos/minijinja/minijinja/src/value/deserialize.rs:12), driven by `serde_json::from_str`, as in [test_templates.rs:79](.repos/minijinja/minijinja/tests/test_templates.rs:79).

   ```moonbit
   Value::from_json_str("01")
   Value::from_json_str("\"a\nb\"")
   Value::from_json_str("\"\\uD800\"")
   ```

   MoonBit accepts the leading-zero integer, unescaped newline, and unpaired surrogate. Rust’s JSON deserializer rejects all three. The string parser writes unchecked code points; the number parser delegates insufficiently validated text to general numeric parsers.

   **Fix:** Enforce JSON number grammar, reject unescaped characters below U+0020, and require valid surrogate pairs before constructing characters.

3. **[P2] Overflowing float literals still fail despite the filter-parsing fix.**

   MoonBit: [lexer.mbt:552](lexer.mbt:552). Rust: [compiler/lexer.rs:499](.repos/minijinja/minijinja/src/compiler/lexer.rs:499).

   ```jinja
   {{ 1e400 }}
   ```

   MoonBit raises `SyntaxError: invalid float`; Rust renders `inf`. The review-1 fix handles string-to-float filters, but the lexer retains a separate parser that rejects overflow.

   **Fix:** Share overflow-aware Rust-compatible float parsing with the lexer, while continuing to reject malformed exponents.

4. **[P2] JSON map keys reject plain objects that Rust serializes as strings.**

   MoonBit: [json.mbt:453](json.mbt:453). Rust: [value/mod.rs:2008](.repos/minijinja/minijinja/src/value/mod.rs:2008), together with map-entry serialization at line 2025.

   ```jinja
   {{ {range: 1}|tojson }}
   ```

   MoonBit raises `cannot serialize to JSON`. With debug enabled, Rust renders:

   ```json
   {"minijinja::functions::builtins::range": 1}
   ```

   Rust serializes `ObjectRepr::Plain` through `serialize_str`, which is valid for JSON keys. MoonBit’s primitive-only key dispatch misses this case.

   **Fix:** Accept plain-object keys through their string rendering. Keep rejecting objects whose serialization produces containers.

5. **[P3] JSON integer parsing loses negative zero.**

   MoonBit: [json.mbt:216](json.mbt:216). Rust: [value/deserialize.rs:12](.repos/minijinja/minijinja/src/value/deserialize.rs:12), using serde_json’s numeric deserializer.

   ```moonbit
   Value::from_json_str("-0").to_json_string()
   ```

   MoonBit returns `"0"`; Rust’s equivalent deserialize/serialize round trip returns `"-0.0"`. Parsing through `BigInt` erases the sign before choosing the value representation.

   **Fix:** Preserve the lexical sign and represent JSON `-0` as negative floating-point zero.

6. **[P3] Failed typed keyword conversions incorrectly consume the keyword.**

   MoonBit: [args.mbt:108](args.mbt:108), also the other typed getters. Rust: [value/argtypes.rs:1169](.repos/minijinja/minijinja/src/value/argtypes.rs:1169).

   Construct `Kwargs::from_pairs([("n", Value::from_string("x"))])`, catch the error from `get_int("n")`, then call `assert_all_used()`.

   MoonBit succeeds; Rust’s corresponding `get::<Option<i64>>` leaves `n` unused, so validation reports an unknown keyword. MoonBit marks usage in `get_opt` before conversion succeeds.

   **Fix:** Mark keywords used only after the requested conversion succeeds.

The other requested areas did not yield additional actionable port divergences in this pass. In particular, reverse-order macro default binding and filtered recursive-loop compilation follow the supplied Rust implementation. Debug columns count Unicode scalars, offsets use the documented UTF-16 convention, and both renderers omit caret underlines for multi-line spans.

For **B**, the core rendering API is broadly complete. The highest-value improvements are at the application integration boundary:

1. **Add consistent value conversion and accessors.** [The current interface](pkg.generated.mbti:301) provides many constructors but lacks strict boolean and full-width integer accessors. Custom argument conversion also requires repetitive manual code.

   ```moonbit
   pub fn Value::as_bool(Self) -> Bool?
   pub fn Value::as_uint64(Self) -> UInt64?
   pub fn Value::as_bigint(Self) -> BigInt?
   pub(open) trait FromValue {
     fn from_value(Value) -> Self raise TemplateError
   }
   pub fn[T : FromValue] Args::next(Self) -> T raise TemplateError
   pub fn[T : FromValue] Kwargs::get_as(Self, String) -> T raise TemplateError
   ```

   Implementing `FromValue` for optional types would also unify required/optional keyword handling.

2. **Make custom objects recoverable and formatting-aware.** [`Object`](pkg.generated.mbti:386) has useful defaults, but applications cannot recover their concrete object type. This particularly limits the newly added `custom_cmp`. Its rendering hook also cannot observe pretty formatting.

   Proposed signatures, with an explicit registered type key for safe extraction:

   ```moonbit
   pub fn[T : Object] Value::downcast_object(Self, ObjectKey[T]) -> T?
   // Proposed Object hook, retaining render() as its default:
   fn render_with_options(Self, pretty~ : Bool) -> String?
   ```

3. **Expose streaming rendering.** [`Template`](pkg.generated.mbti:282) currently requires buffering the full output. Rust exposes writer-based rendering and block rendering.

   ```moonbit
   pub fn Template::render_to(
     Self, Value, write~ : (StringView) -> Unit raise,
   ) -> State raise TemplateError
   pub fn State::render_block_to(
     Self, String, write~ : (StringView) -> Unit raise,
   ) -> Unit raise TemplateError
   ```

   Wrap callback failures as `WriteFailure`, preserving their cause.

4. **Preserve arbitrary error causes and implement `Debug`.** [`with_source`](error.mbt:200) accepts only `TemplateError`, preventing loaders and functions from retaining filesystem, network, or parsing errors.

   ```moonbit
   pub fn TemplateError::with_source(Self, Error) -> Self
   pub fn TemplateError::source(Self) -> Error?
   pub impl @debug.Debug for TemplateError
   ```

   Prefer returning a new error wrapper from `with_source`; its current mutation can surprise callers retaining aliases.

5. **Polish Environment/State APIs and documentation.** Add loaded-template iteration and typed per-render extensions, then replace positional configuration booleans with labels.

   ```moonbit
   pub fn Environment::templates(Self) -> Iter[(String, Template)]
   pub fn[T] State::get_extension(Self, ExtensionKey[T]) -> T?
   pub fn[T] State::set_extension(Self, ExtensionKey[T], T) -> T?
   pub fn Template::undeclared_variables(
     Self, nested? : Bool = false,
   ) -> Array[String]
   ```

   Apply the same `nested` signature to `Expression`. The README’s basic examples are useful; loader, captured-state, and custom-formatter examples would make these embedding APIs substantially easier to discover.