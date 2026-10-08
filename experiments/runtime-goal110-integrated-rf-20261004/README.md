# Integrated join ReleaseFast confirmation

Exact production source `957f97c6d9906ef11cf344ce055dada8be8446ea` was built
with the official compiler builder in a clean worktree, fresh local/global
caches and a disk TMPDIR. The ReleaseFast host completed in 6m13s. Its live
source snapshot, compiler and installed assets passed receipt validation.
Guardian passed all 88 checks, using its documented diff scope. No gate,
benchmark source, contract, accounting setting or reference policy changed.

All 24 guests were built through the official expanded runner. Four external
arms reuse source/tool/binary-verified ReleaseFast-730 references with explicit
manifest SHA256 `94ea9f6343133da2fefdcb327458fbb5fcf6d7f099ba29385ebb5b0bd430d721`.
LLVM guests select O3/full LTO; QBE guests select QBE. The two text guests pass
120 exact oracle outcomes, six accounting/memory refusal probes and two live
artifact records. All 516 unseen-input holdouts pass and replay; their elapsed
values are discarded. The holdouts retain frozen generators and do not claim
coverage of arbitrary Unicode, alias graphs or distributions.

The runner's build-only mode writes its manifest and build log, then exits
without writing the optional timing output. An initial archival attempt expected
that output and stopped; the retained build evidence uses the actual manifest.

Two separate CPU2 sessions run string_join, bytes_scan, string_search and
mutate_nested at both frozen sizes, all six arms, 15 randomized rounds and
three warmups. Each session retains 720 samples and 720 fresh qualification
checks. No build, sanitizer test or external timing ran during either session.
The exact commands are in `commands.json`; `evidence.json` binds raw and gzip
archive hashes, source, sessions and artifact identity. The manifest, receipt,
all24 binaries and clock were revalidated after both sessions.

| Row | A LLVM/current fastest | B LLVM/current fastest |
| --- | ---: | ---: |
| string_join / small | 1.047461 | 1.046350 |
| string_join / large | 1.000000 | 1.000000 |
| bytes_scan / small and large | 1.000000 | 1.000000 |
| string_search / small and large | 1.000000 | 1.000000 |
| mutate_nested / small and large | 1.000000 | 1.000000 |

Small join uses Rust as the concurrent fastest arm. LLVM is fastest for the
other seven rows. These are observed medians; the coordinator independently
checks confidence intervals, source policy and goal acceptance. Equality is
unchanged and remains open. The overall 80-row goal is not complete.

Rearchive while the recorded live artifacts remain available:

```sh
python3 experiments/runtime-goal110-integrated-rf-20261004/archive.py
```
