Source-based review; I did not rebuild or execute either engine in the read-only workspace. Rust links refer to the supplied checkout.

1. **[P1] Large slice steps can cause nontermination or a runtime trap.**

   MoonBit: [value_ops.mbt:874](/Users/hongbozhang/git/minijinja.mbt/value_ops.mbt:874), also lines 878 and 945–957. Rust: [value/ops.rs:169](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/ops.rs:169).

   `{{ "a"[::4294967296] }}` narrows the step to zero, so `slice_array` repeatedly appends the same character. Rust returns `"a"`. For sequences, the narrowed zero reaches the size calculation’s division. Negative steps have the same narrowing problem.

   **Fix:** Keep steps and index arithmetic in 64 bits, converting an index only after bounds checking. Avoid overflow in ceiling-division calculations.

2. **[P2] JSON autoescaping silently replaces serialization failures with `null`.**

   MoonBit: [json.mbt:487](/Users/hongbozhang/git/minijinja.mbt/json.mbt:487), called from [utils.mbt:203](/Users/hongbozhang/git/minijinja.mbt/utils.mbt:203). Rust: [utils.rs:131](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/utils.rs:131).

   `{% autoescape "json" %}{{ {none: 1} }}{% endautoescape %}` renders `null` in MoonBit. Rust raises `BadSerialization` because `none` is not a valid JSON object key. The catch-all hides the failure and substitutes different data.

   **Fix:** Propagate serialization errors through `write_escaped`, wrapping them with Rust’s `BadSerialization` context.

3. **[P2] Includes exhaust candidate iterators before trying the first template.**

   MoonBit: [vm.mbt:768](/Users/hongbozhang/git/minijinja.mbt/vm.mbt:768). Rust: [vm/mod.rs:901](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/mod.rs:901).

   Supply `names` as a one-shot iterator over `["a", "b"]`, with template `a` containing `A`. Rendering `{% include names %}{{ names|list }}` produces `A[]` in MoonBit, versus `A['b']` in Rust. An infinite candidate iterator prevents MoonBit from rendering even when its first candidate exists.

   **Fix:** Iterate candidates lazily and return immediately after a successful include.

4. **[P2] Built-in maps do not preserve Rust’s default ordering and key-lookup semantics.**

   MoonBit: [vm.mbt:238](/Users/hongbozhang/git/minijinja.mbt/vm.mbt:238), [object.mbt:194](/Users/hongbozhang/git/minijinja.mbt/object.mbt:194). Rust: [value/mod.rs:328](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:328), [vm/mod.rs:440](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/mod.rs:440).

   MoonBit always uses an insertion-ordered hash map. Rust defaults to `BTreeMap`, using `Value::cmp` for key identity. Thus `{{ {'z': 0, 'a': 0}|list }}` yields `['z', 'a']` instead of `['a', 'z']`. More substantially:

   ```jinja
   {% set n = "NaN"|float %}{% set d = {n: 1} %}
   {{ d[n]|default("missing") }}
   ```

   MoonBit returns `missing`; default Rust returns `1`, because its total ordering recognizes the key even though NaN equality is false.

   **Fix:** Use ordered-map semantics for the default configuration. This finding specifically concerns Rust without `preserve_order`.

5. **[P2] Custom object comparisons cannot be represented or dispatched.**

   MoonBit: [object.mbt:66](/Users/hongbozhang/git/minijinja.mbt/object.mbt:66), [value_cmp.mbt:155](/Users/hongbozhang/git/minijinja.mbt/value_cmp.mbt:155). Rust: [value/object.rs:260](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/object.rs:260), [value/mod.rs:889](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:889).

   Rust checks `custom_cmp` before structural or string comparison. MoonBit has no corresponding hook. For plain numeric objects rendering `"2"` and `"10"`, with Rust’s `custom_cmp` comparing their numeric fields, `{{ values|sort|join(",") }}` produces `2,10` in Rust and `10,2` in MoonBit.

   **Fix:** Add the comparison hook and same-type dispatch, and consult it in both equality and ordering.

6. **[P2] Default rendering makes distinct plain objects compare equal.**

   MoonBit: [object.mbt:420](/Users/hongbozhang/git/minijinja.mbt/object.mbt:420), [value_cmp.mbt:201](/Users/hongbozhang/git/minijinja.mbt/value_cmp.mbt:201). Rust: [value/object.rs:315](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/object.rs:315), [value/mod.rs:735](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:735).

   Define a plain object containing `n`, without overriding rendering. Two instances with `n=1` and `n=2` both render as `<object>` in MoonBit, making `{{ a == b }}` return `True`. Rust falls back to the object’s `Debug` representation, so a normally derived representation distinguishes them and equality returns `False`.

   **Fix:** Preserve an object-specific debug-rendering fallback instead of substituting a universal string.

7. **[P2] Positive `range` length calculation overflows for valid small ranges.**

   MoonBit: [functions.mbt:21](/Users/hongbozhang/git/minijinja.mbt/functions.mbt:21). Rust: [functions.rs:432](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/functions.rs:432).

   `{{ range(0, 9223372036854775807, 9223372036854775807)|list }}` returns `[]` in MoonBit instead of Rust’s `[0]`. The numerator `end - start + step - 1` wraps to `-3`, producing a zero length.

   **Fix:** Calculate the length using wider arithmetic or overflow-safe unsigned distance and ceiling division, then apply the element limit before narrowing.

