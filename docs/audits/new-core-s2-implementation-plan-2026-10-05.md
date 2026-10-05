# New compiler core, stage S2: implementation plan for Codex agents (2026-10-05)

This plan is for the Codex coordinator and its agents. It turns the accepted S2 design
(`docs/design/new-core-s2.md`) into work packages, an order, gates and rules. **The design
note is the specification**: every package below cites its sections. Where this plan and
the design note disagree, the design note's §11 (integrator review) and §12 (the user's
decisions) win.

## Launch instruction

> Implement stage S2 of mylang's new compiler core following
> `docs/audits/new-core-s2-implementation-plan-2026-10-05.md` on branch
> `claude/new-core-s2-20261005`. Work packages S2-0 and S2-L first, then S2-D, S2-T and
> S2-F in parallel, then S2-X. Use one locked worktree per package and integrate on
> `codex/new-core-s2-integration`. Hold every gate in §5. Never merge into `main`. Finish
> with the S2 exit report in §7 and stop for the user's go/stop decision on S3.

## 1. Where things are

**Base.** Branch `claude/new-core-s2-20261005`, at the commit that adds this plan. It
contains, all accepted:
- **S0:** `mylang-core`, Core IR, facts, LLVM emission, the runtime `src/core/runtime/core_rt.c`.
- **S1:** records, unions, `Option`/`Result` with `?` and traces, lists, one-count RC, `mut`,
  the allocator, stack promotion, and the conformance runner.
- **The S2 design note**, `docs/design/new-core-s2.md`.

**Where S1 left things.**
- **Conformance:** full `tests/lang` has 745 of 1,470 test functions supported, and all 745 match the old core at debug and release (`experiments/new-core-s1-20261005/results/conformance-all-8a87a4fd.txt`).
- **Sweeps:** the leak and `--verify-facts` sweeps are clean.
- **Rows:** all 14 S1 rows are at or below Zig ReleaseSafe.
- **Coverage:** 2,269 of 3,509 functions (`experiments/new-core-s0-20261005/coverage.py`).
- **test-core:** 147 tests in about 60 s; a rebuild after an edit takes 1–5 s.

**Integration.** The coordinator creates `codex/new-core-s2-integration` from the base and owns it. Each package gets its own branch and locked worktree, cut from the integration branch's current head. Claim worktrees with `git worktree lock --reason`.

**Read before any package:**
1. `docs/design/new-core-ir.md`: the S0 design (IR, facts, verify mode, portability rule).
2. `docs/design/new-core-s1.md`. Read all of it, including:
   - §2.1, the frozen S1 IR shapes;
   - §6.1–6.2, ownership and traces as built;
   - §13, the binding review decisions;
   - §14–15, how values and `mut` were really built (`mut` is **by value**: copy-in/copy-out);
   - §15.1, what stays refused.
3. `docs/design/new-core-s2.md`: the S2 design, with §11 (review) and §12 (decisions).
4. `docs/audits/new-core-plan-2026-10-05.md` (on `claude/runtime-levers-plan`): §6, the stage table and S2 exit check.

## 2. Decisions already made (do not reopen)

**From the user, 2026-10-05** (design note §12):
1. **S2 includes function values and fixed arrays `[N]T`.**
2. **Hashing stays unseeded** (PY-DICT-2).
3. **No short strings in S2.**
4. **The view ABI** (a `str` parameter accepting `(ptr, len)` views) is evaluated **only if `string_split` misses the gate.** It needs a design-note entry and the coordinator's sign-off first.
5. **O(n/32) random indexing into long non-ASCII text is accepted.** No sample array.
6. **Language change `MUT-OVERLAP-RECEIVER-1`** (package S2-L).

**Earlier decisions that still bind:**
- L1–L4, D1–D4, N1–N6 (N6: arenas retired; the new core lowers `with arena()` as a plain block) and R1 (the new core has its own runtime: port algorithms, never link the old runtime).
- S1 §13 R-1 to R-6.

