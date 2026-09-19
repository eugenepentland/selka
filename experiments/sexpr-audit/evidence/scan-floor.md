# Scan floor: assembly, hand-written QBE IR, and an LLVM control

The six-phase comparison says which implementation is fastest; this one asks how
fast the `scan` phase can be at all. Same 927,415-byte input, same process-wall
methodology, 151 rounds pinned to one core, only the `scan` workload.

The implementations exist purely to bracket the floor:

| implementation | source | what it is |
| --- | --- | --- |
| `asm startup only` | `asm/exit.s` | static syscall-only binary that exits immediately |
| `asm read only` | `asm/scan.s` `VARIANT=0` | + `open`/`read` the whole file, count nothing |
| `asm scalar` | `asm/scan.s` `VARIANT=1` | + byte-at-a-time loop |
| `asm sse2` | `asm/scan.s` `VARIANT=2` | + 16-byte SSE2 blocks, unrolled 4× |
| `asm avx2` | `asm/scan.s` `VARIANT=3` | + 32-byte AVX2 blocks, unrolled 2× |
| `qbe ir scalar` | `qbe/scan.ssa` | hand-written QBE IL, byte-at-a-time loop |
| `qbe ir swar` | `qbe/scan_swar.ssa` | hand-written QBE IL, 8 bytes/iteration in 64-bit SWAR |
| `zig llvm scalar` | `zigctl/scan_scalar.zig` | control: `zig-bench`'s loop and read/print path, standalone |
| `zig llvm swar` | `zigctl/scan_swar.zig` | control: the *same SWAR loop* as the QBE IR, in Zig |

plus the existing Zig / mylang / Go / Python scan columns for reference. The asm
programs are static and syscall-only (no libc, no loader); the QBE programs are
`qbe` + `cc -static` against glibc and format their integers in IR. Every scanner
prints the same `bytes=<n> delims=<m>` line and matches the Zig digest
`b09d60647e53d710`.

## Results (ms)

The host is shared, so the **fastest observed** sample is the floor statistic and
the median is shown beside it. Sub-0.2 ms differences are at the noise level —
`asm sse2`'s minimum is below the read-only minimum, which is physically
impossible and marks the noise floor.

| implementation | min | p25 | median | min ÷ Zig RF | in-process |
| --- | ---: | ---: | ---: | ---: | ---: |
| asm sse2 | 0.827 | 1.086 | 1.194 | 0.77× | — |
| asm avx2 | 0.851 | 1.003 | 1.069 | 0.79× | — |
| asm startup only | 0.934 | 1.142 | 1.214 | 0.87× | — |
| asm read only | 0.939 | 1.150 | 1.230 | 0.87× | — |
| **zig llvm swar** | **0.959** | 1.124 | 1.177 | 0.89× | — |
| **qbe ir swar** | **0.970** | 1.182 | 1.275 | 0.90× | — |
| zig ReleaseFast (`--scan`, scalar) | 1.073 | 1.257 | 1.361 | 1.00× | — |
| zig llvm scalar | 1.176 | 1.342 | 1.403 | 1.10× | — |
| zig ReleaseSafe | 1.189 | 1.355 | 1.451 | 1.11× | — |
| asm scalar | 1.306 | 1.519 | 1.580 | 1.22× | — |
| go | 1.612 | 1.765 | 1.827 | 1.50× | — |
| qbe ir scalar | 1.722 | 1.883 | 1.982 | 1.60× | — |
| mylang ReleaseFast | 3.183 | 3.420 | 3.498 | 2.97× | — |
| python pure | 20.166 | 20.863 | 21.145 | 18.8× | 11.965 |
| python tuned | 50.332 | 51.913 | 52.266 | 46.9× | 1.061 |
| python + libs | 50.831 | 52.092 | 52.540 | 47.4× | 1.084 |

## Where the milliseconds go

Subtracting the static-binary read floor from each scanner (min column):

