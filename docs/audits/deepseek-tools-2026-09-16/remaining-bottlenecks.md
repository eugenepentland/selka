# Remaining tool-cycle bottlenecks

This follow-up examines the original pre-update logs and local source. It does not measure the new preset's development throughput. No builds, compiler tests, Guardian gates or external model calls were run for this investigation.

## 1. Focused test targets still pull in the full installation

The current `mylang` checkout is at `2afef03c`. Its dependency path is:

```text
test-units / test-cli
  -> run_unit / run_integration
  -> bounded(...)
  -> install_all (the default install step)
  -> installed compiler, QBE, host applications, runtime preparation, Guardian
```

The links are explicit in [build.zig](/home/epentland/ai/canopy/mylang/build.zig:71): `bounded()` adds the install dependency at line 76, runtime preparation joins install at line 146, Guardian joins install at line 216, and the focused targets use `bounded()` at lines 258–267. The comment describing “no Guardian” is inaccurate. This corrects the initial audit's claim that these targets already avoid the broader graph.

The behavior also appears in the recorded logs. Session `9e1591d8-75ae-4863-8419-847b4a6f992b`, call seq `64328`, ran one named test filter for 138.136 seconds. Its build summary contains `test-units -> run test -> install -> install schematic-svg -> guardian-check`, and the Guardian failure prevented the test target from completing. This is not evidence that Guardian itself consumed those 138 seconds; compilation, other dependencies and queueing are included.

Another call, session `session-f0dc790a-c137-467c-8054-7bc0d5a6a5fc`, seq `35043`, took 128.698 seconds for a ReleaseFast filtered run whose ten tests reported `test wall 0.00s`. The important discrepancy is the expensive surrounding build, not test execution. The logs do not split that call into complete compile/install/queue timings.

**Next change:** separate resource/environment setup from install dependencies. Give focused targets explicit dependencies on only the test binary, required compiler/QBE artifacts and necessary runtime assets. Retain Guardian on the required install/full acceptance paths. Confirm the intended development-target policy and test the resulting dependency graph rather than silently disabling the gate. Measure warm no-change, edited-test and edited-compiler cases independently.

## 2. Source identities invalidate more than the compiler's actual inputs

[build_qbe_assets.zig](/home/epentland/ai/canopy/mylang/build_qbe_assets.zig:33) recursively reads every regular file beneath `src`, declares a content dependency on each, and feeds the full set into `compiler_identity` at line 104. This includes test sources. The generated identity is embedded in the asset module consumed by the compiler and test roots.

A test-only file edit therefore changes the generated compiler identity even when compiler behavior did not change. In combination with the full-install dependency above, that can expand an otherwise small edit into compiler rebuilds and downstream cache invalidation. The identity change follows directly from the code; its time cost has not been isolated in a controlled experiment.

**Next change:** distinguish complete build provenance from the actual compiler/runtime dependency closure used for reusable artifacts. Preserve all real semantic inputs, generated inputs, toolchain and optimization-mode identity. Add tests proving a test-only edit does not invalidate the production compiler, while a compiler/runtime edit still invalidates the affected artifacts. Do not remove freshness dependencies without that proof.

## 3. Self-host tests repeatedly invoke the compiler for the same guest program

The active self-host work is in separate worktrees. In the examined [parser differential driver](/home/epentland/ai/canopy/mylang-worktrees/selfhost-stabilize-parser/selfhost/tests/run_parser_diff.py:194), each fixture calls `mylang run selfhost/parser.my -- <fixture>`; the lexer driver does the equivalent for `selfhost/lexer.my`. Cases run sequentially. Warm caches may avoid native recompilation, but each case still enters a fresh compiler process and its run/cache validation path.

In the earlier exploration snapshot, 79 non-sleep shell calls explicitly invoking `python3 selfhost/tests/run_*.py` consumed about 80.6 agent-minutes. Some also performed other work, so this is a command bucket, not isolated driver execution time. One parser-plus-lexer call took 208.686 seconds: session `95b092c8-bd26-4a00-b997-cc64cba49293`, seq `70508`.

**Next change:** build the unchanged self-host parser/lexer once per driver run, then invoke that binary for each fixture. Preserve capabilities, instruction/memory limits, exit status and output equivalence. Keep a small dedicated `mylang run` path test. Add fixture selection for development and bounded parallel execution for independent cases; retain the full comparison at acceptance.

## 4. Budget checks remeasure the exact minimum on every ordinary run

The [parser budget driver](/home/epentland/ai/canopy/mylang-worktrees/selfhost/selfhost/tests/run_parser_budget.py:58) launches `mylang run` for every probe. Its ordinary validation path calls `minimum_steps`, which first checks the ceiling and then binary-searches the exact minimum. The four current recorded ceilings imply approximately 21–25 guest invocations per input, rather than one ceiling verification. The same unchanged guest program is invoked repeatedly with different step limits.

**Next change:** offer a fast ceiling-verification mode for ordinary edit cycles and reserve exact minimum-step measurement for recording/profiling or an explicitly required gate. Verify any separate default-budget requirement as well as the recorded ceiling. Alternatively, report executed-step counts directly so one run supplies the measurement. This reduces invocation count for that specific check; a proportional end-to-end speedup is not established.

## 5. Some commands select much more work than their author intended

Session `922a5fda-0632-4d7e-9c94-9f25a1f471ef`, seq `159815`, used an empty `-Dtest-filter=`. It selected all 1,022 tests and took 293.639 seconds. A space-only filter in another session selected 904 tests and took 281.586 seconds. The original analyzer's “filtered” category only detects the flag's presence; it does not establish that selection was narrow.

Two direct test-binary invocations retained `--listen=-` and each timed out after about 303 seconds, totaling 606.221 seconds. The [Guardian test runner](/home/epentland/ai/canopy/guardian-zig/src/test_runner.zig:434) handles that flag by entering the build-server protocol and waiting for stdin messages. Replaying a build runner's internal command as a standalone shell test is therefore a poor diagnostic path.

**Next change:** provide one supported focused-test command that rejects empty/whitespace-only filters, exposes the selected-test count, preserves exit status, saves full logs and reports phase timings. Use supported build targets instead of copying internal `--listen=-` invocations. Explicitly distinguish a full-suite request from a focused test.

## Lower-priority opportunities

- **Verification reuse:** the repository already has version-2 input inventories and successful-result receipts in `scripts/verification/`, but the top-level `verify.json` is version 1. Connect appropriate checks to complete input/tool/environment inventories before reusing results. Repeated command text alone is insufficient to skip a test.
- **Cross-agent build scheduling:** a shared queue could prevent simultaneous heavyweight builds from competing or duplicating identical work. Existing per-build RSS limits do not form a host-wide queue. The logs do not establish the slowdown caused by contention, and a live snapshot showed load around 3–6 with 20 available logical CPUs, so hardware saturation is not a demonstrated primary cause.
- **Structured results:** return pass/fail, selected count, failing-test names, phase durations and a log path, rather than repeatedly reading full build logs. This can reduce follow-up model/tool round trips. The preset's new output guidance helps, but does not enforce structured summaries.
- **Raw dispatch latency:** nearly 13,000 subsecond calls consumed about 32 minutes in the original audit. Optimizing milliseconds per call is lower priority than the minute-long cases above; batching unnecessary model round trips is a separate opportunity.

Recommended order: fix the focused build graph, narrow compiler identity invalidation with correctness tests, then optimize the self-host driver and budget-check execution paths. These are source changes beyond the preset update and have not been applied by this follow-up audit.
