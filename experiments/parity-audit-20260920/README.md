# parity-audit-20260920 — evidence for the LLVM-arena-vs-Zig parity audit

Report: [`docs/audits/llvm-arena-parity-gap-2026-09-20.md`](../../docs/audits/llvm-arena-parity-gap-2026-09-20.md).
Companion (same day, independent): [`docs/audits/llvm-zig-parity-2026-09-20.md`](../../docs/audits/llvm-zig-parity-2026-09-20.md),
whose `root_stores` transformation this audit reuses through `scripts/rootclean.py`.

Everything here was produced on 2026-09-20 against compiler `zig-out/bin/mylang`
(sha256 prefix `2c2ed027cb8108361`, tree `b8f6ec3f` plus the uncommitted working
tree), the chart's arm `.tmp/bench/armsset/maxperf/whole-o3.bin`
(`efdb3c3267a6ad2c2`), the frozen Zig reference
`.tmp/llvm-streaming-20260919/before/zig` (`a65cfc5c18757a696`) and the input
`.tmp/runtime-audit-20260919/input8.sexp` (`368ebdee5164fdba7`). Full hashes of
every measured binary are in `measurements/hashes.txt`.

| path | contents |
|---|---|
| `scripts/probe.sh NAME SRCDIR [arms]` | builds the `whole-o3` (and `compact-o3`) arena arm for one copy of the port, the way `.tmp/bench/arms.sh` does |
| `scripts/rootclean.py BUILD ARM` | regenerates an arm's merged IR with the companion audit's private-root-record removal, after asserting the arm's own lowering reproduces its IR; links it as `maxperf/build.py` does |
| `scripts/lto.sh ARMDIR OUT FORMATTER COMMON…` | rebuilds an arm as `zlink` (zig-linked, no LTO) and `lto` (runtime as bitcode, one LTO unit); replaces `--wrap` by renaming |
| `scripts/measure.py out.json name=path…` | nine `perf stat` rounds per arm and workload on CPU 6, output byte-compared to the Zig reference first |
| `probes/pa.diff` | `scalar_len` as byte length — views as values, upper bound |
| `probes/pb.diff` | scalar `kind` on the parser cursor — field snapshot through a class |
| `probes/pc.diff` | bare-`Node` parse path — no `Result` wrapper copies |
| `probes/pall.diff` | the three combined |
| `probes/pres.diff` | `pall` plus a pre-reserved output buffer — growth garbage |
| `measurements/probes.json` | batch 1: zig, chart, ctl, ctl-compact, pa, pb, pc, pall, pall-compact |
| `measurements/pres.json` | batch 2: ctl, pall, pres |
| `measurements/lto.json` | batch 3: zig, pall-compact, zlink, lto |
| `measurements/interleaved-pb-pc.json` | 15 interleaved rounds of ctl/pb/pc/pall, raw per-round cycles and instructions |
| `measurements/rootclean.json` | batch 4 (loaded machine, deltas only): zig, ctl, ctl-rootclean, pall-compact, pallc-rootclean, zlink-rootclean, lto-rootclean |
| `measurements/final-interleaved.json` | final batch: 15 random-order interleaved rounds of zig, chart, ctl-rootclean, pallc-rootclean, lto-rootclean, final; raw per-round task-clock, cycles user/kernel, instructions, faults |
| `profiles/self-*.txt` | `perf report --no-children` self-cycle shares: `W`=chart arm, `Z`=Zig, `pallc`=pall-compact, `lto`, `ltorc`=lto-rootclean |
| `profiles/inclusive-*.txt` | LBR call-chain inclusive shares for the chart arm and the LTO arm on render |

The probe sources live in the session scratchpad and are reproducible from the
diffs against `experiments/sexpr-port`. The huge-page experiment
(`GLIBC_TUNABLES=glibc.malloc.hugetlb=1`) and the allocation model are
reproduced from the commands quoted in the report.
