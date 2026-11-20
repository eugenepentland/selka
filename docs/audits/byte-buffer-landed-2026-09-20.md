# Mutable octet buffer beside immutable byte strings — 2026-09-20

These are the first three implementation slices of the recommendations in
[language-performance-ergonomics-2026-09-20](language-performance-ergonomics-2026-09-20.md).
Slice 1 lands the immutable-bytes/mutable-buffer distinction the audit asked to
build views on; slice 2 lands the byte views and the nonallocating byte reads that
follow from it; slice 3 lands direct float formatting into the buffer. The
remaining output path — `write_to(Stream)` without the final snapshot copy — is
the next slice.

## What landed

**`byte_buffer` is its own prelude type.** `src/nominal_templates.zig` declares
the builtin beside `bytes`, with the same one-octet element and the same managed
list representation, and `src/nominal_catalog.zig` gives it the byte collection
kind. Length, indexing, iteration, concatenation-free reads, search, `decode`,
`hex`, `split`/`join` and every conversion therefore read a buffer exactly as they
read a byte string; no new managed representation, descriptor, GC path or
lowering exists for it.

**Only `byte_buffer` declares the in-place methods.** `src/buffer_operations.zig`
carries a new `buffer` receiver flag for `append_byte`, `append_range`,
`append_utf8`, `append_int` and `reserve`, and `src/sema.zig` accepts them only on
the mutable type — a `bytes` literal, slice or future view is rejected with
`E_COLLECTION_METHOD` naming the receiver to use. The old design let both kinds of
the same type mutate and answered `False` at run time for a frozen literal; that
runtime-dependent mutability is gone, and the C runtime's frozen-receiver refusal
is now unreachable defence rather than documented behaviour.

**`byte_buffer(values)` builds one** from a `list[int]` with the same
`R_BYTE_RANGE` trap as `bytes(values)`, and **`bytes(buffer)` copies** the
buffer's current octets into a fresh immutable byte string, so a later append
through the buffer or any alias cannot change an earlier snapshot.

**The two byte kinds interoperate where content is what matters.** Equality
(`==`/`!=`) and membership compare a byte string with an octet buffer directly, in
either operand order, and `append_range` accepts an immutable byte string as its
source; `src/sema.zig` relaxes exactly those three rules and no others. Every
other operator still requires one nominal type on both sides, so the distinction
stays visible.

**`byte_buffer` is materialized on its first mention.** The declaration sits with
the other prelude types so any module may name it without an import, but the
runtime schema is built by `nominal_catalog.materializePrelude` only when a
signature, field or conversion actually names the type. A program that never
mentions it keeps the minimal unconditional type table (`str`, `bytes`, `float`),
which is what `nominal_type_syntax_test` and the `dump-types` golden pin.

**The standard library uses it.** `src/stdlib/byte_builder.my` now holds a
`byte_buffer` and `finish` is `bytes(builder.buffer)`: the builder API, its
effects on the append paths and every published name are unchanged, while
`finish` contributes `managed_allocation` and no longer claims a mutation.

**A capacity-sufficient append pushes no roots.** `buffer_grow_rooted` in
`src/native_bytes.c` tests the reserved capacity before it builds its two root
records, so an append that already fits is one test and a store instead of two
root pushes and pops per call; a growth that must allocate keeps the roots
exactly as before.

## Decisions worth recording

- **A distinct nominal type, not a flag.** Sharing the byte representation keeps
  the change small, but the type is what carries the semantics: a reader of a
  signature can see whether the callee may rewrite the octets, and the checker
  never has to ask what an object's header says about mutability. Reusing the
  `bytes` name with a mutable mode was rejected: it is the ambiguity the audit
  identified.
- **`bytes(buffer)` copies.** Zero-copy would need to consume the buffer or prove
  a unique owner, and a freed-alias append would then be able to rewrite the
  "immutable" result. Snapshot cost is one copy, the same as `finish` had before.
- **No prelude bloat.** Eagerly materializing the type changed the type table of
  every program (and two goldens); first-mention materialization keeps the
  unconditional table at three types while still letting a module write
  `def f(x: byte_buffer)` without an import.
- **Generic bodies keep their existing bounds.** A generic function body may
  carry, read and compare a `byte_buffer` but not call its append methods, which
  matches the current generic-body operation set; extending that set is separate
  work.

## Verification

- `zig build test-units -Dtest-filter=byte`: 97 passed, including the runtime
  conversion traps, the rejection cases, GC-stress growth, and the standard
  builder fixture (run and stress).
