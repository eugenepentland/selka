# Parallel work toward incremental Selka self-hosting

Date: 10 October 2026. These tasks can proceed while the cache Wave 3 branch is
being completed. They are implementation briefs for separate agents, not a
request to replace the compiler all at once.

## Starting point

Use a separate worktree and branch per task. The shared, committed baseline is
`0d9ababf7eb434d2e02e1b2b45fe5c6593715e7a`, the merge of main
`5174fd03fb0f9dcae4f4fa51d7cb76ba649a988f` into the cache branch. It contains the
existing component foundation and the Wave 2 cache work, but excludes the
in-progress, uncommitted Wave 3 implementation. This is an explicit baseline;
do not assume another worktree's dirty checkout represents it.

The active cache worktree is
`/home/epentland/.codex/worktrees/selka-selfhost-wave1/mylang`, on
`codex/selka-cache-wave3`. Do not edit that worktree for these tasks. Reuse an
available clean worktree where practical. Keep each worktree's Zig local cache
and temporary directory private; the global Zig cache may be shared.

Read the repository's `CLAUDE.md` and these current references first:

- [Component build, seed, installation and qualification](../tooling/selfhost-components.md).
- [Qualified bootstrap source profiles](../bootstrap-v1.md).
- [Component value protocol](../tooling/component-protocol.md).
- [Progressive Selka/Zig interop plan](selka-zig-interop-plan-2026-10-09.md).
- [Admission and worktree rules](../tooling/many-agents.md).

The production compiler uses Core IR, LLVM and the pinned Zig toolchain, with
reference-counted value semantics. Older self-hosting documents and donor code
still mention QBE, `Cell`, old syntax and retired host interfaces. Treat those
as historical source material. Neither an old README nor a successful compile
with today's development compiler expands the qualified component profile.

`selfhost/component-seed.json` identifies the qualified component seed. The
older `selfhost/stage0-pin.json` belongs to historical fixtures; they are distinct
bootstrap contracts. Preserve both pins unless a separately justified seed
qualification is part of the assigned work.

## Shared ownership and working rules

The cache agent owns `build.zig`, `build_test_inputs.zig`, `build_verification.zig`,
the verification/admission scripts, existing cache-plan/test-index components,
and the Core cache integration during this pass. Provide standalone commands
for new tests instead of wiring them into the gate immediately. List the exact
gate additions needed in your handoff.

Use the existing process/value boundary. Keep algorithms in ordinary Selka
library modules and put filesystem/process transport in a separate adapter.
Do not add a shared-library ABI, callbacks, Zig pointer sharing, a persistent
worker, or a backend rewrite as a prerequisite for these tasks.

Run builds and test execution through `scripts/build-slot.sh build|gate` as
required by `CLAUDE.md`. Use disk-backed `TMPDIR`. Timing measurements must not
run beside a gate; obtain isolated admission before measuring. Correctness
work can proceed while timing is unavailable. Record deferred measurements
explicitly and do not claim an unmeasured speedup.

Guardian feedback entries and commits are not required. Do not modify
`guardian-zig/FEEDBACK.md` unless the user explicitly requests it.

Each agent should finish with a reviewable commit and a short report containing
the tested commit, exact commands, executed/failed/skipped counts, remaining
limitations, and integration requirements. Do not merge another agent's branch
or change production routing without the integration task authorizing that work.

## Agent A — Qualify a current-language Selka lexer

**Priority:** first. This is the clearest next step toward moving the production
frontend into Selka.

**Copyable task brief:**

> Starting from the shared baseline above, qualify a Selka lexer against the
> current Zig lexer. Inspect the existing `selfhost/lexer.my` closure and
> `selfhost/tests/run_lexer_diff.py` first. Establish current parity, expand the
> valid and malformed corpus, and implement missing behavior in a current
> component-profile lexer. Keep the historical pinned lexer workflow working.
> Prefer a new `selfhost/components/lexer_pilot/` implementation when migration
> would otherwise break the historical source profile. Do not change production
> lexer routing, the seed pin, cache code, or shared build files. Deliver the
> implementation, reproducible differential tests, and a parity report.

**Owned files:**

