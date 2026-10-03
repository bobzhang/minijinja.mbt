# TODO

Open work on the MoonBit port.  The core engine, `minijinja-contrib`
(without `datetime`) and the CLI (JSON / querystring input) are done; see
`docs/PLAN.md` for the status and `difftest/README.md` for the differential
testing against upstream.

## Differential testing coverage (`difftest/`)

The generator (`difftest/gen.mbt`) does not produce these features yet, so
they are only covered by upstream's snapshot tests, not by the Rust oracle:

- [ ] Custom syntax: `SyntaxConfig` delimiters (`block_delimiters`,
      `variable_delimiters`, `comment_delimiters`).  Needs a syntax field in
      `Case`, a matching `env.set_syntax` in the oracle (`difftest/oracle`,
      enable the `custom_syntax` feature) and a printer that uses the chosen
      delimiters.
- [ ] Line statements and line comments (`line_statement_prefix`,
      `line_comment_prefix`).
- [ ] Recursive loops: `{% for x in tree recursive %}…{{ loop(x.children) }}`
      (needs nested context data with children lists).
- [ ] Namespace attribute assignment: `{% set ns = namespace() %}{% set ns.a = 1 %}`.
- [ ] `{% filter %}` and `{% call %}` with arguments and `caller(args)`.
- [ ] Loop controls in more positions (`break`/`continue` inside `if`/`with`
      inside loops) and `loop.previtem` / `loop.nextitem` / `loop.changed`.
- [ ] Fuel (`env.set_fuel`): run both engines with the same fuel and compare
      `OutOfFuel` errors (enable the `fuel` feature in the oracle).
- [ ] Custom auto escape callbacks, `undefined_behavior` combined with
      includes, `render_block` / `call_macro` / `eval_to_state` APIs.
- [ ] Reduce the remaining generated syntax errors (`difftest -- syntax`
      lists the shortest example per message; `{%+`/`-%}` combinations and
      stray `{` in text are the main sources).

Run a survey with: `moon run --target native --release difftest -- survey 5000 <seed>`.

## CLI (`cli/`, `cmd/minijinja`)

- [ ] Input formats: YAML (1.2), TOML, CBOR, INI, JSON5.  Upstream uses
      serde crates; these need MoonBit parsers producing `Value`s with the
      same number/ordering semantics.  Then port the skipped upstream tests
      (`yaml`, `yaml_aliases`, `toml`, `ini`, `ini_casing`, `cbor`, `json5`,
      the `preserve_order_*` tests, `select_from_toplevel`).
- [ ] TOML config file (`--config-file`, `--print-config`, `$HOME/.minijinja.toml`).
- [ ] `--repl` and `--generate-completion`.
- [ ] `-D key:=value` parses JSON only; upstream parses YAML.
- [ ] Template paths are normalized lexically instead of canonicalized
      (symlinks), see the CLI section of `README.mbt.md`.

## Warnings on wasm-gc and js

`moon check --target all --deny-warn` fails because the file IO based test
helpers are only compiled for native and wasm:

- [ ] Gate the helpers used only by the snapshot suites with
      `#cfg(any(target="native", target="wasm"))`: `normalize_snapshot`,
      `snapshot_body`, `split_fixture` (`testsupport_wbtest.mbt`),
      `render_error_chain`, `apply_template_settings`, `render_fragment`
      (`templates_wbtest.mbt`), `finish_debug` (`codegen_wbtest.mbt`),
      `settings_to_configs` (`lexer_wbtest.mbt`).
- [ ] The wbtest imports `moonbitlang/async`, `moonbitlang/async/fs` and
      `moonbitlang/core/json` in `moon.pkg` are unused on wasm-gc/js.  Either
      move the snapshot suites into a separate native+wasm package (now
      possible through the public `debug_tokens` / `debug_ast` /
      `Template::debug_instructions` helpers) or find a per-target import.
- [ ] Then add `--deny-warn` to the wasm-gc/js CI job.

## Contrib

- [ ] `datetime` feature (`datetimeformat`, `dateformat`, `timeformat`,
      `now`); upstream builds on `jiff`.
- [ ] Full HTML entity table for `striptags` (upstream `html_entities`).
- [ ] `unicode_wordwrap` (Unicode line breaking and widths for `wordwrap`).
- [ ] `wordcount` uses the port's Unicode 16.0 letter table; upstream's
      `unicode_categories` crate is older (a few recent letters differ).

## Upstream

Bugs found by differential testing, documented in `difftest/README.md`
(the port does not replicate them).  Consider reporting them upstream:

- [ ] `dict|reverse` does not reverse (reversible enumerators skip `.rev()`).
- [ ] `break` inside `with` inside `for` panics (`Option::unwrap()` on `None`).
- [ ] `[][::-1]` / `''[::-1]` panic (index out of bounds).
- [ ] `x is divisibleby(0)` panics (remainder by zero).
- [ ] `indent` / `batch` / `slice` with huge counts abort on allocation.
- [ ] contrib: `''.count('')` loops forever.

## Performance

- [ ] Rendering is about 2x slower than Rust (`bench/README.md`); profile
      with `moon run --profile` once `xcrun xctrace` is available.
