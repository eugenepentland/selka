# Compiler work and reuse report

A `specialization_bodies` object reports concrete-specialization bodies actually
checked fresh and actually replayed; `instantiated_specializations` remains the
count of specializations present in the checked program and is not a reuse count.
A `symbolic_templates` object reports real checked/reused symbolic-template counts
alongside the ordinary work stages; a template replay is never inferred from an
unchanged fingerprint. Concrete specialization bodies are reported through the
ordinary `checked_bodies` performed/reused split: a replayed concrete
specialization increments `checked_bodies.reused` and does not increment
`checked_bodies.performed`, while `instantiated_specializations` still names how
many specializations the checked program contains. `--no-cache` counts the fresh
specialization checks it performed and reads or writes no entry.

`work-report-v1` separates **actual work and reuse** from the older reports that
compare input fingerprints. A comparison `hit` means "the compared input digest
is equal"; it does not mean the command reused a stored result. `work-report-v1`
counts executions and true cache hits at the sites that perform them, so a
forced fresh check with equal fingerprints still reports the work it performed.

```text
$ mylang check-project app/main.my --report
```

## Emission and versions

`mylang check`, `check-project`, `run`, `run-project`, `emit-qbe`,
`emit-project-qbe` and the other one-shot project commands emit one
`work-report-v1` JSON line on stderr when `--report` or `--timings=json` is
given. `--report --no-cache` still emits the work report (with a
`cache-disabled` bypass) because the work happened even though reuse was
disabled; it does not emit the `frontend-cache-v1` line, which describes an
opened persistent cache.

The earlier receipts are unchanged and remain **comparison-only**:

| version | meaning | migration |
| --- | --- | --- |
| `frontend-cache-v1` | per-stage comparison counts plus raw persistent-cache counters; emitted only when a persistent cache is open | keep parsing it for old consumers; read `work-report-v1` for actual work/reuse |
| `invalidation-report-v1` | nine-stage fingerprint comparison against the stored `project-dependencies-v1` baseline | unchanged; its `hit` is not reuse |
| `work-report-v1` | seven actual-work stages, true reuse, bypasses and session totals | the authoritative receipt |

Consumers that fan out several JSON Lines on stderr should select the object
whose `version` is `work-report-v1`; do not assume a single stderr line.

## Shape

```json
{"version":"work-report-v1","command":"check-project",
 "fingerprint_unchanged":true,"reused":false,
 "parsed_modules":{"status":"miss","performed":2,"reused":0},
 "checked_bodies":{"status":"miss","performed":2,"reused":0},
 "instantiated_specializations":{"status":"miss","performed":0,"reused":0},
 "lowered_functions":{"status":"skipped","performed":0,"reused":0},
 "emitted_fragments":{"status":"skipped","performed":0,"reused":0},
 "links":{"status":"skipped","performed":0,"reused":0},
 "executed_tests":{"status":"skipped","performed":0,"reused":0},
 "reused_results":0,"session_reused_results":0,
 "bypassed":[{"reason":"semantic-reuse-unavailable","count":1}],
 "session":{"parsed_modules":{"performed":2,"reused":0}, "...":"..."}}
```

- `fingerprint_unchanged` is the invalidation comparison result and is omitted
  when no comparison ran. It is **not** `reused`.
- `reused` is true only when a lookup actually returned a stored result or a
  verdict was actually replayed.
- Each stage object carries `status` (`hit`, `miss` or `skipped`), `performed`
  (fresh executions) and `reused` (true cache hits). `skipped` means the command
  never reached the stage and is never counted as reuse.
- `reused_results` counts whole-result reuse that is not one of the seven stages,
  such as a replayed `check-project` verdict.
- `bypassed` lists disabled optimizations with a static reason tag.
- `session` repeats the seven stages as cumulative process totals. For a
  one-shot process the request counters are the session counters.

## Stage semantics

| stage | counted where |
| --- | --- |
| `parsed_modules` | module bodies lexed and parsed fresh vs returned by the in-process or persistent syntax lookup |
| `checked_bodies` | `sema` body-check iterations vs checked-body and concrete-specialization copies |
| `instantiated_specializations` | concrete specializations present in the checked program; a specialization body replay is an actual `checked_bodies.reused` hit |
| `lowered_functions` | functions in the retained bytecode program after lowering |
| `emitted_fragments` | independently linkable QBE units emitted |
| `links` | native publish/run steps; object-level build reuse is not claimed here |
| `executed_tests` | native guest-test executions; see below |

## Check sessions

`check-session-v1` replies add a `work` object:

```json
{"work":{"version":"work-report-v1","reused":true,
 "request":{"parsed_modules":{"performed":0,"reused":0},"...":"..."},
 "session":{"parsed_modules":{"performed":2,"reused":0},"...":"..."},
 "reused_results":1,"session_reused_results":1,"bypassed":[]}}
```

`request` values are deltas for that request and reconcile with the cumulative
`session` counters: the difference between consecutive `session` values is the
next `request`. `parsed_modules` and `checked_bodies` session totals come from
the caches' own cumulative execution-site counters.

## Native tests

`mylang test` keeps its `native-tests-v1` receipt. Its `executed` field counts
tests that ran (`passed + failed`) and `cached` counts replayed receipts, so
`executed + cached == selected` for a successful run. `work-report-v1` names the
same quantity as `executed_tests`; emitting it from the native-test command needs
the test-selection integration (C4). Until then a consumer reconciles
`work-report-v1.executed_tests` for ordinary commands with `native-tests-v1` for
`mylang test`.

## Limitations

- Link-stage object reuse inside the native build is not distinguished; the
  report conservatively counts a publish step and never claims link reuse.
- `instantiated_specializations` is observed from the fresh checked program, not
  from a specialization reuse engine (that is C3).
- One-shot checked-body reuse is implemented by C2 for ordinary `check`,
  project checking, `build`, `run` and native-test preparation. The one-shot
  `checked_bodies.reused` count is observed at the body-copy site, not inferred
  from a fingerprint; a `bypassed` reason names an exact conservative fresh-path
  cause when a body cannot be admitted. Generic specialization reuse remains C3.
