# Performance parity plan — evidence (2026-09-22)

Evidence for [`docs/audits/performance-parity-plan-2026-09-22.md`](../../docs/audits/performance-parity-plan-2026-09-22.md).
Nothing here changes production source. The compiler under test is the
ReleaseFast install `.tmp/perf-audit-20260922/install-a3` (`acbee603` plus
schematic lanes 4, 2 and 3; the tree this directory is committed on,
`perf/schematic-integration` at `4d81f680`, adds only lane 1's runner policy).
The lane-5 compiler is `perf/schematic-5-aggregate-reads` at `24336bf2`
(code identical to `6dfbe274`), built ReleaseFast into
`.tmp/perf-plan-20260922/install-lane5`.

## Layout

| path | contents |
|---|---|
| `suite/SUITE.md` | the 11-program suite: algorithm, sizes, exact output rules |
| `suite/<bench>.{my,zig,rs}` | the ports; `<bench>_<variant>.my` are mylang variants (`_arena`, `_class`, `_tuned`, `_flat`, `_sorted`), `binary_trees_gpa.zig` a Zig variant |
| `suite/<bench>.expected` | the agreed stdout, reproduced independently by CPython transcriptions of SUITE.md |
| `suite/NOTES-agent-{a,b,c}.md` | the porting notes: friction, diagnostics, first observations, per-benchmark mechanisms |
| `suite/repro/` | compiler bugs and performance repros found while porting |
| `micro-rust/` | Rust ports of the eleven `perf-parity-audit-20260921/micro` kernels |
| `probes/` | small programs used to read the emitted IL and machine code |
| `bench.py` | build, qualify (byte-identical stdout) and time arms: fresh pinned processes, arms shuffled per round, wall and CPU time, paired bootstrap ratios to `zig-fast` |
| `rewrite_il.py` | counterfactual manifest rewrites, one language rule or lowering protocol at a time |
| `counterfactual.py` | emit → verify an unmodified rebuild is byte-identical → rewrite → build |
| `build_cf_arms.sh` | builds the per-rule counterfactual arms (`cf-*`, `l5-*`) |
| `build_ladder.sh` | builds the plan's composition ladder (`lad-*`) |
| `parser_bench.py` | S-expression parser census/render against `sexpr-port/zig-bench` |
| `schematic/` | arm spec and arms JSON for `schematic-parity-gap-20260922/scripts/bench_svg.py` |
| `prof.py` | SIGPROF self-PC profiles (hardware counters are unavailable: `perf_event_paranoid=4`) |
| `table.py` | render a result JSON as a ratio table |
| `results/` | raw rounds, ratios and profiles |

## Reproduce

From this directory, with the two compilers installed where the scripts expect
them (see the paths above; both are ordinary `zig build -Doptimize=ReleaseFast
--prefix DIR` installs, the lane-5 one built with `-j2` inside the 16 GB cgroup
of `~/capbuild` because four concurrent ReleaseFast compiles exceed it):

```sh
./build_cf_arms.sh binary_trees nbody ...          # per-rule counterfactuals
./build_ladder.sh binary_trees nbody ...           # the plan's rungs
python3 bench.py binary_trees ... --rounds 7 --cpu 6 --cf cf-nan ... --json results/x.json
python3 table.py results/x.json --ms --ci
```

`build_ladder.sh` needs an LLVM adapter copy that accepts QBE's `hlt`
terminator (a one-branch parser change, marked `AUDIT PATCH`); the unpatched
adapter already lowers `hlt` to `unreachable` in `llvm_emit.on_hlt` but its
parser refuses the opcode. With the patch, every unmodified build is
byte-identical to the stock adapter's.

## Result files

| file | batch | contents |
|---|---|---|
| `results/prelim-suite-a.json` | preliminary, 3 rounds, CPU 6 | first look at seven programs; superseded, kept for the record |
| `results/suite-fast.json` | 7 rounds, CPU 6 | ten programs: language arms, variants, every per-rule counterfactual, lane 5 |
| `results/suite-slow.json` | 5 rounds, CPU 8 | `nbody`, `fannkuch_redux`, `matmul`: the same arms plus the ladder |
| `results/ladder-fast.json` | 7 rounds, CPU 6 | the plan's ladder (`lad-*`) for the ten fast programs |
| `results/micro.json` | 7 rounds, CPU 6 | the eleven micro-kernels: mylang, Zig, Rust (new), variants, ladder |
| `results/parser.json` | 11 rounds, CPU 6 | S-expression census/render: a3 and lane 5, checked and `--unchecked`, against zig-bench |
| `results/parser-ladder.json` | 11 rounds, CPU 6 | the same parser: counterfactual and ladder binaries |
| `results/schematic.json` | 31 rounds × 3 inputs, CPU 6 | schematic SVG: a3 and lane 5 (GC, `--unchecked`, arena) against the Zig and Rust ports |
| `results/profiles/*.json` | SIGPROF | non-LTO `--keep-symbols` builds of the runtime-bound programs |

The parser is built from a copy of `experiments/sexpr-port` migrated from the
removed `mutates(...)` spelling to `mut` parameters and call-site markers (four
declarations, the call sites the compiler's `E_MUTATION_MARKER` diagnostics
named). The in-tree `experiments/sexpr-port` no longer compiles with the current
compiler and needs the same migration.
