# EDA friction repair plan, revision 2

Prepared 2026-09-30. Written for the agents who will implement it.

This revision supersedes revision 1 (`docs/audits/eda-friction-repair-plan-2026-09-30.md`
on `codex/next-eda-compiler-20260930`, commit 395f68f4), which Codex wrote from the
finished EDA port's [friction report](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/FRICTION.md)
and [gap log](/home/epentland/ai/canopy/eda-bench-wt/codex-next-eda-integration-20260930/mylang/GAPS.md).

What changed from revision 1:
- Every finding was reproduced on current main. Stale ones are corrected, and the
  reproducers are in [experiments/eda-friction-repros-20260930](../../experiments/eda-friction-repros-20260930/README.md).
- Two problems revision 1 missed are added:
  - the compiler's recommended write-back idiom is quadratic for list and dict slots;
  - most of the port's copy/store-back code is unnecessary today.
- The work is sequenced after the module-build branches it overlaps, and its scope is cut:
  - concurrency (WP8) and the harder filesystem guarantees are deferred;
  - Zig-compatible formatting stays in the application.
- Revision 1's open semantic questions are decided below, so lanes can start without
  asking. The user may override any decision before handing the plan out.

The port passes 319 fresh tests (all 279 original obligations) and 34 byte-identical
reference cases on Debug compiler e88fcf3c. None of this work may lose that.

## Decisions this plan makes

