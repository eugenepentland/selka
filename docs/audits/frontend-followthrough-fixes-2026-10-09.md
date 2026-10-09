# Front-end follow-through: review fixes and an evidence-free merge branch (2026-10-09)

Status: **ready for Codex.** The user accepted Claude's review recommendations on 2026-10-09, with `noalloc` as a warning (F1).
- **What this is:** Claude reviewed `codex/frontend-followthrough-20261009` at `0bbfeb740` (plan `docs/audits/frontend-followthrough-2026-10-09.md`, closeout `experiments/frontend-closeout-20261009/REPORT.md`). Two independent reviewers built the compiler and probed it.
- **The verdict:** the source work is sound, but the branch must not be merged as it is. This plan builds a merge branch without the bulk evidence, aligns `noalloc` with the accepted VK8 decision, and fixes what the review found.
- **Size:** about 10–16 h.

## Launch instruction (for Codex)

> **One run: the merge branch, then F1–F10, then stop for review.**
> - Create `codex/frontend-merge-20261009` from `claude/frontend-fixes-plan` (current `main` plus this plan).
> - Do §2 first, then §3 in order.
> - **Do not stop to ask:** decide, log the decision in `experiments/frontend-fixes-20261009/DECISIONS.md`, and continue.
> - Stop only at a §6 hard stop, or when the report (§5) is written.
> - Commit at every step. If `main` moves, merge it with a real merge commit and rerun the current step's gates.
> - Never merge into `main` and never push. Claude reviews the branch, then the user merges it.

## 1. What the review found

**Sound (no action):**
- the gate (94/94) and a clean merge with today's `main`;
- recovery never publishes a partial syntax tree;
- no hangs or crashes on about 1,800 mutated inputs;
- `mylang fix` is idempotent;
- no stale specialization reuse across a dozen edit kinds;
- `noalloc` catches copy-on-write, generic instances and transitive allocations, with no false alarms on common operations;
- range lowering is identical to the base compiler on every edge case tried;
- cost and dump output is unchanged for ordinary programs.

