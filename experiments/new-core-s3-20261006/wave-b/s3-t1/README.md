# S3-T1 package qualification

Base: `8918de74720f0832dabe5802c110cd0518324cf5`, on the locked
`codex/new-core-s3-text` worktree. The frozen IR is unchanged. Source commit: `ade0ce29d743aa5168ce14417e2aee6bb11a11f6`.

The package ports the remaining text and immutable-byte algorithms from the old
native helpers into the core runtime: count and scalar/range search, reverse
search, index traps, ASCII case and classification, Unicode/default and explicit
charset trimming, replace, CR/LF splitlines, zfill, chr/ord, Unicode-16 repr,
packed text formatting, find_any, byte views, strict UTF-8 decode/count/range.
Existing step/reverse slices and the S2 hot paths remain in use. List extend and
reverse preserve captured self/nested snapshots through ordinary COW ownership.
Inputs are borrowed; newly materialized strings/lists own independent blocks.
The S2 32-byte str/bytes header is unchanged.

A strict verify sweep exposed a pre-existing emitter lifetime defect: a scalar
conversion's length-bound assertion reloaded a byte-string header after the
ordinary final-use release. The approved fix collects length dependencies once
and snapshots immutable SSA block lengths at definition, parameters/literals at
entry and phis at their block. Assertions use the resolved source snapshot;
normal emitted code and ownership are unchanged. The focused fixture uses a
>1 KiB bytes allocation followed by a concat and final length conversion, and
also covers str/list lengths. See `diagnostics/verify-use-after-free.ll.txt` and
`run31-find-any-signal.log`; final verification is in runs45/46/51.

The D2 oracle is private `.mylang-cache/s3/d2-oracle/mylang`, SHA256
`feb7914ba50d0649180a5257b11f1a821930b40afd18b4f48f0d503127a80073`.
Every recorded command run has a separate log. Gate commands retain the gate
and build locks; core rebuilds additionally own every build slot. Admission
waits are excluded from rebuild elapsed time.

| Check | Evidence | Result |
|---|---|---|
| Exclusive final core rebuild | run58-core-build.log | 1.75 s,324 MiB compiler peak; admission 288.609 s excluded |
| Required eight-shard suite | run18-test-core.log | 221/221, 95.73 s total; longest 94.14 s, requiring more shards |
| Final sixteen-shard suite | run47-test-core16.log | 221/221,70.17 s total; longest 68.20 s |
| Full debug/release conformance | run55-final-conformance.log | 1518 selected,1310 matching,0 mismatching,208 dependent refusals, each mode |
| Own strict leak/verify sweep | run46-leak-verify.log | 102 selected,89 matching,0 mismatching,13 dependent refusals, each mode |
| Long linear find_any verify | run45-find-any-verify.log | 1/1 pass with leak checking |
| Focused final-use verify | run51-large-bound-verify.log | 1/1 pass with leak checking |
| Extended text fuzz | run53-fuzz50.log / range-fuzz | 50 accepted,750 comparisons,1000 native runs,0 mismatches/facts/leaks/refusals;231.33 s |
| Normal benchmark definitions | run61-committed-identity.log | All 35 identical to92590700 |
| Text performance | run50-text-rows.log / text-rows.json | All 5 rows, both sizes,7 shuffled rounds,CPU10 under shared flock; both gates pass |
| Coverage | run49-coverage.log / coverage/ | Qualified 4-corpus sweep;3324/3595 accepted, versus3213/3595 after WaveA |
| Guardian source commit | run57-source-commit.log | All 88 checks pass; ordinary source commit |

`text-row-gates.md` contains the 10 ratios. The worst new/old ratio is 1.016
(string_equal64); the worst new/Zig ReleaseSafe ratio is 1.000. Checksum, native
status and timing validity are checked by the measurement tool. No timed use of
CPUs2,3 or11 occurred. Coverage retains every raw refusal and its ranking.

