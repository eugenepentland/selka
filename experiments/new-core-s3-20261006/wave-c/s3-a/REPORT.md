# S3-A: application admission and measurement foundation

Source dependency: `f1319a774d638c664de9f02bb27098650a13249b` (qualified S3-C,
S3-T1 and S3-T2 integration). This checkpoint qualifies application admission,
literal split fidelity and strict native correctness. **It does not qualify
the application performance gate or S3 exit.** Profile-driven repairs follow.

`split_apps.py --check` verifies five saved fixtures against literal helper and
dispatch-body extraction from the unchanged expanded sources. Row selection and
unused setup/helpers are removed; timed algorithms, input distributions and
checksums remain the originals. Rust and Zig reference sources/binaries are
unchanged. `word_count` was built and measured first.

`measure_all40.py` retains the S2 API, registry and timing method, adds five
applications and records separate new/old and new/Zig ratios and misses. Every
native sample requires exit zero, exactly `checksum elapsed_ns\n`, one positive
finite user-cycle counter and consistent checksums across old/new/Rust/Zig.
Three one-iteration startup samples are subtracted from seven shuffled,
interleaved rounds. Both sizes are 4096/64 and each ratio limit is 1.10.
The original 35 row iteration counts, units and reference naming are unchanged.
Application counts for 4096/64 are word_count 400/25000, CSV 40/2500, JSON
20/1250, packet 400/25000 and Lox 40/2500, normalized per dataset element.

The protected old oracle and adjacent QBE were copied from the coordinator's
qualified corrected oracle, not the pre-D2 S2 baseline. Source commit
`65036fe792ef540392d0eb00c41c9ec71c7b2c82`; the corrected ENV-NAMES-GRANT-1 full
old gate qualified this pair. Compiler SHA-256
`d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`; QBE
`b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
The new compiler was installed from this worktree's source. No copied new binary
or linked old runtime object is used.

All build-heavy runs hold the gate and build slots using the required preserving
shell wrapper. Timing/profile runs also hold
`/run/user/1000/mylang-s2-cpu10.lock`; native perf children use CPU 10 only.
Each command has a unique log. Runtime reference worktrees are preserved.

| Check | Command after slot wrappers | Result and retained evidence |
|---|---|---|
| Own-source installation | `python3 …/wave-a/exclusive_core.py -- /usr/bin/time -f '%e' -o …/logs/core-install-01.time zig build core --summary all` | 3/3 successful; 2.73 s uncontended command time, MaxRSS 374M; `logs/core-install-01.*` |
| Tool syntax and strict parser smoke | `python3 -m py_compile …/{split_apps,measure_all40,qualify_apps}.py`; `measure_all40.py --smoke-test`; `split_apps.py --check` | Registry40/S0 mapping/strict parser/signal-exit checks pass; all five fixtures match extraction |
| Original/split and import qualification | `qualify_apps.py --bin .mylang-cache/s3-a/qualification-01 --evidence …/qualification-01` | 137 native executions; five apps agree with unchanged original-old suites, split old, new debug/release/verify; strict leak/status/stdout checks pass. Unchanged full text entry also reaches strings.repeat and JSON in all three new modes. `qualification-01/summary.json`, per-build command/status logs, `logs/qualification-01.txt` |
| First word row | `flock -x …/mylang-s2-cpu10.lock python3 …/measure_all40.py --build --rows word_count --bin .mylang-cache/s3-a/word-count-01 --json …/word-count-01.json` | Valid and checksum matched, Zig miss at both sizes; `logs/word-count-01.txt` and `word-count-01.json` |
| Other four app rows | Same tool with `--rows csv_aggregate,json_transform,packet_decode,lox_eval --bin .mylang-cache/s3-a/apps-01 --json …/apps-01.json` | All builds/samples valid and checksum matched; Lox passes both gates; other three miss. `logs/apps-01.txt`, `apps-01.json` |
| Miss profiles | Locked CPU10 `perf record -F 997 -e cpu_core/cycles/u -g`; `perf report --stdio --no-children --call-graph none --sort symbol --percent-limit .5` | No lost samples. Compact hotspot reports and separate native record logs retained; binary perf data remains in private `.mylang-cache/s3-a` |

Qualification cases are `(size, iterations, seed)` = `(2,1,7)`, `(64,3,7)`,
`(65,1,17)`, `(4096,1,7)`, `(4100,3,17)`. Each new execution uses
`MYL_CORE_LEAKCHECK=1`. An abnormal status, unexpected stdout or any stderr fails
qualification. The full original text entry additionally runs string_equal and
json_transform at `(64,3,7)` in debug/release/verify mode. Programs use only the
benchmark's linked clock; no filesystem, entropy or network fixture is needed.

## Initial application table and required repairs

Every pair is 4096/64 in user cycles per dataset element.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---:|---:|---|
| word_count | 291.503 / 376.509 | 98.356 / 112.269 | 59.308 / 66.142 | 47.299 / 51.341 | .337 / .298 | 2.079 / 2.187 | miss |
| csv_aggregate | 4891.612 / 4151.454 | 2006.595 / 1806.958 | 1169.335 / 1058.373 | 1043.786 / 985.930 | .410 / .435 | 1.922 / 1.833 | miss |
| json_transform | 13655.770 / 14018.850 | 3160.786 / 3378.116 | 1780.526 / 1976.507 | 2817.246 / 2846.019 | .231 / .241 | 1.122 / 1.187 | miss |
| packet_decode | 15.529 / 15.074 | 48.339 / 48.973 | 10.277 / 10.667 | 18.937 / 19.452 | 3.113 / 3.249 | 2.553 / 2.518 | miss |
| lox_eval | 629.947 / 659.469 | 206.056 / 214.010 | 165.150 / 171.446 | 504.490 / 521.745 | .327 / .325 | .408 / .410 | pass |

Word profile (741 samples): whitespace split 18.65%, block allocation 17.39%,
string hashing 17.74%, block cleanup 8.96% plus block free 3.27%. Emitted IR has
one dictionary probe per input word; materializing every split piece dominates.
The coordinator authorized generic whitespace cursor fusion, with borrowed
spans for lookup and owned materialization plus same-key reprobe only at insert.
No view may escape or travel through a phi; nonqualifying consumers retain the
materialized implementation.

CSV profile (2K samples): equality 18.76%, append 17.74%, allocation 10.01%,
character creation 8.61%, width 7.00%. Character values have multiple comparison
and append consumers; the existing single-use append fusion cannot cover them.
JSON (1K samples): allocation 15.31%, buffer push 14.08%, read_value 7.81%, block
cleanup 7.61%, read_string 7.50%, byte index offset 6.02%. Packet (4K samples):
byte index offset 55.56%, main 40.59%, error traces 3.85%. Owning-package repairs
are routed through the coordinator. No shared compiler source changed at this
foundation checkpoint.

Inherited compiler correctness at `f1319a77` is the coordinator's qualified
254/254 Core32 gate and full 1518/1518 debug/release strict conformance with zero
mismatch or unsupported test, including leak/fact verification. This checkpoint
adds no compiler or gate-list source, so does not rerun that unchanged proof.
The next compiler source change receives fresh required qualification. Frozen
`ir.zig`, record phi ownership, first-64 aggregate parameter masks and persisted
formats remain unchanged. No main merge or push occurred.