**To act on** (F-numbers are §3's fixes):

| # | finding | where |
|---|---|---|
| E | **258 MB of evidence in 24,087 files.** 11 of the 15 commits are evidence only, including three copies of the Lox and EDA captures. The source is in `d8fe5b797`, `fb868aace` and `48e741592`. | `experiments/frontend-closeout-20261009/`, `experiments/frontend-followthrough-20261009/` |
| F1 | **`noalloc` is an error, and `check` computes it.** This contradicts VK8 (`docs/audits/values-keys-trap-search-plan-2026-10-07.md`, decisions VK4 and VK8): a violation is the warning `W_NOALLOC_ALLOCATES`, the lint gate blocks on it, and `check` gains no whole-program obligation. | `src/core/allocation_contract.zig:18`, `src/core/frontend.zig:125,241`, `src/core/cli.zig:213`, `src/main.zig:1921`, `SPEC.md` `FRONTEND-CORE-NOALLOC-1`, `docs/effects.md:155` |
| F2 | **After a `noalloc` body changes, `check-project` never publishes summaries again.** Every later check rechecks every body until the cache is deleted (measured 6 of 6 rechecked against 1 of 6 in the base). | `src/sema_summaries.zig:108,113` (`requireAllocationBodies` sets `.concrete`); `publishes()` at `:251-252`; `src/sema.zig:1885` |
| F3 | **Project and module mode report only the first syntax error.** Every file with `public` or `import` takes this path. | `src/interfaces.zig:1638-1642` (`moduleSyntax` reports `sink.items.items[0]`) |
| F4 | **Recovery ignores `{`/`}`.** One error inside a multi-line dict or set yields one diagnostic per line (20,003 for a 20,000-line dict). | `src/parser.zig:1450-1460` (`recover`) |
| F5 | **`mylang fix` declares a block-scoped `mut` for a local used after the block only through `n += 10` or `xs.append(...)`,** and the result fails to check. | `src/frontend_binding_migration.zig`, `escapes()` around lines 221-235 (only `.name` nodes count as uses) |
| F6 | **Recovery reports a false error at a valid `elif`/`else`/`except`/`finally`/`case`** after a compound statement whose header failed. | `recover()` |
| F7 | **Active docs show old-syntax programs that fail to check.** They sit in console blocks that doctest never runs. Prose is stale too. | `docs/tooling/runtime-budgets.md:153-162`, `docs/tooling/ownership.md:36-42`, `docs/managed-memory.md:29,44-48`, `docs/generics.md:172` |
| F8 | **51 of the 58 excluded idiom fixtures pass `fmt --check`,** and most are accepted programs, so the stated reason is false. `fmt` also rejects six `src/stdlib/*.my` files (`E_INTERNAL_NAME`) that `check` accepts. | `scripts/my_format_exclusions.json` |
| F9 | **The arena fix is withheld for two sequential `with arena() as a:` blocks** reusing the name. | `src/arena_fix.zig` `bindingsCertain` |
| F10 | **Specialization publish and lookup scan names quadratically** (O(specializations × references × records)). This is plausible but not measured. | `src/sema_specialize.zig` around lines 212-221 and 325-335 |

## 2. The merge branch, without the bulk evidence

1. **Cherry-pick the source commits** onto `codex/frontend-merge-20261009`, in order: `d8fe5b797`, `fb868aace`, `48e741592`.
2. **Copy the plan text:** take `docs/audits/frontend-followthrough-2026-10-09.md` from `0bbfeb740` (it was updated inside the evidence commit `cf7c620dc`).
3. **Bring the reports, not the captures.** Copy into `experiments/frontend-followthrough-20261009/` and `experiments/frontend-closeout-20261009/` only:
   - every `REPORT.md` and `STATUS.md`;
   - the small summary and identity JSON (`candidate-qualified.json`, `qualification.json`, `preservation-check.json`, and each sub-report's summary);
   - the final gate log, `full-gate-3.log`.
   
   **Total ≤ 10 MB.**
4. **Point the reports at the evidence.** Each copied `REPORT.md` gets a line at the top naming the full evidence as `codex/frontend-followthrough-20261009` at `0bbfeb740`. Rewrite the relative links to files that are not copied, so they cite that branch and commit with the path. No link may dangle.
5. **Leave the evidence branch unchanged.** It keeps the raw evidence; nothing is deleted from it.
6. **Prove the source matches.** After step 1, `git diff 0bbfeb740 HEAD -- src build.zig tests test docs examples bench scripts SPEC.md README.md` must show only the plan file and the report differences of steps 2–4. Run the full gate on this tree before starting §3, so that later failures are known to come from the fixes.

## 3. Fixes, in order

Each fix starts with a failing test from the reproducer, then the fix, then the test passing.

**F1. `noalloc` becomes a warning, outside `check`** `[FRONTEND-CORE-NOALLOC-1]` (revised).
- **`check` and `check-project`** no longer compute the allocation contract. That removes the `allocation_contracts` body policy from the check path, which keeps VK4's "no whole-program obligation in check".
- **`build`, `run`, `build --run` and `test`** compute it as now (written `noalloc` only, on ownership-expanded Core before optimization, through every callee). They report each violation as the warning `W_NOALLOC_ALLOCATES` at the allocation site, naming the function and the callee, and **do not fail** because of it.
- **`mylang lint`** gets a rule `noalloc-allocates` (`L_NOALLOC_ALLOCATES`) in **block** mode in every profile. `--gate` therefore exits 3 on a violation. The repository gate uses it wherever it already runs lint on its own sources; if it does not, add that step.
- **`cost`** keeps showing static may-allocate sites.
- **Update:**
  - the SPEC bullet, `docs/effects.md`, `docs/tooling/lint.md` (rules table) and the `features.json` entry;
  - the tests that expected `E_CORE_ALLOCATION_BOUND`: they now expect the warning, plus the lint block;
  - the "unsupported concrete body" case, which becomes a warning with its reason, and stays blocking in lint.
- `E_CORE_ALLOCATION_BOUND` is removed. If any code still needs a hard failure (for example a runtime helper allowlist check), log why.

**F2. Summaries keep publishing after a bounded-body change** (a new SPEC bullet).
- F1 takes allocation contracts out of `check`. Still, fix the mechanism wherever it remains (lint uses it): a request that falls back to concrete bodies must still publish its summaries. Either give it a separate "no stand-ins this run" flag, or make `publishes()` true for requests that began as allocation-contract requests.
- **Test** (`src/check_scale_test.zig`): seed; edit a bounded body and check; make an unrelated edit and check. The third run stands in bodies again (`stood_in > 0`), and its facts equal a cold check's.

**F3. Every recovered syntax error is reported in project and module mode.** `project.fail`, or the sink, carries all parser diagnostics, not only `items[0]`. Keep the fix edits per diagnostic.
- **Test:** a project file containing two `public func`s, each with `const x = )`. `mylang check` reports both, at 2:15 and 6:15 in the reviewer's reproducer.

**F4. Recovery counts braces.** `recover` treats `.lbrace`/`.rbrace` like parentheses and brackets.
- **Test:** an error inside a four-line dict literal yields exactly one diagnostic.

**F5. `fix` sees every use after the block.** `escapes()` also counts:
- the name of an assignment or augmented-assignment target;
- method receivers;
- call, buffer, file and resource owners;
- field and index targets.

`arena_fix.termNamed` already lists these; share it.

**Tests,** in the old syntax, each expecting `E_BINDING_SCOPE_MIGRATION` with no confined fix:
- `c = True` / `if c:` `n = 1` / `else:` `n = 2` / `n += 10`;
- the same shape with `xs = [1]` / `xs = [2]` / `xs.append(3)`.

**F6. Recovery does not restart at a continuation keyword.** When the restart token is `elif`, `else`, `except`, `finally` or `case` at nesting 0, keep skipping.
- **Test:** `if a == 1:` … `elif a == = 2:` … `else:` gives exactly one diagnostic.

**F7. Docs.**
- Migrate the four places listed in F7's row, and any others found by the new check below.
- Make console-embedded programs (`$ cat X.my` blocks) checked by doctest or doc-coverage, or convert them to checked `mylang` blocks. Decide and log.

**F8. Format gate exclusions.**
- Remove the 51 idiom fixtures that pass `fmt --check`. Keep only the seven that need an exclusion (`edge_const_bytes`, `edge_const_str`, `edge_declared_len_wins`, `edge_option_try`, `lambda_sort_key`, `rm_clock_cap`, `rm_f64_add`), each with an accurate reason.
- Make `fmt` and `check` agree on the six `src/stdlib/*.my` files (`E_INTERNAL_NAME`), then drop their exclusions.

**F9. The arena fix for sequential blocks.** `bindingsCertain` ignores another `with_scope` binding of the same name when neither block nests the other.
- **Test:** two sequential `with arena() as a:` blocks each get the fix, and the result checks.

**F10. One name→index map per request** for specialization publish and lookup, with duplicates marked. Measure a warm `check-project` of EDA before and after. Log the numbers even if the gain is small.

## 4. Gates

**Correctness:**
- `zig build test --summary all` (every step) and `zig build fmt-check` (including the `.my` format step), on the final tree;
- `experiments/new-core-s5-20261007/tools/qualify_merge.py`: test-core and conformance in both modes, with a fresh `--evidence` directory;
- the frozen external Lox/EDA qualification, as the closeout ran it (450 commands with exact case/mode/verdict membership; 974 Lox native answers; 34 EDA byte-identical outputs).
  - **Store only a summary:** counts, hashes and the source-guard result.
  - **Store raw output only for a command that fails.** The evidence for this run stays ≤ 10 MB.
- the reviewers' reproducers above, all fixed;
- `mylang lint --gate` on the repository's own sources, with no `L_NOALLOC_ALLOCATES` (or each one waived with a reason).

**Performance (deterministic, no quiet hardware):**
- F10's warm-check numbers;
- for F1, the time and the bodies checked of a warm `check-project` on EDA after editing one `noalloc` function, before and after.

## 5. Report

`experiments/frontend-fixes-20261009/REPORT.md` should give:
1. the merge-branch construction, with the source-identity diff of §2 step 6 and the evidence size;
2. each fix with its test and commit;
3. F1's behaviour table (`check`, `build`, `run`, `test`, `lint`, `lint --gate`, `cost`);
4. the gates and the external summary;
5. F10 and F1's measurements;
6. a summary of `DECISIONS.md`.

Report plainly which phases of the follow-through plan are complete and which have only their first step. For example, range is the only construct family on the new lowering.

## 6. Rules and hard stops

**Rules:**
- **Builds:** every build through `scripts/build-slot.sh`; at most four build-heavy processes; TMPDIR and caches on the home volume, never `/tmp`.
- **Processes:** kill only PIDs you started.
- **Guardian**'s rules.
- **Branches:** never modify Claude worktrees or the evidence branch's history.

**Decide, log, continue:** see the autonomy rules of `docs/audits/concurrency-plan-2-2026-10-09.md` §9. Implementation choices, files and gate failures are yours to resolve.

**Hard stops (report and stop only for these):**
1. A semantic change beyond F1's accepted one, or a change to the redesign's syntax rules.
2. `src/core/ir.zig` or `src/core/own.zig`.
3. Lowering a numeric threshold, or skipping a gate.
4. Evidence above 10 MB that cannot be summarised.
5. A correctness failure that about 8 hours of investigation does not fix.
6. Anything that needs a merge into `main`, a push, or a change to a Claude worktree or branch.
7. Resources you cannot recover within your own files and processes.
