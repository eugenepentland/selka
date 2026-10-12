# Matched final-compiler golden comparison

Both original C0 and candidate B0 golden harnesses passed every checked case
using the same authenticated final Debug compiler
`cc827c4e79243f299dc92327fa86049669307d1f0edfa816a5b641dc443176b0`
from source `9d1b51f310477e4ceccffd8ad41ecf6fc2156e13`. Frozen prefix manifest
`f11fb105af095c1c919ea41ad8db77e0eb328b8425f3f6892ba6f4dfb01ff467`
binds all five artifacts and the qualified fixed-seed component provenance.
No compiler was rebuilt by S03. This isolates golden preparation changes;
it is not an old-versus-new compiler or compiler-port/seed acceptance result.

C0's ordinary operational replay passed all 222 cases in 30.620 seconds.
The original 9d1 complete primer also established B0 correctness: execution 222,
checked 222 (167 source/55 fixtures), zero mismatches, 165 source writes,
66,752 source bytes, 222 fresh mutable directories, four selected tests passed.
The golden source SHA is identical to the B0 archived snapshot; the primer's
compiler SHA is identical to the frozen prefix. The four-test primer wrapper
is separate correctness evidence and its duration is not paired timing.

After the compatible primer and five warm requests, S10 released one bounded
exclusive timing window. It ran C0/B0 then B0/C0 with the same isolated
one-corpus-test wrappers, default Debug/native target and pinned Zig. Each
sample used a new private runtime cache and fresh program/cache/source work,
with the shared Zig global cache already warm. OS page cache was not flushed.
Artifact preparation and compiler/component generation were excluded. Cache
authority, compiler/component hashes, source/tool stamps, recipe/helper hashes
and CPU affinity matched before and after. Command identity and raw usage are
retained in the four sample JSONs. Admission waited 35 seconds, separately
from measured commands. Every command bound was 60 seconds; outer window
300 seconds, exited 0 and released its holder. No production limit changed.

| Pair | C0 wall | B0 wall | C0 max process RSS | B0 max process RSS |
| --- | ---: | ---: | ---: | ---: |
| 0 (C0 first) | 26.302 s | 24.227 s | 163,408 KiB | 169,912 KiB |
| 1 (B0 first) | 26.116 s | 24.288 s | 169,876 KiB | 170,020 KiB |

Wall ratios B0/C0 are 0.92110 and 0.93003, descriptive reductions of 7.89%
and 7.00%. Maximum process RSS rises 3.98% and 0.085%. GNU time reports the
maximum waited process, not aggregate concurrent memory. Both prepared Debug
test artifacts remain: C0 20,218,061 bytes, B0 20,273,122 (+55,061 bytes).
Two order-balanced pairs are a small descriptive cohort, not a stable speedup
or p95. No blanket performance or no-regression acceptance is inferred.

Each of the four timed runs checked all 222 cases with zero mismatches,
167 source/55 fixture cases and 382 explicit skips. Actual compiler calls
remain 222 per run (888 timed calls total), fresh mutable directories 222 and
fixtures 444. Source preparation changes from 222 writes/90,182 bytes to
165 writes/66,752 bytes. This preserves execution parity while reusing only
immutable preparation. The candidate counters are runtime-observed; baseline
counts follow the byte-identical audited invocation/selection helpers and the
unchanged one-source-write-per-case path.

`golden-final-summary.json` pairs only matching immutable identities;
`golden-final-timing-warm-{00,01}-{C0,B0}.json`, `raw/golden-final-timing-*`
and `golden-final-paired-window.log` preserve exact commands/results. The final
wrapper/driver SHA values are bd0a640.../47e3d832...; the earlier ordinary C0
operational record retains its original 6b0 wrapper and runtime tier. No fully
cold shared-Zig-global golden cohort was run. Earlier fallback runs are
explicitly canceled/unqualified in golden-fallback-report.md and are never
pooled with these final-context samples.
