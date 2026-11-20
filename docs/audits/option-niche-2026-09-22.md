# Niche `Option`: an optional reference is a nullable pointer — 2026-09-22

Wave 4, item 2 (second half) of [the parity plan](performance-parity-plan-2026-09-22.md)
(§4.6, §6.9). Branch `perf/option-niche` from `base/parity-w4` (`0804a4cf`).

**Status: done.** `Option[T]` where `T` is a managed reference is now just the
reference word: 8 bytes, null for `None`.

- **Node size.** A `binary_trees` node was 16 bytes of header plus 32 of
  payload (48). It is now 16 + 16 (32).
- **Speed.** `binary_trees` runs in 0.75× the time of the base on the
  collecting heap and 0.86× in an arena.
- **Memory.** Peak RSS falls from 55.1 MB to 28.5 MB.
- **Ratio to Zig.** In the final batch the collecting heap went from 1.86× to
  1.39× and the arena from 1.31× to 1.11×. The machine was loaded, so see
  *Numbers* for the spread.
- **Nothing else changed.** All 24 other suite programs, the S-expression parser
  and the schematic renderer build to byte-identical binaries.

## Representation

`QBE-NICHE-1`. This rule covers an `Option` whose `Some` payload's layout is
`.managed`. That is a `class` instance, `list`, `dict`, `str`, `bytes` or
`Cell`: every value that is a non-null pointer into the managed heap or the
image. Such an optional is laid out as one 8-byte, 8-aligned word:

| value | word |
|---|---|
| `None` | `0` |
| `Some(r)` | `r` |

Every other optional keeps the `{u32 tag, payload}` layout:

- A scalar, record, union or domain payload.
- An optional optional. `Option[Option[C]]` is `{tag, niche word}` (16 bytes),
  because the inner `None` already owns the null word. `Some(None)` and `None`
  stay distinct, and a guest test pins it.

The rule reads the schema's `some`/`none` cases through `prelude.optionCases`,
the test `optionShape` makes. So a user `union` of exactly that shape is laid
out the same way. A two-case union with other case names keeps its tag.

A managed reference is never null in a well-formed value. Constructors,
collection reads and codec decoders all produce real objects or immortal image
storage, so the null word is free.

**Not a register value.** To the emitter the optional is still an aggregate: an
8-byte value that lives in a frame slot and crosses calls by address, like
every variant. That keeps the change to the layout and to the few places that
read or write a case tag. LLVM's SROA promotes an 8-byte slot like any other.
Making the optional a scalar register value is the follow-up (see *What is
left*).

## Every place that knows the layout

