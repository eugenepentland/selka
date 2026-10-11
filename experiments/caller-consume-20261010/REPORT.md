# Caller construction and consuming replacement

The prototype eliminates managed allocation for the bounded returned-list case
and removes unnecessary copies when a caller repeatedly replaces its last live
list value. The source still returns ordinary values. Live snapshot controls
preserve their allocations and copies.

This comparison starts from the previous borrow-only stack prototype, not from
unmodified main. Both compilers are ReleaseFast builds on main revision
`1d202d41bfff888ee91354f706cb74e860dc4b94`, with Zig
`0.17.0-dev.1683+5ceec001b`. Guest programs use the current Core/LLVM backend and
`--release`.

| Compiler | SHA-256 |
| --- | --- |
| Frozen borrow-only baseline | `5ca393ede35337754edf06c0cf5551f491dc87037d3988ea4d410b0422e3db2d` |
| Caller construction + consuming replacement | `e0ec1d9b3a5a7d201de28ed3ae60bb2e1702bd6d1e85ac55b6cc7bb5f1a80bbf` |

[results.json](results.json) and [summary.csv](summary.csv) contain both inputs
for all 30 unchanged census programs and both scaled workloads. The
[baseline source manifest](baseline-compiler-sources.json) and
[candidate source manifest](candidate-compiler-sources.json) preserve each
non-test compiler source hash. These are uncommitted prototype builds; their
source manifests and executable hashes identify the measured artifacts.

This first version covers bounded constructors with unmanaged elements (4 KiB
of elements per list and an 8 KiB promotion budget per function), and consuming
leaf list helpers in modules without function value types. Source `mut`
semantics and the runtime are unchanged. The eligibility and alias rules are
described in [ownership](../../docs/tooling/ownership.md).

## Memory and reference counts

[constructor.my](constructor.my) builds eight integers per iteration, returns
the list, and reads it through a looped weighted-sum helper. The offset changes
with the runtime iteration. Its snapshot control also updates the returned list
and reads both versions. At one million iterations, construction loses two
managed block allocations per iteration; the snapshot control remains managed.

[replacement.my](replacement.my) calls a looped helper to append three integers
to a list, then replaces the caller's old value. At 8,000 iterations the result
contains 24,000 integers. Its snapshot control reads the old list after every
call. The helper remains a call in both builds.

Allocation and copy traffic below excludes `<outside>` startup/teardown.
Peak managed live bytes includes the whole program, including startup.

| Case | New managed blocks, before → after | New block bytes | Additional `realloc` bytes | Peak managed live bytes |
| --- | ---: | ---: | ---: | ---: |
| Constructor, 1,000,000 iterations | 2,000,000 → 0 | 128,000,000 → 0 | 0 → 0 | 384 → 256 |
| Constructor, kept snapshot | 3,000,000 → 3,000,000 | 256,000,000 → 256,000,000 | 0 → 0 | 480 → 480 |
| Replacement, 8,000 iterations | 8,022 → 6 | 768,405,640 → 2,184 | 768,203,936 → 265,136 | 770,224 → 266,456 |
| Replacement, kept snapshot | 8,022 → 8,022 | 768,405,640 → 768,405,640 | 768,203,936 → 768,203,936 | 770,224 → 770,224 |

Replacement reduces peak managed live bytes by **65.4%**. New block bytes plus
positive `realloc` growth fall from 1,536,609,576 to 267,320 bytes, a 99.98%
reduction in this cumulative capacity traffic. The candidate performs six new
block allocations and eight `realloc` growths; these are distinct counters.
Neither traffic figure describes peak memory.