**Open language questions. Do NOT decide or implement them;** the new core keeps refusing:
- rebinding a `mut` **list** parameter, which today does not reach the caller, against a `mut` **record** parameter, which does;
- writing to a list while a `for` loop iterates it (D1), where the old core's answer depends on whether the list is shared.

## 3. Work packages

Estimates are agent-hours, calibrated on S1, which took about 5 agent-hours across 4–5 lanes.

### S2-0. IR first (one agent; about 1–1.5 h; blocks D, T and F)

**Spec:** design note §8 "Step 0", with the ops of §2.4, §3, §4 and §5.

**Types:**
- `Compound.dict{key, value}`;
- `Type.bytes`;
- `Compound.array{elem, n}`;
- `Compound.fn(signature)`;
- an SSA-only `str_view`.

Include layout helpers and the `managed`/`isBlock` answers.

**Ops:**
- **dictionaries:** the §2.4 table. Keep them **independent of the table layout** (§11), so the table can be swapped without touching the builder or the facts.
- **text:** `str_char`, `str_width`, `str_code`, `str_append`, `str_append_char`, `str_slice`, `str_view_of`, `str_from_view`.
- **lists and arrays:** `list_sort`, `array_get`, `array_set`.
- **function values:** `func_ref`, `call_indirect`.
- **the `consumesOperand0` op property.** Wire it into `own.zig` for the new consuming updates, under the same rules as `list_push`/`list_set`.

**Verifier rules:**
- operand and result types for every new op;
- a `dict_insert` probe comes from a `dict_find` of the same dict;
- a `str_view` appears only where admitted, never at a phi, store, return or non-admitted call;
- `call_indirect` signatures match.

**New files with dispatch stubs:**
- builders: `build_dict.zig`, `build_text.zig`, `build_fn.zig`;
- emitters: `emit_dict.zig`, `emit_text.zig`, `emit_fn.zig`;
- runtime: `runtime/core_dict.c`, `runtime/core_text.c`, `runtime/core_sort.c`.

`build.zig` and `emit_llvm.zig` gain only the calls into these files, and `driver.zig` compiles the three C files into the cached runtime object. Until a package fills a stub, it refuses precisely (`E_CORE_UNSUPPORTED`).

**Exit:**
- test-core green;
- a hand-built-IR test per new op (valid LLVM; run where the op is simple: `array_*`, `func_ref`/`call_indirect`, `str_char`);
- verifier tests, including a rejection for each new rule;
- S0 kernels and S1 rows unchanged (code identical or within ±1%);
- full conformance still at 0 mismatches;
- fuzz clean.

**Afterwards:**
- Record the as-built shapes in the design note, in a new "as built in S2-0" section.
- **`ir.zig` is frozen after S2-0.** Any later change goes through the coordinator.

### S2-L. Language change `MUT-OVERLAP-RECEIVER-1` (one agent; about 2–3 h; independent, parallel with S2-0)

**The rule.** An assignment or update whose receiver place overlaps a `mut` argument evaluated in the same statement is a compile error, `E_MUTATION_OVERLAP`. It extends D3/`MUT-EXCLUSIVE` and the existing `E_MUTATION_OVERLAP`. Overlap means the same root variable, where one path is a prefix of the other.

**Must be rejected:**
- `items[selected(mut items)] = i`
- `points[save(mut points, …)].x = 13`
- `m.stack[grow(mut m)] = v`
- `rows[0].append(clear(mut rows))`
- `xs[i] = f(mut xs)`

**Must stay legal:**
- a `mut` call on a different root;
- a `mut` call whose result goes into its own variable first;
- read-only arguments that overlap. They get snapshots (MUTATION-OVERLAP-1).

**Diagnostic:** the message tells the programmer to make the call in its own statement first, for example `k = selected(mut items)` and then `items[k] = i`.

**Why.**
- The old core's result for these statements depends on how the callee changed the place: it writes either to the current place or to an orphaned payload.
- The new core refuses them (S1 §15.1, 4 tests).

**Where the work is.**
- The check goes in the shared checker: `src/origins.zig` and the mut-exclusive checks. Do not touch `src/core/`.
- Lowering in the old core should need no change.