| site | before | now |
|---|---|---|
| `native_types.zig` `Catalog.build` | variant = `{u32 tag @0, payload @align}` | `niche()` runs first and gives `Kind.niche`: size 8, one field (payload @0, tag = `Some`), `trace = true`. ABI version `…-layout-v3`. |
| `qbe.zig` `writeTag` | `storew tag, p`, with no type argument | takes the variant type. Niche: `None` → `storel 0, p`; `Some` → nothing, because the payload write that follows is the word. |
| `qbe.zig` `readTag` (new) | inline `loaduw p` at each site | niche: `loadl p; cnel/ceql 0` gives the case index. Tagged: `loaduw`. |
| `qbe_aggregate.zig` `make_variant` / `switch_variant` | inline tag store/load | `writeTag` / `readTag` |
| `qbe.zig` `try_result` (`?` on `Option` and `Result`) | inline `loaduw`, `writeTag(tag, p)` | `readTag` / `writeTag(ty, …)` |
| `qbe_results.zig` `option` (the text and bytes parsers' `Option` results), `payload`, `result` | inline `storew` | `writeTag` |
| `qbe_boundaries.zig` `environment_get` (`Option[str]`, a niche) | inline `storew` | `writeTag` |
| `qbe_resources.zig` `complete_resource` (a `Result`) | inline `storew` | `writeTag`, so every tag store goes through the one helper |
| `qbe.zig` `supported` | admits `.variant` | also `.niche` |
| match-payload projection (`QBE-MATCHPROJ-1`) | payload address = scrutinee + `payload_offset` | unchanged: `payload_offset` is 0, and a managed payload is a scalar binding that is never projected |
| `native_descriptors.zig` | one `MYL_NATIVE_VARIANT` descriptor per option type | a niche optional is emitted as its **payload's pointer descriptor under the optional's name**. The runtime gets no new kind. |
| `native_heap.c` trace, `native_regions.c` region check and escape copier, `native_equal.c` | walk the variant by tag | **unchanged**. `MYL_NATIVE_POINTER` already tolerates null in all four: `mark(NULL)` returns, `reach` reads region 0 for null, `ensure(NULL)` keeps null, and `managed()` answers null/null equal and null/ref unequal. That is exactly the `None` semantics. |
| `native_heap.c` `myl_native_schedule` (resource drop) | — | unchanged: a managed payload owns no resource |
| `native_render.zig` + `native_print.c` | `myl_print_variant` reads the u32 tag | a niche renders through the new `myl_print_niche`, which picks the case with a payload renderer when the word is non-null. `myl_print_variant` is untouched. |
| `qbe_wire.zig` manifest, `qbe_build_shapes.zig` | kind `variant` | kind `niche` (manifest kind 7) |
| `qbe_codecs_runtime.c`, `qbe_wire_runtime.c` | kind 3 reads and writes the u32 tag | kind 7: decoding writes null or reads the payload over the word, and encoding derives the case from null |
| `qbe_host.zig` (host bridge) | — | unchanged: the bridge refuses every traced type, so it never sees a niche optional |
| `invoke` JSON codec, test `--cases` codec | wire nodes | unchanged: they read wire nodes and the checked schema, never native bytes |
| LLVM adapter alias classes | frame vs. foreign by address provenance | unchanged: nothing in them depends on layout |
| dict-key equality/hash | memcmp for non-string keys | unchanged: an optional is not a hashable key |

**Why the descriptor is an alias, not a new kind.** The first version added a
`MYL_NATIVE_NICHE` kind and taught the four C walkers about it. That was
correct, but it made the S-expression parser's census about 1.8% slower, with
the paired interval above 1.0 in two batches, on a program with no niche
optional at all. The cause was `native_equal.c`. Its `managed()` gained a
second call site, so LTO stopped inlining it into a hot guest function that
compares text (`nm -S`: a new 0x50f-byte `managed` symbol, and that guest
function shrank by 1,953 bytes). Aliasing the payload's pointer descriptor
removes every C walker change. The parser, schematic and 24 suite programs are
now byte-identical to the base.

## ABI decisions

- **Native layout ABI.** Internal and versioned: `mylang-native-amd64-layout-v3`.
  Every layout digest changes, so no cached object built for v2 can be linked
  with a v3 one.
- **Copied-value boundary (`QBE-NICHE-3`).** The external form is unchanged. A
  niche optional still crosses as a wire node whose `bits` is the case index and
  whose one child is the payload. Only the internal compiler→adapter manifest
  learns a new kind. `tests/native/option_niche_boundary.my` round-trips
  `Option[str]`, `Option[list[i64]]`, `Option[Option[str]]` and
  `list[Option[str]]` through `--cases` in both directions.
- **Host bridge.** Unchanged. It already refuses every traced type
  (`layout.trace`), so no host sees an optional reference.
- **Descriptor ABI (`native_heap.h`).** Unchanged: no new kind.

## Numbers

Loaded machine: load average 7–24 across the batches, pinned to CPU 4, fresh
processes, arms shuffled every round, paired ratios with 95% bootstrap
intervals. The base compiler is `0804a4cf` built ReleaseFast into
`.tmp/base/install`, because `install-w23` was not yet built. Results are in
`experiments/perf-parity-plan-20260922/results/wave4/`.

**Node layout**, read from the descriptors `emit-qbe` generates for
`binary_trees.my`:

| | `Option[Node]` | `Node` body | node with its 16-byte header |
|---|---:|---:|---:|
| base | 16 (`MYL_NATIVE_VARIANT`) | 32 | 48 |
| this | 8 (the `Node` pointer descriptor) | 16 | **32** |

**`binary_trees`** — `option-niche-binary_trees.json`, final compiler, 11
rounds, load average 7–10:

| arm | ms | ×Zig | this / base | peak RSS |
|---|---:|---:|---:|---:|
| Zig | 319 | 1.00 | — | 4.5 MB |
| base, collecting heap | 603 | 1.86 [1.84, 1.90] | | 55.1 MB |
| **this, collecting heap** | 449 | **1.39** [1.38, 1.42] | **0.750** [0.732, 0.764] | **28.5 MB** |
| base, arena | 417 | 1.31 [1.28, 1.32] | | 17.7 MB |
| **this, arena** | 361 | **1.11** [1.10, 1.15] | **0.863** [0.854, 0.873] | **11.7 MB** |

The niche layout was the same in the three earlier batches; only the runtime C
around it changed. Those batches measured this/base at 0.745, 0.787 and 0.761
(collecting) and 0.872, 0.900 and 0.880 (arena). The ratio to Zig moved with
load, from 1.39× to 1.78×. The paired ratio did not. Peak RSS relative to Zig
falls from 12.1× to 6.3×.

**Against acceptance.** The node is 32 bytes (target: 48 → 32). Time and peak
RSS both improve. The plan's wave-4 target, `binary_trees` ≤ 1.5× on the
collecting heap and ≤ 1.15× in an arena, was set for this lane *combined* with
inline allocation. This lane alone reaches 1.39× and 1.11× in the quietest
batch, and 1.48–1.78× in the loaded ones.

**Nothing slower.** Each program was built with both compilers and the binaries
compared byte for byte (`cmp`):

- all 24 suite programs other than `binary_trees` and `binary_trees_arena`;
- the S-expression parser (`sexpr-port-mut`, `--project`);
- the schematic SVG renderer (`src/schematic/guest`, `--project` with its
  provider).

All are identical. The parser's one changed function, `ast.as_items`, which
returns `Option[list[Node]]`, has no caller, and LTO drops it.

The parser file `option-niche-parser.json` is therefore an A/A measurement:
two byte-identical binaries, 21 rounds. It reads 1.012 [1.003, 1.019] for
census and 1.010 [1.002, 1.023] for render. That is this harness's bias at
this load, about 1%, and a reason to read any other 1% difference here as
noise.

## Tests

- `src/native_types.zig`, `QBE-NICHE-1`:
  - `Option<Node>` is `Kind.niche`: size 8, align 8, one field at 0 tagged
    `Some`.
  - The node body with two optional children is 16 bytes.
  - `Option<Option<Node>>` stays a 16-byte variant with its payload at 8.
  - `Option<Pair>` (a record payload) and a two-case union with other names stay
    16-byte variants.
- `src/native_descriptors.zig`, `QBE-NICHE-1` (spec-case): the optional's
  descriptor body is byte-for-byte the payload's pointer descriptor (size 8,
  `MYL_NATIVE_POINTER`), and a holder's GC table names it at the field offset.
