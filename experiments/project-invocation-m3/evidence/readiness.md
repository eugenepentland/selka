# M3 readiness

captured 2026-09-20T13:05:36.888459+00:00

## Applications

| application | snapshot | public workload | seconds | compiler diagnostics | ready |
| --- | --- | --- | ---: | --- | --- |
| planner | b1795b992bdc7240 | failed | 0.042 | E_REMOVED_SPELLING | False |
| sexpr-port | c7b43e6be85e387e | passed | 38.227 | none | True |

## Cases

| case | split | application | preflight |
| --- | --- | --- | --- |
| sexpr-percent | pilot | sexpr-port | ready=True reference=True regression=True wrong-repairs=True arms=True |
| sexpr-invalid-input | pilot | sexpr-port | ready=True reference=True regression=True wrong-repairs=True arms=True |
| sexpr-units | main | sexpr-port | ready=True reference=True regression=True wrong-repairs=True arms=True |
| sexpr-escaping | main | sexpr-port | ready=True reference=True regression=True wrong-repairs=True arms=True |
| sexpr-nesting | main | sexpr-port | ready=True reference=True regression=True wrong-repairs=True arms=True |
| planner-empty | pilot | planner | blocked — the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14 |
| planner-zero-duration | pilot | planner | blocked — the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14 |
| planner-chain | main | planner | blocked — the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14 |
| planner-ties | main | planner | blocked — the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14 |
| planner-boundary | main | planner | blocked — the frozen planner snapshot does not compile with the frozen toolchain: `E_REMOVED_SPELLING` for `=>` and `&`, and `E_EXPORT_REMOVED` for plain `export`; it predates the Wave 1 surface migration of 2026-09-14 |

## Readiness blocker

The runbook's rule is explicit: if either named application cannot pass preflight with the chosen current toolchain, stop and report readiness as the blocker before spending on participants. No port of an incompatible application was attempted; the scored task pack was not frozen and no session was launched.

### planner

- public workload: failed
- compiler diagnostics: E_REMOVED_SPELLING

```
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_REMOVED_SPELLING","severity":"error","message":"`=>` was removed and has no replacement","location":{"path":"main.my","start":{"line":10,"column":38},"end":{"line":10,"column":40},"bytes":{"start":219,"end":221}},"notes":[],"stack":{"frames":[],"omitted":0}}}
```

