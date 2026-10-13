# Output-keyed, path-free, shared verification: implementation plan

Date: 12 October 2026. Status: decisions D1 to D6 approved by the user on 12 October (each with the proposal in Section 1); Lane A started the same day on branches `claude/lane-a-env-contract-20261012` (environment identity contract, Zig and Python classifiers, receipt adoption) and `claude/lane-a-runner-identity-20261012` (`runner_identity`), in worktrees `canopy/mylang-lane-a-contract-20261012` and `canopy/mylang-lane-a-runner-20261012`; the host tool follows once the contract lands. Lane E started 12 October on branch `claude/lane-e-shared-store-20261012` (worktree `canopy/mylang-lane-e-shared-store-20261012`), landing the default-location mechanism with the switch off per Section 7; it landed as `a151d4f71` (mismatch is a counted, logged miss; reads never wait on a sweep; `shared_cache_policy.default_sharing = false`; `mylang cache gc` hook for the prune job) and is merged on the integration branch at `560f45b8f`. Lane A part 1 landed as `e635ffa8a` plus `2d37749be` (environment identity contract with four classes: keyed, host, placement, dropped; two digest scopes); Lane A part 2 landed as `9a24aad16` (`runner_identity`, 47 runner inputs, `compiler_identity` byte-identical to the old tool) and both are merged on the integration branch `claude/lane-a-env-identity-20261012` at `f6971a623`, whose full gate passed on 12 October at 14:00 UTC: `zig build test --summary all` 146/146 steps, 2,903 tests passed (25,567 sharding skips), exit 0 in 293 s on a fresh worktree with warm shared object store, then `fmt-check` exit 0. Not merged to `main`; nothing pushed. Lane C started 12 October on branch `claude/lane-c-build-graph-20261012` (worktree `canopy/mylang-lane-c-build-graph-20261012`), branched from that commit; it also owns the `build-env` host tool. It landed as `d22d3b219` and `92dde5582` (`build-env digest`/`project`, every `withTools` step projected, `MYLANG_TEST_COMPILER` and relative fixture paths, zero absolute paths outside DWARF in the `core`, `units` and `cli` binaries, producers for all ten artifacts in `artifacts.json` v3) and is merged on the integration branch at `858b6de54`; `21637f937` adds `MYLANG_TEST_COMPONENT_BUILDER` as a placement variable. On `21637f937` (Lanes A, C, D, E) all 14 focused suites passed; both full gates passed at 14:52 UTC: plain `zig build test` 146/146 steps, 2,923 tests, exit 0 in 284 s; coordinator complete verification PASS, exit 0, inputs stable, 47 actions, 743 s cold with new v3 receipts, under the projected environment (acceptance row 12). `artifact_identities`: ten producers, `components` still by bytes, so 34 of 47 actions report `path_free: false`; the Lane C follow-up `de78475c1` adds the `components` producer (recipes over the build files, `selfhost/*.zig`, `selfhost/components/` and the seed pin `selfhost/component-seed.json`; a `MULTI_OUTPUT_PROVIDERS` exemption in the coordinator for multi-file providers) and a two-roots test with identical keys and every action path-free on the fixture; it merges cleanly onto the integration branch and awaits the final gates before merging. Lane D started 12 October on branch `claude/lane-d-coordinator-20261012` (worktree `canopy/mylang-lane-d-coordinator-20261012`), branched from the Lane A integration commit `f6971a623`; it landed as `f7bf86c0a` and `fb844a522` (projected worker environments, host-scope digest in `common` without the root path, receipts under `verification-v3` with action domain v6, producer identities for the four native roots with a reported byte fallback, `DEFAULT_SHARING = False`, per-action `path_free` diagnostics). Projection is live for coordinator workers rather than shadow-only; the merged gate must therefore run through the coordinator as well as plain `zig build test` (acceptance row 12). Lane D is merged on the integration branch at `74812e6b5` (Lanes A, D, E; 51 files against `main`); the A plus E focused suites all passed before the merge. Lane B started 12 October on branch `claude/lane-b-receipts-20261012` (worktree `canopy/mylang-lane-b-receipts-20261012`), branched from the gated Lane A integration commit `f6971a623`; default store locations stay with Lane E. It landed as `d107cc704` and `a063a2671`: `core-test-settings-v3` and `core-test-ir-v3` with root-relative paths, `core-test-exec-v3` and `core-test-whole-exec-v3` keyed on `runner_identity` plus `program_key`, lookup before the first trial, fact and leak receipts, `core-shared-program-v2` without the compiler identity, `exec_receipts` in the report. End to end, a comment-only edit to `src/parser.zig` left all ten probe tests cached as `whole-exec-receipt-hit` with zero trials (acceptance row 2 on one file). Merged onto the integration branch at `6131a113b` with three conflicts resolved (SPEC bullet, guest-tests paragraph, store format string). On that tree every focused suite and the plain full gate passed (146/146, 2,895 tests, 336 s), but the coordinator's complete verification that followed failed two `test/integration.zig` tests (`a test whose result is not bool fails its case and the run`, `CLI formatter and test agree on headerless sibling test imports`): both run `mylang test` on a fixture in a fresh temporary directory and assert `passed`; with path-free keys the second run on the same tree hits the first run's receipt and reports `cached`. The tests relied on the absolute temporary path for isolation; the fix landed as `7313c483e` (`runFixture`/`runProjectFixture` pass a private `--cache-dir` for `test`; the sibling-import test likewise; a sweep found no other test relying on a shared default cache), and `test-cli` passed twice in a row. The integration branch is fast-forwarded to it, and the final gate round on `7313c483e` passed at 15:51 UTC: `zig build test` 146/146 twice in a row (100 s and 118 s warm), `fmt-check` exit 0, coordinator complete verification PASS (exit 0, 47 actions, 585 s cold) with `path_free: true` for all 47 actions and all 11 artifacts by producer. Lane F phase 2 (full acceptance matrix, measurement cohorts, documentation pass, feature slugs, D1/D3 integration profile, plan outcome) started on that commit. The `components` producer follow-up is merged at `5685ac635`. Lane F started 12 October on branch `claude/lane-f-qualification-20261012` (worktree `canopy/mylang-lane-f-qualification-20261012`): phase 1 landed as `5b7b75b28`, `c1aac14f5`, `3b0d7960f`, `2f308ccf2` (audit and plan committed under `docs/audits/`, CLAUDE.md corrections, the 13-row acceptance harness under `experiments/output-keyed-receipts-20261012/` with 21 judge tests and a row-1 smoke pass); it merges cleanly onto the integration branch and phase 2 runs the matrix on the merged tree once Lane B lands. All six lanes are active or landed. Lane F phase 2 landed at `154341fc6` and is merged on the integration branch at `de596cd78` (its results are the Outcome section below); Lane C2 fixed finding F1 at `de957e8de`, merged at `2ea257471`. The final gate round on `1c3175ee7` passed on 12 October at 21:28 UTC: Guardian 88/88, `zig build test` 147/147 steps (2,932 tests), `fmt-check` exit 0, coordinator complete verification PASS cold in 618 s (46 actions, coverage 107 of 107, every action path-free) and the unchanged repeat in 29.2 s request and 18.8 s gate occupancy (35 reused, 11 fresh). On 13 October `main` `1994cb76e` (289 commits since the base) was merged at `8da187660` and the Lane F cohorts at `e023793f6` (plain gate 147/147 on the rerun after a disk-full window). Lane G, four parallel sub-lanes for findings F3 to F8 and F12 to F14, landed and is merged at `3759f7415`, where the final round passed at 04:11 UTC: Guardian 88/88, `test-verification-registry`, `fmt-check`, `zig build test` 147/147 (two load-sensitive durable-storage tests failed once and passed on the rerun), coordinator complete verification PASS cold (46 actions, coverage 107 of 107, 44 path-free) and warm (35 reused, 11 fresh). Open: F15 (two unit actions bind test-binary bytes that carry the debug compile directory), F17 (the 94 tests the sharing policy refuses stay private per worktree), the `default_sharing` flip with its two test blockers, the C4 and C5 cohorts on the Lane G tree, and a live `--integration` run. Not merged to `main`; nothing pushed. Baseline: `main` at
`4892aaba4`. Source: [development-loop audit](development-loop-audit-2026-10-12.md),
changes 1 and 2. All file references are to that tree.