8. **[P2] Converting infinities to integers returns zero instead of saturating.**

   MoonBit: [filters.mbt:648](/Users/hongbozhang/git/minijinja.mbt/filters.mbt:648). Rust: [filters.rs:689](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:689).

   `{{ "inf"|int }}` and `{{ "-inf"|int }}` both produce `0`. Rust produces `i128::MAX` and `i128::MIN`, respectively. `f64_trunc_to_bigint` returns zero for infinities before the saturation helper checks bounds.

   **Fix:** Handle positive and negative infinity explicitly in `f64_to_i128_sat`; retain zero only for NaN.

9. **[P2] Float parsing rejects overflow that Rust accepts as infinity.**

   MoonBit: [filters.mbt:718](/Users/hongbozhang/git/minijinja.mbt/filters.mbt:718). Rust: [filters.rs:722](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:722).

   `{{ "1e400"|float }}` raises `InvalidOperation` in MoonBit, whereas Rust renders `inf`. MoonBit’s `parse_double` reports numeric overflow as an error, and the wrapper treats every error as invalid syntax. This also affects the integer filter’s float-parsing fallback.

   **Fix:** Distinguish syntactically valid overflow from malformed input and return signed infinity for overflow.

10. **[P2] The 128-bit lossless-coercion check differs at the maximum values.**

    MoonBit: [value_ops.mbt:215](/Users/hongbozhang/git/minijinja.mbt/value_ops.mbt:215). Rust: [value/ops.rs:32](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/ops.rs:32).

    Compare `Value::from_bigint((1N << 128) - 1N)` with `Value::from_double(340282366920938463463374607431768211456.0)`. MoonBit returns unequal and orders the integer below the float. Rust’s equivalent `u128::MAX` comparison returns equal: its round-trip cast saturates back to `u128::MAX`. The analogous discrepancy exists at `i128::MAX`.

    **Fix:** For reference compatibility, perform the round-trip check with Rust-style saturating casts using the original signed or unsigned bounds.

11. **[P2] JSON object-key conversion changes booleans and rejects valid float keys.**

    MoonBit: [json.mbt:452](/Users/hongbozhang/git/minijinja.mbt/json.mbt:452). Rust: [value/mod.rs:2020](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:2020), reached through [filters.rs:1236](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:1236).

    `{{ {true: 1}|tojson }}` produces `{"True": 1}` instead of Rust’s `{"true": 1}`. Also, `{{ {1.5: 1}|tojson }}` fails in MoonBit, while Rust’s serializer accepts the finite float key and produces `{"1.5": 1}`.

    **Fix:** Implement JSON-specific key conversion: lowercase boolean spellings, finite-float support, and rejection of nonfinite floats.

12. **[P2] Final-sigma lowercasing uses incomplete Unicode properties.**

    MoonBit: [internal/unicode/unicode.mbt:143](/Users/hongbozhang/git/minijinja.mbt/internal/unicode/unicode.mbt:143), also line 155. Rust: [filters.rs:217](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:217), delegating to `str::to_lowercase`.

    `{{ "ǅΣ"|lower }}` yields `ǆσ` instead of `ǆς`: titlecase `ǅ` is cased, but neither uppercase nor lowercase. Likewise, `{{ "A\u200dΣ"|lower }}` uses the wrong sigma because U+200D is missing from the case-ignorable approximation.

    **Fix:** Generate complete `Cased` and `Case_Ignorable` tables and use them for the contextual rule.

13. **[P2] Negating the minimum rounding precision overflows.**

    MoonBit: [filters.mbt:817](/Users/hongbozhang/git/minijinja.mbt/filters.mbt:817). Rust: [filters.rs:782](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:782).

    `{{ 0.01|round(-2147483648) }}` returns `0.01` in MoonBit instead of `0.0`. Negation wraps in 32 bits; the subsequent retained-digit calculation becomes a large positive number, preserving all digits. Rust widens before negating.

    **Fix:** Widen the precision before negation, or handle `precision <= -309` before computing its magnitude.

14. **[P2] Maximum `split` count overflows into a negative limit.**

    MoonBit: [filters.mbt:556](/Users/hongbozhang/git/minijinja.mbt/filters.mbt:556). Rust: [filters.rs:571](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:571).

    `{{ "a b"|split(none, 9223372036854775807) }}` returns `['a b']` instead of `['a', 'b']`. Adding one overflows `Int64`, and clamping preserves a negative limit that disables whitespace splitting. Rust converts to unsigned before adding one.

    **Fix:** Clamp before incrementing, or perform the increment in unsigned/wider arithmetic.

15. **[P3] Numeric attribute paths reject a leading plus sign.**

    MoonBit: [value.mbt:728](/Users/hongbozhang/git/minijinja.mbt/value.mbt:728). Rust: [value/mod.rs:1935](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:1935).

    `{{ [[42]]|map(attribute="+0")|list }}` produces `[undefined]` instead of `[42]`. Rust’s `usize` parser accepts `+0`; MoonBit treats it as an attribute name.

    **Fix:** Accept one leading `+`, while still requiring subsequent decimal digits and checking bounds.

16. **[P3] Grouped tuples lose pretty-debug formatting.**

    MoonBit: [filters.mbt:1479](/Users/hongbozhang/git/minijinja.mbt/filters.mbt:1479). Rust: [filters.rs:1751](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/filters.rs:1751).

    `{{ ([{"x": 1}]|groupby("x"))[0]|pprint }}` remains compact in MoonBit: `(1, [{'x': 1}])`. Rust renders the tuple and nested containers across indented lines. MoonBit creates a fresh formatter without the caller’s alternate flag.

    **Fix:** Pass the active formatter, or its formatting context, through object rendering rather than pre-rendering `GroupTuple` with default options.