Qualification history is retained rather than overwritten. Runs05/06 found
fixture inference/error-message/format-word migration errors, corrected before
run14. Run12 used a compiler launched before its pending rebuild completed and
is superseded. Run19 and initial oracle-dependent runs used the stale pre-D2
oracle: its dictionary-view membership rejection was a setup error, corrected
in run24 and subsequent D2 runs. Run23 included four nonexistent file names;
its setup failures are superseded by the actual102-test sweep. Its real verify
SIGSEGV led to the lifetime fix above. Run22 identified an actual porting error:
find_any negative starts clamp to zero rather than count from the end; the
runtime now uses the old windowed memchr/bitset algorithm and a negative-start
regression. Runs38/41 exposed the initial capture prototype's missing parameter
entry definitions; final captures include parameters and immortal literals.
Run36 predates the final capture rebuild and is superseded by45/51. Run52 was
intentionally stopped to add random UTF-8 range cuts before the final50-case
run53. The earlier50-case run39 already passed750 comparisons in219.31 s;
the final generator adds scalar_count_range.

Remaining package limits are deliberate: case/classification match the old
ASCII rules exactly; immutable bytes.view materializes an owned slice without
adding a view ABI; split remains materialized because the existing fast row
passes both gates. Float/number text, numeric/octet conversion and mutable byte
buffer ownership belong to T2; capabilities/hosts/tests to C; other aggregate
operations and remaining library surfaces to M/A. T1 changes readonly runtime
signatures to the actual checked receiver/argument types for those integrations.
No tests/lang edits, persisted-format changes, record-phi emptying, pushes or
main merges were made. Shared hooks are retained in `shared-hooks.patch`.

Final source commit initially failed in run54 solely because the new entry loops
raised emitFunction cognitive complexity to 27 (limit 25). Run57 extracted those
unchanged loops into assertEntryFacts and passed Guardian 88. Final source rebuild is 1.75 s in run58; focused verification is in runs59/60 and
normal definition proof in run61.

Reproduction commands (all paths are private to this worktree):

```sh
scripts/build-slot.sh gate -- bash -c 'exec 7>&9; exec scripts/build-slot.sh build -- python3 experiments/new-core-s3-20261006/wave-a/exclusive_core.py -- /usr/bin/time -f "elapsed=%e maxrss=%M" zig build core --summary all'
scripts/build-slot.sh gate -- bash -c 'exec 7>&9; exec scripts/build-slot.sh build -- /usr/bin/time -f "elapsed=%e maxrss=%M" zig build test-core -Dcore-shards=16 --summary all'
scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py --set all --mylang .mylang-cache/s3/d2-oracle/mylang --core zig-out/bin/mylang-core --cache-dir .mylang-cache/s3/t1-conformance-qualified --jobs 4
scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py python_strings python_text_surface text_index text_views text_literal_index python_bytes format_specs text_scanning standard_strings python_collections rc_readonly_bytes --leakcheck --verify --mylang .mylang-cache/s3/d2-oracle/mylang --core zig-out/bin/mylang-core --cache-dir .mylang-cache/s3/t1-final-leak --jobs 4
scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py --kind text --harness experiments/new-core-s3-20261006/wave-b/s3-t1/fuzz_text.py --cases 50 --seed 202610063 --mylang .mylang-cache/s3/d2-oracle/mylang --core zig-out/bin/mylang-core --cache-root .mylang-cache/s3/t1-range-fuzz --evidence experiments/new-core-s3-20261006/wave-b/s3-t1/range-fuzz
scripts/build-slot.sh build -- flock /run/user/1000/mylang-s2-cpu10.lock python3 experiments/new-core-s2-20261005/wave-b/integration/measure_all35.py --build --rows bytes_scan,string_equal,string_search,string_split,string_join --rounds 7 --cpu 10 --mylang .mylang-cache/s3/d2-oracle/mylang --core zig-out/bin/mylang-core --bin .mylang-cache/s3/t1-text-rows --json experiments/new-core-s3-20261006/wave-b/s3-t1/text-rows.json
scripts/build-slot.sh build -- python3 experiments/new-core-s3-20261006/wave-a/compare_all35.py
scripts/build-slot.sh build -- env TMPDIR="$PWD/.mylang-cache/s3/t1-coverage-tmp" python3 experiments/new-core-s2-20261005/wave-a/qualify_coverage.py --evidence experiments/new-core-s3-20261006/wave-b/s3-t1/coverage
```