## 0. What changes

**Change 1, output-keyed verdicts.** A guest test's success receipt today binds
`compiler_identity`, a digest of every production source under `src/`
(`src/core/test_runner_receipt.zig:56,98`; `build_identity.zig`). Any compiler edit
invalidates every receipt, so a comment-only edit reran all 1,579 `tests/lang` tests
(78 s) and the complete gate costs 10 to 17 minutes. After this plan a receipt is
keyed on **what ran**: the linked program's exact object digests (the driver's
existing `program_key`, `src/core/driver.zig:516-531`), the runtime object, the
toolchain, the execution settings, the keyed environment, and a new `runner_identity`
covering the code that drives and judges a test. The present IR-based key stays as
the first, cheaper tier; the program-keyed receipt is the **early cutoff** behind it.
`--release --verify-facts` and `MYL_CORE_LEAKCHECK=1` runs, which refuse receipts
today (`test_runner_receipt.zig:366-400`), become keyed modes. The shared program
key drops `compiler_identity` (`driver.zig:286-295`).

**Change 2, path- and environment-free identities, shared by default.** Today the
verdict cache in `build.zig` hashes the entire live environment
(`build.zig:117-133`), the coordinator keeps nearly all of it and the checkout path
(`scripts/verify_cache.py:320-360, 897`), receipts and test binaries embed absolute
paths (`test_runner_receipt.zig:99-100`; `build.zig:403-410`), and every shared tier
is opt-in and unused. After this plan one environment allowlist is shared by the
compiler, `build.zig` and the coordinator; every path in a key is root-relative;
test binaries receive paths at run time; the shared program, receipt and evidence
stores are on by default for the same user on the same machine; and a determinism
mismatch in a shared store is a miss, not a build failure.

What this plan does **not** do: it keeps `compiler_identity` inside the IR-based
receipt key (an IR-level hit after a compiler edit needs the component identities
of audit change 3), it does not touch Zig unit-test sharding or Guardian, and it
does not share Zig's own build cache across worktrees (audit change 6).

## 1. Decisions needed before the lanes start

