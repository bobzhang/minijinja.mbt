1. **P2 — `cycler` can abort after its input array changes.** [contrib/globals.mbt:61](contrib/globals.mbt:61) retains the caller’s mutable array. Input: create `c = cycler(items)` with `[1]`, call `items.clear()`, then render `{{ c.next() }}`. Upstream owns its vector and returns `1`; the port reaches modulo-by-zero/index failure. **Fix:** store `items.copy()`.

2. **P2 — `truncate` overflows its length threshold.** [contrib/filters.mbt:221](contrib/filters.mbt:221). `{{ "abcdefgh"|truncate(length=3, leeway=2147483647) }}` should return `abcdefgh`; the port returns `...` because `length + leeway` wraps negative. **Fix:** compare using `Int64` arithmetic or an overflow-free subtraction.

3. **P3 — `.format()` splits supplementary characters in errors.** [formatting.mbt:816](formatting.mbt:816), reached through `contrib/pycompat.mbt:243`. `{{ "{:😀}".format(1) }}` should report invalid conversion type `'😀'`; the port embeds only the high surrogate `U+D83D`. The same problem occurs at line 1027. **Fix:** decode a complete character before interpolating it into errors.

4. **P3 — `wordcount` uses different letter classifications.** [contrib/filters.mbt:285](contrib/filters.mbt:285). `{{ "𞤀"|wordcount }}` returns `0` upstream but `1` here: upstream’s pinned `unicode_categories` table lacks this Adlam letter, while the port uses Unicode 15.1. **Fix:** use a separate table matching the pinned dependency for strict compatibility.

5. **P3 — extension-key IDs eventually collide.** [vm_state.mbt:446](vm_state.mbt:446). Keep key `a`, allocate/discard `2³²−1` keys, then create `b`. Their IDs match. After storing values under both, `get_extension(a)` returns `None` instead of its stored value: the loader writes into `b.slot`. **Fix:** use checked, non-reused IDs or identity-based keys.

The first four behaviors were checked using existing compiled JavaScript artifacts; the key collision follows from the 32-bit counter.
---

## Resolution

1. Fixed: `cycler` copies its input.
2. Fixed: `truncate` compares in 64-bit arithmetic (regression test added).
3. Reverted after differential testing: upstream reports the first UTF-8 byte
   (`'😀'` shows as `'ð'`), and the port now matches it exactly.
4. Not changed (deliberate): `wordcount` uses Unicode 15.1 tables shared with
   the rest of the port instead of the older `unicode_categories` tables.
5. Not changed: collision needs 2³² key allocations; keys are expected to be
   created once per extension kind.