- `zig-out/bin/mylang test tests/lang/byte_buffer.my`: 6 guest tests covering the
  append/refusal vocabulary, alias observation, snapshot independence, growth
  past several doublings, byte-kind equality/membership, record and list storage,
  and `byte_buffer(values)`.
- `zig build test-docs`: every documentation example passes, including the
  rewritten "Writing octets in place" section in `docs/bytes.md` and the
  `byte_builder` section in `docs/standard-library.md`.
- `mylang doc-coverage .`: 0 failures, with the new `mutable-byte-buffer` feature
  slug pointing at that section.
- `zig build test --summary all`: 60/60 steps succeeded (root, CLI, guest, docs,
  doc-coverage, Guardian spec coverage).

## What remains, in priority order

Written before the work below; the round-12 sections at the end record what has
since landed and what is still open.

1. **Byte views.** `bytes.view(start, end)` as an owner-retaining range,
   `bytes.copy()` for an explicit owned copy, `bytes.scalar_count()` for a
   validating UTF-8 scalar count, and direct `parse_int`/`parse_float` on byte
   octets so a numeric leaf never decodes a temporary `str`. The audit's `noalloc`
   acceptance applies to those operations.
2. **Writer fast paths.** `byte_buffer.append_float` with the established float
   spelling and `write_to(Stream)` without the final snapshot copy; the
   capacity-sufficient append fast path is already in.
3. **Aggregate-copy follow-ups** in the parser's recursive and match paths, on
   top of the parameter-address change already in the tree.
4. **Compact AST storage**: narrower source-position fields using existing `u32`
   and a frozen child sequence, after measuring the simpler changes.

## Slice 2: views, owned copies, scalar counting and octet parsing

**`b.view(start, end)` answers a `bytes` that reads the range instead of copying
it.** The view is a managed object whose `storage` points into the source's
backing at the range start and whose `length` is the range length, so every read
path — indexing, iteration, comparison, membership, search, slicing, `decode`,
`scalar_count`, numeric parsing — works on a view unchanged and needed no new
lowering. Endpoints clamp exactly like the slice that would have copied them.

**A view retains its source's storage block, not its source object.**
`myl_native_bytes_view` allocates the view's header with a descriptor whose single
traced field is the source's *storage block*: a block carries its own
`myl_native_object` header immediately before it (so the collector can mark it),
whereas the mid-block content pointer a view holds could not be marked at all.
The block survives the collection of the byte string that first owned it, a view
of a view inherits the same record instead of deriving a header from a mid-block
address, and a frozen literal's block is immortal image data the collector never
queues. The C collector tests cover both the heap and literal cases, and the guest
tests read views after thousands of collections.

**`b.copy()` is the explicit owned copy.** It shares no storage with the
receiver, so a small value that must outlive its document has one spelled
operation; slicing a view copies as well, because a slice is a slice.

**`b.scalar_count()` answers `Result[int, str]` without decoding.** One
validating pass counts scalars: ASCII runs advance a word at a time and every
other scalar is decoded with exactly the decoder's acceptance rules, so a
malformed range reports the decoder's invalid-UTF-8 reason instead of a
replacement character. Measuring a width therefore stops decoding the text the
printer only wanted to measure.

**`b.parse_int()` and `b.parse_float()` read the octets through the pinned
grammar.** `number_text.zig`'s grammar is now generic over its character type, so
`integer`/`floating` read `u32` scalars and `integerBytes`/`floatingBytes` read
`u8` octets with one implementation; every vector of the shared
`number_grammar.txt` table is asserted to answer identically through both entry
points. A numeric leaf of a byte string or a view therefore never decodes a
temporary `str`.

**Parsing and counting contribute no `managed_allocation`.** The shared grammar
and the scalar scan allocate nothing, so `buffer_operations.managedAllocation`
lists neither `parse_int`/`parse_float` nor `scalar_count`, `qbe.zig`'s pure-callee
list names all three runtime entry points (so a function whose only call is a
parse keeps no root protocol), and `noalloc` now accepts `int(text)`,
`float(text)`, `bytes.parse_int()`, `bytes.parse_float()` and
`bytes.scalar_count()`. Constructing a view still contributes `managed_allocation`
because it allocates the view's header, and the tests pin that with
`E_EFFECT_BOUND`.

**Wrong receivers are rejected at check time.** `view` and `copy` require the
immutable byte string, so a `byte_buffer` receiver (`view`, `copy`) and a `str`
receiver (`view`, `copy`, `scalar_count`) are `E_COLLECTION_METHOD`, and the
documentation gate caught one routing regression while this landed: a
dictionary's own `copy` had to keep taking the dictionary path.

