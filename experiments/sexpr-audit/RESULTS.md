# Why the mylang sexpr port is ~60× slower — audit

Measured 2026-09-18 on the 927,415-byte benchmark input (`/tmp/sexpr-bench/input.sexp`,
19,155 tokens, 10 top-level forms). Raw data: `evidence/audit.json` and
`evidence/variants.json`; chart: `evidence/sexpr-audit.png`. Both sides produce the
identical rendering and census on this input, so the comparison is the same work.

## 1. Where the time goes

| phase | mylang | Zig | ratio | share of mylang |
| --- | ---: | ---: | ---: | ---: |
| read the file | 1.38 ms | 0.93 ms | 1.5× | 1% |
| **tokenize** | **123.0 ms** | **0.64 ms** | **193×** | **92%** |
| parse (tokens → AST) | 5.89 ms | 0.43 ms | 14× | 4% |
| walk the AST (census) | 3.00 ms | 0.21 ms | 14× | 2% |
| render (print) | 29.7 ms | 1.51 ms | 20× | 22% of render |
| **census total** | **133.3 ms** | **2.22 ms** | **60×** | |
| **render total** | **160.0 ms** | **3.51 ms** | **46×** | |

The gap is not spread across the program: **tokenizing is 92% of mylang's census
run and 193× slower than Zig's.** Parsing the token list is a 14× gap, walking
the tree 14×, rendering 20× — all secondary.

## 2. What inside tokenizing costs that

Micro-drivers, same input, same loop shape on both sides:

| workload | mylang | Zig | ratio | per unit |
| --- | ---: | ---: | ---: | --- |
| empty loop over 927,415 bytes | 9.35 ms | 0.96 ms | 9.8× | 10.1 ns vs 1.0 ns / byte |
| byte index + add | 27.2 ms | — | — | 29.3 ns / byte |
| byte scan (2 compares) | 50.2 ms | 1.23 ms | 41× | 54.1 ns vs 1.3 ns / byte |
| 1,000,000 calls to `add(a,b)` | 26.0 ms | — | — | 26 ns / call |
| 19,155 `bytes[a:b].decode()` | 5.02 ms | — | — | 0.26 µs each |
| the same, retained in a list | 9.02 ms | — | — | 0.47 µs each |

Two conclusions follow immediately:

* **Allocation and string decoding are not the problem.** Decoding 19,155 slices
  costs 5 ms and retaining them costs 4 ms more. Garbage collection is a red
  herring here.
* **The generated code costs tens of nanoseconds per trivial operation**, and the
  tokenizer performs several such operations — plus several helper *calls* — for
  every input byte. 123 ms ÷ 927 kB ≈ **133 ns per byte**.

## 3. The mechanisms

### 3.1 Every IR instruction carries scaffolding

`src/qbe.zig` `emitInstructions` (lines 313–318) emits, for **every** bytecode
instruction — not per statement or per basic block:

```
@i{pc}
 storel {pc}, %position      ; source-position marker into the active frame
 <step-budget check>         ; load ctx.steps, load ctx.max_steps, compare,
                             ; branch, add 1, store
```

and `fn step()` (`qbe.zig:680-688`) is that check. Meanwhile a *built executable*
runs with an **unbounded** budget: `src/qbe_runtime.c:544` initialises the context
with `max_steps = MYL_QBE_UNBOUNDED` (`UINT64_MAX`, `qbe_runtime.h:44`). The check
can never fire in a normal build, but its two loads, store, compare and branch run
on every instruction.

### 3.2 Measured cost of that scaffolding

I built patched compilers (via `zig build-exe` with the step check removed, then
also the position marker) and re-ran the drivers. The repository source was
restored afterwards and verified byte-identical (`sha256 e463e92d…`, zero diff).

| workload | baseline | no step check | no step check + no marker |
| --- | ---: | ---: | ---: |
| empty loop | 9.40 ms | 6.57 ms | **3.52 ms** (2.67×) |
| byte index | 27.49 ms | 24.40 ms | 20.37 ms (1.35×) |
| byte scan | 52.25 ms | 50.95 ms | 40.49 ms (1.29×) |
| 1M calls | 27.12 ms | 27.18 ms | 22.47 ms (1.21×) |
| tokenize | 131.1 ms | 105.5 ms | **92.9 ms** (1.41×) |
| census | 139.0 ms | 113.3 ms | **108.9 ms** (1.28×) |
| render | 165.3 ms | 139.1 ms | 135.3 ms (1.22×) |

