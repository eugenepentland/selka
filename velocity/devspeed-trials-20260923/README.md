# Development-speed trials, 23 September 2026

The harness and evidence behind
[`docs/audits/development-speed-2026-09-23.md`](../../docs/audits/development-speed-2026-09-23.md):
the first Lane A (task velocity) measurements and the scale ladder against Go, Rust and
Zig. Sources and small fixtures only; large generated inputs are rebuilt from fixed seeds.
This is the starting point for recommendation 9 (turn it into `velocity/solve.py` and a
Lane B ratchet).

| Path | What it is |
| --- | --- |
| `tasks/spec_*.md` | Task specifications given to agents (T1 wordfreq, T2 calc, T3 route, T5 csvstats, T6 logstats, T4 Lox `%`, maintenance `break` and `gcbug`) |
| `hidden/ref_*.py` | Independent reference implementations used to generate expected outputs |
| `hidden/gen_hidden.py`, `hidden/gen_logstats.py` | Regenerate the hidden cases for T1/T2/T3/T5 and T6 (deterministic seeds) into `hidden/cases/` |
| `hidden/cases/{lox,break,gcbug}` | Hand-made and binary-derived Lox cases (kept, not regenerable from a script) |
| `hidden/grade.py RUN_DIR TASK` | Runs `RUN_DIR/build.sh` then `RUN_DIR/prog` on every case of TASK |
| `hidden/grade_maint.sh`, `maint/setup_maint.py` | Maintenance trials on the Lox port in four languages (setup plants the GC bug) |
| `hidden/transcript_stats.py`, `hidden/aggregate.py` | Per-agent statistics from Claude Code subagent transcripts (tool calls, tokens, docs read, time to first edit) |
| `tools/make_shim.py` | Logging wrapper for a toolchain binary (argv, exit, duration, stderr head as JSON lines) |
| `tools/latency.py`, `tools/mutfix.py` | Edit-loop latency probe; the first project-wide `mut` marker migrator |
| `scale/gen_scale.py`, `scale/run_scale.py`, `scale/tooling_probe.py` | The scale ladder (same chain project in mylang/Go/Rust/Zig) and the large-codebase tooling probe |
| `scale/results/` | Ladder results: `t10k`/`t50k`/`t200k`, `results.json` = mylang release build, `results-mylang-debug*.json` = Debug/QBE |
| `results/` | Aggregated trial evidence, grades, idiom scores, and every agent's `FRICTION.md` |
| `kit/PRIMER.md` | The one-page primer tested in wave 2 (superseded by `docs/primer.md`) |
| `LANE-RULES.md` | Rules given to the implementation lanes (server-specific paths, as of 24 September 2026) |

The scripts were written on the Linux server and hard-code its paths
(`/home/epentland/...`, the session scratchpad under `/tmp/claude-1000/...`). Before
reusing one, point its path constants at this directory and your compiler.

Regenerate the large hidden cases:

```bash
cd velocity/devspeed-trials-20260923/hidden && python3 gen_hidden.py && python3 gen_logstats.py
```
