# Certified growing append arithmetic, 2026-10-04

Production source `6910e08351a50ce8524a5e37d3f6c23feb4d3383` specializes scalar
arithmetic in an existing certified quiet append loop whose receiver is fresh,
empty and untouched. It retains two copies: the guarded arithmetic copy and the
complete checked original. Both copies retain ordinary per-append capacity,
cached readiness, growth, allocation failure and publication. The general
copy-allocation veto remains in force outside this exact certificate.

Current integration note: root provisionally approved adoption after independent
replay, with the repeated small-filter cost recorded. Integration and normal
RF-host confirmation remain coordinator work. No goal pass is claimed.

The isolated parent is accepted `7e7773e43c934e67e32db3205a9f867049f9b46a`.
Matched control artifacts were built by Debug compiler source
`63842d3c32ab3079d878cff89224478543f9b7f3`; root verified its production inputs
match 7e exactly. Later text changes were deliberately excluded from this causal
comparison. Every guest retains the ordinary ReleaseFast backend policy; LLVM
uses O3/LTO. No fixture, API, benchmark plan or timing policy changed.

## Evidence and scope

`validation-receipt.json` binds 29 saved files by raw and stored SHA256,
including both manifests and compiler receipts, backend receipts, static SSA and
native instructions, the production patch and Guardian logs. Production content
fingerprint: `b1423ec55ea71a52f18a5d1cc8cb22667f47e786aab30ca5a90d67d41900c379`.

Debug compiler SHA256:
`0d06679c84a87b90a361fdc3e7d5dc199e1a58e451747b5236bf09da74ae6216`.
Candidate runner manifest SHA256:
`9726b7b3dbd48a5b3c4399f6a1990276f3615b56b2c18787213fa175ccb49f63`.
Candidate collections LLVM guest SHA256:
`e339b80aedae961389dcd1bfcd3dbaab9e244aea9504a3678152bde7b9feae4a`.
Candidate collections QBE guest SHA256:
`088b93ef3a7cfa2000e289b10bc6f35e721fcecae0ee40cfc60bbbb58b2de1ad`.
The saved manifests bind all 24 guests, clocks, installed assets, tools and build
commands. All 16 external reference arms were copied only after byte verification
against the unchanged matched baseline.

The final targeted unit run passed 27/27 with actual command exit zero. It proves
actual specialization in both a synthetic growing loop and the exact frozen
collection project, and covers checked/GC refusal, retained counting publication, incoming or used
roots, aliases, effectful or collection dependencies, unsafe/cyclic/bounded-work
guard graphs, retained ordinary runtime calls, and exhaustive emitter allocation
failure cleanup. Nine successful native outcomes include negative/zero/short
trips, multiple growth boundaries, signed seeds and a zero-trip maximum seed.
Each asserts an independent expected value, exit status and empty output. Two
additional native pairs assert exact signed overflow and first heap-budget
refusal, including complete trap locations, frames, details and output. All 11
accounted/unaccounted QBE outcomes match exactly; no usage-error equivalence is
used. Saved checksum qualification passed 720/720 across all six arms and official
differential holdouts passed 516/516. No new sanitizer run is claimed.

## Actual code

`static-binary.py` uses read-only `nm`, `objdump` and `readelf`, and checks the ELF
hashes again after inspection. Stored collections SSA contains exactly one new
marker, `mylang-rc-append-range 55`, in the frozen `kind == 1` append loop. Its fast
copy contains zero arithmetic overflow trap calls; its original contains four.
After generated register/label renaming, the entire original SSA loop equals the
matched baseline original loop. Both candidate copies retain one ordinary append,
one readiness query and one allocation failure call, plus the capacity check and
cache invalidation. The prior whole-room copy cannot admit positive trips for
this empty receiver; that refusal is a source/SSA fact, without hardware branch
tracing.

In actual optimized LLVM, fast-loop instructions at
`0x1034b50 <= PC < 0x1034c72` contain no overflow condition and strength-reduce the
value recurrence to `add $0xd,%r9`. They retain the capacity comparison, growth
call at `0x1034c1f` and readiness query at `0x1034c50`. The complete checked
fallback retains its overflow path and both calls. LLVM batch size grows from
52,108 to 52,552 bytes (+0.85%); `.text` grows 293,522 to 293,970 (+0.15%). QBE
batch size grows 132,860 to 133,468 (+0.46%); `.text` grows 419,462 to 420,070
(+0.14%). Other branches may change layout or register allocation; the small
filter cost is measured, without a proven causal attribution.

