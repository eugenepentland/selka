# One canonical operation, one efficient implementation — 2026-09-21

The useful design target is **one canonical spelling per semantic operation,
with efficient lowering by default**. Mylang already has one main grammar. Its
larger remaining problem is that choosing a familiar spelling sometimes chooses
a worse algorithm, extra allocations, or different behavior.

There cannot be a universally fastest spelling independent of input size,
ownership, lifetime and required behavior. A copy and an alias are different
operations; changing one into the other to save time changes the program. The
enforceable target is good asymptotic behavior, no unnecessary intermediate
objects, shared implementation of equivalent operations, and explicit semantic
differences. The compiler should choose small-input and large-input fast paths.

This is an audit and implementation proposal, not a language change. It inspected
the dirty working tree and exercised the existing compiler without rebuilding it.
No existing implementation files were modified. No Guardian gate was invoked.

## Evidence and limits

[The reproducible probes](../../experiments/syntax-canonicalization-20260921/probe.py)
capture 22 check cases, 17 emitted-IR cases, and one native behavioral program.
[The evidence](../../experiments/syntax-canonicalization-20260921/evidence.json)
records commands, diagnostics, source hashes and compiler identity. Five check
rejections are intentional evidence, not failed audit infrastructure.

The compiler SHA-256 before and after the run was
`2dc07d5f71e5bd9d0c8b780536895113b8c04f11724a919a2de277ec1605157d`.
The audit does not claim that this executable incorporates every uncommitted
source edit. Source findings and executable probes are identified separately.
Emitted QBE is evidence of lowering, not final optimized machine code. No new
wall-time speedups were measured, and none are predicted numerically here.

Several older recommendations have already landed: immutable `bytes`, distinct
`byte_buffer`, byte views, direct numeric range parsing, direct buffer float
formatting, chunked managed arenas, and aggregate parameter addressing. These
are starting points, not missing features to implement again.

## Ranked changes

| Priority | Current problem | Canonical direction | Expected benefit |
| --- | --- | --- | --- |
| 1 | `xs.sort()`, `sorted(xs)` and `sort.sort_*` select different implementations | One sorting engine; explicit mutation versus fresh result | Remove quadratic large-input behavior and redundant sorting implementations |
| 2 | `float(text)` and `strings.to_float(text)` parse differently | One numeric grammar and parser; prelude conversions are the taught spelling | Remove semantic drift and the guest parser's repeated work |
| 3 | Parsing a sliced/viewed byte range requires allocation; `*_range` avoids it | Fuse the ordinary range-consuming expression into the existing range operation | Users stop needing a special fast spelling |
| 4 | An f-string becomes a chain of concatenations | Preserve a formatting operation through lowering; construct the result once | Avoid repeatedly copying growing prefixes |
| 5 | Text comparison inside folds/sorts encodes both operands | One direct scalar comparator shared by ordering operations | Remove repeated temporary byte strings |
| 6 | Unfiltered comprehensions start with zero capacity | Reserve known final size and fill once | Avoid growth and backing-storage copies |
| 7 | `d.items()` changes meaning with surrounding syntax; `values()` allocates a snapshot | Define consistent typed iteration and explicit snapshot creation | Remove context-sensitive meaning and make streaming iteration ordinary |

Priorities 1–6 can mostly be delivered through implementation and library work.
Priority 7 needs a language design decision because the existing meanings differ.

## 1. Make sorting one implementation choice

The current [native `list.sort`](../../src/native_collections.c) implementation
at `myl_native_list_sort` (line 266 at audit time) is insertion sort: it shifts
each earlier element until the current element fits. That is quadratic on
reverse-ordered input. The `sort_in_place` probe confirms `xs.sort()` calls it.

[`sorted`](../../src/prelude_builtins.zig), line 474, generates bottom-up merge
sort. It allocates a fresh target buffer on each merge pass. The
[`sort` library](../../src/stdlib/sort.my) separately implements recursive merge
sorts with slicing for integers, floats, strings and keyed records.

Keep the distinction between these operations:

```text
xs.sort()           # Mutates the existing shared list.
ys = sorted(xs)     # Returns independent list storage.
```

