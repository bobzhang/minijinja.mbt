# Recommended approach

Port the existing **lexer → AST → instructions → VM** architecture, while simplifying ownership and storage. Keep the mutually dependent engine types in one MoonBit package initially; isolate only genuinely independent helpers.

I inspected the supplied checkout: **MiniJinja `3.0.0-alpha.2`, commit `5978498b6def57557b75738391fdd2a49484d8e1`**. Treat that revision and its selected Cargo features as the compatibility specification. Some comments describe older behavior, so prefer implementations and tests.

The most important decisions are:

- Preserve **UTF-8 byte offsets and Unicode-scalar columns** in spans.
- Preserve numeric variants and bounded 128-bit arithmetic; use `BigInt` as an implementation tool.
- Keep object identity, mutable closures, and render-state ownership explicit.
- Implement separate formatting paths for template output, value representations, and printf.
- Import the test harness’s behavior, including fixture setup and insta normalization.

## 1. Packages and `Value`

### Package layout

Rust modules are not suitable one-for-one MoonBit package boundaries. The actual dependency graph contains several cycles:

```text
Value → Object.call → State → Environment → registered Value
Value → Invalid(Error) → DebugInfo → Value
Instructions → Value constants → callable objects → State → Instructions
```

My recommended initial layout is:

```text
moon.mod                         # name = "bobzhang/minijinja"
moon.pkg                         # public engine package

value.mbt
value_ops.mbt
value_compare.mbt
value_repr.mbt
object.mbt
object_enumeration.mbt
arguments.mbt

error.mbt
debug_info.mbt
source.mbt
syntax.mbt
lexer.mbt
tokens.mbt
ast.mbt
parser.mbt
compiler_meta.mbt
codegen.mbt
instructions.mbt

context.mbt
state.mbt
vm.mbt
macro_object.mbt
loop_object.mbt
namespace_object.mbt
module_object.mbt
output.mbt

environment.mbt
template.mbt
expression.mbt
filters_string.mbt
filters_sequence.mbt
filters_numeric.mbt
builtin_tests.mbt
functions.mbt
formatting.mbt

internal/text/                   # Unicode and encoding helpers
internal/number/                 # bounded arithmetic and decimal formatting
internal/format_parser/          # optional: syntax only, independent of Value

corpus/                          # portable generated fixtures/test data
tools/corpus/                    # filesystem runner/generator
cmd/main/                        # eventual CLI
```

Files in the root package can freely reference one another. This gives you separation without introducing dependency cycles.

Dependency order:

| Layer | Dependencies |
|---|---|
| `internal/text`, `internal/number` | MoonBit core only |
| Optional format parser | Text helpers; no `Value`, `State`, or engine error |
| Root engine | Independent helpers |
| Portable corpus tests | Engine and fixture data |
| Corpus tools and CLI | Engine, `moonbitlang/async` filesystem/stdio |

Keep public `Value`, `Object`, `State`, `Environment`, `Template`, errors, and spans owned by the public package. Do not hide these in `internal/*` and rely on re-exporting to restore their API.

If the engine later needs separate compiler and VM packages, first introduce an explicitly designed runtime capability interface. Splitting packages before establishing that interface creates unnecessary complexity.

**IO boundary:** templates are registered as strings; rendering is synchronous. A CLI can asynchronously preload a template tree, then render through an in-memory loader. A synchronous loader callback cannot directly call async filesystem APIs. Async’s Wasm support does not require the engine itself to become async.

### Value representation

The source representation is in [value/mod.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/mod.rs:553).

Use an opaque public `Value` wrapping a private enum. The following is a design sketch, not compiled code:

```moonbit
priv enum ValueRepr {
  NoneValue
  Undefined(UndefinedType)
  BoolValue(Bool)
  I64(Int64)
  U64(UInt64)
  F64(Double)
  I128(@bigint.BigInt)
  U128(@bigint.BigInt)
  StringValue(String, StringType)
  BytesValue(Bytes)
  ObjectValue(ObjectHandle)
  Invalid(ErrorInfo)
}

priv enum UndefinedType {
  Default
  Silent
}

priv enum StringType {
  Normal
  Safe
}
```

