# Changed-source semantic queries

`check-session` retains successful checked function bodies across source edits, in
addition to its syntax and exact-verdict caches. Replies add a `functions` object
with actual `checked`, `reused`, `stored`, `bypassed`, and `retained_bytes` counts.
Library callers can use `Compilation.checkWithCache` or the project equivalent
with a caller-serialized `compiler.semantic_cache.Cache`. Ordinary `check` remains
fresh. `clear-cache` evicts retained trees and source generations.

A changed body is checked again. An unchanged body is copied into the current
compilation with relocated spans, expression IDs, statements and loan metadata.
Declaration/type collection and global region, effect and domain-codec checks
still run every time; an edited allocating callee can therefore invalidate an
unchanged `noalloc` caller. Only fully successful checks publish snapshots.
Diagnostics and warnings are freshly rendered against the current source.

The dependency key covers source origins, all text outside function bodies and
the resolved record catalog. Signature, type, import, export or declaration edits
invalidate the function snapshot. Generic functions, nominal type templates or
applications, aliases, generic domains, constant declarations and constant
functions conservatively use full checking. This is useful body-query reuse,
not dependency-minimal incremental checking of every language feature.

The session retains at most 16 MiB of accounted cache trees/source arenas;
allocation peaks while preparing a replacement are not a hard memory limit.
Unchanged entries share owned source generations. Invalid relocation falls back
to fresh checking. Failed checks and allocation failures preserve the previous
successful snapshot. Caches are in-process and never shared across compiler
binaries or concurrent callers.

## Reproduce the measurement

From the repository root, with the pinned Zig on PATH:

```sh
zig build-exe -O ReleaseFast --dep mylang \
  -Mroot=experiments/semantic-incremental/benchmark.zig \
  -Mmylang=src/compiler.zig -femit-bin=.zig-cache/semantic-benchmark
.zig-cache/semantic-benchmark
```

The benchmark creates 80 scalar functions with 40 sequential bindings each and
one caller. Each of 21 measured samples edits one function, requires exactly 80
reused bodies, and compares the executed result with a fresh compilation. It
alternates cached/fresh measurement order. Check time includes parsing and
semantic checking; edit-to-test includes lowering and VM execution. Source
construction, final destruction, navigation and schema serialization are excluded.

One local ReleaseFast run on 2026-09-07 measured:

| Operation | Cached p50 / p95 | Fresh p50 / p95 |
| --- | --- | --- |
| Parse and check | 5.82 / 6.22 ms | 6.00 / 6.33 ms |
| Parse, check and execute | 7.11 / 7.53 ms | 7.23 / 7.72 ms |

It checked 102 bodies and reused 1,680, retaining 3,234,526 bytes. This small
synthetic result establishes actual reuse and a reproducible comparison; it does
not establish a broad speed advantage. Small programs, global validation costs,
or unsupported query shapes can erase the benefit.

## Correctness checks

```sh
zig test src/root_test.zig --test-filter 'semantic '
python3 tests/check_session.py --compiler zig-out/bin/mylang
```

Tests compare fresh/cached results and rendered diagnostics after body edits,
module relocations, signature/import/export changes and failed edits. They also
exercise transitive effects, stale IDs, source-span rejection, cache eviction and
allocation failures during lookup/publication.