**Tests and docs.** Follow `CLAUDE.md`.
- **Diagnostics:**
  - rejection and acceptance tests as Zig tests carrying `// spec: MUT-OVERLAP-RECEIVER-1`;
  - a matching `SPEC.md` bullet.
- **Existing tests:**
  - rewrite every `tests/lang` and `src/*_test.zig` test that relied on the old behaviour into the legal two-statement form, or into a rejection test;
  - retire or amend the SPEC bullets that described the accidental behaviour.
- **Docs:**
  - update the `mut`/overlap documentation with a runnable example;
  - keep `mylang doc-coverage .` and `zig build test-docs` green.
- **Stop and report** if the rule would reject legal-looking code in `examples/`, `bench/` or the Lox port.

**Exit:**
- the full old-core gate is green:
  - `zig build test`;
  - `zig build test-qbe`;
  - `zig build test-qbe-build`;
  - `zig build fmt-check`.
- New-core conformance still has 0 mismatches. The 4 refused tests disappear or become rejection tests.

### S2-D. Dictionaries and sets (one agent; about 4–5 h; after S2-0)

**Spec:** design note §2 and §11.
- **Layout:** the hybrid one.
  - Insertion-ordered dense entries.
  - A separate index of 1-byte control tags, probed in 16-slot SSE2 groups, plus a `u32` entry-number array, kept at most ½ full.
  - **No index for 8 entries or fewer:** those lookups scan the entries, comparing cached hashes.
  - Deletions use DELETED tombstones, cleared only at the next rebuild.
- **Probes:** pure SSA, fused so that a get/in/set sequence on the same key is one probe (§2.4). No hint record.
- **Ownership:** copy-on-write, ownership and D2 views per §2.5.

**Owns:**
- `build_dict.zig`, `emit_dict.zig` (the inline probe) and `runtime/core_dict.c`;
- a new `fuse_dict.zig`;
- the dict section of `facts.zig`;
- `test/core/row_dict_*.my`, `row_set_dedup.my` and `test/core/d_*.my`.

**Depends on** S2-T's `myl_core_str_hash` and its string header flags. S2-T publishes them about 30 minutes in; until then S2-D works on integer keys.

**Layout check, required before merge:**
- Re-measure the chosen layout with D's real emitted probe against the `old` shape on CPU 10 (`experiments/new-core-s2-design-20261005/dict-layout/run.sh` is the reference).
- **Dense-key rows** (`dict_lookup`, `dict_update`, `set_dedup`) are the layout's weak case (§11). If one misses the gate, the remedies in order are:
  1. builder-known capacity;
  2. the cheap scalar-probe rebuild;
  3. the CPython layout behind the same ops.
- **Never tune the hash to the fixtures' sequential keys** (WP-10e).
- Record the decision and its numbers in the design note.

**Exit:**
- the five dict and set rows build, match the old core and are measured;
- the dict and set files of design note §6 are at 0 mismatches;
- fuzz is extended with dict programs (aliasing, `mut`, deletion, iteration traps) and is clean;
- leak check shows 0;
- the verify build asserts the probe invariant and `count == 1` before in-place updates.

### S2-T. Text, bytes, numbers (one agent; about 5–6 h; after S2-0)

**Spec:** design note §3 and §4.
- **Representation:** one block layout for `str` and `bytes`, so `encode()` is free. The header caches flags for ASCII, the hash and the scalar count.
- **Iteration:** a UTF-8 cursor for `for ch in text`, with the 128 one-character ASCII strings immortal.
- **Indexing:** code-point indexing at O(n/32), with the ASCII fast path.
- **Building:** in-place `+=` under S1's uniqueness rules, plus `join` and formatting.
- **Views:** SSA-only views, and a fused `split` loop.
- **Numbers:** an 8-digit SWAR fast path for `int(text)`, and two digits at a time for `str(int)`.
- **Bytes:** byte iteration and `^`.

