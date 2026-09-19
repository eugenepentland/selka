# Runtime: Zig RF/RS, mylang RF, Go, and three Python ports

Produced by `compare_impls.py` (measure) and `runtime_charts.py` (draw). Input is
the same 927,415-byte EDA-module sexpr file as the earlier charts
(`sha256 0a670a08470e5b19…`, the 185,482-byte `poe-pd-flyback-tps23757` module
repeated five times). Every implementation runs the same phase on the same bytes,
31 interleaved rounds pinned to one core, medians reported. Everything the run
needs is built under the gitignored `.tmp/sexpr-implcmp/`, because this sandbox
makes `/tmp` private to a single process invocation.

Seven columns, all printing the same stdout lines as `zig-bench`:

| column | source | notes |
| --- | --- | --- |
| `zig ReleaseFast` / `zig ReleaseSafe` | `experiments/sexpr-port/zig-bench` | pinned zig 0.17.0-dev.1683 |
| `mylang ReleaseFast` | `main.my` + the audit drivers | `mylang build --mode ReleaseFast` |
| `go` | `go/main.go` | Go 1.27.0, straight port |
| `python pure` | `python/sexpr_pure.py` | stdlib only, hand-rolled byte tokenizer |
| `python + libs` | `python/sexpr_np.py` | numpy for `--scan`, `re` for tokens |
| `python tuned` | `python/sexpr_tuned.py` | same core, rewritten tokenizer |

## Process wall clock (ms, median of 31)

Compiled engines:

| phase | Zig RF | Zig RS | mylang RF | Go | RS÷RF | mylang÷RF | Go÷RF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| loop (empty while) | 1.535 | 1.313 | 4.184 | 1.775 | 0.85× | 2.7× | 1.16× |
| scan (byte compare) | 1.887 | 1.679 | 6.022 | 2.000 | 0.89× | 3.2× | 1.06× |
| tokens (read+tokenize) | 2.306 | 2.185 | 29.196 | 2.442 | 0.95× | 12.7× | 1.06× |
| parse | 2.906 | 2.751 | 32.259 | 5.580 | 0.95× | 11.1× | 1.92× |
| census (parse+walk) | 2.995 | 2.908 | 33.212 | 5.721 | 0.97× | 11.1× | 1.91× |
| render | 4.492 | 4.291 | 57.427 | 8.599 | 0.96× | 12.8× | 1.91× |

Interpreted columns (same CPython 3.14.4; start-up included):

| phase | python pure | python + libs | python tuned | pure÷RF | libs÷RF | tuned÷RF | tuned÷pure (process) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| loop | 21.487 | 26.482 | 26.369 | 14.0× | 17.3× | 17.2× | 1.23× |
| scan | 21.346 | 52.381 | 52.048 | 11.3× | **27.8×** | 27.6× | 2.44× |
| tokens | 38.819 | 39.407 | 26.044 | 16.8× | 17.1× | 11.3× | 1.49× |
| parse | 45.733 | 47.128 | 32.975 | 15.7× | 16.2× | 11.4× | 1.39× |
| census | 47.212 | 48.426 | 34.515 | 15.8× | 16.2× | 11.5× | 1.37× |
| render | 53.549 | 54.428 | 40.475 | 11.9× | 12.1× | 9.0× | 1.32× |

## In-process work (ms, median of 31; start-up and imports excluded)

Each Python driver writes `work_ms` to stderr; it covers read + phase work only.
The compiled columns have no separate figure — their start-up is sub-ms, so their
process wall clock *is* the work.

| phase | python pure | python + libs | python tuned | libs speed-up | tuned speed-up |
| --- | ---: | ---: | ---: | ---: | ---: |
| loop | 12.253 | 12.581 | 12.592 | 0.97× | 0.97× |
| scan | 12.180 | 1.091 | 1.067 | 11.2× | **11.4×** |
| tokens | 29.370 | 25.267 | 12.244 | 1.16× | **2.40×** |
| parse | 35.984 | 32.709 | 18.662 | 1.10× | **1.93×** |
| census | 37.241 | 34.013 | 20.177 | 1.09× | **1.85×** |
| render | 41.621 | 38.324 | 24.362 | 1.09× | **1.71×** |

## What the numbers say