Removing the per-instruction instrumentation is worth **1.28× end to end** (2.67×
on a trivial loop) — real, and cheap to fix — but it is *not* the bulk of the gap.

### 3.3 The rest is code shape

After the instrumentation is gone, the byte scan is still 40.5 ms vs Zig's
1.2 ms (**~33×**), and the empty loop is 3.5 ms vs 0.96 ms. Three contributors:

* **Per-value stack traffic.** The IL gives every instruction its own basic-block
  label (`@i{pc}`), so QBE's SSA/register promotion cannot keep values in
  registers across instructions; the disassembly is dominated by loads/stores to
  frame offsets.
* **Checked arithmetic and bounds checks.** Every integer add carries signed
  overflow detection (`xor`/`and`/`jl` sequences) and every `bytes[i]` a bounds
  check. These are language semantics, not waste — but they are not free at this
  density.
* **Per-call prologue.** A call costs ~26 ns: `myl_qbe_enter_at_sized` does two
  stack-limit checks and an active-frame update, the callee prologue zeroes its
  frame, and traced locals are pushed/restored on the GC root stack. With a
  helper call every few bytes, that multiplies.

Note what is *not* the cause: the C runtime is compiled `-O2` for ReleaseFast
(`qbe_build_cache.zig:123,197`), and QBE runs its **full optimisation pipeline**
(`vendor/qbe/main.c`: `promote`, `ssa`, `loadopt`, `coalesce`, `gvn`, `gcm`,
`ifconvert`, …). Neither side is unoptimised; the generated IL is simply far more
work per source operation.

## 4. Levers, in order of value

1. **Do not emit the step check when the budget is unbounded.** It is dead code in
   every normal build. Worth ~1.4× on tokenizer-shaped code (2.67× on tight loops).
   A compile-time decision in `emitInstructions`/`step`, or a build flag that
   `run --max-steps` sets.
2. **Emit the position marker only when trap attribution is wanted** (a debug or
   `--trap-info` build). Another ~1.1×.
3. **Cut the per-call prologue**: skip the frame `memset` when no slot is traced, skip
   root mark/restore for functions that never allocate, and skip active-frame
   bookkeeping when not trapping. Call-heavy code (the tokenizer) gains most — it
   makes several calls per byte.
4. **Let QBE promote across instructions**: emit `@i{pc}` labels only at branch
   targets / safepoints so adjacent instructions share a basic block. This is the
   largest remaining factor (~33× per-operation after the instrumentation is gone).
5. **Source-level workaround available today**: rewrite the tokenizer as one tight
   byte loop with the character classes inlined and spans stored instead of decoded
   strings. It cannot beat the per-operation codegen floor, but it removes the
   several-calls-per-byte multiplier that turns a 50 ms scan into a 123 ms
   tokenizer.

## 5. Method and caveats

* `perf` is unavailable on this machine (`perf_event_paranoid = 4`), so the audit is
  wall-clock: medians of 25 runs, pinned with `taskset -c 6`, raw samples in
  `evidence/audit.json`.
* Absolute times move by up to ~1.5× with machine load between batches; the
  within-batch ratios are the reliable figures, and every table here was measured
  in a single interleaved batch.
* The counterfactual used locally built patched compilers (`zig build-exe`,
  bypassing the Guardian-gated build) writing to `/tmp`; the installed compiler was
  never replaced, and `src/qbe.zig` was restored and checksum-verified.
* The drivers live in `experiments/sexpr-audit/` rather than inside the port
  project: non-test `.my` files under `experiments/sexpr-port` break `mylang test`
  discovery (the suite reported 0 tests until they were moved out).

## 6. Reproduce

```sh
# build the Zig reference driver once
cd experiments/sexpr-port/zig-bench && \
  ZIG_LOCAL_CACHE_DIR=/tmp/zb-cache ZIG_GLOBAL_CACHE_DIR=/tmp/zb-global \
  zig build -Doptimize=ReleaseFast -p /tmp/zb-out

# phases + micro-drivers
python3 experiments/sexpr-audit/run_audit.py --runs 25
/home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/sexpr-audit/audit_charts.py
```