| Case | COW list copies | Copied list payload bytes | Core retains | Core releases | Core uniqueness tests |
| --- | ---: | ---: | ---: | ---: | ---: |
| Constructor, 1,000,000 iterations | 0 → 0 | 0 → 0 | 0 → 0 | 1,000,000 → 0 | 0 → 0 |
| Constructor, kept snapshot | 1,000,000 → 1,000,000 | 64,000,000 → 64,000,000 | 0 → 0 | 2,000,000 → 2,000,000 | 0 → 0 |
| Replacement, 8,000 iterations | 8,000 → 0 | 767,904,000 → 0 | 8,000 → 0 | 16,001 → 1 | 24,000 → 8,000 |
| Replacement, kept snapshot | 8,000 → 8,000 | 767,904,000 → 767,904,000 | 8,000 → 8,000 | 16,001 → 16,001 | 24,000 → 8,000 |

The replacement snapshot keeps its required copies. Both replacement variants
test uniqueness once per helper invocation after the change; the older code
tests once per appended element. Runtime retain/release hook counts are kept
separate from these Core events in the JSON and CSV.

The smaller scales also pass: constructor 10,000 iterations eliminates 20,000
managed blocks; replacement 2,000 iterations changes 2,022 blocks to six and
peak managed bytes from 192,224 to 65,832. Independently calculated outputs are
recorded for every input. Constructor's per-iteration weighted sum is
`36 * (seed + batch % 257) + 168`; replacement's final score is
`3*r*(seed+2) + 3*r*(r-1)/2`. The snapshot adjustments are in
[compare.py](compare.py), independent of compiler output.

## Unchanged 30-program census

Every original source and all 159 artifacts under
`experiments/rc-census-20261010/` remain unchanged. At both `n=4` and `n=11`, only
samples 04 and 20 change their recorded memory/RC metrics or selected static
counts. The other 28 programs retain identical recorded metrics.

| Sample | Input | New managed blocks | New block bytes | COW list copies | Peak managed live bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 04 returned list | 4 | 2 → 0 | 128 → 0 | 0 → 0 | 448 → 320 |
| 04 returned list | 11 | 2 → 0 | 128 → 0 | 0 → 0 | 960 → 832 |
| 20 loop replacement | 4 | 5 → 2 | 352 → 128 | 4 → 0 | 512 → 448 |
| 20 loop replacement | 11 | 18 → 5 | 3,840 → 1,120 | 11 → 0 | 2,144 → 1,664 |

Sample 04 gains one Core inlined call and one stack list. Its
[candidate LLVM](evidence/candidate-04_returned_list.llvm) contains a
96-byte, 32-byte-aligned allocation in `probe`; the constructor call has been
spliced into that caller. This is bounded constructor inlining, not a general
hidden destination ABI. The unused original constructor body remains in the
Core listing, so the static allocation-site total does not fall even though
this execution allocates no managed blocks in the kernel.

Sample 20 gains no inlining and no stack list. Its
[candidate Core](evidence/candidate-20_loop_carried.core) retains the
`append_batch` call, removes the helper's parameter retain and the caller's
per-iteration release, and moves the copy-on-write branch before the inner
loop. The copy branch remains available for shared inputs. Exact before/after
Core and LLVM function fragments and full-source hashes are in
[evidence/index.json](evidence/index.json).

## Validation and limits

Each compiler passed **230 executions**: 180 census runs, 30 scaled/control/trap
runs, and 20 cold/warm cache runs. Ordinary, counting, and fact-verification
builds match their independent outputs and exit statuses. Successful runs use
`MYL_CORE_LEAKCHECK=1`, have empty stderr, and counted runs finish with zero
managed live bytes. Expected integer-overflow cases produce identical
`R_OVERFLOW` diagnostics in all three modes. Traps do not follow normal cleanup
and are excluded from the successful-run leak claim.

All four selected cold/warm builds produce identical executable hashes and
outputs. The full Debug Core target passed all **833 tests** across eight
shards; 5,831 skipped instances belong to other shards. The whole-tree Guardian
gate passed **88 checks**. [validation.json](validation.json) preserves the
private log paths and hashes, including
`.tmp/caller-consume-20261010/core-tests-final.log` and
`.tmp/caller-consume-20261010/guardian-full-final.log`. This records the Core
target and compiler gate, not every repository test target.