## Timing results

The four-case six-arm screen used five measured rounds and one warmup, then the
matched Debug638→Debug6910 pair used exactly the same frozen plans. The independent
repeat used 15 measured rounds and three warmups for append at both sizes and
small filter. All sessions ran on CPU 2 under the ordinary internal timing lock,
with root coordinating a quiet lane and no overlapping builds, tests or reports.
Raw reports and original logs are retained unchanged. This is diagnostic evidence
under Debug hosts, not a normal goal acceptance or confirmation.

| Case | Profile | Initial LLVM ratio | Repeat LLVM ratio (paired 95%) | Repeat QBE ratio |
|---|---|---:|---:|---:|
| list_append | small | 0.88887 | 0.88833 [0.88640, 0.89233] | 0.92549 |
| list_append | large | 0.77683 | 0.76986 [0.76429, 0.77310] | 0.96757 |
| list_filter | small | 1.03956 | 1.03905 [1.02700, 1.04217] | 0.97556 |

The independent repeat confirms 11.17%/23.01% LLVM append gains with a 3.91%
small-filter cost. Initial LLVM control ratios for filter-large, sort-small,
sort-large, nested-small and nested-large were respectively 0.99653, 1.00750,
1.00810, 0.98720 and 0.98971; corresponding QBE ratios were 1.00053, 1.03212,
0.99298, 1.01677 and 0.93867. Absolute medians, intervals and every outcome remain
in the raw reports and `timing-evidence.json`.

Six-arm LLVM/current-fastest append levels remain **2.38780 small and 1.85022
large**. Both goal cells remain open. Filter levels are 2.57339/2.39246, integer
sorting 1.34599/1.01076 and nested mutation 1.0/1.0. QBE remains informational.

The initial six-arm session `def9ac1d-2d1e-4914-8b41-fab6208c5474` ran
05:38:56.488168–05:39:45.430029 UTC; matched pairs
ran 05:40:06.465538–05:40:31.208127 UTC, session
`4d1c67cf-48ef-445f-ada7-66062f1a191b`. The independent repeat ran
05:46:14.176480–05:46:52.558039 UTC, session
`009005dd-aec6-47dc-b5d9-04169c3e6ddc`. The receipts bind their exact raw hashes,
plans, helper bytes and all live artifact checks. There are 240 six-arm samples,
720 timing-session checksum qualifications and 408 paired outcomes including
warmups.

## Replay and commands

From this worktree, replay saved evidence without guest execution:

```sh
python3 experiments/runtime-goal110-append-range-20261004/verify-archive.py --check-artifacts
python3 experiments/runtime-goal110-append-range-20261004/verify-timing.py --check-artifacts
python3 experiments/runtime-goal110-append-range-20261004/static-binary.py
```

Final targeted source test command:

```sh
TMPDIR="$PWD/.mylang-cache/goal110-append-range-review/tmp" scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build test-units -j2 -Doptimize=Debug -Dtest-filter='append range' -Dtest-filter=RC-PRESIZED-APPEND-1 -Dtest-filter='RC append loop' -Dtest-filter=RC-FRESH-APPEND-GENERATION-1 --cache-dir .mylang-cache/goal110-append-range-review/zig-local
```

The official `build_compiler.py` receipt contains the exact source-bound host
command. The runner manifest and screen identities preserve the full guest and
screen commands; `time-paired.py` and `time-paired-repeat.py` preserve the two
diagnostic procedures. No further timing is authorized without root coordination.

## Guardian outcomes and retained failures

The first production commit gate rejected seven findings in five checks:
`doc-comments` (two fixture methods), `cognitive-complexity` (Lower 30 > 25),
`debug-print-ban` (two test logger references), `bool-ops-per-condition` (five >
three) and `repeated-string-literal` (fixture path). The source was repaired by
real method documentation, extracting the guard emitter and named readiness
predicate, the prescribed file-scope test logger alias and a shared fixture path.
No Guardian policy changed. The final production commit passed all 88 whole-tree
checks; the final unit run passed 27 tests. Full rejection and success logs are
saved. Root owns mandatory consolidated Guardian feedback and has the exact check
names and original paths.

An initial reference-reuse invocation was refused before guest compilation
because an alternate Zig invocation path differed from the saved manifest. The
final command used the exact recorded `/home/epentland/.local/bin/zig` invocation;
tool bytes and policy were unchanged. That refusal log is retained. Earlier test
fixture/discovery failures were repaired before the final 27/27 run; no failed
production validation is presented as passing.