- `selfhost/components/lexer_pilot/` for the current-profile library and adapter.
- `selfhost/tests/run_lexer_pilot.py` and
  `selfhost/tests/fixtures/lexer_pilot/` for the new differential harness/corpus.
- Historical lexer/harness changes only when needed to preserve compatibility;
  describe those changes separately and coordinate ownership before editing.

**Required work:**

1. Build the existing baseline and record what the current differential harness
   actually compares. Its `--compiler` mode adapts historical source in a
   temporary directory; passing that mode alone is not proof that the unmodified
   component builds with the qualified seed.
2. Cover current keywords, operators, indentation/dedentation, comments, numeric
   spellings, strings/bytes/escapes, format strings, source encodings, end-of-file
   behavior and malformed input. Include current limits and boundary conditions.
3. Compare token kinds, ordering, byte start/end positions and lexical errors
   with the current Zig implementation. Keep fixture bytes immutable; temporary
   source adaptation must never change the input being compared.
4. Separate lexical errors from parser/checker failures. Record any exclusion
   with its exact reason; no blanket skips or silently accepted mismatches.
5. Keep the lexing algorithm independent of transport. Bound requests and replies,
   validate source spans, and report malformed transport separately from a source
   program's lexical error.

**Acceptance:** the agreed corpus has identical tokens and byte spans, with
explicitly compared error codes/locations and documented diagnostic differences.
The new library builds with the qualified seed using only its declared profile;
its pure tests pass normally and under release fact/leak checks. A component
implementation edit can be rebuilt and tested without rebuilding the Zig host.
Production use remains unchanged until a separate adoption review.