Managed counters measure block size classes and large blocks' usable sizes.
They exclude stack space, reserved heap chunks, RSS, dictionary side tables,
sort/text scratch, and transient allocation inside the C allocator's `realloc`.
Some text/buffer payload copies lack hooks. Core RC events are instrumented
before LLVM optimization and counted during execution; LLVM may remove the
corresponding native operation while preserving its instrumentation. They may
also overlap runtime hooks, so these counts should not be summed as distinct
machine operations. See [counter definitions](../../docs/tooling/counters.md)
and the original census for the runtime-container blindspots. The results
establish these specific opportunities, not a broad application improvement.

## Ordinary binary timing

After the Core gate and our builds finished, ordinary binaries ran nine
alternating-order pairs after two warmups per compiler, pinned to CPU 10.
Counters, leak checking, and fact verification were disabled. All 88 timing
and warmup executions matched their outputs. [timing.json](timing.json) retains
every sample, binary hash, CPU/sibling activity sample, and host load average.

| Case | Baseline median ms | Candidate median ms | Median absolute deviation, before / after |
| --- | ---: | ---: | ---: |
| Constructor, 1,000,000 iterations | 16.524 | 5.826 | 5.36% / 4.18% |
| Constructor, kept snapshot | 36.617 | 36.918 | 1.31% / 0.74% |
| Replacement, 8,000 iterations | 176.147 | 1.494 | 2.45% / 6.65% |
| Replacement, kept snapshot | 116.507 | 116.352 | 0.47% / 0.52% |

These are exploratory whole-process timings on a shared host, including process
startup. The candidate replacement run is particularly short and sensitive to
startup noise. The snapshot medians are effectively unchanged within the
observed variation. No general speedup ratio is inferred from these workloads.

## Reproduction

Keep the frozen baseline install: rebuilding the current tree produces the
new prototype. From the repository root, with both measured installs present:

```bash
caller_zig=/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
caller_work=.tmp/caller-consume-20261010
caller_exp=experiments/caller-consume-20261010

scripts/build-slot.sh build python3 -B "$caller_exp/compare.py" \
  --compiler "$caller_work/baseline/bin/mylang" --zig "$caller_zig" \
  --frozen "$caller_exp/frozen.json" \
  --source-manifest "$caller_exp/baseline-compiler-sources.json" \
  --output "$caller_work/repro-baseline"
scripts/build-slot.sh build python3 -B "$caller_exp/compare.py" \
  --compiler "$caller_work/candidate/bin/mylang" --zig "$caller_zig" \
  --frozen "$caller_exp/frozen.json" \
  --source-manifest "$caller_exp/candidate-compiler-sources.json" \
  --output "$caller_work/repro-candidate"

python3 -B "$caller_exp/summarize.py" \
  --baseline "$caller_work/repro-baseline/results.json" \
  --candidate "$caller_work/repro-candidate/results.json" \
  --output "$caller_work/repro-summary"
python3 -B "$caller_exp/evidence.py" \
  --baseline "$caller_work/repro-baseline" \
  --candidate "$caller_work/repro-candidate" \
  --output "$caller_work/repro-summary/evidence"
python3 -B "$caller_exp/timing.py" \
  --baseline "$caller_work/repro-baseline/results.json" \
  --candidate "$caller_work/repro-candidate/results.json" \
  --cpu 10 --pairs 9 --output "$caller_work/repro-timing.json"
```

Capture output directories must be fresh; `--resume` accepts completed matching
case identities. Timing takes the shared timing lock without waiting and must
run outside the build-slot wrapper. Raw commands, counting JSON, complete IR,
compiler installs, binaries, and build caches remain private under
`.tmp/caller-consume-20261010/`. The original census report is not overwritten.