1. **Go is essentially Zig's equal on the byte-level phases and ~1.9× on the
   tree phases.** loop 1.8 ms (1.16× Zig), scan 2.0 (1.06×), tokens 2.4 (1.06×),
   then parse 5.6, census 5.7, render 8.6 ms — all 1.9× Zig. The tokenizer reaches
   Zig speed because both are tight index loops over `[]byte`; the gap opens where
   nodes are allocated, which is where Go pays for slice headers and the GC and
   Zig pays an arena. Go beats mylang ReleaseFast on all six phases (2.7–12.8×).

2. **Tuned Python turns "Python loses to mylang" into "Python roughly ties or
   beats mylang" on the tree phases.** In-process, the new tokenizer is 2.4× the
   naive one on `tokens` and carries through to parse (1.93×), census (1.85×) and
   render (1.71×). End to end, `python tuned` is 26.0 ms on tokens against
   mylang's 29.2 (0.89×), 40.5 ms on render against 57.4 (0.70×), and a tie on
   parse/census (1.02×/1.04×). mylang still wins the byte-level phases by a wide
   margin: loop 6.3×, scan 8.6× (numpy scan *work* alone is 0.18× mylang, but its
   import is not).

3. **The libraries only buy the byte-level phase; tuning is what moves the rest.**
   numpy makes `scan` 11.2× faster in-process but is not even the best tool:
   stdlib `bytes.count(40) + bytes.count(41)` is 0.363 ms warm against numpy's
   0.408 ms. `re` buys only 1.16× on `tokens`, and the shared tree code is
   unchanged, so the library column is 1.09–1.10× on parse/census/render. The
   1.7–2.4× on those phases comes from rewriting the tokenizer, not from a
   library. `loop` is at parity in both (0.97×) — there is nothing to vectorise.
   `evidence/scan-floor.md` takes the byte-level phase to its limit with a
   static assembly scanner, a hand-written QBE IR scanner and an LLVM control.
   With the *same* SWAR loop, QBE and LLVM tie (0.97 vs 0.96 ms) — the earlier
   "QBE IR beats Zig ReleaseFast" was the algorithm and the bare driver talking,
   not codegen — and mylang's 3.18 ms is an IR/runtime cost, not a QBE backend
   ceiling.

4. **Zig ReleaseSafe is faster than ReleaseFast again** (0.85–0.97×), a fourth
   independent batch. The safe build keeps bounds and overflow checks, so this is
   not "safety is free" in general; on this workload the fast build's more
   aggressive optimisation evidently buys code size or layout that costs more
   than the checks it removes.

5. **mylang still has no ReleaseSafe guest mode**, so its column is the best case
   (`--mode ReleaseFast`, no instruction-budget accounting).

## Other ways to make the Python faster

The profile is unambiguous: **tokenization dominates**. In-process, `tokens`
costs 29.4 ms of pure Python and parse/census/render only add ~6–12 ms on top;
inside the tokenizer, `re.Pattern.match` alone accounted for ~24 ms of a 43 ms
cProfile run (37,075 calls, ~18,000 of them whitespace runs). What was tried:

| lever | result |
| --- | --- |
| One `finditer` pass instead of `match` per token | no gain on its own (26.4 vs 24.7 ms); the per-match Python work, not the call, dominates |
| **Unrolled string subpattern** `"[^"\\]*(?:\\.[^"\\]*)*"` | **~10×** on the string scan: 2.73 ms vs 27.0 ms for `"(?:\\.\|[^"\\])*"`, and exactly correct (5,145 matches, same as the escape-aware form) |
| Number grammar folded into the pattern (possessive `\d++…?+` on the fallback-atom arm) | removes the per-number `match` + tail extension; needed `++`/`?+` to stop `12.063` being read as an atom |
| Masking strings/comments to spaces, then a second token regex | slower and more complex; not used |
| numpy for anything but `scan` | no benefit; the parser/census/printer are pointer-chasing, not array math |
| `python -S` (skip site) | 9.89 → 6.68 ms start-up, ≈3.2 ms off every phase; not applied here to keep the three Python columns on one interpreter invocation |
| `-X jit` / `PYTHON_JIT=1` | no measurable effect on this build (loop 31.2 → 30.4 ms, within noise) |
| PyPy / Cython / mypyc / Nuitka | not installed, and would be a different runtime rather than "the Python code" — PyPy is the one with a real chance of a large win |

