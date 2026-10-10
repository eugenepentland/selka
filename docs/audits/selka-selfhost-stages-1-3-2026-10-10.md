# Frontend qualification and integration follow-up

Implementation branch: `codex/selka-selfhost-stages-1-3-20261010`.
Worktree: `/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang`.
This continues the committed pilots at `6f70cb720`. The active cache Wave 3
worktree and the original working checkout were not modified.

## Implemented

1. **Register qualification.** The full gate includes independently invokable
   lexer, parser and compiler-probe lanes. Each verifies its qualified seed
   receipt, runs nonempty debug and release/fact/leak selections, and rejects
   missing summaries, cached pure verdicts, unsupported cases and failures.
   Inputs include recursive fixture membership and shared lexer source bytes.
2. **Package and compare the lexer.** The native coordinator installs a
   content-addressed `lexer-pilot`. `dump-tokens` supports explicit reference
   and verified shadow modes. Requests have correlated, bounded framing;
   launches use sealed executable snapshots, deadlines, bounded output and
   deployment revalidation. Both modes preserve native output and diagnostics.
   Component-only algorithm edits are qualified against the complete lexer
   fixture corpus with an unchanged host executable.
3. **Expand parser grammar and validate complete syntax.** The Selka producer
   now covers current declarations, types, patterns, expressions, control flow,
   resources, format strings, metadata, recovery, migration notes and repairs.
   The independent native codec validates complete named AST fields, spans,
   IDs, graph bounds and diagnostic provenance. The coordinator installs a
   `parser-pilot`; `dump-syntax` exercises its native shadow boundary. The
   installed command can run both frontend shadow components with an empty
   `PATH`. It does not need Python or load source imports.

This is grammar qualification and an installed comparison boundary. It does
**not** complete compiler-wide frontend adoption: ordinary compilation, import
loading, formatting and their caches still use the reference frontend.

The qualified component seed remains source `0689d3407c17df34915aeb2a92e309af3a04921c`
with executable SHA-256
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
Neither bootstrap pin nor the admitted source profile changed. Source repair
text is encoded as bytes, including Unicode; diagnostic prose uses the
qualified ASCII encoder and rejects unsupported conversion explicitly.

## Evidence

The registered pure selections contain 17 lexer, 86 parser and 11 compiler
probe tests in each mode. Lexer comparisons select 79 immutable fixtures and
compare 1,714 token/error rows per mode. The original 50-case parser projection
remains a separate regression; it does not substitute for complete AST equality.

The complete parser fixture selection has 101 cases: 26 ASTs and 75 complete
diagnostic reports in the explicit module/trust contexts declared by fixtures.
Installed CLI comparisons use ordinary module parsing without intrinsic trust,
so their classification is 25 ASTs and 76 diagnostic reports. The installed
driver additionally checks 103 valid framed exchanges, 28 malformed/invocation
cases, three deployment failures and a component-only implementation edit.

The recursive parser corpus selects all 379 `.my` files under `tests/lang/`,
`tests/value_semantics/` and `src/stdlib/`. Of those, 378 compare as exact ASTs.
The historical `src/stdlib/fixtures/time_random_provider.my` uses retired
capability spellings and is rejected by the native lexer before parser tokens
exist. That one exclusion is pinned to source SHA-256
`c00a39d7b71a7c9ff0cacd4a0d2144e9a8d35562a6fdb3bb1fc52bcacbb9f3ba`
and its native lexical rejection is rechecked on every run. It never counts as
parser parity. Codec-only roundtrips are reported independently. The corpus
caught and fixed a generator-comma check incorrectly applied to ordinary
multi-argument method calls.

The coordinator's 19 regression tests include entry selection and shared lexer
file-link invalidation. Eight orchestration tests reject incomplete, duplicated,
skipped or incorrect qualification summaries. Cached test inputs include all
four installed component manifests, while pilot seed checks always execute.

Plain installation passed 12/12 steps. The focused lexer gate passed 16/16
steps after the final range correction, and the installed `dump-syntax` CLI
selection passed 6/6 tests, including both shadow components with empty `PATH`.
The full repository gate on code commit `6a77ea11f` passed **110/110 steps**.
Guardian's actual selected native test results total **2,620 passed, zero failed,
zero skipped**. Zig's aggregate also prints 23,863 skips for tests assigned to
other shards; those are excluded shard slots, not omitted selected cases.
The three pilot lanes passed in this same run: 17 lexer, 86 parser and 11 probe
pure tests in each mode, both complete corpus comparisons and both installed
parser qualification runs. Their selected checks have zero failures or skips.
The historical lexer harness retains its three documented exclusions, and the
documentation runner retains its explicitly tagged skips; neither is counted
as current-pilot parity.

The final combined `fmt-check test-docs` run passed **21/21 steps** after the
range correction. All 88 blocking Guardian checks also passed at the code
commits. No Guardian feedback file was modified.

