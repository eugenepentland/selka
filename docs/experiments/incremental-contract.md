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
| generic specialization | template identity, concrete arguments, provider shape, target ABI, compiler identity | unrelated specializations |
| emitted fragment | symbol identity, fragment kind, normalized emitted bytes | untouched fragments |

The observable interface hash of a declaration (`interface_sha256`) includes only
what a dependant can observe: canonical name and kind, parameter and return
types, explicit generic parameters and requirements, effect ceiling and inferred
effect set, capability/restriction flags, exported record fields or union
variants, and public layout flags. It excludes function bodies, comments,
formatting, diagnostic spans, private declarations and local names. A body edit
with an unchanged interface does not change the interface hash; a signature,
effect, constant, record or union change does. Parameter defaults participate in
the callable interface, because an unchanged call site can behave differently
after a default changes.

The project interface fingerprint (`project_interface_sha256`) is composed from
the sorted `interface_identity`/`interface_sha256` pairs of exported interface
items only. It is a dedicated semantic encoding, not a hash of the whole public
schema: exported constants, declared effect ceilings, parameter defaults and
exported type shapes participate, while comments, formatting, source paths,
source hashes, spans and private declarations are excluded.

```console
$ mylang project-dependencies app/main.my | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["incremental"]["version"]); print(d["incremental"]["project_interface_sha256"])'
incremental-identities-v2
9f2c...e1
```

## Interface versus implementation

An exported-interface fingerprint is independent of the implementation body.
A private body edit rechecks and re-emits that body but does not recheck callers
whose imported interface did not change. Inferred effects are the one subtle
case: body reuse never reuses an effect verdict, because effects are recomputed
over the whole call graph after every check, so adding an effect in a callee body
still rejects an unchanged effect-bounded caller.

## Query stages

The incremental model names nine explicit stages. Each records its input
fingerprints and dependency identities. A stage a command did not run is
reported `skipped`, never as a hit; a report therefore distinguishes actual
reuse from work that never happened.

1. `load_source` — every module name, path and source hash, plus the compiler
   identity, target and toolchain.
2. `lex_parse` — the exact path and bytes of each module.
3. `collect_declarations` — module identities and the module set.
4. `resolve_interface` — the project exported-interface fingerprint.
5. `check_body` — per-declaration body fingerprints.
6. `instantiate_specialization` — generic specialization keys.
7. `lower_function` — checked declaration identity, interface hash and body
   hash; lowering consumes the checked body.
8. `emit_fragment` — emitted function/data fragment fingerprints.
9. `link` — compiler, toolchain, target, runtime ABI identity and the emitted
   fragment inputs.

A command that lowers (such as `run` or `emit-project-qbe`) builds its receipt
after lowering, so the fragment table holds real inputs. A check-only command
reports lowering, emission and linking as `skipped`.

## Cache-key contract

Every incremental cache entry is distinguished by a contract fingerprint with
the same six dimensions:

| Dimension | Current value |
| --- | --- |
| compiler build identity | the build-time digest already embedded in the compiler |
| bootstrap-language version | `bootstrap-v1` |
| target | the selected native target |
| runtime ABI | `runtime-abi-v0-unfrozen` until Wave 4 freezes `runtime-abi-v1` |
| effects/capabilities contract | `effects-v1` |
| relevant flags | the invoking command's frontend flags |

```text
contract fingerprint = SHA256(compiler_identity, bootstrap-v1, target, runtime-abi-v0-unfrozen, effects-v1, flags)
```

A generic specialization key mixes the template identity, the canonical
concrete arguments, the concrete provider type shape (record fields, variants and
layout flags), the target ABI and the compiler build identity. A provider-shape
edit changes the key even when the template is unchanged; the target and compiler
inputs are the real receipt values, not placeholders.

The fingerprint is folded into the persistent syntax key, the whole-program
verdict key, the checked-function-body digest, the generic-specialization key and
the native object identity. Changing any dimension invalidates those entries even
when every source byte is identical. The persistent frontend cache also keeps its
existing compiler-identity partition; `runtime_abi` and `flags` are explicit so a
future runtime ABI or flag change cannot silently reuse an older entry.

## Invalidation observability

`--explain-invalidation` compares the current checked project against the previous
`project-dependencies-v1` receipt and prints exactly one `invalidation-report-v1`
JSON line on stderr. A missing baseline makes every executed stage miss with
`first_changed` `"no-baseline"`; a baseline is compared only after its version,
implementation identity, inputs array and incremental module table validate, and
a structurally invalid baseline (for example `{}`) makes every executed stage
miss with `"corrupt-baseline"` instead of comparing missing fields into hits.
Skipped stages stay skipped and are not counted as hits or misses. A rejected
check still emits a best-effort report from a partial receipt, but it never
publishes a successful verdict. The baseline lives at
`<cache-dir>/invalidation/<entry>.json` and is deliberately **not** partitioned
by compiler identity, so a compiler change can be explained. `--no-cache` reads
and writes no baseline.

`--report` adds a `stages` object to the existing `frontend-cache-v1` line with
`hits`, `misses` and `skipped` counts for each of the nine stages. When
`--explain-invalidation` is also given, the counts come from the receipt
comparison; otherwise stages the command did not run are `skipped` and stages it
ran fresh are misses.

```console
$ mylang check-project app/main.my --explain-invalidation --report --cache-dir=.mylang-cache/demo
{"version":"invalidation-report-v1","hits":6,"misses":1,"skipped":2,"queries":[{"stage":"load_source","status":"hit","key":"c354..."},{"stage":"lower_function","status":"skipped","key":"lower_function"}, ...]}
{"version":"frontend-cache-v1","syntax_hits":1,"syntax_misses":0,...,"stages":{"load_source":{"hits":1,"misses":0,"skipped":0},"lower_function":{"hits":0,"misses":0,"skipped":1}, ...}}
```

## Declaration-backed body reuse

Ordinary checked-body reuse is gated by declaration identity and interface
dependencies, not by hashing the whole project's source. Each ordinary
declaration carries a stable `declarationIdentity` and a semantic interface
digest; the cache publishes the ordered table of those keys together with the
resolved type-catalog digest. A second check may reuse bodies only when the
ordered declaration identities and interface digests and the catalog are
unchanged. Per body, reuse additionally requires the declaration's own full
source text (header plus body) to be byte-identical, so span relocation is exact.
An interface change to any declaration remains conservative: every body is
rechecked, because an unchanged caller may depend on the changed contract.

```text
gate = ordered declarationIdentity + interface digest + resolved type catalog
reuse one body = gate unchanged AND that declaration's full text byte-identical
```

## Correctness: clean versus warm

Every incremental scenario is compared against a clean rebuild. The invalidation
matrix in `src/invalidation_matrix_test.zig` asserts all of the following for
whitespace, comments, private bodies, exported signatures, effects, constants,
record and union shape, imports, generic templates, specialization arguments,
runtime ABI, compiler version and damaged cache entries:

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