| # | Decision | Why |
| --- | --- | --- |
| D-a | `check-module` must accept and reject exactly what the program route does. Prelude names (`str`, `bytes`, `int`, `set`, …) stay reserved: `def str(...)` is `E_DUPLICATE_NAME` at the declaration in every route. A local declaration never shadows a builtin conversion. | The program route already does this. G25/G26 exist only because `check-module` skips that validation. |
| D-b | Fields and parameters share one default grammar (the parser already uses one `defaultArgument`). It covers scalar, float, bytes and text literals; negated numeric literals; enum cases; module constants of immutable type; the empty collections `[]`, `{}` and `set()`; fixed-array literals of allowed defaults; and a record constructor whose arguments are allowed defaults. Each construction or call evaluates the default afresh. | Value semantics means a fresh value per use, so Python's shared-mutable-default problem cannot arise. |
| D-c | A line `*` in a record body makes the fields after it keyword-only, and keyword-only fields may mix required and defaulted ones. Without the marker, required-after-defaulted stays `E_DEFAULT_ARGUMENT`. | This is the existing function rule (`def f(a: int = 0, *, b: int)` works today), like `dataclass(kw_only=True)`. It needs no new positional-prefix rule. |
| D-d | `mut` accepts record-typed field and element paths (`mut t.cur`, `mut comps[k]`, `mut table[key]`). The slot is moved out and back, never copied, and MUT-EXCLUSIVE still rejects overlapping places. | Copy-based lowering is quadratic (see WP4a). |
| D-e | The stdlib gains `sort.sort_by(items, less)` and `sort.sort_by_ctx(items, ctx, less)`, stable and in-place, with `less` a named function or noncapturing lambda. There is no key-with-context variant. | All three real context sorts in the port are comparators over indices with explicit tie-breaks. Keyed variants need composite keys, and there are no tuples. |
| D-f | The stdlib gains SHA-256, CRC-32 (IEEE 802.3, reflected, init and xorout `0xFFFFFFFF`), bit-preserving integer conversions between signed and unsigned of the same width, and float ↔ `u64` bits. | These are generic, and a native implementation is cheap. |
| D-g | Zig's `{d:.N}` float formatting and Zig's hex-float parser stay in the EDA application, not the mylang stdlib. | They reproduce one source language's quirks. mylang already has Python-style f-string specs (`{x:.2f}`, `{x:.3e}`, `{255:x}`). |
| D-h | Concurrency (revision 1's WP8) is out of scope. Symlinks, traversal hardened against races, and crash-durable transactions (WP7b) are deferred. | No port test fails without them; the port passes single-threaded. Concurrency needs its own ADR and the user's decision. |

Record every decision a lane implements as `SPEC.md` rules and in the matching guide
page. A lane that finds a decision unworkable stops and reports rather than choosing
differently.

## What was verified (main 5041d690, ReleaseFast; the port's e88fcf3c agrees)

Still broken:
- `set[bytes]()` in a library: `InternalError` via `check-module`.
- `def str` in a library: accepted by `check-module`.
- Bytes, enum and collection defaults.
- Required-after-default fields.
- A None-only comprehension infers `list[unit]`.
- `assert x is not None` does not narrow.
- A record-field guard does not narrow.
- A fixed array compared with a list literal fails.
- `mut t.cur` on a record-typed path.
- `u64(-1)` traps.

Already fixed, so leave these out of any work package:
- nested `for _` (G17);
- sequential loops reusing a name;
- `f(x) == Some(v)` (G16);
- float and `-0.0` defaults;
- f-string format specs;
- `str` quadratic on non-ASCII (G11);
- sorting and comparing `bytes` (G07/G08).

Deliberate and unchanged:
- A loop variable may not reuse an earlier *assigned* local's name (G05). Only its
  message improves (WP1).

## Prerequisites (before any lane starts)

**Merged into `main` with this plan (the user's OK, 2026-09-30):**

1. `claude/symbol-invalidation` (4f97aa7a): per-symbol cutoff for body edits
   (MODULE-SYMBOL-CUTOFF-1..5).
2. `claude/interface-cutoff` (a319d027): per-symbol cutoff for interface edits
   (MODULE-INTERFACE-CUTOFF-1..4, MODULE-ARCHIVE-TRIM-1).
   - Its commit 630bd41a (MODULE-EMISSION-RECORDS-1) also fixes the incremental
     build's `InvalidNativeManifest` after a record gains a field.
3. `claude/edit-fuzz`: the random edit tester, `experiments/edit-fuzz-20260930/`.

Gate results for the merged source:

| Check | Result |
| --- | --- |
| `zig build test -Dtest-rerun` | 115/115 steps |
| `test-qbe` / `test-qbe-build` / `fmt-check` | 51/51, 29/29, 2/2 |
| `tests/lang` | 1486/1486 in each of default, `--gc-runtime` and `--release` |
| Lox port | 65/65 tests and 13/13 driver cases, under RC and GC |
| Both Lox oracles (34 + 6 edits) | all matched, RC and GC |
| `default-oracle` | 6/6 matched |
| InvalidNativeManifest reproducer | builds, RC and GC |
| Fresh-seed tester, single edits | 8 runs × 50 steps, 0 mismatches |
| Fresh-seed tester, 3 edits per step | 4 runs × 30 steps, 0 mismatches |
| Lane's own tester runs | 1,680 steps, 0 mismatches |

**Still to merge before the lanes start, each with the user's OK:**

4. `claude/test-zig-cache` (f2e53ada): `zig build test` no longer leaks `zig cc`
   objects. Gated by its own session.
5. `codex/next-eda-compiler-20260930` (Phase C: native sin/cos, G29/G30 repairs, and
   revision 1 of this plan).

`git merge-tree` reports no conflicts between (5) and (1)–(4). After those merges, the
combined main is the base for every lane below.

## Rules for every implementing agent

- **One worktree per lane**, under `/home/epentland/ai/canopy/mylang-worktrees/`.
  - Reuse a merged, clean pool tree (`git switch -c <branch> main`) only if
    `git worktree list --porcelain` shows no `locked` line for it.
  - Claim it with `git worktree lock --reason "<agent>: <branch>"`, and unlock it when
    the lane is merged or abandoned.
- **Never edit** `/home/epentland/ai/canopy/mylang` (someone's uncommitted work) or
  another agent's worktree. Never run bare `git stash`, `pkill` or `killall`, or kill a
  process you did not start. There is no remote. Never merge into `main`; the user
  approves each merge.
- **In every shell**, export `ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache`
  and set `TMPDIR` inside your worktree. Never share `.zig-cache` or `.mylang-cache`
  between worktrees.
- **Run every `zig build` and heavy `mylang test`** through
  `scripts/build-slot.sh build|gate …`. At most four build-heavy agents fit on this box.
- **Compiler builds:**
  - Use Debug for the gate.
  - For timing, and for any compiler an application agent uses, build
    `zig build -Doptimize=ReleaseFast --prefix <immutable dir>`.
  - Guest `--release` is a separate setting.
- **Python** is fine in tests and experiments. Building, compiling and using mylang
  must need only Zig or mylang.
- **Guardian (CLAUDE.md):**
  - every behavioral change carries a `// spec: TAG` test and a `- [TAG]` bullet in
    `SPEC.md`;
  - structs have ≤ 7 fields and functions ≤ 6 parameters;
  - every `pub` declaration has a `///` doc;
  - no empty `catch {}`;
  - test bodies are straight-line.

  Guest-behaviour tests go in `tests/lang/*.my`; diagnostics and caches go in
  `src/root_test.zig`; CLI behaviour goes in `test/integration.zig`.
- **Lane gate, before reporting done:**
  - `zig build test`, `test-qbe`, `test-qbe-build` (with `-Dtest-rerun` if it
    finishes suspiciously fast) and `fmt-check`;
  - `zig-out/bin/mylang test tests/lang --force` in default, `--gc-runtime` and
    `--release` modes;
  - the Lox port's `mylang test . --max-steps=100000000` and its driver cases, under
    RC and GC;
  - `experiments/eda-friction-repros-20260930/run.sh`, which should show your WP's rows
    flipped and nothing else changed.
- **Anything that changes interfaces, fingerprints, defaults or module compilation**
  must also pass:
  - `experiments/symbol-invalidation-20260930/oracle.py`, under RC and GC;
  - `experiments/eda-friction-repros-20260930/default-oracle/oracle.sh`;
  - the random edit tester `experiments/edit-fuzz-20260930/edit_fuzz.py`, with
    ≥ 2 seeds × 50 steps each on Lox and synthetic projects,
    under RC and GC.

  A byte mismatch against `--whole-program` blocks the lane.
- **Commit** in small, explained commits. Report (per WP):
  - the before/after EDA expression;
  - remaining workaround counts;
  - spec rules added;
  - negative tests;
  - gate counts;
  - anything skipped or refused.

## Work packages

### WP0: ReleaseFast baseline (coordinator)

On the merged main, install a ReleaseFast compiler into an immutable prefix. Build the
EDA port with it and confirm 319 fresh passes and 34/34 byte-identical cases. Then
record:
- the port's 12 development-loop metrics;
- a focused one-module check;
- an unchanged cached test run.

Take at least three samples of each and report the median and spread. Keep the
compiler hash, the exact commands, and the fresh/cached test counts. Record machine
load only when a comparison sits inside the noise.

The Debug numbers (334.6 s cold; 7–14 s incremental builds; 62–119 s edited-test
commands; 66.7 s for an all-cached test run) are not baselines for this work. Neither
ReleaseFast nor the module-build cutoffs had landed when they were taken.

### WP1: one checking route, better diagnostics (compiler-frontend lane)

- **Route agreement:** make `check-module` run the declaration and constructor
  validation the program route runs, so these become the program route's diagnostics:
  - `wp1/svg_probe.my` gives `E_UNKNOWN_FUNCTION` at `set[bytes]()`;
  - `wp1/str_probe.my` gives `E_DUPLICATE_NAME` at the declaration (D-a).

  Find the fork in the code rather than patching the two symptoms. Keep genuine
  internal invariant failures visible: no blanket relabelling of `InternalError`.
- **Route-differential test:** for every `# doc: expect-error` example under `docs/`
  (about 20 pages), and any other rejected-program corpus the lane finds, check it as a
  program and as a module (wrapped mechanically) and require the same diagnostic code
  and location. This catches the
  whole class of divergence.
- **Messages:**
  - `set[bytes]()` and the other typed collection-constructor spellings suggest
    `set()` / `[]` / `{}`, with the element type taken from the annotation.
  - `E_DUPLICATE_NAME` for a prelude name suggests a rename.
  - `E_SHADOWING` names the earlier declaration's line and suggests a rename
    (`wp1/shadow_earlier_local.my`).
  - An unknown builtin such as `repr` reads as a missing builtin, not a missing module
    declaration.

Done when both routes agree on the whole reject corpus and the wp1 rows read as above.

### WP2: record and parameter defaults (compiler-frontend lane, after WP1)

- **Grammar:** implement D-b and D-c.
  - Bytes literals first, because the records guide already promises them.
  - Then enum cases and immutable module constants.
  - Then fresh-collection recipes and record-constructor recipes.
- **Checks:**
  - check each default against its declared type;
  - a default may not read a local, a capability or anything effectful;
  - invariants still run on constructed values.
- **Cross-module:** carry each default's recipe in the interface, inside the owning
  declaration's per-declaration fingerprint. After interface cutoff, a reader stays
  fresh when the fingerprints it used held, so a default edit must change the
  fingerprint. Extend `default-oracle/oracle.sh` with bytes, enum, collection and
  keyword-only edits.
- **Tests:**
  - two records constructed from the same default stay independent after one is
    mutated, under RC and GC and on QBE and LLVM;
  - positional construction still binds the declaration-order prefix before `*`.

Done when the wp2 rows flip, the port's `*_default` factory functions can be deleted,
and the oracles and tester match.

### WP3: Option and literal inference (compiler-frontend lane, after WP2)

- **Expected element types:** propagate an expected element type into list, dict and
  set literals and comprehensions (`wp3/none_comprehension.my`).
- **Fixed arrays:** context-type a literal compared with a fixed array, in either
  operand order and without evaluating either side twice (`wp3/array_compare.my`).
- **Assertions:** make `assert x is not None` narrow `x` on the continuing path
  (`wp3/assert_narrow.my`).
- **Field paths:** narrow a guarded field path rooted in a value-record local
  (`wp3/field_guard.my`). The fact dies when:
  - the root, the path or an ancestor is written;
  - a `mut` call receives any of them;
  - a loop body writes them;
  - control flow joins with a path where the fact does not hold.
- **Scope and conformance:**
  - dictionary lookups, list elements and calls stay unnarrowed;
  - ordinary and symbolic-generic checking share the rule;
  - negative tests show each invalidation rejecting an unsafe read.

Done when the four wp3 rows compile, the negative tests reject, and the port's typed
temporaries for these cases can be removed.

### WP4: mutation through paths (ownership lane)

**WP4a: fix the quadratic write-back first.** This is a standalone performance bug and
can start immediately.
- The compiler's own `E_MUTATION_MARKER` advice (copy into a local, pass `mut`, store
  back) costs a full copy per iteration when the source is a list element or dict value.
- The field form is already moved by `RC-CLOSED-FIELD-TRANSFER-1/2`, which extracts,
  mutates and stores back under a certificate.

| Pattern at 80k iterations | RC | GC |
| --- | ---: | ---: |
| field slot | ≤ 0.01 s | — |
| element or dict slot | 4.9–9.1 s | 4.3 s |

Extend the closed-transfer certificate to list-element and dict-value slots with a key
that is stable across the interval, and give GC an equivalent move.
- Programs: `wp4/writeback_element_80k.my`, `wp4/writeback_dict_80k.my` and
  `wp4/copy_append_store_80k.my` must drop below 0.1 s under both runtimes.
- Keep the certificate's existing refusals: observers, views, second writable
  parameters, returns and `?` exits, arena transitions, and indirect or host calls.
- Add the 80k programs as performance regressions with a generous bound.

**WP4b: `mut` on record-typed paths (D-d).** Accept `callee(mut state.child)` and
record-typed element and dict slots (`wp4/mut_record_field.my`). Lower through the same
move, not a copy.
- **Evaluation:** evaluate receiver and index expressions exactly once, in source
  order.
- **Exclusivity:** extend MUT-EXCLUSIVE to reject parent/child overlaps and uncertain
  same-container overlaps (two variable indices). Disjoint fields and distinct constant
  indices stay allowed.
- **Snapshots and invariants:** other arguments' by-value snapshots, runtime trap
  cleanup, parent and child invariants, and arena escape rules all stay as they are.
- **Tests** cover nested records with managed fields, list and dict slots, two disjoint
  fields, overlapping paths, side effects in later arguments, and invariants. Run them
  under RC and GC, on QBE and LLVM, including cached cross-module calls.

Done when the wp4 rows read as the README says. The port's record copy/store-back
sites (`sexpr_tokenizer.my:267`, `export_kicad_sch.my:284`, and the `Multiset` fields
in `kicad_sch_verify.my`) then become single calls with identical output.

### WP5: sorting with explicit context (library lane)

Move the port's `support_sort.sort_by` and `sort_by_ctx` (stable merge sorts; in the
EDA worktree `mylang/src/support_sort.my` with `support_sort_test.my`) into
`src/stdlib/sort.my` under D-e, with doc examples. Use a native sort where its
contract fits, or keep the guest merge sort and benchmark it against
`sort_by_key`/`sorted`.

Tests:
- equal-key stability;
- bytes, str and float comparators, including the existing NaN policy;
- a managed context value;
- generic callers;
- a comparator whose effects exceed its bound is rejected;
- module-interface cache reuse.

Done when the port's three callers (`kicad_sch_bank.my:139`, `kicad_sch_plan.my:80`,
`kicad_sch_stagger.my:84`) and its five `sort_by` callers use the stdlib, and
`support_sort.my` is deleted with unchanged output.