**Owns:**
- `build_text.zig`, `emit_text.zig` and `runtime/core_text.c`;
- `fuse_text.zig`;
- `test/core/row_string_*.my`, `row_bytes_scan.my`, `row_int_*.my` and `test/core/t_*.my`.

**Publishes first:** `myl_core_str_hash` and the header flags, for S2-D.

**Exit:**
- the 7 text rows build, match and are measured;
- the bytes and text files of design note §6 are at 0 mismatches;
- the verify build asserts that a `str_view` never escapes;
- Unicode cases are tested: mixed ASCII, 4-byte scalars, empty strings, and non-ASCII indexing over at least 256 bytes;
- fuzz is extended with random ASCII and non-ASCII strings, slices, `find`, `split`, concatenation in loops, and `int()` of 19-digit edges.
- If `string_split` misses the gate, report it with counter evidence before proposing the view ABI (§2, decision 4).

### S2-F. Function values, sort, fixed arrays (one agent; about 3–4 h; after S2-0)

**Spec:** design note §4.3 and §5.
- **Function values:** `func_ref` and `call_indirect`. A `call_indirect` of a known target becomes a direct call, and the loop is unswitched on the target.
- **Sort:** a port of the old core's algorithm and its stability into `runtime/core_sort.c`, including `sort_keyed` with a key function.
- **Fixed arrays `[N]T`:** they reuse the record paths, and F owns those paths during S2. Follow PY-ARRAY-MUT-1's semantics exactly.

**Owns:**
- `build_fn.zig`, `emit_fn.zig` and `runtime/core_sort.c`;
- in `build.zig` and `emit_llvm.zig`, **only** the `array` cases;
- `test/core/row_call_indirect.my`, `row_sort_*.my` and `test/core/f_*.my`.

**Exit:**
- `call_indirect`, `sort_int` and `sort_records` build, match and are measured;
- the function-value and fixed-array files of §6 are at 0 mismatches;
- an IR test shows a known-target `call_indirect` becoming a direct call.

### S2-X. Integration and exit (coordinator)

1. **Merges.** Merge each package after its exit check.
   - Expect **semantic** conflicts, not only textual ones. In S1, a facts table moved into a sub-struct and another lane's new code still read the old field.
   - Rebuild and run test-core after every merge, even a clean one.
2. **After every merge into the integration branch:**
   - test-core;
   - the S1 rows (`measure_rows.py`), checking for no regression;
   - full conformance at debug and release with 0 mismatches.
3. **At the end:**
   - **sweeps:** the leak sweep and the `--verify-facts` sweep over every supported test (`conformance.py --leakcheck` and `--verify`);
   - **coverage:** the coverage sweep;
   - **rows:** all 35 microbenchmark rows measured against Zig ReleaseSafe and Rust.

## 4. Order

| Wave | Packages | Parallel? |
|---|---|---|
| A | S2-0 (IR), S2-L (language change) | yes; they touch disjoint files (`src/core/` against the shared checker) |
| B | S2-D, S2-T, S2-F | yes, after S2-0 is merged; T publishes the string hash first |
| C | S2-X | after B |

At most four build-heavy agents at once on this machine.

**Shared files:**
- `own.zig` changes beyond `consumesOperand0` go through the coordinator as patches.
- For `conformance.pins`, `src/core/root_test.zig` and the test-core list in the root `build.zig`, agents only append or regenerate; the coordinator resolves conflicts.

## 5. Gates and tools