Specific choices:

| Rust representation | MoonBit treatment |
|---|---|
| `Arc<str>` | Ordinary immutable `String` |
| `SmallStr` | Merge into normal strings initially |
| `Packed<i128/u128>` | Drop packing; retain bounded signed/unsigned semantics |
| `Arc<Vec<u8>>` | Owned bytes, with mutation hidden or copied at construction |
| `DynObject` | Stable object handle containing built-in payload or `&Object` |
| `Arc<Error>` | Shared immutable error information |
| `None` | Distinct from both undefined variants |

`SmallStr` is a 22-byte inline-storage optimization, not a semantic distinction. Do not reproduce its layout. Preserve safe-string provenance independently.

Keep `Bytes` distinct: `len()` counts bytes, indexing yields a numeric byte, and slicing returns bytes. Rust’s `as_str()` accepts bytes only when valid UTF-8; `to_str()` and display perform lossy UTF-8 decoding. Those are different conversions.

**Keep `Invalid` even without serde.** `Value::validate()` also transports failures from otherwise infallible iteration and object operations.

### Objects and identity

Mirror [value/object.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/object.rs:172), with defaults supplied by the library:

```moonbit
pub(open) trait Object {
  repr(Self) -> ObjectRepr
  get_value(Self, Value) -> Value?
  get_value_by_str(Self, String) -> Value?
  enumerate(Self) -> Enumerator
  enumerator_len(Self) -> Int?
  is_true(Self) -> Bool

  call(Self, State, ArrayView[Value]) -> Value raise TemplateError
  call_method(Self, State, String, ArrayView[Value]) -> Value raise TemplateError

  render(Self, RenderMode) -> String
  custom_cmp(Self, &Object) -> Int?
}
```

