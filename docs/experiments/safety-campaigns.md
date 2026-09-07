# Reproducible safety campaigns

Run `python3 scripts/safety_campaign.py --seed 20260907 --rounds 20 --output report.json`.
The report retains every source and source hash, seed, compiler/generator/template
hashes, commands' outcomes, timings and family coverage. The generated concrete
arithmetic and generic-copy cases independently expect the same calculated
answer. The arena cases combine generic-independent arithmetic with pools,
snapshot ownership, buffers, scoped views and fallible propagation. Mutations
exercise malformed input; valid mutations are permitted, crashes/host failures
and timeouts fail. Crash candidates undergo at most 32 delta-debugging attempts.
VM executions have explicit step/frame limits and subprocess deadlines.

The retained Debug and ReleaseFast campaigns in `experiments/safety/` each passed
240 cases (60 generated executions and 180 mutations) for seed 20260907. Their
compiler hashes identify the tested executables; later source edits do not
retroactively receive these results. The first local harness trial incorrectly
passed VM-only flags to `check`; that was a campaign setup error corrected before
these retained runs, not a source-language failure.

This is deterministic family coverage, not instrumented code coverage or a
soundness proof. It complements the existing exhaustive allocator-failure tests.
JSON/host failure combinations, new split borrows, stored views, and actual
coverage-guided compiler/runtime fuzzing remain extensions to this campaign.
Unexpected compiler infrastructure failures are retained rather than counted as
successful rejection. Minimized candidates are diagnostic artifacts; they need
independent triage before becoming regression fixtures.
