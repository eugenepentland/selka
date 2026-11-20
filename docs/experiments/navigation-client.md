# Bounded compiler navigation

Generate checked source relationships or ask a focused question:

```sh
mylang index-project path/to/main.my
python3 scripts/navigate.py --compiler zig-out/bin/mylang --entry path/to/main.my \
  --symbol model::Board --relation impact --limit 20 --context-bytes 8192
python3 scripts/navigate.py --compiler zig-out/bin/mylang --entry path/to/main.my \
  --query validate --type model::Validation --effect host --relation context
```

The client supports `definition`, `references`, `callers`, `callees`, `impact`, and
`context`. Name searches are case-insensitive substrings; symbol, checked type, and
effect filters use exact names. Callers/callees use resolved call edges. Impact
walks reverse static relationships, including type and field dependencies. It is
not runtime coverage, automatically selected tests, or proof of complete change
impact. Generic declarations are indexed; the compiler explicitly describes the
scope of checked relationships in each index.
Concrete generic specializations share their original declaration identity and
contribute combined relationships and effects. A local's displayed type is the
first observed instantiation; type relationships retain other concrete uses.
Uninstantiated generic bodies have declaration metadata without checked body edges
or inferred effects. Use the public generic schema inventory for their symbolic
requirements and declared effect ceilings.

Top-level declaration IDs remain qualified by module/name across whitespace edits.
Local/reference IDs also include their original declaration byte offset to distinguish
same-named bindings in disjoint scopes; these IDs are specific to a source snapshot.
Results include exact source locations, signatures, types,
effects, bounded snippets, and the source snapshot identity. Defaults cap symbols
and relationship rows at 20 each and combined snippets at 8 KiB. Omitted counts
and per-snippet truncation are explicit. Reverse traversal has its own scan bound;
`traversal_truncated` marks an incomplete exploration. Qualified IDs are the reliable
query target when short names occur in multiple modules.

Broken semantic or syntactic source can produce a partial declaration index with
`checked: false`, no checked edges, and `semantic_relations_available: false`.
Syntax recovery scans declaration candidates only after the complete project was loaded;
missing imports and failures during module-header loading still return diagnostics
without an index. Lexically invalid modules are counted as omitted.
Partial declarations support finding and repairing source. They are never a
successful type-check verdict or evidence that old relationships still hold.

Add `--cache-dir /tmp/mylang-navigation` to reuse an exact index across agent roots.
The key includes the compiler binary digest, entry name, and every `.my` file's
relative path and content digest beneath the entry directory. Scanning extra,
unimported files is deliberately conservative. Each compiler-produced dependency
hash and snapshot digest is verified. Sources and compiler bytes are rechecked
before returning either a generated or cached index. Partial indexes may be reused
only for their exact failed source snapshot; repairing source cannot retain their
missing edges or reuse stale checked facts.

Receipts include a digest of the full index, publish atomically, and regenerate on
corruption. The dedicated store retains at most 128 receipts and 64 MiB after
publication; oversized results remain uncached. Navigation caching has no scheduler
or duplicate-job suppression; the separate verification scheduler handles test
jobs. Source scanning caps 50,000 filesystem entries and 16 MiB of `.my` bytes.
Index reads cap 64 MiB. Nonregular source/cache files are opened without blocking,
symlinks are rejected, and directory symlinks are not traversed. Use a bounded
application root, rather than placing the entry above unrelated large repositories.

The cache is trusted local tooling, not a hostile-filesystem sandbox. The generated
compiler response is bounded by compiler navigation limits and a request timeout;
query payload limits do not change the compiler's internal analysis cost.

`tests/navigation_client.py --compiler BINARY` exercises actual compiler queries,
call relationships, source-equivalent roots, semantic failure/repair, corruption,
source edits during generation, UTF-8 context bounds, traversal limits, nonregular
files, retention, and partial parse-error indexes.

A same-binary ReleaseFast trial on 97 generated modules / 2,401 functions produced
4,705 symbols and 4,704 references. Five fresh queries had a median of 944 ms
(p95 955 ms); five validated cache reads had a median of 53.2 ms (p95 54.0 ms).
Those measurements include Python inventory/digest/JSON costs and describe this
local workload, not a general speed guarantee. The evidence includes the exact
compiler hash in `experiments/navigation-profile.json`; reproduce it with
`scripts/profile_navigation.py --compiler BINARY --output /tmp/navigation-profile.json`.
This measured index cost justified exact index reuse on its own; it did not
decide whether semantic body-verdict caching should exist. Per-function
checked-body, symbolic-template and concrete-specialization reuse later landed
independently through the shared semantic cache; see
[development velocity implementation status](../audits/velocity-implementation/final-status.md).
