# Runtime levers toward 2× Zig: matched A/B evidence

Audit that names the work: [runtime-to-2x-2026-09-19.md](../../../../docs/audits/runtime-to-2x-2026-09-19.md).
Landing report with the conclusions: [runtime-to-2x-landed-2026-09-19.md](../../../../docs/audits/runtime-to-2x-landed-2026-09-19.md).

`measure.py` builds nothing. It takes two already-built executables and compares
them **inside one batch**, so the only difference between the sides is the change
under test. Both sides are the census port (`experiments/sexpr-port/main.my`)
compiled by the same driver: `A` is the tree before the change, `B` after, so the
linker picks a different runtime archive and the guest IL is identical.

```
python3 measure.py --a /tmp/rt2x/base --b /tmp/rt2x/new --out bulk-output.json
python3 measure.py --a /tmp/rt2x/new --b /tmp/rt2x/block --out text-block.json
```

Nine randomly interleaved rounds per workload, parent and children pinned to CPU
6. Instructions retired are load-independent; cycles and wall time are not, so the
two census workloads double as the noise control — nothing in either change can
move their output (`summarise` prints one short line), and their instruction
counts move by 0.00%. Every round re-checks that stdout is byte-identical to the
first capture, and the script aborts on any mismatch.

## 1. Bulk raw-text output — `76c7e58f`

`myl_print_text` walked a raw `str` one scalar at a time, calling
`myl_print_raw` (capacity test, branch, possible `realloc`) per character. At
depth zero the value needs no quoting or escaping, so it is now sized once,
reserved once and filled directly.

| workload | instructions A → B | cycles A → B | wall median A → B |
|---|---:|---:|---:|
| census 927 KB | 119,482,620 → 119,479,709 (**−0.00%**) | 30,931,079 → 30,938,677 (+0.02%) | 25.06 → 25.47 ms (+1.63%) |
| render 927 KB | 195,859,883 → 179,802,692 (**−8.20%**) | 50,459,735 → 48,391,588 (**−4.10%**) | 32.63 → 31.76 ms (−2.68%) |
| census 7.42 MB | 1,022,523,707 → 1,022,528,516 (**+0.00%**) | 311,794,668 → 311,285,118 (−0.16%) | 113.03 → 112.39 ms (−0.56%) |
| render 7.42 MB | 1,633,901,919 → 1,546,564,432 (**−7.86%**) | 487,121,907 → 469,499,954 (**−3.62%**) | 174.93 → 168.54 ms (−3.65%) |

The audit's prototype measured 7.5% fewer instructions, 5.6% fewer cycles and
3.8% less wall time on the render workload; this landing lands inside that range
on instructions and cycles and reproduces the wall direction. A wall column is
only evidence when it agrees with the counters: the machine had other active
processes, and the control's ±1.6% shows the resolution.

## 2. Coallocated text — the change after it

A run-time `str` was two managed allocations: a 168-byte list object plus a
backing array behind a 96-byte header of its own — 264 fixed bytes and two
allocator round trips per nonempty text. It is now one block: a
`myl_native_list` header followed by the scalars, allocated as a single object
whose payload holds no traced pointer, so the collector never walks it and one
free releases both. 168 fixed bytes, one allocation.

| workload | instructions A → B | cycles A → B | wall median A → B |
|---|---:|---:|---:|
| census 927 KB | 119,479,710 → 115,963,475 (**−2.94%**) | 31,045,377 → 29,787,157 (**−4.05%**) | 25.22 → 25.03 ms (−0.75%) |
| render 927 KB | 179,802,689 → 174,072,469 (**−3.19%**) | 47,775,452 → 45,716,814 (**−4.31%**) | 32.25 → 31.08 ms (−3.63%) |
| census 7.42 MB | 1,022,528,506 → 980,865,442 (**−4.07%**) | 314,324,530 → 293,699,702 (**−6.56%**) | 113.63 → 107.33 ms (−5.54%) |
| render 7.42 MB | 1,505,464,424 → 1,446,012,501 (**−3.95%**) | 469,050,304 → 440,094,298 (**−6.17%**) | 168.95 → 159.59 ms (−5.54%) |