## Verification of slice 2

- `tests/native_heap_test.c` (C runtime, `zig build test-native-heap`): a view
  reads its range, a view of a view reads one range further in, slicing and
  searching a view agree with the byte string they came from, clamped endpoints
  behave, and both a heap source and a frozen literal stay readable after the
  collector runs with every allocation collecting. The validating count is
  asserted to accept exactly the sequences `myl_native_text_valid_utf8` accepts,
  with the expected scalar counts.
- `src/number_text_test.zig`: every shared grammar vector answers identically
  through the scalar and UTF-8 entry points.
- `src/python_bytes_test.zig`: wrong-receiver rejections, and `noalloc`
  acceptance for all three read operations plus `E_EFFECT_BOUND` for `view`.
- `tests/lang/byte_views.my`: six guest tests over view reads, clamping, retention
  across collection, nesting and slicing, scalar counting with five malformed
  forms, and the parsing vocabulary including a view of a document.
- `zig build test-docs`: the two new `docs/bytes.md` sections run as examples.
- `src/semantic_cache_test.zig`'s generic-publication allocation-failure test now
  warms the native-build artifacts twice before it varies the failing allocation
  index. Creating an artifact on first use costs a few allocations, so a baseline
  run that paid them while a later run did not looked like nondeterministic memory
  usage; the added tests shifted that test's shard and exposed the latent
  fragility. The scenario itself is unchanged.

## Slice 3: direct float formatting

**`byte_buffer.append_float(value)` appends the canonical spelling.** It is the
same text `str(value)` prints — shortest round-tripping digits, the `.0` of an
integral value, and the `nan`/`inf`/`-inf` names — because it is the same
formatter: `native_format.zig` exposes `myl_native_bytes_buffer_append_float`,
which builds the spelling on its own stack and hands it to a new C entry point,
`myl_native_bytes_buffer_append_raw`, that grows the buffer and copies the octets
straight into its capacity. No temporary `bytes`, `str` or formatted text is
created, and the `str(value)` path and the buffered path cannot drift because
they call one `format`.

**The stdlib builder exposes it** as `byte_builder.append_float(builder, value)`,
so assembly code that mixes text, integers and floats keeps writing each fragment
into the buffer's own capacity. `append_int` now shares the raw-append entry point
as well, which removed its duplicated growth code.

## Verification of slice 3

- `tests/lang/byte_buffer.my`: every value of a mixed list is appended twice into
  a fresh buffer and asserted to equal `str(value).encode()` (and its
  concatenation), plus a seeded `area=2.5mm` buffer and the `inf`/`-inf`
  spellings reached through runtime overflow.
- `src/stdlib/fixtures/byte_builder.my` (run and under GC stress): the same
  spellings through the module, and the non-finite pair.
- `docs/bytes.md` and `docs/standard-library.md` examples exercise
  `append_float`; `doc-coverage` names the new standard-library export.
- `zig build test` (60/60 steps), `test-qbe`, `test-qbe-build`,
  `test-native-heap`, `test-docs`, `fmt-check`, `doc-coverage` and Guardian's
  88 checks are green with all three slices in the tree. One gate run failed a
  guest-build step with an unexpected errno while creating the build cache's
  shared `.pending` staging directory; the code already documents and retries
  that concurrent-remove race, the immediate re-run passed, and no source of this
  change touches that path.

## Current copy-site state (audit item 3, measured 2026-09-20)

The audit's remaining aggregate-copy work is now measurable directly from the
tree, without the frozen compilers it used. `mylang emit-project-qbe
experiments/sexpr-port/main.my` writes every unit's IL, and counting `blit `
instructions gives the current static copy sites in the port the audit profiled:

| Function | Audit "after parameter change" | Now |
|---|---:|---:|
| `sexpr.parser::parse_node` | 49 | 37 |
| `sexpr.parser::parse_leaf` | 23 | 20 |
| `sexpr.printer::estimate_width` | 21 | 10 |
| `sexpr.printer::push_node` | 21 | 10 |

