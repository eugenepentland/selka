# Review probes for P1 (Claude, 2026-10-09)

These are the probes behind §2 of `docs/audits/concurrency-plan-2-2026-10-09.md`.
They were run against `main` `ab85c16c2`.

Every probe `#include`s `core_rt_all.c`, which is not committed. It is the
runtime concatenated in the order `src/core/driver.zig`'s `runtime_source` uses.
Build each probe with `zig cc -O2 -g -std=c11 -pthread` (TSan probes add
`-fsanitize=thread`), as `src/core/native_fixture.zig` does.

| file | finding |
|---|---|
| `a/probe_growth.c` | A1: blocks carved under cross-thread frees |
| `a/probe_stacks.c` | A2: pool start under `RLIMIT_AS` |
| `a/probe_alarm.c` | A3: timeout handler parks |
| `a/probe_exit.c` | A4: exit status after pool start |
| `a/probe_tsan.c` | output staging and stand-ins under TSan (clean) |
| `b/walk.c` | B1: octets walked indexing shared text |
| `b/group.c` | B2: shared group races (TSan) |
| `b/tsan1.c` | shared text, dict and copy paths under TSan (clean) |
| `b/p1.ll` | `unordered` retain/release diamonds at `-O2` |
