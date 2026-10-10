# Wave 4A: indexed property campaigns

Baseline: main `1d202d41bfff888ee91354f706cb74e860dc4b94`.
Implementation branch: `codex/selka-cache-wave4a`.
Toolchain: the unchanged `0.17.0-dev.1683+5ceec001b` pin.

Implementation and qualification details are in [REPORT.md](REPORT.md).

## Deliverable

An explicit `--property-policy indexed-v1` preserves generated input prefixes
when the requested passing-run budget grows. Generation uses the existing
100-run size schedule independently of that budget. The legacy default remains
unchanged. Passing and discarded inputs both consume ordinals; generated but
unclassified inputs do not authorize reuse.

The first implementation retains one bounded cumulative completed prefix per
qualified campaign. It uses atomic checksummed replacement and a per-campaign
lock with expected-previous validation. This is disposable cache evidence for
process-crash recovery, not arbitrary range history or application durability.
Smaller budgets can conservatively rerun. Coverage-guided fuzz-engine recovery,
differential fuzz adapters, performance evidence reuse and cross-worktree
sharing are later milestones.

## Ownership

- Generation agent: versioned policy/progress contract, input schedule, bounded
  execution chunks, resume hooks and classification accounting.
- Evidence agent: budget-independent campaign settings, bounded prefix encoding,
  guarded atomic publication, concurrent-writer and corruption qualification.
- Integration agent: same validated target-closure facts, CLI/directory wiring,
  source/tool checks at checkpoints, honest reporting and end-to-end regressions.
- Parent: shared contract review, SPEC and documentation, test-root registration,
  independent cancellation/oracle qualification, full gate and final review.

## Qualification

First qualify small cold/unchanged/extended/reduced budgets with whole-test and
report receipts bypassed. Compare generated prefix bytes and fresh execution
against an independent forced indexed run. Include discards/exhaustion, first
failure, shrinking, reproduction, dependency edits and seed/settings changes.

Exercise corrupt/missing/conflicting evidence, concurrent publication and
interrupted execution. Observe a committed prefix, terminate the owned command
group, then verify that restart reuses that prefix without certifying unfinished
work. Force, fact verification and leak checks must continue executing fresh.

All builds/focused tests use normal build admission. The parent schedules the
combined gate; no timing runs beside a gate. Record counts, verdicts, source and
binary hashes, process resources and admission context. Qualification durations
are not performance-speedup claims.
