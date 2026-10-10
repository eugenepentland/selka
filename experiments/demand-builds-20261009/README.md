# Selective function reuse: measured results

The new compiler reduces median optimized-debug edit builds by **29–35% at
191,416 lines** and **41–47% at 510,436 lines**. Eight of nine measured 510k-line
edits finish within 15 seconds. The first entry edit after cache setup takes
**19.04 seconds**, so a strict 15-second maximum is **not yet achieved**.

Both versions use optimized debug. This compares the previous compiler-stage
implementation with demand-driven frontend bodies, optimizer shortcuts, stable
managed-byte literal catalogs and indexed type-suffix resolution. Runtime C
optimization stays at O2. Release guest builds are not measured.

## Edited builds

Each median includes three distinct edits, including the first edit after setup.
Every sample changes source length. Times include compiler startup, cache work,
native compilation and linking; validation runs afterward.

| Physical lines | Edit | Previous median | New median | New min–max | Time reduction |
|---:|---|---:|---:|---:|---:|
| 191,416 | Entry literal | 9.17 s | 5.94 s | 5.52–7.39 s | 35.3% |
| 191,416 | Helper body | 6.81 s | 4.83 s | 4.79–4.85 s | 29.1% |
| 191,416 | Three files | 7.68 s | 5.45 s | 5.27–5.51 s | 29.1% |
| 510,436 | Entry literal | 25.47 s | 14.25 s | 13.91–19.04 s | 44.0% |
| 510,436 | Helper body | 23.94 s | 12.69 s | 12.49–12.96 s | 47.0% |
| 510,436 | Three files | 23.04 s | 13.65 s | 13.30–13.79 s | 40.8% |

The first 510k entry edit improves from 34.25 to 19.04 seconds. The remaining
eight edits range from 12.49 to 14.25 seconds. These are observed times on this
fixture and host, not a worst-case guarantee for arbitrary 500k-line programs.

| Physical lines | Edit | Previous median peak RSS | New median peak RSS |
|---:|---|---:|---:|
| 191,416 | Entry literal | 1.323 GiB | 1.224 GiB |
| 191,416 | Helper body | 1.207 GiB | 1.231 GiB |
| 191,416 | Three files | 1.203 GiB | 1.230 GiB |
| 510,436 | Entry literal | 3.498 GiB | 3.254 GiB |
| 510,436 | Helper body | 3.182 GiB | 3.254 GiB |
| 510,436 | Three files | 3.185 GiB | 3.256 GiB |

RSS is GNU time's largest-process high-water mark, not simultaneous aggregate
compiler-plus-worker memory. This stage improves speed; helper/three-file median
RSS increases about 2% from the previous memory-reduced implementation.

## What is reused

On repeated 510k single-function edits, raw lowering reuses 23,596 functions and
lowers one; repeated three-file edits reuse 23,594 and lower three. The frontend
omits roughly 27,400 unchanged or previously unreachable ordinary bodies. The
optimizer bypasses intermediate stage work for roughly 16,700 functions while
still validating final artifacts. None of the 20 candidate builds falls back to
a complete checked-tree retry.

Native compilation remains per source module: each single-function edit compiles
one of 2,020 units; three-file edits compile three. Catalog construction, raw IR
restoration, final-artifact validation and emission-key construction still visit
the wider program. On the 510k helper case, median frontend time drops from
11.83 to 2.97 seconds; optimizer time is 3.55 seconds and emission work 3.86
seconds after this change.

The remaining first-edit overrun is not a full retry: it lowers 1,436 functions
and reuses 22,161. A separate read-only two-copy EDA diagnostic found that all
123 cold/replayed typed-body hash differences were global loop IDs or their exit
targets; canonical per-function numbering made all 123 trees equal. Correcting
that requires consistently normalizing or relocating Core IR loop metadata too,
because optimizer and test receipts consume it. It is not safe merely to remove
those fields from the body hash. That normalization is follow-up work.

The first and second entry samples have identical optimizer hit/miss counts.
Their wall times differ by 5.13 seconds, but summed user and system CPU times by
only 1.77 seconds. This suggests I/O or scheduling also contributes; no precise
wait-time attribution was measured. Eliminating repeated whole-program artifact
reads/validation remains necessary to provide a comfortable cold-cache margin.
Declaration, type and call-graph changes can still trigger broader rebuilding.

## Method and validation

- Twelve and thirty-two reachable copies of the EDA tool, with every replica
  imported and called. This is a scaling fixture, not an independently developed
  half-million-line application.
- Same source paths and edits for both compilers; separate frontend, stage and
  native caches. Execution order alternates. Three repeats per edit kind.
- Intel i7-12700H shared host, reserved CPUs `2,3,10,11` (two physical cores/four
  threads), four native workers. The gate lock prevents timing beside another
  gate. Ordinary builds stay off the timing CPUs.
- Both compiler executables built with pinned Zig
  `0.17.0-dev.1683+5ceec001b`, `-Doptimize=fast`. Their SHA-256 identities and all
  commands are in [results.json](results.json).
- Setup uses empty intermediate caches and only validated original cold native
  objects. Setup is excluded from edit medians and is **not** a full cold-build
  measurement. At 510k lines it takes 89.83 seconds before and 76.97 seconds after.
- All 40 builds execute every replica, pass the EDA export hashes and pass runtime
  leak checking. All 20 paired executables and all 30 edited native-object pairs
  are byte-identical, including debugger and trap metadata.
- `zig build test fmt-check --summary all`: 93/93 steps, 2,275 executed tests
  passed; 21,040 test assignments skipped by sharding. Whole-tree Guardian:
  88/88 checks. Regression coverage includes source relocation, cache corruption,
  newly reachable bodies, changed signatures/visibility, warning relocation,
  incoming optimizer intervals, managed bytes and nested generic type suffixes.

[compare.py](compare.py) reproduces the paired method using the previous scaling
generator and validated native seed. [object_audit.py](object_audit.py) also
supports equivalent literal-pool layouts, although every final measured object
pair is byte-identical. [validation.json](validation.json) records final log
paths, hashes and check counts.

Full local artifacts:
`/home/epentland/.cache/mylang-demand-builds-20261009/paired-complete`.
The separate loop-ID investigation is preserved as `treehash-diagnostic.log`
and `treehash-diagnostic-harness.txt` under the same artifact root's parent.