The port's own suite also still passes against this tree: `mylang test
experiments/sexpr-port` reports **114 passed, 0 failed across 8 programs**, the
same count the audit recorded.

One shape is still worth a compiler change, and it is visible in the IL rather
than inferred. `sexpr.ast::span_of` matches a union and returns the payload's
trailing `span` field; it emits **12 blits for six arms** — one full payload copy
into the arm's binding slot (`32` bytes for `form`, `48` for `atom`, `string` and
`integer`, `64` for `decimal`) plus one 24-byte copy of the returned `Span` per
arm. A match arm whose payload binding is only read should project the field from
the matched value's storage instead of copying the whole payload, which is the
audit's "project match fields without copying entire payload records when safe".
That lowering change needs the address-holding local machinery the parameter
change introduced (`by_reference`), a proof that the binding is never written and
that the matched slot's storage outlives the arm, and GC/ownership review; it is
the next compiler slice rather than part of these three.

## Match payload projection (audit item 3, landed after the measurement above)

**Correction, round 12: this section describes a projection that is switched off
in the tree.** `payloadAddresses` (src/qbe.zig) returns an empty slice before it
computes anything — the generated program segfaulted on the two largest corpus
inputs and the projection was disabled while that is unproven — so the copy
counts below were cache-confounded *and* attribute an effect the shipped compiler
does not have. The cache-free A/B in the round-12 section at the end measures
the projection at exactly zero. Read the description here as the design of the
optimization, not as its measured effect.

`QBE-MATCHPROJ-1` removes the payload copy the measurement named. A match arm
whose binding owns nothing now names the payload where it already lives: when the
scrutinee is the local the dispatch loads and no branch reaches the dispatch
directly, the payload address is that local's slot plus the union's payload
offset — a compile-time constant — so it is stored into the binding once at
entry and every arm reads fields, tags and elements through it.

The safety argument is the analysis, not a hope:

- the scrutinee local is never written — a whole-value store, a move, an explicit
  drop or a second binding all decline the projection, and a record binding is
  immutable, so a field write through it is already `E_IMMUTABLE`;
- the binding is written by nothing but its own arm (`writtenOutsideBindings`),
- the payload type owns nothing (`!drop`) and is not zero-sized, so no copy it no
  longer has is needed to release anything — a payload that *contains* managed
  fields is eligible and safe, because root pushing, drop cleanup and the
  by-address call convention already read an address-holding local through its
  address and trace it where it lives;
- a scrutinee that already holds an address (a read-only parameter, or another
  projected binding) is one load deeper and just as constant;
- a callee that mutates its by-value parameter writes its own copy, so a
  `mutates(...)` call through a binding cannot reach the scrutinee — the guest
  test below pins that.

Measured on the port with `emit-project-qbe` and `blit` counts:

| Unit | Before | After |
|---|---:|---:|
| `sexpr.ast::span_of` | 12 | 6 |
| `sexpr.printer::estimate_width` | 10 | 4 |
| `sexpr.printer::push_node` | 10 | 4 |
| `sexpr.ast::value_text` | 13 | 10 |
| `sexpr.ast::children` | 1 | 0 |
| whole project | 209 | 175 |

`span_of` loses exactly its six payload copies, one per arm; the six that remain
are the return-value copies the audit lists next ("forward result destinations
through constructors, `return` and `?`"). `parse_node` and `parse_leaf` are
unchanged, because their remaining copies are not arm bindings.

Evidence: three `src/qbe_test.zig` tests (a scalar payload projects to zero
`blit`s, an aggregate payload field keeps exactly its intermediate field copy,
and a scrutinee the arm writes keeps its payload copies), a guest probe covering
field reads, a `mutates` callee that must not reach the scrutinee, a payload with
a managed `str` field under `--gc-stress` and `--max-memory=16M`, and the port's
own suite: **114 passed, 0 failed across 8 programs**.

## Borrowing a local past the operands pushed after it (round 6)

Two follow-ups on the same theme, both landed after the projection.

**One branch-target pass per unit.** `isBranchTarget` used to walk every
instruction of the unit each time it was asked, and it is asked once per local
read, once per fusible slice and once per projected binding. The emitter now
collects the answer in one pass (`collectBranchTargets`, which the projection
analysis also uses), so a unit with hundreds of reads costs one walk instead of
one per read.

**`QBE-AGGREF-2`: the borrow reaches the operand's consumer.** A local read as an
operand used to be named by its own slot only when the very next instruction
consumed it; when another operand was pushed first — `f(record, x)` — the value
was snapshotted into aggregate scratch instead. The window now runs to the first
instruction whose execution leaves the stack at or below the read's operand,
which is the instruction that consumes it, and it declines whenever anything in
between writes that local (a store, move, drop or match binding) or a branch
reaches into the window without passing through the read. The address it hands
over is the local's own slot, which lives for the whole frame, and a call in the
window runs with this frame suspended, so the operand is read during that
instruction's own execution.

The first attempt at this rule broke on the *consumer* too late (it waited for the
stack to fall below the operand rather than to it) and made things worse — the
port went from 175 to 209 copies, because a chain like `span.line` kept the
window open across branch targets. Measuring caught it, and the corrected rule
keeps the earlier behaviour for that shape while adding the multi-operand case.

Measured on the port with `emit-project-qbe` and `blit` counts:

| Unit | After projection | After the window |
|---|---:|---:|
| `sexpr.parser::parse_leaf` | 20 | 19 |
| `main::tally` | 4 | 3 |
| `main::summarise` | 2 | 1 |
| whole project | 175 | 171 |

Evidence: `QBE-AGGREF-2` in `src/qbe_test.zig` (the record crosses a two-argument
call as its own slot's address and is never blitted out of the local), the port's
**114 passed, 0 failed**, and the full gate.

## Measurement correction: emit with `--no-cache` (round 7)

The copy-site numbers above were read from `emit-project-qbe` runs whose unit
emission came partly from the port's frontend cache. Re-emitting the same source
with `--no-cache` gives a different answer: 13 units differ and the project total
is **205** `blit`s where the cached emission reported **171**. Per function, the
cached reading understated the fresh one (`main::tally` 3 vs 5,
`sexpr.ast::is_form` 0 vs 1, `sexpr.ast::is_atom_named` 1 vs 2,
`sexpr.printer::estimate_width` 4 vs 10).

So the *deltas* quoted for the projection and the borrow window are not
trustworthy as written: both sides of each comparison have to come from fresh
emissions of the same source. What still stands from those rounds is the code and
its tests — `QBE-MATCHPROJ-1` and `QBE-AGGREF-2` are pinned by `src/qbe_test.zig`
assertions that read a freshly emitted manifest, and the port's 114 tests pass.
The re-measurement, the same-session A/B with `--no-cache` on both sides, is the
first task of the next round.

A width-measurement migration was attempted this round as well — replacing the
printer's `len(text_of(view))` with `bytes.view(...).scalar_count()` — and was
reverted: its A/B reading was taken across a cache boundary, so it could not be
told apart from the cache effect above. The migration itself is still the right
change for the audit's "migrate the printer's width calculation"; it needs a
cache-free measurement to land with evidence.

### Cache-free baseline (round 8)

Fresh emission of the unmodified port with `--no-cache`, which is the number any
future A/B must start from: **205 `blit`s** across the project.

| Unit | `blit`s |
|---|---:|
| `sexpr.parser::parse_node` | 37 |
| `sexpr.parser::parse_leaf` | 19 |
| `sexpr.parser::parse_with_depth_cap` | 14 |
| `sexpr.ast::value_text` | 13 |
| `sexpr.ast::span_of` | 12 |
| `sexpr.printer::estimate_width` | 10 |
| `sexpr.printer::push_node` | 10 |
| `sexpr.parser::parse_si` | 9 |

Every delta claim in the earlier sections has to be recomputed from a fresh pair
like this one; the code they describe is unchanged and its tests pass.

## Round 12: the copy-site A/B, rebuilt cache-free (audit item 3)

The round-7 correction withdrew every delta because both sides have to come from
fresh emissions of one source revision. They are rebuilt here that way: a
snapshot copy of the tree (HEAD `4919ea9f`) with a throwaway environment switch
at each analysis, so **one binary** emits every variant, always with
`--no-cache`.

| Variant | total `blit` | Δ vs base |
|---|---:|---:|
| base | 205 | — |
| match projection disabled | 205 | **0** — byte-identical to base |
| borrow family disabled | 298 | **+93** |
| both disabled | 298 | +93 (identical to the borrow row) |
| AGGREF-2 window rule reverted | 196 | −9 |

Method: `./zig-out/bin/mylang emit-project-qbe experiments/sexpr-port/main.my
--no-cache`, counting QBE `blit` instructions per emitted unit (98 units,
205 `blit`s, 30 units carrying one). Every variant was emitted from the same
binary in the same session; the toggles were then removed, the binary rebuilt,
and the emission compared byte for byte with the pre-toggle one — identical.

Three findings, one of them a correction:

1. **The borrow family is what pays.** Turning it off adds 93 `blit`s across 25
   units — 45% of the project's copies. `parse_node` 37→49, `span_of` 12→24,
   `push_node` 10→21, `estimate_width` 10→21, `parse_with_depth_cap` 14→17,
   `value_text` 13→17, `parse_leaf` 19→23, `parse_si` 9→11, `tokenize` 6→8,
   `view::equal` 2→6, `tally` 5→10, and thirteen smaller units. The eliminated
   sites are the `readLocal` scratch copies: the base emits `storel %lN, %sK`
   where the disabled variant emits `blit %lN, %aggM, SIZE` and
   `storel %aggM, %sK` — `parse_node`'s `blit %l2, %agg3, 64`, `span_of`'s
   `blit %l1, %agg2, 32`, `push_node`'s `blit %l3, %agg2, 32`, `value_text`'s
   `blit %l1, %agg2, 64`.
2. **The match projection currently eliminates nothing, because it is disabled
   in the tree.** `payloadAddresses` (src/qbe.zig) opens with
   `if (true) return &.{};`: the projection that gives a match arm's payload
   binding the payload's own address was switched off after the generated
   program segfaulted on the two largest corpus inputs, and `byReference` is set
   only by `addressLocals` (parameters) and by that function, so the early
   return in `qbe_aggregate.armPayload` can never fire. The QBE-MATCHPROJ-1
   numbers recorded in the round-5 section above are therefore both
   cache-confounded *and* describing code that does not run; the SPEC bullet and
   the emitted-IL test behind that tag outlive the behavior they claim. Proving
   the binding's lifetime and re-enabling it, or withdrawing the tag, is the
   question this round leaves open.
3. **The −9 is not a clean window isolation.** Reverting `height <= slot + 1` to
   `height <= slot` makes the consumer scan skip *past* an instruction that
   consumes exactly the pushed operand, so it retargets which instruction counts
   as the consumer rather than undoing the window. It moves copies both ways —
   15 removed and 6 added across 9 units — so it must not be read as "the
   AGGREF-2 window is worth 9 copies". A clean isolation stops the scan at the
   pushed operand instead of skipping it, which is a separate change.

## Round 12: the port stops decoding for width and for numbers (audit item 1)

The audit's acceptance names two migrations and two constraints: migrate "the
printer's width calculation and parser's numeric ranges", "preserve
scalar-counting semantics", "do not replace `len(str)` with byte length", and
keep "full-consumption, overflow, floating-point and suffix behaviour" in
numeric parsing. Both migrations are in `experiments/sexpr-port`.

- `sexpr/printer.my`: `estimate_width`'s atom and string cases call a new
  `scalar_len`, which counts Unicode scalars with
  `bytes.view(start, end).scalar_count()`. That is scalar semantics rather than
  byte length, an invalid range still answers 0 exactly as the empty spelling
  did, and the decode — a slice copy plus a fresh `str`, two allocations and a
  copy of the whole range, per measured leaf — is gone.
- `sexpr/parser.my`: the numeric leaves read their octets.
  `src.view(start, end).parse_int()` and `.parse_float()` replace
  `int(text_of(...))` and `float(text_of(...))`; the `mm`/`mil` suffix test is a
  byte comparison on the source (`spelling_ends_with`, `spelling_ends_with_mil`)
  rather than `spelling.endswith` on a decoded copy; `si_number_end` scans the
  source range instead of a copied `view.bytes_of` spelling; `si_scale` reads
  the suffix octet; and the parser's `text_of` helper is gone with its last
  caller. `parse_unit` now takes the parsed value instead of a string, so the
  unit path parses once from the range it already has.

Emission evidence, `--no-cache`, the same compiler on both sides. Project-wide
callee counts move exactly where the migration says they should:

| helper | before | after |
|---|---:|---:|
| `myl_native_number_parse` (scalar, decoded text) | 4 | 0 |
| `myl_native_bytes_number_parse` (octets) | 0 | 4 |
| `myl_native_text_points` | 4 | 0 |
| `myl_native_text_slice` | 4 | 2 |
| `myl_qbe_bytes_scalar_count` | 0 | 1 |
| new unit `sexpr.printer::scalar_len` | — | 1 |
| dropped unit `sexpr.parser::text_of` | 1 | — |

`sexpr.printer::estimate_width` calls `scalar_len` twice where it called
`text_of` twice, and its IL is 22 lines shorter. The per-unit `blit` count is
unchanged for the printer and moves only inside the parser: `parse_leaf` 19→23
(the three numeric branches now each carry a view and a match), `parse_unit`
6→2 (the string-passing path is gone), project total **205 → 205**.

Runtime evidence. Corpus: 4,000,160 bytes, 13,510 balanced numeric-heavy forms,
sha256 `c09de3a3…`, generated by
`experiments/sexpr-audit/gen_port_input.py`. Both binaries were built by the
same compiler with `mylang build <entry> -o <bin>` in the default mode. Fifteen
interleaved rounds via `experiments/sexpr-audit/bench_port.py`, minimum and
median:

| mode | before | after | delta |
|---|---|---|---|
| census (parse + count nodes) | 324.8 / 349.8 ms | 283.3 / 309.3 ms | **+12.8%** min, +11.6% med |
| render (parse + canonical bytes) | 776.4 / 804.8 ms | 708.3 / 725.4 ms | **+8.8%** min, +9.9% med |

Attribution, from a printer-only intermediate (`scalar_len` present, parser
unchanged), 11 rounds each:

| comparison | census | render |
|---|---|---|
| printer migration alone | +0.0% min / −0.2% med | +1.0% min / −0.1% med |
| parser migration alone (both vs printer-only) | +9.4% min / +13.3% med | +8.9% min / +8.3% med |

Final pair, once the round's other changes had landed (projection re-enabled,
forwarding, `u32` spans): the shipped port against its own pre-migration
sources, both built by the same compiler, 15 rounds —

| mode | before | shipped | delta |
|---|---|---|---|
| census | 316.2 / 323.1 ms | 276.2 / 278.9 ms | **+12.7%** min, +13.7% med |
| render | 762.7 / 768.7 ms | 669.6 / 682.6 ms | **+12.2%** min, +11.2% med |

Runs are tight (the census samples span 276–290 ms against 316–330 ms), and the
render gain is larger here than in the two-migration pair because the `u32`
spans shrink the tree the printer walks.

So the parser's numeric ranges carry the measured win. The printer's width
measurement removes a decode per measured leaf, but on this corpus it sits at
the noise floor: the migration is justified by the work it removes, not by a
wall-clock number.

Honesty notes for this round:

- `bytes.view(a, b)` allocates its own small header, so `scalar_len` and each
  parser range makes **one** allocation where the old path made two (a slice
  copy and a decoded string) plus an O(n) copy and decode. A range operation
  that allocates nothing would need a range-taking runtime entry point;
  `myl_native_bytes_scalar_count_range` and the octet parser already take a
  range, but nothing exposes them to guest code without a view.
- The `noalloc` acceptance is now complete for the operations the audit names:
  `PY-BYTES-9` covers `int(text)`, `float(text)`, `bytes.parse_int()`,
  `bytes.parse_float()`, `bytes.scalar_count()` and `bytes == bytes`, and
  rejects `bytes.view(a, b)` with `E_EFFECT_BOUND`. A `bytes` literal inside a
  `noalloc` function is still rejected, exactly as `PY-BYTES-1` already pins, so
  the comparison case is written with parameters.
- The corpus is synthetic. It is a fair A/B for these two migrations because the
  two sides differ only in them: the pre-migration port was rebuilt out of the
  current tree and its emission checked byte for byte against the recorded
  round-8 baseline before it was timed.

## Round 12: the match projection re-enabled, and forwarding landed

The A/B above found `QBE-MATCHPROJ-1` switched off. Re-enabling it — deleting the
guard and the two test skips, no logic change — is correct on this tree and pays:

| variant (one compiler, every emission `--no-cache`) | total `blit` |
|---|---:|
| projection disabled (the state this round started from) | 205 |
| projection enabled, migrated port, `int` spans | 171 |
| shipped port: projection, `u32` spans and forwarding | **170** |
| pre-migration port sources under the same compiler (control) | 169 |

Read the last two rows together: with the projection on, the sources from before
the two decode migrations emit 169 copies and the shipped port emits 170. The
migrations do not add copies in aggregate — `u32` spans add one and forwarding
removes one — and what the migrations remove is heap work, not copies.

The projection alone removes 34 copies — 16.6% of the project's — across 13
units: `span_of` 12→6, `estimate_width` 10→4, `push_node` 10→4, `as_number` 3→0,
`value_text` 13→10, `tally` 5→3, `as_text` 8→6, `as_atom` 4→3, `as_string` 4→3,
`is_atom_named` 2→1, `as_items` 1→0, `children` 1→0, `is_form` 1→0. The emitted
IL grows by 4,299 bytes (2,388,957 → 2,393,256): each elided copy becomes one
entry-time address store plus loads through it, which is the trade the analysis
makes.

Why enabling it is safe: `payloadAddresses` admits a binding only when
`writtenLocal` proves the scrutinee's local is never written anywhere in the
function, so the projected address is that local's slot plus a compile-time
payload offset inside the current frame — it can neither dangle nor go stale for
the life of the call. The segfault the guard cited (exit 139 on
poe-pd-flyback-tps23757 and remora-rf) does not reproduce on this revision: both
corpus inputs now render byte-exactly (140,085 and 109,470 stdout bytes against
140,084 and 109,469 golden bytes plus the driver's newline), `golden_compare.py`
is 17/17 — re-run on the merged tree, after the projection, forwarding and the
`u32` spans had all landed, including poe-pd-flyback-tps23757 and remora-rf —
the port suite 114 passed / 0 failed, `zig build test` 60/60 steps with
1,371 passed and 0 failed, and a control run with the guard restored fails
exactly those two tests and nothing else. The guard's lifetime claim was never
demonstrated against the current lowering; if a reproducer for the 139 still
exists, it should be captured as an input before the guard is ever reinstated.

**Constructor destination forwarding** (`QBE-CTORFWD-1`) is the last copy site
this round lands. A plain record's `.make_record` whose very next instruction is
the `.store_local` of the same type writes its field stores into that local, and
the store emits nothing, so `start = Point(x=3, y=4)` loses both its staging slot
and its copy. It is claimed only when the destination needs no drop, is not
by-reference, is nonzero-sized and has the record's type, the next pc is that
store and is not a branch target, and no instruction that can reach the
constructor reads that local — the last rule keeps `p = Pair(a=p.b, b=p.a)` on
the copying path, pinned by a negative test. With the projection off it removes
two copies (`parse_with_depth_cap` 14→13, `tokenizer::raw` 5→4); with the
projection on, the surviving site is `tokenizer::raw` 5→4, so the two analyses
overlap and the honest count is the **170** the project emits now. Runtime output
is identical before and after on every fixture tried, including under
`--gc-stress` and explicit step and frame budgets, as it must be: this changes
where a value is built, not what it is.

## Round 12: compact AST storage (audit item 4)

Two experiments, both in the port, both measured on the 4.0 MB corpus with the
interleaved harness.

**Narrower spans: landed.** `ast.Span`'s three fields become `u32` instead of
`int` (`Span` 24→12 bytes, `Node` 72→64), with `max_source_bytes()` = 4 GiB−1
rejecting a longer document with a located error before any span exists, so the
checked `u32()` conversion is unreachable on valid input. Four files change
(`sexpr/ast.my`, `sexpr/parser.my`, `sexpr/tokenizer.my`,
`tests/tokenizer_test.my`, where 88 literal comparisons needed the `u32` suffix)
plus the frozen `Span` declaration in `CONTRACT.md`, whose field *types* this
changes — the audit's "use checked conversion and an explicit maximum
document/position range", satisfied.

| metric | before | after |
|---|---|---|
| `Span` / `Node` | 24 / 72 B | 12 / 64 B |
| peak RSS, census | 224,516 KB | 211,932 KB (−5.6%) |
| peak RSS, render | 486,352 KB | 469,356 KB (−3.5%) |
| census min, 21 rounds | 416.8 ms | 394.5 ms |
| render min, 21 rounds | 956.8 ms | 909.9 ms |

The port suite is 114 passed / 0 failed with byte-identical output in both modes;
the emission gains one `blit` (205→206 in the pre-projection tree) and 22 KB of
JSON, which is a fair price for eight bytes off every node.

**Frozen child sequences: rejected.** Copying each form's children into an
exact-size slice, so the runtime's min-capacity-4 floor no longer applies, is
4–18% *slower* on minima in two independent runs (census 390.8→460.7 ms, render
940.7→1055.2 ms) with no memory change (211,712→211,616 KB): the exact buffer per
form costs what the floor saved, and the extra copy and pop loop are pure cost.
That is a measurement rather than an opinion, and it closes the audit's "test
frozen child sequences" question for this shape.

**Flat node array with child ranges: quantified, not built.** A microbenchmark of
the port's own shape (283,710 two-child lists against the same records in one
appended list) puts per-form `list[Node]` overhead at ≈297 bytes, ≈70 MB — a
third of the port's census peak. But an append-built flat array commits 1.85×
slots for its payload, and the refactor counts 13 construction sites, 56 consumer
sites and 44 match arms across 7 files, with the two CONTRACT-frozen accessors
(`as_items`, `children`) unable to express a range without allocating per call.
The real language ask is a pre-sized or hand-over builder, not a frozen list, and
the application experiment says so with numbers instead of adding a feature
speculatively — which is what the audit's "after measuring simpler changes" and
"avoid requiring `ref`/`borrow`/`move` before exhausting compiler-proven
optimizations" ask for.

