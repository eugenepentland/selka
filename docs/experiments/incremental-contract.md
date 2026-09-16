# Incremental compilation contract

This document is the public tooling contract behind Wave 3 of the
[self-hosting implementation plan](../audits/self-hosting-implementation-plan-2026-09-14.md).
It fixes the identities, query stages, interface boundary, cache keys and
observability that the incremental compiler must reproduce. It describes public
behavior, not incidental implementation details: cache files and query keys may
change layout, but the rules here may not silently change.

## Stable identities

Every identity is a lowercase SHA-256 over a domain-separated, canonical
encoding. Identities never contain a source byte offset, an arena address or a
hash-map iteration position. Source spans remain diagnostic data attached to an
identity, so inserting or removing text before a declaration does not change that
declaration's identity. `mylang project-dependencies` exposes the current
manifest under the `incremental` object of the `project-dependencies-v1` receipt.

| Identity | Derived from | Survives |
| --- | --- | --- |
| module | canonical module name | edits inside the module |
| top-level declaration | module identity, kind, owner, canonical name | edits elsewhere in the module |
| exported interface item | module, kind, owner, canonical name | body edits |
| type / nominal template | module, kind, canonical name, template marker | body edits |
| function body | declaration identity plus exact body bytes | untouched bodies |
| generic specialization | template identity, ordered positional type/length descriptors, transitive name-ordered provider contracts, template constraint dependencies, declared effect/mutation/return-origin contracts, build context | unrelated specializations |
| emitted fragment | symbol identity, fragment kind, normalized emitted bytes | untouched fragments |

The observable interface hash of a declaration (`interface_sha256`) includes only
what a dependant can observe: canonical name and kind, parameter and return
types, explicit generic parameters and requirements, the declared effect ceiling,
the normalized `mutates(...)` input footprint and the published `return_origin`
bound, capability/restriction flags, exported record fields or union variants,
and public layout flags. It excludes function bodies, comments, formatting,
diagnostic spans, private declarations, local names and inferred implementation
facts. A body edit with an unchanged interface does not change the interface hash;
a signature, declared effect ceiling, mutation footprint, constant, record or
union change does. A body that uses a different subset of the same declared
ceiling keeps the public interface hash but still invalidates runtime-test
receipts because the body hash changed.

```console
$ mylang project-dependencies app/main.my | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["incremental"]["version"]); print(d["incremental"]["project_interface_sha256"])'
incremental-identities-v2
9f2c...e1
```

## Interface versus implementation

An exported-interface fingerprint is independent of the implementation body.
A private body edit rechecks and re-emits that body but does not recheck callers
whose imported interface did not change. Inferred effects are the one subtle
case: body reuse never reuses an effect or mutation verdict, because both are
recomputed over the whole call graph after every check, so adding an effect or an
input-mutation footprint in a callee body still rejects an unchanged bounded
caller.

## Query stages

The incremental model names nine explicit stages. Each records its input
fingerprints and dependency identities, and each can be reported as a hit or a
miss with the first changed dependency.

1. `load_source` — every module name, path and source hash, plus the compiler
   identity, target and toolchain.
2. `lex_parse` — the exact path and bytes of each module.
3. `collect_declarations` — module identities and the module set.
4. `resolve_interface` — the project exported-interface fingerprint.
5. `check_body` — per-declaration body fingerprints.
6. `instantiate_specialization` — generic specialization keys.
7. `lower_function` — checked function identities.
8. `emit_fragment` — emitted function/data fragment fingerprints.
9. `link` — compiler, toolchain, target and runtime ABI identity.

## Cache-key contract

Every incremental cache entry is distinguished by a contract fingerprint with
the same six dimensions:

| Dimension | Current value |
| --- | --- |
| compiler build identity | the build-time digest already embedded in the compiler |
| bootstrap-language version | `bootstrap-v1` |
| target | the selected native target |
| runtime ABI | `runtime-abi-v1` |
| effects/capabilities/mutation contract | `effects-v3` |
| relevant flags | the invoking command's frontend flags |

```text
contract fingerprint = SHA256(compiler_identity, bootstrap-v1, target, runtime-abi-v1, effects-v3, flags)
```

The fingerprint is folded into the persistent syntax key, the whole-program
verdict key, the durable `semantic-cache-v1` checked-body key and header, the
generic-specialization key and the native object identity. The checked-body store
also embeds the M1/M2 mutation-contract version. Changing any dimension
invalidates those entries even when every source byte is identical. The
persistent frontend cache also keeps its existing compiler-identity partition;
`runtime_abi` and `flags` are explicit so a future runtime ABI or flag change
cannot silently reuse an older entry.

### Durable checked-body entries