| Id | Decision | Proposal |
| --- | --- | --- |
| D1 | Receipts for fact-verification and leak-check runs. Closeout S06 keeps them always fresh. | Allow receipts keyed on the mode. The integration gate forces one fresh fact/leak run per integrated commit; `--force` and `-Dtest-rerun` stay. Rationale: both checks are deterministic functions of the program bytes and the runtime object, which the key binds. |
| D2 | Trust boundary of default-on sharing. | Same Unix user, same machine. Cross-machine stores stay explicit, as `remote-development.md` already requires. |
| D3 | Determinism mismatch policy. | Miss, never publish the second bytes, count it in `cache-report-v1`, write one line to `<store>/mismatches.log`. The integration gate fails if the counter is non-zero over a window. |
| D4 | Namespace bump. | `receipts-v3`, `manifests-v3`, `native-tests-v3`, `compiler-artifacts-v3`, `verification-v3`. One cold gate per worktree at rollout; schedule it. |
| D5 | Initial environment allowlist (Section 2.3). | Approve the three classes and the initial lists; any later addition is a reviewed change to one file. |
| D6 | Scope of `runner_identity` (Section 2.2). | Approve the prefix list; unknown is conservative (wider). |

## 2. The identity contract

### 2.1 Receipt tiers

| Tier | Key | When it can hit |
| --- | --- | --- |
| IR receipt (today's NEW-CORE-S4-TEST-3, kept) | `H(domain, compiler_identity, cache_plan, tool, relative entry, settings, cases, configuration, keyed env)` then `programKey(base, name, IR)` | Edits that leave a test's reached IR and the compiler unchanged |
| **Execution receipt (new)** | `H("core-test-exec-v3", runner_identity, program_key, settings, name, cases bytes, configuration bytes, policy bytes, keyed env)` | Any compiler edit that leaves the linked program's bytes and the runner unchanged |
| **Whole-program execution receipt (new)** | the same over the program plus the sorted list of ready test names | One lookup per test file, as NEW-CORE-TEST-WHOLE-1 does for IR keys |
| Shared program (`core-shared-program-v2`, changed) | `H(domain, program_key, link environment)`; `compiler_identity` removed | A second worktree links nothing when its objects match |

`program_key` already exists in `driver.link` (`driver.zig:199,516-531`): link
sanitizer, object format, optimize level, link target, CPU flags, CPU, tool digest,
every linked object's digest in order (the runtime object and `--link` foreign
objects included), `-lm`, and the two linker environment variables. It contains no
path and no compiler identity. The driver exposes it by adding `program_key:
?Digest` to `driver.Outcome` (`driver.zig:81-96`; the struct has six fields today,
so this stays within Guardian's limit of seven).

Lookup order in `test_runner.zig` `select` (lines 835-882): IR key as today. On a
miss, the test is still "ready"; the runner lowers, emits and links the program as
it does now (objects come from `units-v1`, programs from `programs-v1` or the shared
tier), then, before the first forked trial in `test_runner_execute.zig`, consults
the whole-program execution receipt, then the per-test execution receipt. A hit
marks the test `cached` with `cache.reason = "exec-receipt-hit"`; the IR receipt is
also saved so the next run hits at the first tier. A pass saves both receipts.

Admission (`reuseReason`, `reusable`, `test_runner_receipt.zig:366-400`): keep
`missing-cache-plan` for the IR tier only (the execution tier does not use the
planner), keep `uncacheable-toolchain`, `force`, `native-links` (until foreign header
tracking is proved; the objects are in the key but their headers are not) and
`untracked-loader-environment`. Remove `verify-facts` and `leak-check` as refusals;
`facts` is already in the settings JSON, and the leak-check value joins it
explicitly.

### 2.2 `runner_identity`

The execution receipt is sound only if the code that builds the test executable's
driver, forks trials, applies budgets and judges outcomes is in the key. The program
bytes cover the emitted code and the runtime; they do not cover the Zig side of the
runner. `build_identity.zig` gains a second generated constant, `runner_identity`,
computed the same way as `compiler_identity` but over this prefix list, relative to
`src`:

```
core/test_runner*.zig (production files only; *_test.zig excluded as today)
core/test_builder.zig  core/test_shared_store.zig  core/property_*.zig
core/run_budget.zig    core/trap_contract.zig      core/process_spawn.zig
core/native_receipt.zig core/cli_run.zig           core/cli_args.zig
core/pipeline.zig      core/driver.zig             core/unit_cache.zig
core/target.zig        core/version.zig            memory_budget.zig
```

`pipeline.zig`, `driver.zig` and `unit_cache.zig` are included because they decide
how a program is linked and launched, not only what it contains. Test discovery and
screening (`test_runner_discover.zig`, `test_runner_cases.zig`, `test_runner_options.zig`)
are covered by the glob. Anything the list misses is a bug class the acceptance
matrix (row 4) must catch; when in doubt, widen the list, never narrow it.

### 2.3 Environment identity

One file, `src/environment_identity.json`, embedded by the compiler like
`src/features.json`, read by a new host tool in `build.zig` and by the coordinator.
Three classes:

| Class | Meaning | Initial members |
| --- | --- | --- |
| **keyed** | `NAME=VALUE` enters every identity; the variable is passed to children | `MYL_*`, `MYLANG_*`, `SELKA_*` (minus the placement variables below), the C and Zig toolchain variables already listed in `test_runner_receipt.zig:150-157`, `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE`, `LANG`, `LC_*`, `TZ`, `PYTHON*`, `LD_*` (non-empty `LD_*` still refuses receipts) |
| **placement** | passed to children, not keyed: selects where content-addressed storage lives or how much parallelism to use, and cannot change an outcome | `HOME`, `XDG_CACHE_HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `ZIG_LOCAL_CACHE_DIR`, `ZIG_GLOBAL_CACHE_DIR`, `MYLANG_CORE_RUNTIME_CACHE`, `MYLANG_COMPILER_SHARED_CACHE`, `MYLANG_TEST_SHARED_CACHE`, `MYLANG_JOBS`, `MYLANG_TEST_ISOLATE`, `MYLANG_TEST_CHILDREN`, `MYLANG_SLOT_DIR`, `MYLANG_ADMISSION_*`, the tool-ticket hint, `PATH` |
| **dropped** | removed from children and absent from keys | everything else: `PWD`, `OLDPWD`, `SHLVL`, `_`, `TERM*`, `COLUMNS`, `LINES`, `USER`, `LOGNAME`, `DISPLAY`, `SSH_*`, `CODEX_*`, `CLAUDE*`, `ANTHROPIC*`, `OPENAI*`, `GIT_*` (the coordinator already scrubs these), `BASH_ENV`, `ENV`, `BASH_FUNC_*` |

`PATH` is placement, and the tools it resolves are keyed by content: `build.zig`
records the digests of the tools its steps name (`sh`, `env`, `python3`, `git`,
the pinned `zig`) instead of the `PATH` string; the coordinator already does this in
`tool_contract` (`verify_cache.py:417-441`).

"Run what you key" is the invariant: the same tool that computes the environment
digest also projects the environment a test runs in, so a dropped variable cannot
influence a verdict. The compiler already follows this rule for receipts
(`keyedVariable`, `test_runner_receipt.zig:168-174`); `build.zig` and the
coordinator adopt it.

### 2.4 Paths

Every path that enters a key or a binary becomes relative to the project or build
root, which the process receives at run time:

- Receipts: `settingsWithBudget` hashes `entry.path` and `entry.root`
  (`test_runner_receipt.zig:99-100`) and `manifestPath` hashes `entry.path`
  (`:530-538`). Both become the entry path relative to the root; the root is
  identified by its content through the captured module dependencies, as
  `portableSettings` (`:53-85`) already does. The private and portable domains
  merge into one v3 key.
- Emission: `programKey` receives `source_path` as the realpath of the entry
  (`test_runner.zig:819`) and the single-file fallback in `pipeline.zig:289` is
  absolute. Both become root-relative, so unit text, object keys and program bytes
  are identical across worktrees (the parity harness's `same-binaries` check is the
  oracle).
- Test binaries: `build.zig:403-410` bakes `core_path` (a per-tree cache path, found
  verbatim inside the installed `units` binary), `fixtures`, `lang_tests` and
  `clock_path` into Zig options. They become cwd-relative strings
  (`test/core`, `tests/lang`, `benchmarks/runtime/ports/native_clock.c`) with every
  test Run step on `setCwd(b.path("."))`, and the compiler path arrives at run time
  through `MYLANG_TEST_COMPILER`, a placement variable set by the launcher from the
  artifact's path. The step still declares the compiler as a file input, so its
  verdict stays correct.
- Coordinator: `common["root"]` and `env["PWD"] = str(root)` go. Checkout locks keep
  using the real path; identities do not.

### 2.5 Installed-artifact identities in the coordinator

The coordinator identifies `mylang`, `units`, `core` and `cli` by the bytes of the
installed binaries (`verify_cache.py:563-605`). Those bytes embed the worktree path in
DWARF (`comp_dir`, `.debug_line_str`, `.debug_str`), verified on the installed
binaries today, so two worktrees can never share those groups' receipts by bytes.
`scripts/verification_producers.py` already has the alternative for two roots:
`CLOSURES` plus `qualified_identity`, a producer identity over the exact sources and
embedded data. This plan extends it to the four native roots with **recipe-based**
closures (globs over `src/**/*.zig`, `src/**/*.json|txt|tsv|my`, the embedded docs
listed in `src/user_docs.zig`, `build*.zig`, `.zigversion`, `guardian.toml`, and the
test-only sources of each root) computed from the preparation snapshot the
coordinator already hashes. `build_verification.zig` exports the recipe per artifact
in `artifacts.json` so the two sides cannot drift. A debug-stripped ELF digest
(sections other than `.debug_*` and `.comment`) is recorded as telemetry to detect
nondeterministic builds; it is not the identity.

## 3. Lanes

Each lane is one session in its own worktree off the integration base. The
coordinator owns shared files (`build.zig`, `build_identity.zig`,
`build_verification.zig`, `src/environment_identity.json`, `SPEC.md`,
`src/features.json`) and merges small patches from lanes. No lane runs a full gate
independently; the coordinator runs the integration gate.

### Lane A: identity contract (prerequisite, 1 session)

Deliverables:
- `src/environment_identity.json` with the three classes; `src/environment_identity.zig`
  (`pub fn classify(name) Class`, embedded JSON, no allocation) used by
  `test_runner_receipt.keyedVariable` and by the new host tool.
- `build_env.zig`, a host tool shaped like `build_identity.zig` (configure-time
  `module()` wires it; make-time `main()` runs): `build-env project -- CMD...`
  executes `CMD` with the projected environment; `build-env digest OUT` writes the
  environment manifest (keyed `NAME=VALUE` lines sorted, plus `tool:<name>=<sha256>`
  for the named tools). One binary, one definition.
- `scripts/verification_environment.py` reading the same JSON; a test that feeds one
  fixture environment through the Zig tool and the Python module and asserts the same
  classification and digest.
- `build_identity.zig`: emit `runner_identity` from the Section 2.2 prefix list into
  `identity.zig`; `frontend_reuse.zig` re-exports it as it does `compiler_identity`.
- `docs/tooling/environment-identity.md`: the contract, the classes, how to add a
  variable, the "run what you key" rule.
- Spec tags: `ENV-IDENTITY-1` (classification), `ENV-IDENTITY-2` (projection equals
  digest), `RUNNER-IDENTITY-1` (runner sources move it, front-end sources do not).

Acceptance: the Zig and Python classifiers agree on a 200-variable fixture; a
`CODEX_THREAD_ID` or `TERM` difference yields identical digests; a `MYLANG_MEMORY_LIMIT`
difference yields different digests; editing `src/parser.zig` leaves
`runner_identity` unchanged and editing `src/core/test_runner_execute.zig` changes it.

### Lane B: compiler receipts (change 1; depends on A)

Files: `src/core/test_runner_receipt.zig`, `src/core/test_runner.zig`,
`src/core/test_runner_execute.zig`, `src/core/test_runner_portable.zig`,
`src/core/test_shared_store.zig`, `src/core/driver.zig`, `src/core/pipeline.zig`.

Deliverables:
- v3 domains and root-relative entry paths in `settingsWithBudget`, `portableSettings`
  and `manifestPath`; private and portable keys unified (the shared store is a second
  location for the same key, not a second identity).
- `executionKey(context, program_key, name)` and `wholeExecutionKey(...)` in
  `test_runner_receipt.zig`; `driver.Outcome.program_key`; `pipeline.linkEmittedCached`
  passes it through.
- Lookup before the first trial in `test_runner_execute.zig`; save on pass in the
  same place `receipt.save` runs today (`test_runner.zig:280-282`);
  `cacheExplanation` gains `exec-receipt-hit` and `whole-exec-receipt-hit`.
- `reusable`/`reuseReason`: drop the `verify-facts` and `leak-check` refusals; bind
  `MYL_CORE_LEAKCHECK` explicitly in the settings JSON (D1).
- `sharedProgramKey` without `compiler_identity`, domain `core-shared-program-v2`.
- Shared test receipts default location when `MYLANG_TEST_SHARED_CACHE` is unset:
  `$XDG_CACHE_HOME/mylang/native-tests-v3`, else `~/.cache/mylang/native-tests-v3`;
  an explicitly empty value disables, `--no-cache` disables, as documented today.
- Eligibility: every ordinary test that `publishes()` (no live effects), under either
  property policy; `--link` stays private until foreign headers are keyed.
- `cache-report-v1` and the `--json` test report gain `exec_receipts: {hits, saves}`.

Spec tags: `EXEC-RECEIPT-1` (program-keyed hit after a compiler edit), `EXEC-RECEIPT-2`
(runner edit misses), `EXEC-RECEIPT-3` (whole-program receipt), `EXEC-RECEIPT-4`
(fact/leak modes keyed and not cross-hitting), `SHARED-PROGRAM-2` (no compiler
identity, byte-exact), `RECEIPT-PATHS-1` (two roots, same key).

Guardian notes: `receipt.Context` is at the seven-field limit; `runner_identity` goes
inside `context.identity`. Keep new functions at six parameters by passing a
settings struct.

### Lane C: build graph (change 2, Zig side; depends on A)

Files: `build.zig`, `build_verification.zig`, `build_test_inputs.zig`,
`src/core/root_test.zig` and `src/root_test.zig` option readers, `test/integration.zig`.

Deliverables:
- `addEnvironmentManifest` runs `build-env digest` instead of `environment_script`
  (`build.zig:117-133`); `withTools`/`tools_script` exec through `build-env project`
  after exporting the Zig cache variables (`build.zig:171-211`). No
  `setEnvironmentVariable` anywhere; `requireLiveEnvironment` keeps enforcing that.
- Relative option strings for `fixtures`, `lang_tests`, `clock_path`; `core_path`
  replaced by `MYLANG_TEST_COMPILER` supplied by the launcher from the artifact path;
  every test Run step `setCwd(b.path("."))` and declares the compiler artifact as a
  file input. The `units`, `core` and `cli` binaries then contain no cache path
  (verify with the audit's `grep -a` check).
- `build_verification.zig`: per-artifact producer recipes in `artifacts.json`
  (version 3) for `mylang`, `units`, `core`, `cli`, alongside the existing two roots.
- `build_test_inputs.zig`: declare `src/environment_identity.json` where needed.

Spec tags: `ENV-PROJECTION-1` (a dropped variable is invisible to a test step and
leaves its verdict cached), `TEST-PATHS-1` (binaries carry no absolute paths).

### Lane D: coordinator (change 2, Python side; depends on A and C)

Files: `scripts/verify_cache.py`, `scripts/verification_producers.py`,
`scripts/verification_snapshot.py`, `scripts/cache_session.py`, their tests.

Deliverables:
- `normalized_environment` becomes a projection through `verification_environment.py`;
  `common` drops `"root"` and the `PWD` pin; `environment` in `common` is the
  projected digest.
- Producer identities for the four native roots from the recipes in `artifacts.json`
  (Section 2.5); byte identity stays as a fallback when a recipe is missing, and the
  report names which one was used.
- Receipts under `verification-v3`; the shared evidence store defaults to
  `~/.cache/mylang/verification-shared` (D2) with `--shared-cache-dir` overriding and
  an empty value disabling.
- `last-run.json` reports, per action, whether its identity was path-free and which
  environment variables entered it.

Tests (`verify_cache_test.py`): identical action keys for two environments differing
only in `CODEX_THREAD_ID`, `TERM`, `PWD` and `TMPDIR`; different keys for a
`MYLANG_*` change; two roots at one commit produce identical keys for all 46 actions.

### Lane E: shared-store hardening (change 2 prerequisite; independent)

Files: `src/shared_artifact_store.zig`, `src/native_cache_retention.zig`,
`src/core/compiler_sharing.zig`, `src/core/driver.zig` (`SharedProgram.failed`),
`src/core/test_shared_store.zig`.

Deliverables:
- `DeterminismMismatch` is a miss: `SharedProgram.failed` and the test store return
  "not found", increment a counter in the outcome, append one line to
  `<store>/mismatches.log` (D3). Nothing is published for that key.
- `Store.open` stops running `automatic()` under the exclusive `.lock`
  (`shared_artifact_store.zig:35-43`); the sweep runs in a detached child or from the
  prune job, and `open` takes only the shared lease.
- `publish` checks `record(kind, key)` before staging a full copy
  (`shared_artifact_store.zig:200-236`).
- Default locations when the variables are unset: `~/.cache/mylang/compiler-artifacts`
  and the test store above; an unusable **default** store degrades to a warning and
  no sharing, an unusable **explicit** store stays an error (`compiler_sharing.zig:20-28`).
- `scripts/prune-caches.sh` learns the new directories.

Spec tags: `SHARED-STORE-3` (mismatch is a miss and is counted), `SHARED-STORE-4`
(default store absent or unusable never fails a build), `SHARED-STORE-5` (no
exclusive lock across the sweep; a concurrent open completes while a sweep runs).

### Lane F: qualification, docs and rollout (depends on all)

- The acceptance matrix in Section 4 as checked-in tests where possible and as
  frozen experiment manifests otherwise, under
  `experiments/output-keyed-receipts-20261012/`.
- Docs: `docs/tooling/guest-tests.md` (the receipt identity section, lines 536-620),
  `docs/tooling/native-build.md` (caches and shared artifacts), `docs/tooling/caches.md`,
  `docs/tooling/many-agents.md` (per-worktree environment; sharing is default),
  `docs/tooling/development-loop.md`, `docs/tooling/cache-retention.md`, `CLAUDE.md`
  (caches and worktrees; the unchanged-gate claim).
- `src/features.json` slugs for the tooling changes with runnable examples, so
  `doc-coverage` passes.
- SPEC bullets for every tag above.

## 4. Acceptance matrix

Every row is a test or a frozen qualification case with an expected decision. "Hit"
means no trial executed and the verdict reported `cached` with the named reason.

| # | Case | Expected |
| --- | --- | --- |
| 1 | Unchanged repeat in one worktree | All receipts hit; `language` members in fact and leak modes execute zero tests (today 1,790) |
| 2 | Comment-only edit to `src/parser.zig`, then `mylang test tests/lang` | IR keys miss; all program bytes unchanged; 100 % `exec-receipt-hit`; zero `zig cc`; zero trials. Record the time (expected: lowering and emission only) |
| 3 | Emitter edit that changes one helper's code | Only tests whose program bytes changed execute; verdicts equal a `--force` run |
| 4 | Edit to `src/core/test_runner_execute.zig` behaviour | Every execution receipt misses (`runner_identity`); IR receipts also miss |
| 5 | Edit to `src/core/runtime/core_rt.c` | Every execution receipt misses (runtime object digest is in `program_key`) |
| 6 | Fact and leak modes | A second identical `--release --verify-facts` run hits; a leak-check run hits its own receipt; neither hits the other's; `--force` reruns |
| 7 | Two worktrees at one commit, different paths, different launcher environments (`CODEX_THREAD_ID`, `TERM`, `PWD`, `TMPDIR`) | The second worktree's `mylang test` reuses every eligible receipt and its complete verification reuses every group except the host-fresh collectors; all 46 action keys identical |
| 8 | Negative controls | `MYLANG_MEMORY_LIMIT` change: keys change. `LD_PRELOAD` set: no receipts. A fixture test reading `CODEX_THREAD_ID` sees it absent under projection |
| 9 | Transitive failure injection | An edit in a function a cached-pass test reaches makes it execute and fail; no stale pass |
| 10 | Mismatch injection | Different bytes published under one shared key: the build proceeds with a miss, the counter is 1, the log has one line, the integration check fails |
| 11 | Program path independence | The same test program built from two roots yields identical `program_key`s and identical bytes |
| 12 | Projection safety of the whole gate | The complete gate passes under `build-env project` before projection becomes the default |
| 13 | Namespace bump | Old v2 receipts are ignored, not misread; the first v3 gate is a full run and the second is a hit |

## 5. Measurement

Frozen manifests, exclusive timing windows, queue time recorded separately, no
summing of overlapping steps, in the style of the wave-2 report. Baselines come from
the audit and the 12 October reports.

| Cohort | Baseline | Target after this plan |
| --- | --- | --- |
| Unchanged complete verification, one-shot, 5 samples | 33.5 to 36.8 s; gate occupancy 23 to 28 s | About 13 s less gate occupancy from the fact/leak receipts; the rest of the floor is audit change 7 |
| Front-end comment edit, `mylang test tests/lang`, 5 edits | 78 s, 0 cached (5 Oct) | Zero trials; time equals lowering plus emission of the suite |
| Front-end comment edit, complete verification | 596 to 1034 s, every group | Zig roots and drivers still rerun; guest and language groups reuse; measure the remainder honestly |
| Second worktree at the same commit, first verification | Cold gate plus 2.3 GB hashed | Equal to the unchanged case above once the snapshot is hashed |
| Ten agents, one base commit, warm requests | Ten independent gates through one slot | One execution, nine hits; record queue time separately |

## 6. Risks and mitigations

- **A judge dependency outside `runner_identity`.** Mitigation: the prefix list is
  wide and errs toward including driver and pipeline code; acceptance row 4 is a
  standing test; `--verify-cache`-style shadow mode (`MYLANG_TEST_VERIFY_RECEIPTS=1`,
  keyed) executes a sample of hits and compares.
- **Nondeterministic program bytes** (ordering, hash seeds, timestamps). Mitigation:
  row 11 and the mismatch counter; the emitter already avoids timestamps and
  absolute directories except the single-file fallback this plan removes.
- **Projection breaks a driver or test that needs a variable.** Mitigation: the
  placement class; row 12 before flipping the default; `MYLANG_ENV_PROJECTION=off` as a
  keyed diagnostic switch so a disabled projection can never hit a projected receipt.
- **Shared-store contention at default-on.** Lane E lands before any default flips;
  qualify with ten concurrent agents on one store.
- **One cold gate per worktree at the namespace bump.** Schedule during low activity;
  the first worktree to run warms the shared stores for the others.
- **Zig's configure cache freezes environments.** Nothing uses `setEnvironmentVariable`;
  the projection happens in the launcher at make time, as `withTools` does today.
- **Receipt keys that still carry a path.** Row 7 and a key audit (grep every
  `field(` call in the receipt module for `path`/`root`) in Lane B's review.

## 7. Rollout

1. **Week 1.** Lane A (contract), Lane E (store hardening), Lanes C and D in
   **shadow mode**: compute both the old and the new identities, log every difference,
   change no decision.
2. **Week 2.** Lane B behind `MYLANG_TEST_EXEC_RECEIPTS=1` (keyed, opt-in); fact and
   leak receipts behind D1; two-worktree qualification (row 7) and the edit cohorts.
3. **Week 3.** Flip defaults: projection on, shared stores on, execution receipts on,
   v3 namespaces, docs and SPEC; the integration gate adds the forced fact/leak run
   and the mismatch check.

`--force`, `--no-cache` and `--verify-cache` keep their documented meanings
throughout, and the quick/complete verification profiles are unchanged.

**Integration gate (D1, D3), landed with Lane F phase 2.** The integration gate
is `python3 scripts/verify_cache.py --zig "$ZIG" --integration`: the complete
profile, then one forced run of every `--release --verify-facts` language member
(`MYL_CORE_LEAKCHECK=1`, `--force`, a private cache directory removed afterwards,
so ordinary requests keep their fact/leak receipts) under one gate admission, and
a check of every `mismatches.log` in the native shared stores the request's
environment selects. A failing or `cached` forced test fails with status 1; a
log that grew during the request or is non-empty fails with status 5. The result
is recorded under `integration` in `last-run.json` and in
`integration-last-run.json`; see `docs/tooling/development-loop.md#integration-gate`.

## Outcome, 12 October

**Integration.** All six lanes are merged at `7313c483e` on
`claude/lane-a-env-identity-20261012` (tree `3117cf99`). The coordinator's
gates on that commit: `zig build test` 146/146 twice, `fmt-check`, and a cold
complete verification (exit 0, 47 actions, 585 s, `path_free: true` for every
action, all 11 artifacts identified by producer). Lane F qualified the same
sources (its branch adds only `experiments/`), compiler SHA-256 `27385c43…`,
inventory SHA-256 `41adb0c4…`. Evidence:
`experiments/output-keyed-receipts-20261012/evidence-phase2/`.

**Acceptance matrix.** Pass: rows 3 (an emitter edit reran exactly the 621
tests whose execution keys changed; verdicts equal `--force`), 4, 5, 6, 8, 9,
10 and 12 (the forced complete gate under `build-env project` passes in an
ordinary worktree). Partial: row 1 (all 1,549 eligible `tests/lang` tests
reused in debug and in fact/leak modes; the `language` telemetry is unknown,
and the gate log shows 3 executed, the `uncacheable-metadata` ones). Fail:
row 2 (1,544 of 1,549 eligible are execution-receipt hits; the 5 misses embed
`function_digest`, which binds the compiler identity), row 7 (no reuse across
two worktrees in either tier, all 47 action keys differ), row 11 (program bytes
name the entry's absolute path) and row 13's coordinator part (scratch-location
gates failed; the receipt namespaces themselves behave as specified).

**Findings for the owners** (diagnosed to file and line in the evidence):
(F1) the unregistered `build-env` compile step made every complete
verification run the original complete gate (unchanged request 532 s,
gate 475 s); fixed the same day by Lane C2 (`de957e8de`, merged at
`2ea257471`): the tool's compile step is registered as infrastructure,
`test-verification-registry` fails every gate root while any required action is
unregistered, and two consecutive unchanged complete verifications observed
under load took 40.7 s then 23.1 s (gate 22.6 s and 13.4 s; 11 fresh, 35
reused, 0 executed); (F2) `function_digest` programs change with every compiler edit;
(F3) coordinator action keys include path-dependent loaded-code digests;
(F4) the cache-plan component's bytes, and so every IR receipt key, differ per
worktree; (F5) the gate fails when the shared-store variables are set;
(F6) a single-file entry's absolute path is in its objects; (F7) test binaries
keep DWARF paths only; (F8) one CLI test depends on the checkout location;
(F9) `verification_measurement_test.py:120` failed inside an exclusive
coordinator window.

**Cohorts.** All exclusive-window samples; evidence in
`experiments/output-keyed-receipts-20261012/evidence-phase2/cohorts/`. C2 ran
on `7313c483e`; C1, C3 and C4 ran on `385c46bae` (after the F1 fix), compiler
SHA-256 unchanged across each cohort.

- **C1, unchanged complete verification, 5 samples:** request median 29.9 s
  (24.2 to 36.5), gate occupancy median 14.4 s (13.8 to 24.8); 35 actions
  reused, 11 always fresh, all keys equal to the prime's; window queue at most
  0.1 s; no sample voided. Baseline 33.5 to 36.8 s request, 23 to 28 s gate.
  The prime itself took 660.6 s because a windowed request never reuses an
  unwindowed receipt (F14, below).
- **C2, comment edit then `mylang test tests/lang`, 5 edits:** median
  14.15 s (7.75 to 16.17), queue at most 5 s; 1,544 execution-receipt hits and
  5 executions per edit. Baseline 78 s, 0 cached.
- **C3, comment edit then complete verification, 2 samples:** request
  737.8 s and 787.4 s (median 762.6), gate 712.0 s and 753.9 s; window queue
  0.1 s and 10.1 s. 16 actions reused, 19 executed, 11 fresh: the Zig roots,
  drivers and their dependants rerun because the compiler is their input, while
  every guest and language member answered from execution receipts (8 tests
  executed per `tests/lang` mode). Baseline 596 to 1,034 s, every group.
- **C4, first verification in a fresh worktree, 3 worktrees sharing one
  evidence store:** request 1,096.8 s, 902.5 s and 941.5 s (median 941.5),
  gate 1,069.0, 877.9 and 910.7 s; window queue 5.1 s, 331.7 s and 456.7 s
  (other teams' timing runs). Every worktree executed 35 actions and reused
  none; worktrees two and three had different action keys from the first
  (F3), and every gate failed on F8 (the first also on F9), so nothing was
  published to share. Snapshot work per worktree: 28,912 files, 2.33 GB,
  2,294 directories, 763,484 metadata observations. Baseline: a cold gate plus
  2.33 GB hashed, 600 to 1,000 s. This is the pre-Lane-G baseline.

The warm floor moved by the fact/leak share (C1); a compiler edit no longer
reruns guest tests (C2, C3); nothing is yet shared between worktrees (C4).

**F14 (Lane D).** `measurement_window_seconds` is part of
`common.execution_limits` (`scripts/verify_cache.py`, the `common` dictionary
of `execute`), so windowed and unwindowed requests have disjoint receipts: a
timed request after an untimed one reruns everything, and a C1 prime must use
the samples' own window. Two windows of different lengths are disjoint too
(C3's prime under 1,800 s reran the gate C1 had warmed under 900 s).

**Integration gate.** `--integration` (Section 7) is implemented in
`scripts/verify_cache.py` with eight tests in `scripts/verify_cache_test.py`.

**Lane G, 13 October.** Four parallel sub-lanes from the `main` merge
`8da187660`, merged at `3759f7415`. G1 (`6d3aa6271`): a single-file entry is
named by its basename in `source_filename` and the entry `DIFile`
(`ENTRY-PATH-1`), so program bytes and execution keys are identical across
roots; row 11 passes in both sub-cases and `tests/lang` execution keys are equal
for 1,592 of 1,592 tests; F8 was the test's own absolute entry path. G2
(`ae9d20363`, `6ea8127d8`): the coordinator hashes its loaded code by base name
(loaded-code format 2) and `path_free` rehashes relocated code;
`DECLARATIVE_CONSUMERS` replaces the drifted fingerprint; the new
`src/semantic_cache_format.zig` keeps `build.zig`'s import closure out of the
front end and `BuildToolIdentity` walks that closure; `measurement_window_seconds`
left the action identity (F14); `verify_cache.py --dry-run` exports the plan
without running a gate. G3 (`4d2986b55`): component identity format 3 with a
path-free builder identity and one stable staging directory, so two worktrees
install byte-identical components and `cache.component` agrees. G4
(`6d7aa8230`, `3de621886`): the F5 "race" was the expected stderr of the
SHARED-STORE-4 negative tests; store creation now retries (SHARED-STORE-6) with
an eight-thread test; about fifty test sites run against private stores through
`test_paths.privateEnvironment`, and the full gate passes with fresh shared
stores three times. Row 7 on the merged Lane G tree: worktree B's gate passes,
44 of 46 action keys and the budget context are identical, and 1,495 of 1,589
tests are served from the shared store. The 94 that still run are refused by
`shareable()` on purpose (host capabilities, error traces, C externs, function
values: F17); `text_scalar_unit` and `tooling_unit` differ because their
producer identities bind test-binary bytes that carry the debug compile
directory (F15). The `default_sharing` flip has two test blockers:
`test_store_roots_follow_the_compiler_resolution` asserts it off, and
`compiler_shared_cache_test`'s suppression treats an unset variable as
disabled.