This shape keeps `Self` only in the receiver position, satisfying MoonBit’s trait-object requirements. No `Send`, `Sync`, lifetimes, or `Arc<Self>` receivers are needed. [MoonBit trait-object documentation](https://docs.moonbitlang.com/en/latest/language/methods.html#trait-objects)

Preserve these defaults:

- Representation defaults to `Map`, not `Plain`.
- Missing lookup returns `None`; the engine translates that into undefined.
- Plain objects default to non-enumerable; other representations default to empty enumeration.
- Default truthiness is `enumerator_len() != Some(0)`: unknown length is truthy.
- Default invocation errors; default method invocation returns `UnknownMethod`.

Use an internal payload enum to replace the source’s **engine-required downcasts**:

```text
ObjectPayload =
    List | Tuple | Map | Kwargs
  | Namespace | Loop | Macro | Module
  | NativeCallable
  | Host(&Object)
```

That makes namespace assignment and loop-recursion dispatch explicit. Arbitrary Rust-style host downcasting can remain outside scope. For optional host custom comparison, provide a registered type key and an object-safe comparison protocol.

Give each object handle an explicit stable identity, preserved when a `Value` is copied. This supports `sameas` and the identity fast paths in equality.

Do **not** implement semantic identity using MoonBit’s `physical_equal`: the installed core explicitly documents it as an optimization hint whose result may vary by backend and optimization settings. See [intrinsics.mbt](/Users/hongbozhang/.moon/lib/core/builtin/intrinsics.mbt:39).

### Enumeration, tuples, and kwargs

Avoid reducing every enumerable object to `Array[Value]`. You need:

- Non-enumerable versus empty.
- Known versus unknown length.
- Repeatable versus one-shot iteration.
- Map keys versus map key/value pairs.
- Optional reverse iteration.

An iterator wrapper with a `next` closure and size information is sufficient; repeatable objects create fresh wrappers. One-shot objects share a cursor.

Preserve tuples. This checkout’s [value/tuple.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/tuple.rs) distinguishes tuples from lists in equality, ordering, representation, and several sequence operations. A one-item tuple renders `(x,)`.

`Kwargs` must be a **tagged mapping**, not merely a map-shaped value:

- Internally, retain the trailing tagged argument used by `BuildKwargs` and `MergeKwargs`.
- Public callers may use a convenient `CallArgs { positional, keywords }` wrapper.
- Extracting kwargs creates fresh “used argument” tracking.
- Implement `peek`, `get`, `has`, and `assert_all_used`.
- Preserve duplicate-key and non-string-key errors.
- Distinguish `Rest<Value>` from the permissive `Rest<ValueOrKwargs>` equivalent.

See [value/argtypes.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/argtypes.rs:1037).

### Integers, equality, ordering, and hashing

Use `BigInt` for 128-bit calculations, with explicit bounds:

```text
I128: −2^127 … 2^127−1
U128:       0 … 2^128−1
```

Do not expose arbitrary-precision template arithmetic as an accidental extension.

Port [value/ops.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/value/ops.rs) closely:

- Literals parse through `u64`, then `u128`.
- Arithmetic commonly coerces to signed 128-bit, performs checked operations, and narrows results through `int_as_value`.
- Division and remainder use the source’s floor-division helpers.
- `/`, `//`, and `%` reject zero divisors.
- Preserve exceptional cases such as `i128::MIN // -1`.
- Rust float-to-integer casts used by filters are not interchangeable with checked argument conversion.
- Audit `U128` coercion carefully: the same-variant branch casts to signed 128-bit. Mathematical `BigInt` conversion alone changes behavior.

Implement **equality and ordering separately**:

- Equality uses lossless numeric coercion.
- Ordering first compares `ValueKind`.
- Thus booleans can compare equal numerically while still occupying a separate ordering category.
- NaN equality and total ordering differ.
- Positive and negative zero compare equal.
- Tuples and lists differ.
- Object identity, custom comparison, and structural fallback all matter.
- Map equality ignores enumeration order; map ordering can depend on enumeration order.

For the first compatibility target, use the default Rust **ordered-map** behavior, equivalent to `BTreeMap<Value, Value>`. A sorted entry array is acceptable initially. MoonBit’s ordinary insertion-ordered hash map is not a drop-in replacement.

Delay `preserve_order` until numeric hashing and object hashing are tested. Do not derive `Eq`, `Compare`, or `Hash` from the enum tags.

## 2. Replace generic argument conversion with an explicit call ABI

Rust’s `Function`, `FunctionArgs`, and `ArgType` machinery mainly adapts ordinary Rust functions to this existing underlying signature:

```text
(State, arguments) → Value or Error
```

Use that directly:

```text
NativeFunction =
    (State, ArrayView[Value]) -> Value raise TemplateError
```

Provide an `Arguments` cursor for builtins and advanced users:

```text
required_value()
required_int64()
required_string()          # strict string conversion
required_string_input()    # coercion plus safety provenance
optional_int64()
rest_values()
kwargs()
finish()
```

A schematic registration:

```moonbit
env.add_filter_raw("surround", fn(state, values) {
  let args = Arguments::new(state, values)
  let input = args.required_string_input()
  let left = args.optional_string().unwrap_or("[")
  let right = args.optional_string().unwrap_or("]")
  args.finish()
  Value::from_string(left + input.text() + right)
})
```

The result here is deliberately a normal string: arbitrary delimiters introduce new content.

For ergonomic host APIs, add a small number of adapters—`function0`, `function1`, `function2`, perhaps `function3`—using explicit converter functions or simple conversion traits. Keep variadic and keyword-heavy functions on the raw ABI. No need to reproduce Rust’s tuple-trait machinery.

Important conversion distinctions from `argtypes.rs`:

| Conversion | Required behavior |
|---|---|
| Raw value | Accept explicit undefined; distinguish absent argument; ordinarily reject tagged kwargs |
| Boolean argument | Accept a boolean, rather than applying template truthiness |
| Integer argument | Follow checked numeric conversion, including accepted integral floats |
| Strict string | Follow `as_str()` semantics |
| Coerced string | Apply state-aware undefined checks and MiniJinja display |
| `StringInput` | Coerced text plus safe-string provenance |
| Optional argument | Rust `Option<T>` treats absent, none, and undefined as absent |

Do not apply one blanket undefined check before calling every builtin. `default`, `defined`, and related operations must inspect undefined themselves.

Also avoid automatically accepting keyword spellings for every positional parameter. Rust’s typed argument conversion does not generally bind arguments by Rust parameter name; keyword support is implemented explicitly through `Kwargs`.

## 3. VM, state, frames, macros, and recursion

### Ownership and execution

Use GC references for immutable compiled templates and mutable render-local state:

```text
CompiledTemplate:
  source
  instructions
  blocks
  syntax configuration
  initial autoescape

State:
  environment
  context
  active instruction stream
  current block
  autoescape
  block stacks
  loaded inheritance templates
  temps
  closure storage
  render identity
```

Each evaluator invocation owns its operand stack, program counter, filter/test caches, and local autoescape stack.

`Template` can directly retain its environment and compiled template. `Captured` can simply retain `{ output, state }`. The self-referential wrappers in [template.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/template.rs:210) disappear.

Keep registered configuration stable during a render. Rust borrowing prevents many environment mutations that MoonBit would otherwise permit. Either freeze configuration for active renders or render against a retained configuration snapshot.

### Context lookup and frame behavior

Port [vm/context.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/context.rs) directly. Lookup visits frames from innermost outward:

1. Locals.
2. The special loop variable.
3. Closure context.
4. Frame context object.
5. Environment globals after all frames.

Stores affect the current frame and its attached closure. Loop iteration clears frame locals before binding the next item.

Preserve that scope behavior instead of using a single mutable context dictionary.

### Cleanup is the main borrowing replacement

The key abstraction is [State::with_execution_state](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/state.rs:155).

Implement scoped save/restore helpers using `defer`, or explicit result capture followed by restoration. Restoration must occur on both normal return and raised errors:

- Active instructions and template name.
- Autoescape and current block.
- Context/frame depth.
- Block stacks and inheritance tracking.
- Closure attachment.
- Output capture state belonging to that invocation.

Attach VM error information **before restoring the caller’s instruction stream**.

Nested callbacks can render blocks or invoke macros, so arguments passed into them must remain stable. Copy the argument slice if it aliases a stack that the callback can mutate.

### Macro closures

The current implementation has precise semantics:

- `compiler/meta.rs::find_macro_closure` identifies captured names.
- `Enclose` creates a closure shared by macros declared in the same frame.
- Subsequent stores in that frame update the closure.
- Macro argument defaults execute in the macro’s instruction body.
- `caller` is special and is only accepted when the macro references it.
- Closures can escape a macro invocation through namespaces or state storage.

GC lets you use direct closure objects instead of indices, but **do not capture the entire live frame** and do not copy captured values into an immutable environment.

Retain the render identity check in [Macro::call](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/macro_object.rs). Owning the instructions under GC does not mean an escaped macro should become callable in an unrelated render state.

The strongest tests here are in `tests/test_macros.rs`, especially:

- `test_nested_macro_can_escape_invocation`
- `test_nested_macro_can_escape_into_state`
- `test_escaped_macro_survives_failed_invocation`
- `test_macro_reuses_mutable_state`

### Loops

Replace mutexes and atomics in [vm/loop_object.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/vm/loop_object.rs) with ordinary mutable fields for synchronous execution.

Preserve:

- Shared loop identity when assigned to an alias.
- Optional length.
- Lazy `nextitem` lookahead.
- `previtem`.
- Recursive depth.
- A single previous-argument tuple for `loop.changed`.

`loop.changed` compares against the previous **call**, not the previous iteration or a cache per argument name.

Do not eagerly materialize all iterators. In this checkout, unknown-length loops have undefined length/reverse indices, and `last` returns false when length is unknown. `nextitem` advances the underlying iterator only when requested.

Recursive loops are VM control flow: `recurse_loop!`, `PushLoop`, and `PopLoopFrame` carry return PCs and capture flags. Ordinary `Object.call` on a loop intentionally errors. Preserve the special named-call path, including loop aliases.

### Includes, inheritance, imports

Follow `vm/mod.rs::{perform_include,load_blocks,perform_super,call_block}`:

- `extends` loads parent blocks, discards subsequent child output, continues executing child declarations, and runs the parent afterward.
- Blocks do not have macro-style closures.
- Includes temporarily detach the closure receiving local writes.
- Includes install their own block table and initial autoescape, then restore the caller’s state.
- `super()` advances the current block’s implementation stack.
- Imports execute through capture plus a scope and export locals into a module object.
- Module rendering returns captured output; it is not ordinary map rendering.

Preserve parser and runtime recursion limits. The source uses parser limit `150`, VM limit `500`, include cost `10`, and macro cost `4`. Start with guarded nested calls; consider a VM continuation stack if backend stack limits require it.

## 4. Errors and debug information

Model error information separately from the checked-error wrapper:

```text
TemplateError = EngineError(ErrorInfo)

ErrorInfo:
  kind: ErrorKind
  detail: String?
  name: String?
  line: Int?
  span: Span?
  source: ErrorCause?
  debug_info: DebugInfo?

ErrorCause:
  Template(ErrorInfo)
  Host(HostErrorInfo)
```

Use an immutable `ErrorInfo`; attaching location or a cause returns a new value. This avoids accidentally changing errors shared through `Invalid`.

Mirror the relevant `ErrorKind` variants and their exact human-readable descriptions from [error.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/error.rs). Keep causes structured; do not flatten an include failure into one concatenated message.

Implement explicit renderers:

```text
display_error()
display_error_with_debug()
debug_error(pretty)
display_error_chain()
```

Derived MoonBit `Debug` will not match the Rust snapshots.

Key source behaviors:

- `vm/mod.rs::process_err` adds location only when missing.
- Debug information is attached only when enabled and absent.
- Includes wrap causes as `BadInclude`.
- `super()` wraps causes as `EvalBlock`.
- `Error::range()` returns UTF-8 byte offsets.
- Pretty Rust debug output omits the extra source panel; alternate display includes it.

Port [debug.rs::render_debug_info](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/debug.rs) as a compatibility renderer:

- 79-character separators.
- Up to three preceding and following lines.
- Scalar-column caret placement for single-line spans.
- Sorted referenced-variable names.
- Exact empty-variable wording.

Keep source and instruction location tables even when expensive debug snapshots are disabled. `Instructions::get_line`, `get_span`, and `get_referenced_names` provide the necessary structure.

## 5. UTF-16 and formatting

### Source coordinates: preserve Rust’s units

A crucial distinction in [Tokenizer::advance](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/compiler/lexer.rs:386):

| Coordinate | Rust behavior to preserve |
|---|---|
| Offset | UTF-8 bytes |
| Line | Starts at 1; incremented by LF |
| Column | Unicode scalars, starting at 0 |
| Line/column overflow | Saturates at `u16::MAX` |

I recommend a byte-oriented compiler source abstraction:

```text
Source:
  original UTF-16 String
  cached UTF-8 Bytes
  line-start offsets
  optional byte↔UTF-16 boundary index
```

Lex primarily over UTF-8 bytes, preserving Rust delimiter searches and offsets. Decode scalars when advancing line/column information. Decode token slices or map their boundaries back into the original string.

This is simpler to audit than translating every Rust byte operation into UTF-16 indexing.

Expose helpers such as `source_slice(span)` and `range_utf16()` rather than encouraging users to apply byte offsets directly to MoonBit strings.

Normal token spans end on scalar boundaries. Synthetic error spans can extend past EOF or cover only part of a multibyte character; diagnostic excerpt helpers must handle those safely.

### Template strings: scalar operations

Implement a small shared set of scalar helpers:

```text
scalar_length
scalar_at
scalar_slice
scalar_reverse
scalar_boundaries
utf8_length
```

For `"A😀B"`:

```text
Unicode scalars: 3
UTF-16 units:   4
UTF-8 bytes:    6
```

`length`, indexing, slicing, reverse, string iteration, `first`, and `last` must follow scalar behavior. Combining marks remain separate scalars; do not introduce grapheme-cluster semantics.

Other pitfalls:

- Rust string ordering follows UTF-8/scalar order. UTF-16 lexicographic order differs for some BMP versus supplementary characters.
- Case conversion can expand one scalar into several.
- Rust whitespace predicates differ from ASCII whitespace and JavaScript trimming.
- The `unicode` feature controls identifier recognition and some comparison behavior; Unicode upper/lower conversion is not limited to that feature.
- `sort`/`groupby` and `unique` do not use identical case-normalization implementations.
- Empty-separator splitting and replacement need scalar-aware behavior.
- String indexing and slicing in `value/ops.rs` return ordinary strings; do not universally propagate safety.

Define a policy for malformed UTF-16 entering through host APIs. Rejecting malformed template/source strings is closest to Rust’s valid-UTF-8 input domain. Preserve separate lossy decoding behavior for `Bytes`.

Port `utils.rs::Unescaper`: it combines `\u` surrogate pairs, rejects malformed pairs, handles hex/octal escapes, and preserves unknown escapes. A JSON string decoder is not equivalent.

### Printf has mixed units

[formatting.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/src/formatting.rs) deserves its own port:

- Format-error offsets count UTF-8 bytes.
- String precision truncates by scalar count.
- `%c` accepts a single scalar or valid scalar integer.
- Ordinary padding uses `text.len()`, hence **UTF-8 byte count**.
- Character padding explicitly uses width one.

Consequently, `%5s` applied to `"é"` gets three spaces, while `%5c` gets four. That is the current implementation’s behavior, even if scalar-width padding would seem more natural.

Also preserve safe-format behavior in `filters.rs::format`: unsafe substitutions are escaped **before** width/precision, typed numbers remain numbers, and `%c` is rejected for safe format strings.

The builtin `format` filter uses printf syntax. Calling a string’s `.format()` belongs to contrib’s Python-compatibility integration.

### Float formatting: three separate paths

Implement:

1. **Value display** for `{{ value }}` and string coercion.
2. **Value debug/repr** for lists, maps, `pprint`, and diagnostics.
3. **Explicit numeric formatting** for `%f`, `%e`, `%g`, and rounding.

In `Value::Display`:

- `50.0` renders `50.0`.
- Finite values use Rust `f64::to_string()`, then append `.0` if no decimal point exists.
- `1e100` therefore renders an expanded decimal integer followed by `.0`.
- Negative zero renders `-0.0`.
- Special values render `NaN`, `inf`, and `-inf`.

Containers use the debug representation of contained floats, which can use exponent notation.

MoonBit’s installed formatter explicitly follows ECMAScript formatting policy and converts negative zero to `"0"`; see [double_ryu_nonjs.mbt](/Users/hongbozhang/.moon/lib/core/builtin/double_ryu_nonjs.mbt:668). Simply appending `.0` to `Double::to_string()` is insufficient.

A practical implementation plan:

- Reuse or adapt a pure shortest-decimal conversion algorithm.
- Apply Rust-compatible decimal/exponent presentation separately.
- Inspect the sign bit for negative zero.
- Implement fixed/scientific precision using exact binary-value rounding, potentially with `BigInt`.
- Differential-test both digit selection and presentation against the pinned Rust toolchain.

Expanding MoonBit’s exponent notation is a useful prototype, but does not by itself prove exact compatibility.

`filters.rs::round` needs particular care: the source uses decimal formatting with half-even rounding, including a separate exact-decimal path for negative precision. Multiplying by `10^p` and calling a generic round operation changes results such as `2.675`. Rust’s formatting documentation specifies half-even rounding. [Rust formatting reference](https://doc.rust-lang.org/std/fmt/)

## 6. Reusing the snapshot corpus

The supplied corpus contains:

| Suite | Cases |
|---|---:|
| Rendering inputs | 160 |
| Lexer inputs | 22 |
| Parser inputs | 40 |
| Block-fragment inputs | 6 |
| Compiler snapshot files | 4 |

The rendering suite includes `.html` files as well as `.txt`; filenames affect autoescape.

### Reproduce the Rust harness

Use [tests/test_templates.rs](/Users/hongbozhang/git/minijinja.mbt/.repos/minijinja/minijinja/tests/test_templates.rs:66) as the specification:

1. Split an input once at `"\n---\n"`.
2. Decode the first part as context JSON.
3. Read `$settings` from that context.
4. Create a fresh environment.
5. Register `get_args`, accepting the equivalent of `Rest<ValueOrKwargs>`.
6. Apply whitespace, syntax, and undefined settings.
7. Register `.txt` and `.html` templates from `inputs/refs`.
8. Register the main template under its basename.
9. Add a fresh one-shot iterator yielding `0, 1, 2`.
10. Render and reproduce the harness’s success/error formatting.

Do not remove `$settings` from the context: the Rust harness retains it.

Syntax failures use `!!!SYNTAX ERROR!!!`; render failures use `!!!ERROR!!!` and include the source chain. Successful output has a newline appended before snapshot comparison.

Block-fragment tests have their own reference directory and render `fragment` through the retained captured state.

### Preserve JSON numeric types

This is a major harness risk.

`inputs/context_number_types.txt` explicitly distinguishes:

```json
{"integer": 4, "float": 4.0, "exponent": 4e0}
```

The last two must produce floats.

The installed MoonBit JSON representation has `Number(Double, repr?)`, but its parser retains the source representation only in selected cases. It does not preserve ordinary integer-versus-float spelling reliably. See [lex_number.mbt](/Users/hongbozhang/.moon/lib/core/json/lex_number.mbt:211).

Choose either:

- A small number-preserving fixture JSON decoder that constructs `Value` directly.
- A fixture generator that retains numeric lexemes and emits typed MoonBit values.

Match serde_json’s numeric range decisions as well; JSON fixture decoding and template-literal parsing are separate contracts.

### Parse `.snap` files without interpreting the body

A text `.snap` file contains YAML front matter between two lines exactly equal to `---`, followed by the expected body.

For these files, you can skip the front matter without a general YAML parser. Preserve the body verbatim during extraction.

Do not use front-matter `description` or `info` as fixture input. They are presentation metadata and can lose information.

Match insta `1.43.1`, pinned in the checkout’s lockfile. Its file-snapshot normalization:

1. Removes leading CR/LF characters.
2. Removes trailing whitespace.
3. Replaces CRLF with LF.

Apply it equally to expected and actual bodies. This behavior comes from insta’s `TextSnapshotContents::normalize`. [Pinned insta implementation](https://github.com/mitsuhiko/insta/blob/1.43.1/insta/src/snapshot.rs)

**Add exact-output tests separately.** Normalized snapshots cannot fully verify trailing newlines or whitespace-control behavior.

### Portable execution

Use an IO-capable corpus runner for development, and generate embedded fixtures for backend CI:

```text
filesystem corpus → generator → portable fixtures → engine tests
```

Then run the portable tests on all targets:

```sh
moon test --target native
moon test --target js
moon test --target wasm-gc
```

Keep lexer/parser tests as white-box tests so you need not expose compiler internals publicly.

For parser and lexer snapshots, write dedicated Rust-compatible printers. Preserve distinctions such as `Token::Str` versus `Token::String` if you want exact lexer snapshots. MoonBit-derived debug output will differ.

Before trusting the baseline, run the Rust suites with a recorded feature set and `INSTA_UPDATE=no`. Include `unstable_machinery` for compiler tests and `deserialization` for the gated template suite. Keep `preserve_order` and `unicode` as explicit compatibility choices rather than enabling everything indiscriminately.

## 7. Milestones and risks

| Milestone | Deliverable and exit test | Main risk |
|---|---|---|
| 0. Freeze baseline | Revision, feature manifest, corpus reader, Rust baseline results | Comparing different feature configurations |
| 1. Semantic primitives | Values, bounded integers, comparison, Unicode helpers, errors, basic float display | Foundational mismatches spreading everywhere |
| 2. Lexer | All 22 lexer cases; exact whitespace tests | Raw blocks, custom delimiters, scalar columns |
| 3. Parser and AST | All 40 parser cases; stable compatibility printer | Precedence, spans, assignment validation |
| 4. Instructions and basic VM | Compiler tests and expression/if/set rendering | Stack effects, short-circuiting, constant folding |
| 5. Calls and builtins | Argument conversion, kwargs, filters, tests, printf | Coercion and safety provenance |
| 6. Loops and captures | Loop corpus, namespaces, recursive loops, one-shot tests | Iterator consumption and scope cleanup |
| 7. Multiple templates and macros | Includes, inheritance, imports, caller, escaped closures | Reentrant state restoration |
| 8. Backend parity | Full corpus plus targeted regression tests on three backends | Formatting, integer conversions, stack limits |

Start numeric formatting work early, even if complete printf support lands later.

Port these non-snapshot tests early:

- `test_value.rs`: equality, ordering, byte conversion, objects, floats.
- `test_undefined.rs`: all four undefined policies.
- `test_regressions.rs`: operand-preserving logical operators, division by zero, bankers rounding.
- `test_filters.rs`: safe-string transformations and composition.
- `test_format_filter.rs`: numeric formats, Unicode characters, large precision.
- `test_state.rs`: restoration after errors.
- `test_macros.rs`: escaping closures and shared mutable state.
- `test_tuples.rs` and `test_set_unpacking.rs`.

Additional details worth making explicit in the port checklist:

- **Undefined policy and undefined value are separate.** `Silent` comes from omitted conditional-expression alternatives and bypasses several strict checks. `SemiStrict` permits truth tests but rejects printing and iteration.
- **Logical operators return operands.** Both codegen and constant folding must preserve this.
- **Power precedence follows this parser.** `parse_pow` uses the left-associative binary-operator helper; do not substitute Python’s grammar.
- **Chained comparisons evaluate intermediate operands once.** Preserve `CompareAndPreserve` behavior.
- **Sorting must be stable.** Reverse the comparator, not the completed ascending result, which reverses equal-key groups.
- **Filtered loops are materialized before the visible loop.** `compile_for_loop` uses a hidden filtering loop, affecting length and side-effect timing.
- **Only namespaces allow attribute assignment.** A mutable ordinary map is not sufficient.
- **Safety is operation-specific.** Some string transformations preserve it; composition may escape components; concatenation and slicing can discard it.
- **HTML escaping includes `/`**, rendered as `&#x2f;`, as well as the more familiar five characters.
- **Raw blocks are lexer behavior.** Preserve interaction with custom markers, `+`/`-` controls, trimming, and missing `endraw`.
- **Line statements depend on indentation and bracket balance.** They also close at EOF.
- **Lazy concatenation needs bounded structural depth.** `MergeSeq` flattens its own structure to avoid deep iterator nesting without consuming unsized streams.
- **Host-size arithmetic needs a defined policy.** Rust `usize/isize` must not accidentally become MoonBit’s narrower `Int` everywhere; use checked conversions for indices, ranges, and allocation sizes.
- **Do not reproduce Rust panics as engine semantics.** Record problematic upstream edge cases separately, while retaining ordinary observable behavior.

The first useful end-to-end target is expressions, `if`, `set`, scalar-safe strings, default undefined behavior, and correctly formatted errors. Build that through the real bytecode VM so later macros and inheritance extend the same execution model.