Net effect of the tuning that landed, per phase, is the `tuned speed-up` column
above: **2.4× on tokens, 1.9× parse, 1.85× census, 1.71× render**, with identical
tokens (verified token-for-token against the reference tokenizer before the
digest check).

Two hard floors remain, and neither is addressable in the source:

* **Interpreter start-up.** `work_ms` is 12.3 ms but the process is 21.5 ms on
  `loop`: ~9.2 ms of every interpreted run is interpreter start-up before the
  input is even opened (~13.8–16.1 ms for the numpy/regex ports, and ~51 ms for
  `scan` once the 32.4 ms numpy import is charged). Go's *entire* run is
  1.8–8.6 ms.
* **The input itself.** 927,415 bytes is below the size at which a library's
  import cost amortises. numpy is a net loss on this workload end to end.

## Output identity

Byte-identical across all seven implementations for `scan`, `parse`, `census`
and `render` — including the tuned tokenizer, which produces a token-for-token
identical list. `loop` and `tokens` are identical across Zig RF, Zig RS, Go and
all three Python ports; mylang differs only in its own summary line
(`bytes=… count=…` rather than `bytes=… index=…`, and `tokens=` counting the
`eof` token). Digests are in `runtime-compare.json`.

Go gets there with `strconv.FormatFloat(v, 'f', -1, 64)`, which is the same
shortest-round-trip-positional spelling as Zig's `{d}`; the Python ports use
`zig_decimal()`, verified against a Zig `{d}` harness on 27 edge cases.

## Caveats and method notes

* **The mylang column is a moving target, and moved again mid-session.** The
  working tree is being rebuilt while this runs: `zig-out/bin/mylang` was written
  at 20:50:55 during the benchmark, and `src/qbe.zig` changed at 20:54. The
  `mylang ReleaseFast` binaries are rebuilt from whatever `zig-out/bin/mylang` is
  when the harness starts. The same workload across three compiler builds:

  | phase | before 19:39 | 20:11 build | 20:50 build |
  | --- | ---: | ---: | ---: |
  | loop | 3.53 | 3.82 | 4.18 |
  | scan | 46.49 | 6.39 | 6.02 |
  | tokens | 89.45 | 52.30 | 29.20 |
  | parse | 93.06 | 56.20 | 32.26 |
  | census | 94.75 | 59.68 | 33.21 |
  | render | 120.10 | 82.71 | 57.43 |

  Treat the mylang ratios as a snapshot, not a stable baseline; Zig, Go and the
  Python columns were stable across all of these runs.
* **The three Python columns run under one interpreter** — CPython 3.14.4 from
  `/home/epentland/ai/canopy/rust-workflow/.venv/bin/python` (chosen because it
  has numpy) — so the differences between them are code, not runtime. The tuned
  tokenizer needs CPython ≥3.11 for possessive quantifiers.
* **Python token text is a bytes slice (Zig/Go-style), not an eagerly decoded
  `str` (mylang-style), and no line/column span is materialised.** Spans never
  reach the output; this is a small constant work reduction that favours all
  three Python columns equally.
* **numpy is imported lazily, only for `--scan`** (median 32.4 ms), and reported
  separately as `import_ms`; the other phases pay only `import re`.
* **`work_ms` excludes interpreter start-up, module import and the final stdout
  write.** The process columns include all three.
* Load average was 4.32 / 3.54 / 2.93 at the start and 3.09 / 3.31 / 2.87 at the
  end; the machine is shared. Absolute times move with load; the ratio columns
  are the comparable numbers.
* `go` is Go 1.27.0; `zig` is the pinned `0.17.0-dev.1683+5ceec001b`; the Zig
  drivers are built from `experiments/sexpr-port/zig-bench`.

## Reproduce

```sh
# regenerates the input, builds the Zig drivers, the Go driver and the six
# mylang phase binaries under .tmp/sexpr-implcmp, then measures; --rebuild forces
python3 experiments/sexpr-audit/compare_impls.py --runs 31

# draw the linear-axis figure (matplotlib needs a writable config dir here)
MPLCONFIGDIR=$PWD/.tmp/mplcfg \
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
  experiments/sexpr-audit/runtime_charts.py
```

`compare_impls.py` takes `--runs`, `--input`, `--rebuild`; `runtime_charts.py`
takes the JSON path and `-o`. Raw medians, every sample, in-process work samples,
per-phase import times, output digests and the load average are in
`evidence/runtime-compare.json`.