These are not synonyms: aliases must see the first operation's writes and must
not see the second operation mutate its input. They should nevertheless share
one scalable sorting core, with insertion sort confined to small runs and a
bounded number of reusable work buffers. Specialize that core for concrete
element types. Consolidate redundant `sort.sort_ints`, `sort.sort_floats` and
`sort.sort_strs` APIs only after checking their edge-case contracts.

Specify stability, NaNs, signed zero, key evaluation, allocation failure and
mutation behavior before sharing the engine. The keyed implementation currently
invokes the key callback during comparisons; a once-per-element key cache is a
useful proposed contract, but changes callback/trap/accounting behavior and needs
explicit qualification. Keep binary search and comparison helpers where their
result contracts add something the sorting operations do not provide.

Acceptance: sorted, reversed, random and duplicate-heavy inputs over increasing
sizes; alias preservation; stable equal keys; float edge cases; callback call
counts under the chosen contract. Measure comparison counts and allocated bytes
as well as runtime. Users should not switch to a copying API just to avoid a
quadratic mutating implementation.

## 2. Remove parallel numeric parsers

[`strings.to_int`](../../src/stdlib/strings.my), line 179, already delegates to
`int(text)`. `strings.to_float`, line 202, still scans digits in guest code,
constructs/accesses digit tables, accumulates a mantissa and scales via
`math.pow`. It does not use the prelude's pinned number grammar.

Fresh native output demonstrates the behavioral difference:

| Input | `float(text)` | `strings.to_float(text)` |
| --- | --- | --- |
| `" 1.5 "` | `Some(1.5)` | `None` |
| `"1_000.5"` | `Some(1000.5)` | `None` |
| `"inf"` | `Some(inf)` | `None` |

The prelude parser passes a `noalloc` probe. The library integer wrapper also
passes, so its redundant spelling is not evidence of an allocation penalty.

Teach `int(text)` and `float(text)`. First make the floating wrapper delegate to
the same parser, with a documented behavior change for previously rejected
inputs. Then deprecate redundant wrappers if strict surface reduction is the
goal. Do not silently auto-rewrite callers that intentionally relied on the old
grammar's validation restrictions; give that restriction an explicit validator
if it is needed.

Audit the rest of `strings` the same way. `starts_with`, `ends_with`, `strip`,
`upper`, `lower`, `is_digit`, `is_alpha` and `is_space` delegate to methods and
are candidates for mechanical migration to methods. Other apparent synonyms
have different contracts: `strings.find` returns an `Option`, the method returns
`-1`; `strings.ord`/`chr` return a checked error while prelude versions trap;
`strings.count` handles an empty needle before invoking the method. Those need a
semantic decision, not a blind rename.

Acceptance: one grammar corpus through every supported parser entry point,
including overflow, separators, whitespace, infinities, NaNs, malformed input
and exact floating results. Retain explicit error behavior where it is useful.

## 3. Hide range fast paths behind normal expressions

All three forms currently exist and return the same numeric result for a fixed
immutable byte string and the same bounds:

```text
raw[start:end].parse_int()            # Copies the bytes, then parses.
raw.view(start, end).parse_int()      # Allocates a view header, then parses.
raw.parse_int_range(start, end)       # Parses the range directly.
```

The first two fail `noalloc`; the third passes. Emitted IR calls
`myl_native_bytes_slice`, `myl_native_bytes_view`, or `myl_native_bytes_range`,
respectively, followed by the number parser. The allocation distinction is
confirmed in [the runtime](../../src/native_bytes.c), not inferred from naming.

Make `raw[start:end].parse_int()` and equivalent immediate view consumption
normalize to a typed range operation when the intermediate does not escape.
Apply the same rule to floating parsing and, where their contracts agree,
comparison, searching, scalar counting and appending into a buffer. Evaluate
receiver and bounds exactly once in source order. Reuse existing runtime range
operations rather than adding another public family of `fast_*` methods.

If the canonical expression is intended to pass `noalloc`, normalization must
feed the effect checker. A backend-only optimization leaves the source-level
rejection in place. Make this a deterministic supported lowering rule, with
precise allocation/effect semantics, rather than a promise depending on optional
release optimization. Scalar counting's invalid-UTF-8 error path requires its
own allocation audit; numeric parsing's result does not prove it allocation-free.