### WP6: hashes and bit conversions (library lane, after WP5)

Implement D-f natively in the runtime (Zig's std has both hashes) behind small stdlib
modules; choose names that read well in `docs/`.
- **Hashes:**
  - validate against published vectors (the NIST SHA-256 vectors; CRC-32 `"123456789"`
    → `0xCBF43926`);
  - boundary inputs: empty, large, and payloads with NUL or invalid UTF-8.
- **Bit conversions:**
  - signed ↔ unsigned of the same width round-trips every bit pattern and never traps
    (`wp6/int_bit_reinterpret.my`);
  - float ↔ `u64` bits round-trips signed zero, subnormals, infinities and NaN
    payloads.

Done when the port's handwritten `support_sha256.my`, `support_crc32.my` and its
bit helpers are replaced, with all support tests still passing. The port's Zig-compatible formatter and hex-float
parser stay (D-g), but may use the new float-bits API.

### WP7a: bounded reads and basic file operations (I/O lane)

Add the following through the existing `Filesystem` grants, including the in-memory
filesystem (`filesystem.memory()`):
- `read_file` with a byte limit enforced *while* reading, before the whole file is
  allocated; it must handle files that grow or shrink during the read and an exact-limit
  file;
- `stat` with entry kind, choosing whether to follow symlinks;
- `rename`;
- atomic whole-file replace (write a temporary file, then rename it into place).

Requirements:
- read-only views refuse writes;
- cross-directory renames respect both grants;
- temporaries are cleaned up when an operation is refused;
- a provider lacking a guarantee returns an explicit `Unsupported` error;
- denial and failure-injection tests for each operation.

Done when the port's D4 fail-closed stubs for these operations become real calls, and
its tests assert the real behaviour. WP7b (symlink creation, race-hardened traversal,
crash durability) is deferred (D-h).

### WP9: private-intrinsic projection (compiler, only after `claude/interface-cutoff` merges)

Do this only when a new stdlib wrapper needs it. Revision 1's intent stands:
- validate projected interface bodies against the exact embedded stdlib
  source/declaration and the compiler identity;
- never grant private-name authority from cache text, file paths or self-declared
  flags;
- test tampered and stale caches.

It edits the same interface files as the cutoff work, so it must not run concurrently
with another lane touching `module_*` or `native_interface.zig`.

### WP10: compiler overhead (coordinator, after WP0)

`mylang test` builds through `module_build.openTests`, so the per-symbol cutoffs in the
prerequisites already change this path. On the Lox port (ReleaseFast):

| Edit | Before cutoffs | After cutoffs |
| --- | --- | --- |
| private body edit | 16 of 18 modules, 0.19 s | 1 module, 0.05 s |
| signature edit | 13 modules, 0.29 s | 1 module, 0.06 s |

Profile the WP0 baseline:
- break the time down by discovery, validation, frontend, interface and dependency
  planning, object and link work, test enumeration and result reuse;
- fix only what the profile shows dominates;
- measure cold, no-op, and leaf/hub/interface edits separately;
- report fresh versus cached test counts next to wall time.

Keep every content and transitive-dependency check. A stale fast answer is a failure.
Remaining known fallbacks from the cutoff lane, which are candidates if the profile
points there:
- a kept (inlined) body, template, constant, domain member, re-export or type edit
  still recompiles every reader;
- a module that invokes function values keeps the whole-module rule;
- test runs take no interface cutoff.

### WP11: simplify the port and qualify (coordinator, rolling)

After each WP lands, simplify the matching EDA sites and rerun the port's full suite
and 34 cases.
- **Start now, with no compiler change:** the port's copy/store-back sites for
  collection-typed fields and elements already have direct forms
  (`wp4/direct_collection_paths_work.my`).
  - `labels = self.labels; f(mut labels); self.labels = labels` becomes
    `f(mut self.labels)`.
  - `seen = comp.seen; seen.add(p); comp.seen = seen` becomes `comp.seen.add(p)`.
  - `bucket = buckets[h]; bucket.append(i); buckets[h] = bucket` becomes
    `buckets[h].append(i)`.

  The last one is also the quadratic pattern. Known sites include `labels`, `owners`,
  `src` and `segs` in `export_kicad_sch.my` and `kicad_sch_compose.my`,
  `export_kicad_sch.my:287-292`, and `kicad_sch_plan.my:73`. Update `docs/value-semantics.md`
  and the porting guide to show these forms next to the record-only restriction.
- **Tracking:** count removed factories, typed temporaries, store-back sites and
  support modules.
- **Final qualification:**
  - one frozen combined compiler source, installed ReleaseFast;
  - the full compiler gate;
  - both Lox runtimes;
  - the 100-seed fuzz;
  - the port's 319 tests and 34 cases;
  - the 12 metrics against WP0.

## Lanes

At most four build-heavy agents at once.

| Lane | Owns | Order | Shares files with |
| --- | --- | --- | --- |
| Coordinator | prerequisites check, WP0, WP10, WP11, integration branch, lane gates | WP0 first; WP11's no-compiler cleanup at once | everyone (read); merges lanes into an integration branch for the user |
| Compiler frontend | WP1 → WP2 → WP3 | sequential: parser, checker and inference overlap | WP4b (checker's `mut` rules): rebase on this lane's checkpoints |
| Ownership | WP4a, then WP4b | WP4a starts immediately; WP4b after WP1 lands | RC/GC lowering; nobody else |
| Library and I/O | WP5 → WP6 → WP7a | sequential | runtime natives; stdlib |

WP9 runs only when needed and never alongside a lane touching module-interface files.

A lane reports each WP separately with the items listed under "Rules". The
coordinator gates each checkpoint itself before asking the user to merge anything.