- `tests/lang/option_niche.my`, `QBE-NICHE-2`, run under `--gc-stress` by
  `zig build test-lang`. Twelve cases:
  - construction, `is None` and `match`;
  - a depth-6 tree across collections;
  - `?` propagating `None` and unwrapping `Some`;
  - `is_some`/`is_none`/`unwrap_or`;
  - `==`/`!=` by identity (class) and by value (`str`);
  - f-string rendering of `Option[str]` and `Option[list[int]]`;
  - optionals in a list, a dict, a record field and a fixed array;
  - optionals through callbacks;
  - `Option[Option[Node]]`;
  - a user union of the same shape;
  - `escape` of a list of optional lists out of an arena;
  - `list[Option[str]]` under collection.
- `src/native_test_wire.zig`, `QBE-NICHE-3`: the `--cases` fixture above, six
  cases.

## Gate

Run on the Debug build of `17ea7fd4` through the gate slot and the memory cap,
then compared with the coordinator's base logs (`gate_diff.py w23-<step>.log`):

| step | result | vs. base |
|---|---|---|
| `zig build test` | 45 failed (base 47) | **0 new**. One cleared: `native_test_wire` aggref, which was `/tmp` quota on the base run. |
| `zig build test-qbe` | 2 failed (base 3) | **0 new**. The same one cleared. |
| `zig build test-qbe-build` | green | — |
| `zig build test-schematic` | green | — |
| `zig build test-byte-io` | green | — |
| `zig build fmt-check` | green | — |
| Guardian (whole tree, commit hook) | 88 checks passed | — |

`zig build test-lang` runs every `tests/lang` program under `--gc-stress`,
including `option_niche.my`: 329 passed across 78 programs.

An earlier gate run, made while `/tmp` was full, showed 27 "new" failures. They
were CLI and `invoke` integration tests failing with exit 2 (host failure).
Rerun alone after `/tmp` was freed, they passed (for example `invoke_test` "a
record holding a text or a list composes with Option and Result"). The rerun
above has none of them.

## Found on the way

- **`escape` cannot copy a `class` instance.** `native_regions.c` `shallow()`
  returns NULL for a non-collection managed object, and the copier reports it as
  `OutOfMemory`. The base does the same: a probe that escapes a list of
  `Option[Node]` fails identically on the base compiler `0804a4cf`. The guest test escapes
  optional lists instead.
- **`?` on an `Option[Node]` is rejected in a function returning
  `Option[int]`.** The checker reports `E_TYPE` ("expected int, found Node") at
  `node.left?`: it evaluates the operand against the function's payload type. It
  is a checker question, not a layout one, and happens on the base too.

## What is left

- **Register representation.** The niche optional is still a stack-slot
  aggregate, passed and returned by address. Treating it as a `scalar` would
  remove the slot traffic that QBE does not promote: one `l` register, rooted
  with the value-carrying root word like any managed pointer. That touches
  `qbe_wire.scalar`, every `isScalar` site, `make_variant` and `switch_variant`
  on a register, and the codec ABI (`by_address`). It is a follow-up, to be
  measured against this one.
- **Other niches.** `Option[int]` and other scalars have no free bit pattern.
  Nothing else can take a niche without a range type.