Full gate log:
`/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots/stages-full-gate-final.log`.
Final formatting/documentation log:
`/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots/stages-final-docs-fmt.log`.
The final installed parser SHA-256 is
`956974d29374d96cacec3db3c752475a73fcf02cf5653a751588bfde0b24d3bd`.

## Isolated measurement

Timing held the gate reservation and all three build reservations through FIFO
admission, after the preceding Wave 3 benchmark finished. No actual gate or
build ran beside the transport measurements. The ReleaseFast host and its
children ran on reserved CPUs `2,3,10,11`; the edit compilation used the ordinary
nonreserved build CPUs. Every warm sample also required exact output equality.

| Source | Reference median | Shadow median | Added latency |
| --- | ---: | ---: | ---: |
| 34 bytes | 0.241 ms | 1.849 ms | 1.608 ms |
| 64 KiB comments | 0.323 ms | 2.174 ms | 1.851 ms |
| 64 KiB token-heavy input | 6.786 ms | 22.062 ms | 15.276 ms |

Each median contains 20 samples of the complete `dump-tokens` command. Shadow
mode performs both implementations and validation; these numbers measure its
overhead and are not a component-only lexing speedup claim. The largest response
was 2,178,985 bytes. The measured final lexer artifact SHA-256 was
`295c0ba2215157e9bc92e054b1c9f4cf48f62b2fee089be2215fd5ee68a80936`;
the ReleaseFast host was
`4be9e89a596bb413c675083d0fc7a1584cc9236065e6e53baebeb16f493f02d8`.

A separate, single sample of a qualified-seed debug lexer algorithm edit and
rebuild took **60.447 ms**. It used a private copy of the final source closure,
`build ... --project --no-cache`, after a baseline build warmed the toolchain.
The producer artifact changed, the host digest stayed unchanged, and all 79
fixtures / 1,714 rows matched again. This excludes coordinator hashing,
installation, parser rebuilding caused by a shared lexer edit, and cold seed
provisioning. It is not an end-to-end `zig build components` measurement.

The complete measurement log is
`/home/epentland/.cache/selka-lexer-tmp/lexer-isolated-timing.log`.
The reusable transport driver is
`selfhost/components/lexer_pilot/measure_transport.py`; obtain isolated admission
before using its `--isolated` assertion.

## Reproduce

Use the pinned Zig, private disk-backed `TMPDIR`, private `ZIG_LOCAL_CACHE_DIR`
and the shared global cache described in `CLAUDE.md`. Then run:

```console
scripts/build-slot.sh build zig build --summary all
scripts/build-slot.sh build zig build test-selfhost-pilots --summary all
scripts/build-slot.sh gate zig build test --summary all -j4 --maxrss 8589934592
scripts/build-slot.sh build zig build fmt-check --summary all
```

The individual targets are `test-selfhost-lexer-pilot`,
`test-selfhost-parser-pilot` and `test-selfhost-probes-pilot`. The parser lane
runs its original projection, complete fixtures, codec roundtrips, recursive
corpus and installed-boundary checks in both modes.

## Remaining adoption work

The production whole-source parser consumers are `compiler.zig` (`parseCached`
and `formatModule`), `interfaces.zig` (module parsing), and `declarations.zig`
(parse-only tooling). Route these through the validated boundary with explicit
runtime capabilities and distinct host/source failures. Thread that context
through `Compilation`, project/interface loading, Core frontend sessions and
CLI entry points. Internal format-hole parsing belongs to its enclosing parse;
it should not launch a second whole-source component.

Syntax cache hits in `compiler.zig` and `interfaces.zig` currently bypass the
boundary. Before any production switch, bind authenticated component identities
to retained syntax, persistent frontend/semantic state, executable replay and
test-result validity before lookup. A shadow-only first rollout can disable
those reuse paths, but must prove warm hits cannot bypass comparison or hide a
missing/corrupt/replaced component. The host APIs already expose mode/schema/
verified-artifact identities; publishing those APIs alone is not cache adoption.
Cache identity must also include module mode and intrinsic authority, alongside
the source bytes/path and frontend profile. These request properties can change
the parse of identical bytes. Retained in-process caches need the same partition
or explicit invalidation when their boundary configuration changes.

Coordinate that work with Cache Wave 3. Its build registry must retain the
always-run seed checks described in the [pilot gate handoff](../tooling/selfhost-pilot-gates.md).
Qualify auxiliary lexer consumers separately, and extend malformed-program and
large-input coverage before changing defaults. The selected corpus is evidence,
not a claim that every possible program or diagnostic has been proved equivalent.

After frontend adoption, the next original plan stages are contained analyses
followed by checker/lowering slices, then staged self-compilation and
reproducibility. Neither requires changing the current seed profile in this pass.

Protocol details: [complete syntax values](../tooling/parser-syntax-values.md),
[installed parser checks](../tooling/parser-component-qualification.md), and
[component installation](../tooling/selfhost-components.md).
