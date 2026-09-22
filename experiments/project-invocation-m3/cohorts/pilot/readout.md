# M3 cohort pilot

captured 2026-09-20T13:05:41.317805+00:00  ·  status **not-run**

## Readiness blocker

no participant session was launched: the frozen application pack is not preflight-ready, and the runbook stops here rather than spending on participants

- ready applications: sexpr-port
- ready cases: sexpr-escaping, sexpr-invalid-input, sexpr-nesting, sexpr-percent, sexpr-units
- blocked cases: planner-boundary, planner-chain, planner-empty, planner-ties, planner-zero-duration
- detail: the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14
- evidence: `/home/epentland/ai/canopy/mylang/experiments/project-invocation-m3/evidence/preflight.json`, `/home/epentland/ai/canopy/mylang/experiments/project-invocation-m3/evidence/readiness.md`

| application | public workload | seconds | diagnostics | ready |
| --- | --- | ---: | --- | --- |
| planner | failed | 0.042 | E_REMOVED_SPELLING | False |
| sexpr-port | passed | 38.227 | none | True |

## Gate

not evaluated — the headroom pilot was not run because the runbook's readiness check failed before any participant was engaged

## Decision rule

- row: **not-reached**
- the predeclared decision rule cannot be applied without a scored cohort; the readiness stop takes precedence

## Next action

do not spend on participants; either supply a current second application snapshot (a working-tree application that compiles with the frozen toolchain) or re-specify the experiment