The gain grows with input size, which is what a per-object representation change
should do: the larger run holds more live text, so the collector marks and sweeps
fewer objects and the allocator serves fewer chunks. Peak RSS, one
`/usr/bin/time -f %M` observation per case:

| workload | before | after | change |
|---|---:|---:|---:|
| census 927 KB | 13,096 KiB | 11,464 KiB | **−12.5%** |
| census 7.42 MB | 80,716 KiB | 73,952 KiB | **−8.4%** |

## Correctness evidence for both

* all 17 rendering goldens pass with every binary involved
  (`experiments/sexpr-port/golden/manifest.tsv`);
* census and render stdout are byte-identical with and without `--gc-stress` for
  the whole-program runtime, and the script itself re-checks stdout on every
  timed round;
* 214 guest tests under `mylang test tests/lang` (each built and run natively
  under `--gc-stress`) pass with the coallocated text;
* each landing carries its own `SPEC.md` bullet and test — `QBE-BULK-TEXT-1` in
  `src/io_print_test.zig`, `QBE-TEXT-BLOCK-1` in `src/managed_lists_test.zig`
  (which runs its guest under `.gc_stress = true`, so a text block that still
  traced its interior `storage` pointer would corrupt or crash rather than
  quietly leak);
* the full gate — `zig build test`, `test-qbe`, `test-qbe-build`, `fmt-check` —
  was 58/58, 36/36, 22/22 steps and clean before each commit.

## 3. No exit sweep in a final run — the change after that

Every process that ran a guest freed every object that was still live before
returning, which is work nothing can observe: the address space is about to be
released. A ReleaseFast executable's generated entry now declares that its single
run is the process's last, and the runner leaves the heap to the process. A Debug
executable keeps the sweep as a heap check and a library entry never claims to be
final, so a host that runs the guest repeatedly still reclaims each run's heap.

```
python3 measure.py --a /tmp/rt2x/block --b /tmp/rt2x/final --out teardown.json
```

| workload | instructions A → B | cycles A → B | wall median A → B |
|---|---:|---:|---:|
| census 927 KB | 115,963,489 → 112,349,009 (**−3.12%**) | 29,806,063 → 28,468,383 (**−4.49%**) | 22.28 → 22.42 ms (+0.61%) |
| render 927 KB | 174,072,472 → 169,713,296 (**−2.50%**) | 45,778,892 → 44,307,863 (**−3.21%**) | 28.22 → 28.02 ms (−0.72%) |
| census 7.42 MB | 980,865,445 → 952,164,024 (**−2.93%**) | 292,486,525 → 273,695,454 (**−6.42%**) | 101.94 → 97.19 ms (−4.66%) |
| render 7.42 MB | 1,446,012,505 → 1,411,189,829 (**−2.41%**) | 436,302,754 → 410,921,227 (**−5.82%**) | 150.55 → 146.63 ms (−2.60%) |

The saving is larger in cycles than in instructions because the sweep is a
pointer-chasing walk over the whole live set: 2,400–7,900 instructions per
kilobyte of inputs are freed objects the process never had to visit.

## 4. Priced and not landed: aggregate copy elimination

Every aggregate copy in the program was counted by temporarily emitting a counter
call before each `blit` in the emitter and reporting it at exit, then priced by
emitting each copy twice — the second copy is idempotent, so the instruction
delta over the unmodified build is the exact cost of all of them.

| workload | executed copies | per copy | cost |
|---|---:|---:|---:|
| census 927 KB | 492,214 | 8.82 instructions | 4,341,227 (**3.74%** of the run) |
| census 7.42 MB | 3,937,684 | 8.82 | 34,726,302 (**3.54%**) |
| render 927 KB | 563,734 | 9.28 | 5,233,308 (**3.01%**) |
| render 7.42 MB | 4,509,844 | 9.28 | 41,862,929 (**2.90%**) |

That is the ceiling for scalar replacement of aggregates, and it is the ceiling
for *all* copies: a large share are the parameter and return-storage copies value
semantics requires at every call, which no pass removes. The eliminable remainder
— payload bindings and scratch round-trips — is a fraction of it, so the work is
not the next thing to build. Method and counts: the audit landing report §4.