| step | ms over floor | cumulative |
| --- | ---: | ---: |
| static process start + exit | −0.005 | ~0.93 |
| + open and read 927,415 bytes | +0.000 | 0.939 |
| + scalar asm scan | +0.367 | 1.306 |
| + SSE2 / AVX2 scan | ≈0 (in the noise) | 0.83–0.94 |
| + SWAR scan in Zig (LLVM) | +0.020 | 0.959 |
| + SWAR scan in QBE IR | +0.031 | 0.970 |
| + Zig ReleaseFast (scalar loop + std runtime) | +0.135 | 1.073 |
| + scalar scan in Zig (LLVM) | +0.237 | 1.176 |
| + scalar scan in QBE IR | +0.783 | 1.722 |
| + Go | +0.674 | 1.612 |
| + mylang ReleaseFast | +2.245 | 3.183 |

## Did the hand-written QBE IR beat LLVM? No.

That was the wrong reading of the first batch. `qbe ir swar` at 0.97 ms against
`zig ReleaseFast` at 1.07 ms compared three things at once: the **algorithm**
(SWAR vs a byte-at-a-time loop), the **driver's runtime** (the bare QBE program
calls raw `open`/`read`/`malloc`/`write`; `zig-bench` goes through
`std.process.Init`, an arena `readFileAlloc` and `std.Io`), and only then the
**codegen**. To separate codegen, `zigctl/scan_swar.zig` implements the same SWAR
loop in Zig through `zig-bench`'s exact read/print path, compiled by LLVM at
`-OReleaseFast`.

| loop, algorithm held equal | min | median |
| --- | ---: | ---: |
| scalar, Zig + LLVM (`zig llvm scalar`) | 1.176 | 1.403 |
| scalar, QBE IR (`qbe ir scalar`) | 1.722 | 1.982 |
| **SWAR, Zig + LLVM (`zig llvm swar`)** | **0.959** | 1.177 |
| **SWAR, QBE IR (`qbe ir swar`)** | **0.970** | 1.275 |

* **Same algorithm, two compilers: a dead heat.** 0.959 vs 0.970 ms is 1.1%,
  well inside the ±0.1 ms noise. QBE did not out-generate LLVM; it was handed a
  better algorithm than the loop in `zig-bench`.
* **Where codegen is visible, LLVM wins.** On the scalar loop — where the scan is
  ~0.24–0.78 ms rather than ~0.02 ms, and therefore above the noise — LLVM is
  ~0.55 ms faster (1.176 vs 1.722). That is the honest codegen verdict: LLVM >
  QBE.
* **SWAR is worth more to QBE than to LLVM** (0.75 ms vs 0.22 ms), because QBE's
  scalar loop is the weaker starting point. Both SWAR versions then bottom out at
  the process floor.

### What the generated loops look like

The disassembly agrees with the numbers. LLVM (`zig-scan-swar`) hoists all four
constants out of the loop, unrolls 4× (32 bytes/iteration, `and $…fc` on the
count) and software-pipelines two loads at a time; LLVM also found an equivalent
cheaper form of the SWAR expression (`and 0x7e7e…`, `add 0x7f7f…`, `shr 7` then
`and 0x0101…`). QBE (`qbe-swar.s`) emits **22 instructions per 8 bytes**, with
six `movabs $imm64` constant loads *inside* the loop and an unconditional `jmp`
back to the loop head:

```
.Lbb20:
	cmpq %rcx, %rax
	jae .Lbb22
	movq (%rbx, %rax, 8), %rdx
	movq $-72340172838076674, %rsi     # mask
	andq %rsi, %rdx
	movq $2893606913523066920, %rsi    # c28
	xorq %rsi, %rdx
	movq $9187201950435737471, %rsi    # c7f
	andq %rdx, %rsi
	movq $9187201950435737471, %rdi    # c7f again
	addq %rdi, %rsi
	orq %rsi, %rdx
	xorq $-1, %rdx
	movq $-9187201950435737472, %rsi   # c80
	andq %rsi, %rdx
	shrq $7, %rdx
	movq $72340172838076673, %rsi      # c01
	imulq %rsi, %rdx
	shrq $56, %rdx
	addq %rdx, %r12
	addq $1, %rax
	jmp .Lbb20
```