Keep explicit `.view()` and `.copy()` for retained values. A view can retain a
whole large document; a small copied slice can allow that document to be freed.
Do not globally change slicing into views in pursuit of speed, and never change
mutable list slices into aliases. Those lifetime and snapshot choices are useful
semantic distinctions.

Acceptance: no slice/view allocator call for immediate numeric consumption;
clamped, negative, empty and reversed bounds; overflow and malformed numbers;
side-effectful bound expressions; retained view lifetime; GC stress and nested
arena ownership. Decide how allocation elision interacts with resource limits
and effect guarantees instead of silently weakening them.

## 4. Make f-strings the efficient formatting path

[`checkFormat`](../../src/sema.zig), line 2054, immediately turns pieces into
left-associated string additions. The probe

```text
f"x={x}; y={y}!"
```

emits **four `myl_native_text_concat` call sites**, in addition to scalar
rendering. Each runtime concatenation creates new storage and copies both
operands. More pieces therefore repeatedly copy the accumulated prefix.

Keep an explicit formatting node in typed IR. Evaluate holes and render them
once, compute the required size, allocate the destination once, and fill it in
order. Use the same renderer as `print` and `str`, as the current language
already promises. Apply equivalent concatenation-chain fusion where it preserves
evaluation behavior; a programmer should not have to rewrite a naturally composed
string merely to get the same construction algorithm.

Next consider direct formatting into an existing byte buffer or stream. The
buffer primitives for text, integers and floats already exist. A compiler can
target them without teaching application authors a separate sequence of
`append_text`/`append_int` calls for every interpolation. Preserve when externally
visible output begins: a later failing hole must not cause output that previously
would never have been written. Stream fusion is a separate step from constructing
one string efficiently.

Acceptance: exact existing output, Unicode, floats and aggregate rendering;
once-only left-to-right evaluation; failures before output; allocation counts
and bytes copied versus number and size of pieces. Do not claim that ordinary
loop-carried `text += piece` is already optimized by fixing one f-string.

## 5. Compare text directly in folds and sorts

The text comparator in [`prelude_builtins.textLess`](../../src/prelude_builtins.zig),
line 656, encodes each string to bytes before comparing. The current text runtime
stores scalar values in `u32` backing storage
([`native_text.c`](../../src/native_text.c)); it already has the data needed to
compare Unicode scalar order directly.

`min(list[str])` fails `noalloc`, while `min(list[int])` passes. Both the text
minimum and text sorting probes emit `myl_native_bytes_encode` calls. The
library's `sort.compare_strs` also encodes its inputs.

Introduce one nonallocating scalar comparator and use it in text `min`/`max`,
sorting and the explicit comparison API. This removes a cost from ordinary
operations without another user-facing spelling. Do not use bytewise comparison
of native-endian `u32` storage: compare scalar values, and preserve prefix rules.

Acceptance: Unicode scalar ordering, empty strings, shared prefixes, equality,
zero temporary encodings, and `noalloc` acceptance for a text minimum. This
finding concerns the inspected fold/sort paths, not a claim that every string
operation has this implementation.

## 6. Give comprehensions their known capacity

Both [`checkRangeComprehension` and `comprehensionLoop`](../../src/sema.zig)
(lines 1986 and 2009) initialize the result with capacity zero, including when
there is no filter. They then append each value. `list(range(...))` has the same
zero-capacity starting point in `rangeListCall`.

For an unfiltered collection comprehension, the final length is the initial
iteration bound if execution completes successfully. For a numeric range it is
the nonnegative range length. Reserve that amount with overflow checking, then
use a bounds-proven fill path. Keep mutation detection and evaluation order.

Do not automatically reserve the full source size for every filtered
comprehension: a huge input with one retained value would waste memory. Choose a
bounded growth policy there. Also qualify eager reservation against the
language's allocation-failure/resource-limit behavior.

The canonical list-building expression can remain the comprehension. Keep
ordinary loops for early exits, multiple results and side effects; banning loops
would not improve the generated code.