**Starting command:** after building the current compiler through admission,
run the existing harness with its live compiler option:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_lexer_diff.py --compiler zig-out/bin/mylang
```

Provide separate commands for the new pilot and its seed qualification. Do not
assume the existing component builder already knows about a third component.

## Agent B — Salvage and qualify a parser slice

**Priority:** run alongside Agent A. This task can use baseline token fixtures
while the lexer evolves; it does not need to wait for the lexer port to finish.

**Copyable task brief:**

> Audit the preserved self-hosted parser and salvage only the closure needed for
> a small current-language parser pilot. The historical donor was recorded at
> `fe94e0d0` on `selfhost/integration`; verify the source revision before using it.
> Inspect current Zig AST/parser behavior and the qualified component profile.
> Implement a standalone Selka parser slice under
> `selfhost/components/parser_pilot/`, with fixtures and a documented provisional
> syntax-value format. Do not import the historical checker/lowerer/backend or
> route production compilation through the pilot. Deliver working code, parity
> evidence for the chosen grammar slice, and a concrete inventory of remaining
> grammar and integration work.

**Owned files:** `selfhost/components/parser_pilot/`,
`selfhost/tests/run_parser_pilot.py`, and
`selfhost/tests/fixtures/parser_pilot/`. Read lexer files and current Zig frontend
code; coordinate with Agent A before requesting lexer changes.

**Required work:**

1. Audit donor imports, syntax assumptions, scope rules, diagnostics and runtime
   dependencies. Use `git show` or an isolated donor checkout. Do not copy the
   entire historical toolchain into the current tree.
2. Choose and document a coherent first slice: literals, names, precedence,
   calls, explicit bindings, simple function declarations, returns and blocks
   are a useful starting point. Reject unsupported constructs explicitly.
3. Use explicit syntax records or node tables with indices and source spans.
   Describe ownership, invalid indices, maximum counts and error representation.
   The format is a pilot contract, not a frozen production ABI.
4. Establish a structural oracle for the supported slice using existing Zig
   facilities. If no suitable AST export exists, report the missing adapter
   precisely; do not claim acceptance/rejection parity proves AST equivalence.
5. Audit all syntax consumers that a later production switch must cover:
   single-file compilation, import/module discovery, projects/interfaces,
   formatting and syntax caches. Produce a call-site list against this baseline.

**Acceptance:** a supported source slice parses with the qualified seed; valid
and malformed fixtures exercise precedence, spans and failures. Structural
comparisons are explicit about what they prove. Remaining grammar and required
Zig adapters are enumerated. No changes to the production frontend are required
to review or run the pilot.

**Important donor caveat:** the September partial-self-hosting plan contains
useful salvage ideas but an obsolete QBE diagram. Reuse source and fixtures
only after checking them against today's Core/LLVM and bootstrap contracts.

## Agent C — Prove compiler-oriented Selka library building blocks

**Priority:** run alongside both pilots. Turn suspected language/library gaps
into small, reproducible engineering tasks.

**Copyable task brief:**

> Build standalone compiler-shaped Selka probes using the qualified component
> profile. Exercise source-byte access, token arrays, syntax-node pools,
> dictionaries, worklists, sorting and diagnostic construction. Demonstrate
> correctness at useful input sizes and identify unsupported operations or
> accidental repeated copying. Keep probes under `selfhost/probes/compiler/`.
> Do not introduce language features, modify the runtime, or expand the seed
> profile in this task. Deliver reusable examples and a ranked gap report with
> minimal reproductions and concrete workarounds.

**Owned files:** `selfhost/probes/compiler/` and an optional standalone driver
`selfhost/tests/run_compiler_probes.py`. Leave shared library, compiler and
runtime implementations to separately assigned follow-ups.

**Suggested probes:**

- Source byte offsets, line lookup, non-ASCII spans, slicing and stable source
  ownership; distinguish byte positions from code-point positions.
- Append/read/update token arrays and indexed syntax-node pools using explicit
  `mut`, including nested records/collections and copy-on-write behavior.
- Name-to-ID tables, deterministic traversal, stable ordering and work queues.
- Building diagnostics from many fragments without repeatedly copying the
  entire prefix; preserve locations and deterministic output.
- Repeat the same operation over increasing input sizes with assertions and
  available work/allocation evidence. A wall-time trend alone does not prove
  an asymptotic complexity claim.

**Acceptance:** probes build with the declared seed, give reproducible expected
outputs, and pass normal plus release fact/leak checks where supported. Every
reported blocker includes a minimal example, current behavior, required behavior
and a workable alternative or an explicit absence of one. Separate confirmed
limitations from unmeasured performance suspicions.

## Coordination and later integration

Send the lexer and parser agents each other's token/span/error contract early.
Agent B can start with fixture token tables; Agent C can start independently.
Do not make every task depend on agreeing a final AST wire protocol first.

The integration order is:

1. Land qualified probes and fixture/harness improvements.
2. Qualify the lexer component, then add a Zig adapter and comparison mode as a
   separate task. Adoption requires end-to-end compatibility and measured
   transport/edit-loop cost.
3. Expand the parser pilot to complete grammar and diagnostics, then integrate
   all syntax consumers through one validated boundary.
4. Migrate contained analyses, followed by larger checking/lowering slices.
5. Pursue full staged self-compilation and reproducibility when enough of the
   compiler is in Selka; none of the first three tasks requires that milestone.

Before production adoption, component identities must participate in syntax,
semantic and test-result validity. The unchanged Zig host digest alone cannot
identify a compiler whose lexer or parser component changed. Coordinate that
integration with the cache work after its current wave is qualified.

## Continuation through complete bootstrap — 11 October 2026

The later user instruction extends this initial parallel pilot plan through a
complete Selka compiler and requires compile time, test time and generated
runtime to stay within 1.5 times the Zig implementation. This is an acceptance
requirement for the completed compiler, not a claim about the current pilots.

The last qualified boundary is B4, recorded in
[the record body audit](selka-body-records-2026-10-11.md). Seven packages build
with the unchanged qualified seed; ordinary scalar, text, byte, list and
nongeneric record bodies use Selka checking without native body fallback.
Complete typed metadata, ordered list recipes and final catalog schemas match
native checking. Constructors/defaults, field access and mixed record/list
mutation include finite recursion through lists and snapshots. B5 variants,
patterns and checked failures are in progress in separate Sol lanes. The
compiler still cannot check its own source, and neither a complete compiler
nor a bootstrap fixed point is proven.

| Remaining stage | Completion evidence |
| --- | --- |
| B5 variants, patterns and checked failures | Nongeneric variants, exhaustive/nested matches, Result/Option construction, fail/try and result consumption match complete native typed tables, catalogs and diagnostics. |
| B6 byte/string and buffer operations | Slicing, conversions, byte-buffer construction, mutation and snapshots cover the compiler's pure algorithm libraries. Complete native typed metadata and diagnostics match; existing pure tests pass in debug and release with fact/leak checks. This does not yet qualify executable entrypoints. |
| B7 capabilities and scoped resources | Filesystem/Stream signatures, file opening/reading, stream output and scoped file cleanup cover all seven component entrypoints. The selected Selka body checker checks and builds the actual component source closures without native body fallback, preserving capability, ownership and cleanup metadata. This is component-source bootstrap coverage, not a complete compiler bootstrap. |
| Remaining body language | Other collections, generic specialization, callbacks, scalar widths, additional resources, contracts and all remaining forms cover the current language. Unsupported profile refusals cannot count as success. |
| Remaining semantic ownership | Selka owns declaration/catalog construction, entry handling, effects/origins, contracts, codecs and warnings, with diagnostics and accepted/rejected programs matching the native reference. |
| Core and LLVM backend | Selka lowers checked programs, performs required Core transformations and emits LLVM; generated programs pass the complete behavior, ownership, fact and leak suites. |
| Compiler driver | Selka owns source/module loading and build/test/cache orchestration, invokes the external toolchain, and performs supported installed commands without a native compiler fallback or Python dependency. |
| Staged bootstrap | The pinned Zig seed builds stage 1; stage 1 builds stage 2; stage 2 builds stage 3. Retained source/toolchain/artifact identities and explained reproducibility comparisons establish the fixed point, and the resulting compiler passes the full language and tooling gates. |
| Performance acceptance | Isolated matched native/Selka measurements cover representative compiler sources and projects, compile/check/edit workflows, cold and warm tests, and generated release runtime. Every required workload stays within 1.5 times native; averaging away a failed row is not acceptance. |

The C runtime and pinned external Zig/LLVM tools may remain dependencies. Full
self-hosting requires Selka ownership of the compiler, not rewriting those
dependencies. The native implementation remains an independent qualification
oracle during migration; selected production paths must not silently fall back.

The latest qualified [B4 performance measurements](selka-body-records-2026-10-11.md#isolated-performance)
fail 20 of 24 strict median/p95 rows. Compile/check/test medians are approximately
4.4–7.2 times native; the four short generated-runtime rows pass. Both sides use
the same B4 ReleaseFast host, with only the candidate body checker selected as a
component. These are component measurements with warm shared native units, not
whole-compiler or cold-toolchain benchmarks. Performance work therefore runs
alongside feature coverage, with exact mode/cache provenance and behavior checks.
Intermediate subset benchmarks cannot establish full-language acceptance.

The proposed B6/B7 split follows actual compiler source dependencies. Byte slices
appear in `body_check/graph.my` and the codecs; buffer construction and writes
appear in `parser_pilot/syntax_codec.my`, `type_interface/codec.my`,
`declaration_index/codec.my` and `cache_plan/incremental.my`. Those pure libraries
can be qualified before resource support. Executable adapters such as
`body_check/main.my` additionally require `Filesystem`, `Stream`, `fs.open`,
`with file as input`, `input.read` and output methods. The native representation
and validation contract for each wave must be audited before its schema is
frozen; these planned boundaries are not completed implementation claims.

The B3 strict measurements also fail: only the three generated-runtime rows pass
out of 18 workflows. Compile/check/test medians are about 6–10 times native with
the standard producer and 3.4–5.1 times native with a separately qualified
whole-unit release producer. Both require further work; the release experiment
is a substantial improvement, not performance acceptance. The list audit retains
all median/p95 verdicts, exact receipts and isolation records. Transitioning to a
fused compiler removes intermediate process/transport boundaries, but remaining
Selka algorithm, allocation and generated-runtime costs must still be measured.

The B4 matched-host sweep fails all 20 compile/check/test rows across four
workloads, with medians around 4.4–7.2 times native. Only the four short
runtime rows pass. The record audit retains all 24 median/p95 verdicts,
20 samples per row, exact package provenance and FIFO isolation receipts.
Both sides use the same B4 ReleaseFast host, unlike B3's older B2 baseline;
no full-language performance or bootstrap acceptance is claimed.
