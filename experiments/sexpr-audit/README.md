# sexpr-audit — where the mylang execution gap comes from

Driver programs and a harness that decompose the mylang-vs-Zig execution gap on
the sexpr workload. Findings, numbers and caveats: **[RESULTS.md](RESULTS.md)**.
Chart: `evidence/sexpr-audit.png`; raw samples: `evidence/audit.json`.

`sexpr` is a symlink to `../sexpr-port/sexpr`, so this directory is its own small
project importing the port's modules. (Non-test `.my` files placed *inside*
`experiments/sexpr-port` break `mylang test` discovery, which is why they live
here.)

Each driver prints one short line, so process time is the measurement:

| driver | workload |
| --- | --- |
| `a_read` | read the input only |
| `b_tokens` | read + tokenize |
| `c_parse` | read + tokenize + parse, no walk |
| `d_decode` | 19,155 `bytes[a:b].decode()` calls |
| `e_scan` | every byte with two comparisons |
| `f_calls` | 1,000,000 calls to `bump(n)` |
| `g_append` | `d_decode` plus retaining each result in a list |
| `h_loop` | empty two-statement loop over the byte count |
| `i_index` | every byte read and added |
| `j_one` | one-statement loop (per-statement baseline) |
| `k_three` | three-statement loop (per-statement slope) |
| `l_calls2` | 1,000,000 two-argument calls |

`run_audit.py` builds them, runs the phase and micro measurements for both
implementations, and writes `evidence/audit.json`:

```sh
# build the Zig reference driver once
cd experiments/sexpr-port/zig-bench && \
  ZIG_LOCAL_CACHE_DIR=/tmp/zb-cache ZIG_GLOBAL_CACHE_DIR=/tmp/zb-global \
  zig build -Doptimize=ReleaseFast -p /tmp/zb-out

python3 experiments/sexpr-audit/run_audit.py --runs 25
/home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/sexpr-audit/audit_charts.py
```

The Zig side of the phase and micro workloads is `experiments/sexpr-port/zig-bench`
(`--read`, `--tokens`, `--parse`, `--loop`, `--scan`, `--render`, default census).

## Seven-way runtime comparison (adds Go and Python)

`compare_impls.py` measures the same six phases on Zig ReleaseFast, Zig
ReleaseSafe, mylang ReleaseFast, a Go port and three Python ports (pure,
numpy/regex, and a tuned-tokenizer variant), and `runtime_charts.py` draws the
figure. Findings and caveats: **[evidence/runtime-compare.md](evidence/runtime-compare.md)**;
chart: `evidence/runtime-compare.png`; raw samples: `evidence/runtime-compare.json`.

```sh
python3 experiments/sexpr-audit/compare_impls.py --runs 31
MPLCONFIGDIR=$PWD/.tmp/mplcfg \
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
  experiments/sexpr-audit/runtime_charts.py
```

The ports live in `go/` (`main.go`, a straight port) and `python/`:
`sexpr_pure.py` (stdlib only), `sexpr_np.py` (numpy for `--scan`, `re` for token
scanning), `sexpr_tuned.py` (unrolled-string `finditer` tokenizer) and the shared
`sexpr_core.py` (parser, census, printer, Zig-compatible float spelling). All
seven implementations emit the same stdout line for `scan`, `parse`, `census` and
`render`. Scratch state is rebuilt under the gitignored `.tmp/sexpr-implcmp/`,
because the sandbox makes `/tmp` private to one process invocation.

## Scan floor (assembly, hand-written QBE IR, LLVM control)

`scan_floor.py` brackets the `scan` phase with implementations written directly
against the hardware and directly in mylang's backend IR — `asm/scan.s` (static
syscall-only x86-64: startup / read / scalar / SSE2 / AVX2), `qbe/scan.ssa` plus
`qbe/scan_swar.ssa` (hand-written QBE IL, scalar and 64-bit SWAR), and
`zigctl/scan_scalar.zig` / `zigctl/scan_swar.zig` (the same two loops in Zig
through `zig-bench`'s read/print path, compiled by LLVM). It also measures a
startup-only binary to expose the fixed cost. Findings:
**[evidence/scan-floor.md](evidence/scan-floor.md)**; chart:
`evidence/scan-floor.png`; raw samples: `evidence/scan-floor.json`.

```sh
python3 experiments/sexpr-audit/scan_floor.py --runs 151
MPLCONFIGDIR=$PWD/.tmp/mplcfg \
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
  experiments/sexpr-audit/scan_floor_charts.py
```

Headline: a static process start plus reading the 927 KB is ~0.94 ms; SSE2, AVX2
and both SWAR loops (hand-written QBE IR and a Zig/LLVM control) all sit within
noise of that floor. With the same SWAR loop QBE and LLVM tie (0.97 vs 0.96 ms),
so the hand-written IR was not out-generating LLVM — it had the better algorithm.
mylang's 3.18 ms is not the QBE backend's ceiling: the compiler-generated QBE
scalar loop is ~0.5 ms behind LLVM's, and the rest of the gap is the IR and
runtime the compiler emits.