Acceptance: one backing allocation for known-size successful output, empty and
reversed ranges, narrow integer bounds, overflow, throwing/trapping element
expressions, and mutation through aliases. Compare backing bytes moved, not just
the number of source lines.

## 7. Make collection iteration compositional

This is a meaning problem as well as a performance problem:

```text
d = {"a": 10, "b": 20}
d.items()                         # The probe prints [10, 20].
for key, value in d.items():       # Binds "a", 10 and then "b", 20.
    ...
```

[`statementForEach`](../../src/sema.zig), line 4592, recognizes the AST shape
`d.items()` and bypasses the ordinary method result. The direct two-binding
loop passes `noalloc`. `for value in d.values()` fails it because `values()`
materializes a snapshot list. Merely moving an expression to a binding therefore
does not preserve the conceptual iterable behavior one would expect.

Define `items()` as pairs everywhere, with an explicit pair representation.
Decide whether `keys`/`values`/`items` produce live typed iteration views, then
use explicit list materialization for a snapshot. Under that proposed design,
binding an iterator and passing it to a helper preserves its meaning, and loops
lower through one typed iteration protocol rather than method-name AST tests.
The current `list(...)` implementation would need extension for such views.

This is a versioned semantic migration. Existing snapshots can observe different
values from live iteration after mutation; the compiler cannot generally elide
them across arbitrary loop bodies. Preserve snapshots explicitly when migrating
those programs. Specify size-change detection, value replacement visibility and
iteration order before broadening the optimization.

Acceptance: inline and bound iterable forms agree, items always supply key/value
pairs, snapshots remain independent, live iteration performs no snapshot
allocation, and aliased mutation has one documented behavior.

## Surface cleanup that should follow, not substitute for, this work

- The removal machinery already rejects `.push`, `.len`, `List`, raw `f64_*`
  names and old capability spellings. The `f64_sqrt` probe confirms rejection.
  Do not count these as current parallel syntax. Some current-looking prose,
  notably `docs/floating-point.md`, still describes removed `f64_*` calls as
  available; reconcile it with the compiler-derived reference.
- `byte_builder.Builder` is a managed wrapper around `byte_buffer`, and its
  forwarding functions expose a second building API. Make one public builder
  interface sufficiently ergonomic, then retire redundant forwarding vocabulary.
  Keep the distinction between appending an octet, appending numeric text and
  taking an immutable snapshot. All three mean different things.
- Use formatting and canonical examples for harmless textual choices such as
  quote style and omitted `-> None`. Positional versus keyword arguments and
  inferred versus explicit generic arguments already have useful contexts;
  removing them does not establish a runtime gain.
- Retain `record` versus `class`: value snapshots versus shared identity. The
  simple record projection probe already emits zero `blit` operations. Continue
  copy elimination through construction, returns and matching while preserving
  snapshots; do not make users switch to a heap class or annotate every borrow
  to compensate for compiler copies.
- Retain text versus bytes, mutable versus immutable storage, fixed-width versus
  default integers, checked versus wrapping arithmetic, error handling versus
  propagation, and GC versus scoped arenas. These expose semantic or lifetime
  requirements. No one choice is fastest for every program.

## Delivery and success criteria

First consolidate sorting and numeric parsing, and add the direct text comparator.
These remove either an algorithmic trap or parallel definitions of the same
operation. Next preserve formatting/range intent in typed IR and preallocate
known-size comprehensions. Then decide and migrate the iteration model. Remove
old public spellings only after the canonical forms have the required behavior
and performance.

For each operation, maintain one table of source form, semantic contract, typed
IR operation, effects and runtime implementation. Reuse it in reference output,
diagnostics and migration tooling where practical. Backend helpers may be many;
users should not have to select among them to avoid incidental overhead.

Qualify changes with semantic tests and representative allocation/complexity
measurements, then inspect optimized QBE and LLVM output where relevant. Include
GC stress, alias mutation, malformed inputs and the configured execution budgets.
`noalloc` checks managed allocation; it is not proof of fastest execution, no
stack copies, or no C allocator calls. In particular, the current in-place sort
calls C `malloc` for its temporary key.

The practical acceptance question is: **can a user choose the operation for its
meaning, without also having to know which spelling selects the good algorithm?**
