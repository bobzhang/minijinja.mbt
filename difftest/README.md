# Differential testing against upstream MiniJinja

This package checks the port against the upstream Rust implementation with
property based testing (`moonbitlang/core/quickcheck`):

* `oracle/` is a small Rust program built on upstream MiniJinja (at the commit
  in `scripts/MINIJINJA_COMMIT`, with upstream's `Cargo.lock`).  It reads one
  JSON test case per line and answers with the rendered output or the error.
* The MoonBit side generates random templates (expressions, filters, tests,
  loops, macros, call blocks, whitespace control, autoescaping, ...) and
  render contexts, renders them with both engines and requires identical
  output or identical error messages (including the error chain).  Failing
  cases are shrunk to a minimal template.

## Running

```bash
git clone https://github.com/mitsuhiko/minijinja .repos/minijinja
git -C .repos/minijinja checkout $(cat scripts/MINIJINJA_COMMIT)
cargo build --release --manifest-path difftest/oracle/Cargo.toml
moon run --target native --release difftest -- survey 3000 1
```

Modes (`difftest -- <mode> [count] [seed] [max_size]`):

* `survey`: runs `count` cases, shrinks every mismatch and prints the
  distinct minimal ones (and upstream crashes separately).
* `check`: runs `@quickcheck.check` with shrinking and stops at the first
  counterexample.
* `show`: prints generated templates.

## Known upstream differences

Cases where upstream misbehaves and the port deliberately does not follow:

* `{{ {"a": 1, "b": 2}|reverse }}` renders `['a', 'b']` upstream: `reverse`
  does not reverse map keys (it skips `.rev()` for reversible enumerators).
  The port reverses them, like Jinja2.
* `{% for x in 'a' %}{% with y = 1 %}{% break %}{% endwith %}{% endfor %}`
  panics upstream (`Option::unwrap()` on `None`).  The port renders nothing.
* `{{ [][::-1] }}` and `{{ ''[::-1] }}` (reverse slices of empty sequences
  and strings) panic upstream with an out of bounds index.  The port returns
  an empty result.
* `{{ 1|indent(huge) }}` (for example `indent(2 ** 63)`) aborts upstream with
  an allocation failure.  The port raises an error.
