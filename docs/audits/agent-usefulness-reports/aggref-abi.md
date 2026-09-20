# AGGREF-ABI — the copied-value adapter and the QBE-AGGREF-1 argument crossing

Worktree: `.worktrees/agent-usefulness`. Status: **fixed, verified end to end, and
`mylang invoke` widened to execute aggregate arguments.** Every command below was
run in this worktree; the compiler under test is the one `./zigw build` installed
(or `zig-out/focus/mylang` for the focused test roots, which install the same
sources).

The defect was a long-standing mismatch between two spellings of one ABI rule:

* the QBE emitter (`src/qbe.zig::argumentType`) has passed a copyable aggregate
  argument as the **address of the caller's storage** since `QBE-AGGREF-1`;
* the generated C adapter (`src/qbe_build_shapes.zig`) still declared that
  parameter as the aggregate **by value** and passed `*(T *)buffer`, so the callee
  dereferenced the first eight bytes of the record as a pointer.

The fix gives the rule exactly one home — `qbe_wire.byAddress` — read by both the
emitter and the manifest the adapter consumes.

## The defect and its reproduction

`.tmp/abi/shapes.my` (the lead's fixture, copied here for the record) exports a
record argument and a fixed-array argument:

```mylang notest
module shapes


public record One:
    a: i64


public def test_one(p: One) -> i64:
    return p.a


public def test_sum(values: [3]i64) -> i64:
    return values[0] + values[1] + values[2]
```

and `.tmp/abi/cases.json` gives each its expected value. On the frozen W0
baseline binary `/home/epentland/ai/canopy/mylang/zig-out/bin/mylang-baseline-20260920`:

```console
$ mylang-baseline-20260920 test .tmp/abi/shapes.my --cases .tmp/abi/cases.json
failed shapes::test_one: NativeTestProcessFailed: .{ .signal = .SEGV }

failed shapes::test_sum: expected 6, got 34
0 passed, 0 cached, 2 failed, 0 skipped
$ echo $?
1
```

With the fixed compiler:

```console
$ ./zig-out/bin/mylang test .tmp/abi/shapes.my --cases .tmp/abi/cases.json
passed shapes::test_one
passed shapes::test_sum
2 passed, 0 cached, 0 failed, 0 skipped
$ echo $?
0
```

The defect is reachable without `mylang invoke` at all: it is the ordinary
`mylang test --cases` path. `mylang emit-project-qbe` on the same fixture shows
the callee was always right — `export function l $myl_f_a16f…(l %ctx, l %a0)`
followed by `storel %a0, %l0` — the caller was the side that disagreed.

### The shape matrix, before and after

`.tmp/edge/edges.my` (scratch, not committed) covers the whole argument surface in
one program: a scalar, a plain record, a fixed array, a nested record, a
zero-length aggregate, a 4800-byte aggregate, and a record **result**.

```console
$ mylang-baseline-20260920 test .tmp/edge/edges.my --cases .tmp/edge/cases.json
failed edges::test_array: expected 10, got 65
passed edges::test_big
passed edges::test_empty
failed edges::test_nested: expected 54, got 1
failed edges::test_record: NativeTestProcessFailed: .{ .signal = .SEGV }

passed edges::test_result
passed edges::test_scalar
4 passed, 0 cached, 3 failed, 0 skipped
$ ./zig-out/bin/mylang test .tmp/edge/edges.my --cases .tmp/edge/cases.json
passed edges::test_array
passed edges::test_big
passed edges::test_empty
passed edges::test_nested
passed edges::test_record
passed edges::test_result
passed edges::test_scalar
7 passed, 0 cached, 0 failed, 0 skipped
```

The three failing shapes are exactly the copyable aggregates at or below 4096
bytes. The scalar argument and the aggregate result passed before and after, and
the two shapes at the edge of the by-value budget (>4096 already crossed by
address; a zero-length aggregate whose bytes the callee never reads) also passed
before — so the change moves only what was broken and leaves the rest spelled the
same way.

## Root cause

`src/qbe.zig`:

```zig
pub fn argumentType(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
    if ((try self.layout(ty)).copy == .prohibited) return self.abiType(ty);
    return if (self.isScalar(ty)) self.abiType(ty) else "l";
}
```

`src/qbe_build_shapes.zig` (before):

```zig
if (try self.size(name) > 4096) try w.writeAll("const void *") else try self.ctype(w, name);
...
} else if (packed_value or try self.size(name) > 4096) {
```

For a copyable aggregate of 8 or 24 bytes, the emitter asked for `l` (an address)
and the adapter supplied a C struct by value. The two sides agreed only by
accident, in the two places where the emitter's *by-value* branch and the
adapter's size branch happened to coincide: a scalar (a register word either way)
and a >4096-byte aggregate (a pointer either way).

## The fix

One decision, one home.

| File | Change |
| --- | --- |
| `src/qbe_wire.zig` | Now owns `scalar(ty, records)` (moved verbatim from `qbe.zig`) and `byAddress(layout, ty, records)` — QBE-AGGREF-1's crossing rule. `Type` gains an explicit `by_address` fact, emitted by a `jsonStringify` that flattens the aggregate shape, so each `wire_types` entry keeps its `name`/`kind`/`size`/`alignment`/`count`/`stride`/`fields` keys in their existing order and appends `by_address` last. `Type` stays at six fields, under Guardian's seven-field cap. No type enters or leaves the manifest: the `layout.trace or layout.drop` filter is untouched. |
| `src/qbe.zig` | `argumentType` now returns `"l"` exactly when `qbe_wire.byAddress` says so, and the module aliases `qbe_wire.scalar`/`qbe_wire.ownedPointer` instead of keeping a second copy of the predicate. Behaviour is unchanged; the spelling is now shared. Four lines, no other edit. |
| `src/qbe_build_shapes.zig` | `declaration` declares `const void *` and `argument` passes `wire_arguments[i]`/`co_arguments[i]` whenever the manifest records a crossing; the `size(name) > 4096` test is gone from both. `byAddress` reads the recorded fact and never looks at the type's shape. |
| `src/qbe_build_codecs.zig` | `methodArgument` (the codec callback boundary) uses the same recorded fact instead of `size > 4096`, so a callback input agrees with the callee too. |
| `src/native_test_wire.zig` | The guest-level guard below, plus the shared `tools`/`runFixture` driver. |
| `src/aggref_abi_test.zig` (new) | The three-way agreement test below. Registered in `src/root_test.zig` with one import line. |
| `tests/native/aggref_arguments.my`, `tests/native/aggref_arguments.cases.json` (new) | The committed guest-level regression guard. |
| `src/invoke.zig`, `src/invoke_test.zig` | `argumentRefusal` no longer refuses a copyable aggregate, so `mylang invoke` executes one. |
| `tests/invoke/requests/sample.json` (new) | A nested record request for the invoke round-trip. |
| `SPEC.md` | `QBE-AGGREF-3`, `QBE-AGGREF-4`, `QBE-AGGREF-5` and `INVOKE-9` at the `<!-- WS4-AGGREF-SPEC-APPEND -->` marker. `QBE-AGGREF-1` and `QBE-AGGREF-2` were already taken, so the new bullets start at 3. |

What deliberately did **not** change: a scalar parameter keeps `co_word(...)` /
`wire_word(...)` with its `uint64_t` declaration, a move-only parameter keeps the
by-value `ctype` copy, every aggregate result keeps its by-value or large-result
storage, and `qbe_wire.describeWithDomains` still emits exactly the same set of
types for a given program.

The manifest now says, for the reproduction fixture:

```console
$ ./zig-out/bin/mylang emit-project-qbe .tmp/aggref/shapes.my | python3 -c '...'
{"name": "i64", "kind": "scalar", "size": 8, "alignment": 8, "count": 0, "stride": 0, "fields": [], "by_address": false}
{"name": "shapes::One", "kind": "record", "size": 8, "alignment": 8, "count": 1, "stride": 0, "fields": [{"type": "i64", "offset": 0}], "by_address": true}
{"name": "[3]i64", "kind": "array", "size": 24, "alignment": 8, "count": 3, "stride": 8, "fields": [{"type": "i64", "offset": 0}], "by_address": true}
```

## The agreement test

`src/aggref_abi_test.zig` compiles one guest program with a scalar export, a
record export, an array export, a nested-record export and a 4800-byte export,
through the real project path (`project.Project` → `interfaces.build` →
`project_compile.Compilation.emitQbe`), and then requires three artifacts to agree
parameter by parameter:

1. the manifest's `by_address` fact,
2. the **emitted QBE callee signature** parsed out of the unit's `il`
   (`export function … $symbol(l %ctx, …)`), and
3. the **generated C** — every declaration `qbe_build_embed.libraryWrapper`
   spells for that symbol, parsed out of the produced source.

The rule is: a recorded crossing is the emitted `l` address and a `const void *`
C parameter; a recorded non-crossing is never emitted as `l`; a scalar is `l` and
`uint64_t`. It also asserts there are exactly five exports, so a renamed or
dropped export cannot silently shrink the check.

The second test is the one that pins the *source* of the adapter's decision: it
renders the adapter from a hand-written manifest in which two structurally
identical records carry opposite `by_address` values, and requires the by-value
parameter and the address parameter to differ accordingly.

**Falsifiability, measured.** Both directions were reverted in turn and the test
re-run:

```console
# adapter re-derived from size(name) > 4096 again
$ ./zigw build test-units -Dtest-filter=aggref
guardian/test: RESULT {"passed":11,"failed":2,"skipped":0}
error: 'aggref_abi_test.test.every exported aggregate argument is recorded as a crossing and emitted as an address' failed
error: 'aggref_abi_test.test.the generated adapter spells and passes an argument from the recorded crossing alone' failed

# emitter kept the manifest fact but passed the aggregate by value again
$ ./zigw build test-units -Dtest-filter=aggref
guardian/test: RESULT {"passed":12,"failed":1,"skipped":0}
error: 'aggref_abi_test.test.every exported aggregate argument is recorded as a crossing and emitted as an address' failed

# restored
$ ./zigw build test-units -Dtest-filter=aggref
guardian/test: RESULT {"passed":14,"failed":0,"skipped":0}
```

A test that would still pass with either side reverted is not evidence; this one
fails on both.

## The guest-level regression guard

`tests/native/aggref_arguments.my` is a language-level fixture driven by
`mylang test --cases` (the same path the defect lived in), with
`tests/native/aggref_arguments.cases.json` carrying seven cases: a record
argument, a fixed array, a nested record, a zero-length aggregate, a 520-element
(4160-byte) aggregate, a scalar argument and an aggregate result.

```console
$ ./zig-out/bin/mylang test tests/native/aggref_arguments.my --cases tests/native/aggref_arguments.cases.json --cache-dir .mylang-cache/aggref-fixture
passed aggref_arguments::test_aggregate_result
passed aggref_arguments::test_array_argument
passed aggref_arguments::test_large_argument
passed aggref_arguments::test_nested_record_argument
passed aggref_arguments::test_record_argument
passed aggref_arguments::test_scalar_argument
passed aggref_arguments::test_zero_length_argument
7 passed, 0 cached, 0 failed, 0 skipped
```

On the frozen baseline the same fixture fails exactly the three copyable
aggregates:

```console
$ mylang-baseline-20260920 test tests/native/aggref_arguments.my --cases tests/native/aggref_arguments.cases.json --cache-dir .mylang-cache/baseline-aggref2
passed aggref_arguments::test_aggregate_result
failed aggref_arguments::test_array_argument: expected 456, got 430
passed aggref_arguments::test_large_argument
failed aggref_arguments::test_nested_record_argument: expected 30, got 139024323932993
failed aggref_arguments::test_record_argument: NativeTestProcessFailed: .{ .signal = .SEGV }

passed aggref_arguments::test_scalar_argument
passed aggref_arguments::test_zero_length_argument
4 passed, 0 cached, 3 failed, 0 skipped
```

The case runs inside the suite from a Zig test in `src/native_test_wire.zig`
(`// spec: QBE-AGGREF-5`), which resolves the installed compiler from the build's
own `MYLANG_QBE` (`dirname(MYLANG_QBE)/mylang`, project root three levels up) and
runs the fixture against a fresh temporary cache, so a stale receipt can never
turn a regression into a pass.

## `mylang invoke`

`src/invoke.zig::argumentRefusal` refused an unmanaged aggregate argument with
kind `aggregate-argument`, `wire_supported: true`, `eligible: false`, purely
because of this defect; `invoke.md` predicted the fix and where it would land.
The refusal is gone, the `wire`/`execution` double walk is now a single walk
because the two subsets agree on every argument shape the codec reconstructs, and
`tests/invoke/tool.my::sample_label` executes:

```console
$ ./zig-out/bin/mylang invoke tests/invoke/tool.my --function tool::sample_label --input=tests/invoke/requests/sample.json
{"version":"native-invocation-v1","status":"completed","target":{"function":"tool::sample_label","entry":"tests/invoke/tool.my"},"invocation":{"kind":"value","value":"7","steps":3,"output":"","diagnostics":""},"context":{...}}
$ echo $?
0
```

`sample.json` is `{"sample": {"label": "7", "span": {"low": "1", "high": "2"},
"weights": ["1", "2", "3"]}}`, so a nested record, a nested record's field and a
fixed array all cross the copied boundary in one call. The end-to-end assertion
lives in `src/invoke_test.zig` (`// spec: INVOKE-9`), which spawns the installed
compiler for that exact command and requires `"status":"completed"` and
`"value":"7"`. `docs/tooling/invocation.md` and `invoke.md` are updated; the
`aggregate-argument` refusal kind no longer exists.

## Acceptance

| Check | Command | Observed |
| --- | --- | --- |
| Reproduction | `./zig-out/bin/mylang test .tmp/abi/shapes.my --cases .tmp/abi/cases.json` | `2 passed, 0 cached, 0 failed`, exit 0 (baseline: 2 failed, exit 1) |
| Shape matrix | `./zig-out/bin/mylang test .tmp/edge/edges.my --cases .tmp/edge/cases.json` | `7 passed, 0 failed` (baseline: `4 passed, 3 failed`) |
| Guest guard, fixed | `./zig-out/bin/mylang test tests/native/aggref_arguments.my --cases tests/native/aggref_arguments.cases.json --cache-dir .mylang-cache/aggref-fixture` | `7 passed, 0 cached, 0 failed` |
| Guest guard, baseline | `mylang-baseline-20260920 test tests/native/aggref_arguments.my --cases … --cache-dir .mylang-cache/baseline-aggref2` | `4 passed, 3 failed`, exit 1 |
| Agreement test | `python3 scripts/focused_test.py units aggref` | `selected: 14 test(s)`, `PASS - 14 passed, 0 failed` |
| Guest guard in the suite | `python3 scripts/focused_test.py units round-trip` | `selected: 17 test(s)`, `PASS - 17 passed, 0 failed` (the fixture test is the slowest at `0.87 s`) |
| Invoke | `python3 scripts/focused_test.py units invoke` | `selected: 27 test(s)`, `PASS - 27 passed, 0 failed` |
| Native-test suite | `./zigw build test-native-tests` | exit 0; `guardian/test: RESULT {"passed":94,"failed":0,"skipped":0}`; `guardian: run-all: 88 check(s) passed` |
| QBE suite | `./zigw build test-qbe` | exit 0; `guardian: run-all: 88 check(s) passed` |
| Golden corpora | `./zigw build test-golden` | exit 0; `guardian: run-all: 88 check(s) passed` |
| Adapter generation | `./zigw build test-qbe-build` | exit 0; `guardian: run-all: 88 check(s) passed` |
| Guardian gate + install | `./zigw build` | exit 0; `guardian: run-all: 88 check(s) passed`; installed `zig-out/bin/mylang` |
| Formatting | `./zigw fmt --check` on every changed `.zig` file | exit 0 |

The native/qbe/golden suites were also run together
(`./zigw build test-native-tests test-qbe test-golden --summary all`, exit 0)
before the final `./zigw build`.

### Files that changed outside the package's own list

`src/qbe.zig` is not in the package's file list, and it carries the emitter's
`argumentType`. Leaving it alone would have meant a **second** implementation of
the crossing rule in `qbe_wire.zig` — exactly the duplication this defect is
made of — so the emitter now calls `qbe_wire.byAddress` and aliases
`qbe_wire.scalar`/`qbe_wire.ownedPointer` instead of keeping its own copies.
The substitution is behaviour-preserving and is proved by the whole test corpus
plus `test-golden`.

## Limits not closed

* **A callable parameter is still spelled by its shape, not by the recorded
  fact.** A record whose `contract.callback` is set is one code word
  (`qbe_wire.scalar` is true for it, so `by_address` is false), but
  `Shapes.scalar` — which the adapter uses to choose the *word* branch — reads
  the manifest `kind`, which is `record` for it. It therefore still takes the
  by-value `*(WireValueN *)buffer` branch, whose eight bytes are the code word,
  which is what the emitted `l` parameter wants; the C type is an 8-byte
  `_Alignas(8)` struct rather than `uint64_t`. This is unchanged from before the
  fix and is not exercised by any committed fixture, so it is recorded rather
  than rewritten.
* **The zero-length case is a crash guard, not a value guard.** No language
  expression can read a `[0]T`, so the case can only show that the argument
  crosses without a fault; it passed on the baseline too.
* **A >4096 move-only aggregate would still disagree** (the emitter passes it by
  value, an adapter that used the old `size > 4096` test would pass a pointer).
  `qbe_wire.describeWithDomains` cannot emit one — `native_wire.supported`
  excludes every move-only record and every type containing one — so the
  disagreement is unreachable, and the adapter now follows the recorded fact
  rather than the size, which would be the right answer if it ever became
  reachable.
* **Domain arguments are not covered by a fixture.** The manifest path is the
  same one the record and array cases exercise, and a domain over a scalar is
  `by_address: false`, but no committed invoke or guest fixture passes a domain
  argument.
* **`mylang invoke` still refuses the capability and effect cases** it refused
  before (`authority`), and an unsupported nested path still names its own first
  path; neither is affected by this change.