Why the dead heat, then? **Because at this input size the scan is too small to
measure.** The fixed cost (start + read) is ~0.94 ms; once the loop is SWAR or
SIMD it is ~0.02–0.03 ms. A 22-instruction loop and a 13-instruction loop differ
by well under the run-to-run jitter of a ~1 ms process. Codegen quality is
visible in the assembly and in the scalar timings, but it is not measurable
end-to-end on this workload.

As a side note, Zig's own x86-64 backend (`-fno-llvm`) built the same SWAR file
and measured 1.027 ms min in a quiet 31-round batch against 0.873 (LLVM) and
0.862 (QBE) in the same window — so for this loop, LLVM ≈ QBE > Zig's
self-hosted backend.

## What this means for mylang

* **"QBE is the ceiling" is not supported.** Hand-written IR on QBE reaches the
  same floor as LLVM (0.97 vs 0.96 ms), and the compiler-generated QBE scalar
  loop is only ~0.5 ms behind LLVM's — not the 2.2 ms that separates mylang from
  the floor.
* **mylang's gap is mostly its IR and runtime, not its backend.** mylang is
  3.183 ms, +2.245 ms over the read floor. Of that, the QBE-vs-LLVM codegen
  difference accounts for roughly 0.5 ms; the remaining ~1.7 ms is what
  `e_scan.my` asks for: `read_file`'s managed byte list, bounds-checked
  indexing, and formatting the summary through the runtime.
* So the lever with headroom is the IR the compiler emits and the runtime it
  links, not the backend choice. A SWAR-shaped loop in the emitted IR reaches
  0.97 ms on QBE; a byte-at-a-time loop that also allocates and bounds-checks
  does not.

## Caveats

* **The host is shared and load drifts on a minutes timescale.** The 151-round
  batch above ran at load average 1.35, but an earlier quiet batch put the same
  `asm read only` floor at 0.71 ms, so absolute values carry ±0.2 ms of
  session-to-session offset. Only the min column is meaningful at the 0.1 ms
  scale, and even it has ~0.1 ms of jitter (proved by the `asm sse2` < `asm read
  only` inversion). Read "0.83–0.97 ms" as one band.
* **Linkage differs.** `asm-*` are static syscall-only binaries with no libc and
  no dynamic loader; `qbe-*` are statically linked against glibc; the Zig
  controls and `zig-bench` are static; mylang is dynamically linked against
  libc. The `asm startup only` number is the strongest lower bound here.
* **AVX2 is assumed present** (it is, on this host); the SSE2 variant is the
  portable one.
* **The QBE IR is scalar by construction.** QBE has no vector types, so SWAR is
  the strongest trick available in the IR; it works because the predicate is a
  byte class, and would not generalise.
* **SWAR correctness matters.** The usual `(x - 0x01…) & ~x & 0x80…` zero-byte
  test over-counts when a `0x01` byte borrows from a neighbouring `0x00` byte
  (verified: 18,398 mismatches in 200,000 random words). The IR and the Zig
  control use the exact `~(((x & 0x7F…) + 0x7F…) | x) & 0x80…` form, which had
  zero mismatches.
* The QBE IR formats its own integers (no `printf`): QBE does not set `%al` at
  call sites, so variadic libc calls are avoided.
* `zig-out/bin/mylang` is rebuilt from the working tree, so the mylang row moves
  with the compiler, as in the six-phase comparison.

## Reproduce

```sh
# measure (builds asm/qbe/zig-controls, then all scanners, interleaved on one core)
python3 experiments/sexpr-audit/scan_floor.py --runs 151

# draw
MPLCONFIGDIR=$PWD/.tmp/mplcfg \
  /home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
  experiments/sexpr-audit/scan_floor_charts.py

# the build recipes, standalone
as --defsym VARIANT=3 -o scan3.o experiments/sexpr-audit/asm/scan.s && \
  ld -s -o asm-scan-3 scan3.o
zig-out/bin/qbe experiments/sexpr-audit/qbe/scan_swar.ssa -o scan_swar.s && \
  cc -static -o qbe-swar scan_swar.s
zig build-exe -OReleaseFast -femit-bin=zig-scan-swar \
  experiments/sexpr-audit/zigctl/scan_swar.zig
```

Raw minima, quartiles, medians, every sample, output digests and the load average
are in `evidence/scan-floor.json`; the figure is `evidence/scan-floor.png`.