C2 persists one ordinary function body per `semantic-cache-v1` file. C3 adds two
more payload kinds in the same contract namespace: `symbolic-template-v1` for
abstract generic templates and `specialization-v1` for concrete specializations.
The specialization key is canonical over the template identity, the ordered
positional type/length descriptors, the transitive name-ordered provider
contracts, the template constraint dependency, the declared
effect/mutation/return-origin contract and the build context, with every boundary
length-prefixed. A concrete reuse is admitted only when the defining template's
declaration region/body bytes are byte-identical, the template dependency context
matches, and every stored function/record reference remaps to exactly one fresh
identity; a missing or ambiguous remap, a nested specialization that the fresh
run has not instantiated, or a synthesized lambda reference is a conservative
miss. The whole-graph effect and mutation passes are never cached: they rerun from
the combined fresh and replayed trees on every request, so a changed provider or
callee body can never inherit a stale transitive verdict.

C2 persists one ordinary function body per `semantic-cache-v1` file. The header
repeats the format version, cache-contract fingerprint, mutation-contract version,
stable declaration key, dependency context, entry count, payload length and
checksum. The payload contains the owned relocatable `typed.Function` tree, node
and statement slices, checked-contract digest, stable referenced function/record
identities, the source region/body bytes and the derived body-local
binding-warning notes. The fresh binding pass still relocates and re-emits those
warnings from the copied locals rather than replaying the notes, so relocation
and cold-check diagnostics stay identical. It never contains pointers, allocator
capacity or runtime catalog ordinals.

A decode is admitted only after every field, range, tag, ordinal and declared
length validates. C1R then remaps stable identities into the fresh catalog;
missing or ambiguous remapping is a miss. Only successful checks publish, using a
same-directory temporary file, flush/sync and atomic rename. Damaged, truncated,
oversized, foreign-version and contract-incompatible files are discarded and
re-derived; `--no-cache` performs no durable reads or writes. The store is bounded
by total bytes and entry count and evicts oldest-mtime-first after publication.

## Invalidation observability

`--explain-invalidation` compares the current checked project against the previous
`project-dependencies-v1` receipt and prints exactly one `invalidation-report-v1`
JSON line on stderr. A missing baseline is reported as nine misses with
`first_changed` `"no-baseline"`; a corrupt baseline is reported as nine misses
with `"corrupt-baseline"` rather than failing the command. The baseline lives at
`<cache-dir>/invalidation/<entry>.json` and is deliberately **not** partitioned
by compiler identity, so a compiler change can be explained. `--no-cache` reads
and writes no baseline.

`--report` adds a `stages` object to the existing `frontend-cache-v1` line with a
hit/miss count for each of the nine stages. When `--explain-invalidation` is also
given, the counts come from the receipt comparison; otherwise they are derived
from the live syntax and verdict cache counters.

`--report` and `--timings=json` also print a `work-report-v1` line that
distinguishes an unchanged fingerprint from actual result reuse and counts what
each stage performed, reused or skipped. See
[Compiler work and reuse report](../tooling/work-report.md#compiler-work-and-reuse-report).

```console
$ mylang check-project app/main.my --explain-invalidation --report --cache-dir=.mylang-cache/demo
{"version":"invalidation-report-v1","hits":9,"misses":0,"queries":[{"stage":"load_source","status":"hit","key":"c354..."}, ...]}
{"version":"frontend-cache-v1","syntax_hits":0,"syntax_misses":0,...,"stages":{"load_source":{"hits":1,"misses":0}, ...}}
```

## Correctness: clean versus warm

Every incremental scenario is compared against a clean rebuild. The invalidation
matrix in `src/invalidation_matrix_test.zig` asserts all of the following for
whitespace, comments, private bodies, exported signatures, effects and mutation
footprints, constants, record and union shape, imports, generic templates,
specialization arguments, runtime ABI, compiler version and damaged cache
entries:

- the accepted/rejected status is identical;
- the diagnostic JSON is identical (codes, messages, causes and order);
- the checked `language-schema-v1` interface manifest is identical;
- the normalized QBE is identical for accepted programs; and
- the declared reuse counts match the expected per-declaration reuse.

Missing or damaged cache data always falls back to recomputation. A partial,
truncated or foreign entry is never decoded into a result; a damaged frontend
entry increments the `damaged` counter and rechecks fresh.

```text
for every matrix case: warm accepted == clean accepted
                       warm diagnostics == clean diagnostics
                       warm interface manifest == clean interface manifest
                       warm QBE == clean QBE
                       observed reuse == expected reuse
```

## Reference workload budget

The reference compiler-shaped workload is
[`selfhost/prototype/bench.my`](../../selfhost/prototype/bench.my), a
4,000-piece source builder and lexer. On the recorded reference machine, a
private-body edit (`line_count = 4000` to `4001`) measured through
`scripts/profile_development.py` with seven samples on the named reference
machine (`linuxserver`, Linux 7.0.0 x86_64, 20 logical CPUs, Debug compiler
build) is:

```text
cold check    median 20.4 ms  p95 23.2 ms
warm verdict  median  2.4 ms  p95  2.6 ms
edited check  median  7.6 ms  p95  8.6 ms
```

The warm-edit p95 budget is 500 ms; the recorded warm-edit p95 is 8.6 ms. A
timing report is only valid with its expected reuse counts, so the recorded
profile is stored with the measurement in
[`incremental-contract-profile.json`](incremental-contract-profile.json) and the
matrix asserts reuse alongside equivalence.
