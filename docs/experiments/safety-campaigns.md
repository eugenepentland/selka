# Reproducible safety campaigns

Run `python3 scripts/safety_campaign.py --seed 20260907 --rounds 20 --output report.json`.
The report retains every source and source hash, seed, compiler/generator/template
hashes, commands' outcomes, timings and family coverage. The generated concrete
arithmetic and generic-copy cases independently expect the same calculated
answer. The current managed cases use ordinary lists, snapshot ownership, buffers,
scoped views and fallible propagation; mutation helpers take explicit `mut`
parameters and callers pass explicit mutable arguments. Positive executions must
print the complete expected integer and return its low eight bits as process
status. Compiler warnings on stderr do not change that oracle. Mutations
exercise malformed input; valid mutations are permitted, crashes/host failures
and timeouts fail. Crash candidates undergo at most 32 delta-debugging attempts.
Compiler checks and native executions have 15-second subprocess deadlines.

The retained Debug and ReleaseFast campaigns in `experiments/safety/` each passed
240 cases (60 generated executions and 180 mutations) for seed 20260907. Their
compiler hashes identify the tested executables; later source edits do not
retroactively receive these results. The first local harness trial incorrectly
passed VM-only flags to `check`; that was a campaign setup error corrected before
these retained runs, not a source-language failure.

This is deterministic family coverage, not instrumented code coverage or a
soundness proof. It complements the existing exhaustive allocator-failure tests.
The later `campaign-interactions-{debug,releasefast}-20260907.json` reports each
pass 480 cases (120 generated executions and 360 mutations), adding typed JSON
success/budget paths inside arenas, generic whole-owner references, checked split
siblings and immutable snapshots. Their source/helper hashes pin their generators.

`python3 scripts/safety_host_interactions.py --runner zig-out/bin/mylang-io --output report.json`
describes the retained byte-host runner campaign. Its source fixtures and runner
contract are frozen historical inputs, including retired host/effect syntax; this
command does not establish support in the current compiler. The retained
Debug/ReleaseFast host reports each
pass 60 cases: JSON backing inside an arena, normal copied output, provider failure,
and callback-budget exhaustion. Failures must have the expected trap code, suppress
unpublished output and leave zero requested live bytes after cleanup. These reports
pin the byte runner separately from the compiler CLI.

Initial local generator trials used an untyped zero against u64 slice lengths,
an owner without an explicit borrow, an incomplete host module and an incorrect
runner flag. Corrected fixtures passed before the retained reports; these were
campaign setup failures rather than compiler defects. Stored views and actual
coverage-guided compiler/runtime fuzzing remain extensions to this campaign.
Unexpected compiler infrastructure failures are retained rather than counted as
successful rejection. Minimized candidates are diagnostic artifacts; they need
independent triage before becoming regression fixtures.