| Tool | Command | Use |
|---|---|---|
| Build | `scripts/build-slot.sh build -- zig build core` (new core), `… -- zig build` (old core, the oracle) | after every source change |
| Lane gate | `scripts/build-slot.sh build -- zig build test-core --summary all` | before every commit; must stay ≤ 5 min |
| Conformance | `python3 experiments/new-core-s1-20261005/conformance.py --set all --jobs 4 [--why] [--leakcheck] [--verify] [--pin test/core/conformance.pins]` | per test function against the old core; 0 mismatches always |
| Fuzz | `experiments/new-core-s1-20261005/fuzz.py --features …`, `experiments/new-core-s1-20261005/lane-o/rc_fuzz.py`, `experiments/new-core-s0-20261005/fuzz.py`, all under `MYL_CORE_LEAKCHECK=1` | each package extends it for its features |
| Rows | `experiments/new-core-s1-20261005/measure_rows.py --runner /home/epentland/ai/canopy/mylang-worktrees/runtime-baseline-20261003/.mylang-cache/runtime-expanded/runner/bin --build --rows …` | CPU 10; ≤ 1.10× Zig ReleaseSafe per row; checksums identical |
| Kernels | `experiments/new-core-s0-20261005/measure_kernels.py` | S0 kernels within ±1% |
| Coverage | `experiments/new-core-s0-20261005/coverage.py` | reported at each package's exit |
| Full old-core gate | `scripts/build-slot.sh gate -- zig build test --summary all`, then `test-qbe`, `test-qbe-build` and `fmt-check` | **only S2-L** (it changes the shared checker) and the final S2-X integration |

**Gate-log caution.** A `failed command:` line also prints for a green step that writes to stderr. Read the Build Summary lines.

**binary_search is layout-noisy.** With identical code it swings by up to ±30% from branch-predictor aliasing; no alignment flag fixed this (S1 §13). Report it as noise, never as a regression, when its search-loop IR is unchanged.

## 6. Rules

- **Machine** (shared with other agents and the runtime campaign):
  - every build goes through `scripts/build-slot.sh build`, and every gate step through `scripts/build-slot.sh gate`;
  - timing runs only with `taskset -c 10`; never on CPUs 2, 3 or 11 (2 and 3 are the campaign's timing core);
  - never prune `runtime-baseline-20261003`: its runner binaries are the Rust/Zig references.
- **Guardian** runs on every commit (88 checks), and they must pass:
  - a `///` doc comment on every `pub` declaration;
  - at most 7 struct fields and 6 parameters;
  - tests with `expect*` and no top-level `if`/`while`/`for`/`switch`;
  - every new `src/*.zig` file reachable from a `guardian.toml` root;
  - a spec tag for every behavioural line: `// spec:` with a matching `SPEC.md` bullet (`NEW-CORE-*` for the new core).
- **Never edit `tests/lang/`,** except S2-L for its rule. Copies and split programs go under `test/core/`.
- **Correctness:**
  - **A wrong answer is never acceptable.** A construct either matches the old core or is refused precisely with `E_CORE_UNSUPPORTED`.
  - **Every new fact needs a verify-mode assert,** and every new promotion or uniqueness claim needs one too.
- **Check premises.** S1 had two plans that rested on "LLVM will remove X": the bounds check in binary_search and retain/release pairs. Neither held. Measure the generated code before relying on an LLVM optimization.
- **Stop and report** if:
  - a rebuild takes over 10 s;
  - test-core takes over 5 min;
  - a mismatch is unexplained;
  - a language-behaviour change seems needed;
  - `ir.zig` must change after S2-0.
- **Old-core bugs** are reported, not fixed (S2-L is the only old-core change).
- **Branches:** no pushes or merges to `main`; the old core stays the default until S5.
- **Clean-up:** delete temporary caches outside the worktrees at hand-off. `scripts/prune-caches.sh` handles stale worktree caches.

## 7. S2 exit check and report

The S2 exit check is plan §6:
- all 35 microbenchmarks build under the new core;
- conformance for S2's areas passes (0 mismatches; supported and unsupported counts reported);
- the coverage sweep: functions and loops accepted, per refusal reason.

S2 then stops at a **go/stop point for the user**: whether to commit to S3–S5.

The final report records, in the design note and in `experiments/new-core-s2-*/`:
- the commits per package;
- the row table: all 35 rows at both sizes, against Zig ReleaseSafe and Rust, with count updates in inner loops;
- the dict layout decision with its numbers;
- conformance (full `tests/lang`, debug and release);
- the leak and verify sweeps;
- coverage before and after;
- the dev-loop times (rebuild, test-core);
- every refusal that remains, and every open question for the user.
