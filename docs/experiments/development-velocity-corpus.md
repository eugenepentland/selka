# Development velocity corpus v1

This is an untimed, versioned preparation corpus with twelve new tasks across six
families. Eight feature tasks and four equivalent seeded-bug tasks expand beyond
the earlier planner/EDA examples. Nothing here certifies a timed launch or changes
historical evidence.

The catalog, exact language-neutral briefs, executable expected-value models,
deterministic request generator and tests live in
`experiments/development_velocity/corpus`. Each application receives one bounded
JSON batch `{ "requests": [...] }` and returns `{ "results": [...] }` in one
process. The shared `PROCESS.md` defines strict transport and integer handling.
Python and .selka receive identical public contracts and request bytes. Filesystem
work uses supplied virtual snapshots; timing does not depend on host disk contents.

| Family | Feature task | Second task |
|---|---|---|
| Data/text | data-rollup | ascii-table (feature) |
| Configuration | config-layers | quota-boundary (bugfix) |
| Stateful collections | lru-cache | ttl-boundary (bugfix) |
| Binary codecs | record-frames | little-endian-read (bugfix) |
| Filesystem/path | snapshot-diff | mount-routing (feature) |
| Multi-module maintenance | inventory-reservations | atomic-transfers (bugfix) |

`catalog.MUTATIONS` names one corresponding semantic defect per bug task:
exclusive instead of inclusive quota, late expiry at equality, wrong byte order,
and committing part of a failed transaction. Both language starters must be
prepared from correct implementations, apply exactly the declared mutation, pass
unchanged behavior checks, and fail the intended public witness before clocks.
Mutation descriptions are preparation metadata, not a substitute for verified
starters. Feature starters share parse/process/emit scaffolding and an I/O module;
the two maintenance tasks retain model, ledger and report/process modules.

Run the independent model tests with:

```
python3 -B -m unittest experiments.development_velocity.corpus.test_corpus
```

Generate packs outside the repository, using a private seed file:

```
python3 -B -m experiments.development_velocity.corpus.pack \
  --task atomic-transfers --seed-file /private/seed.txt \
  --directory /private/corpus-v1/atomic-transfers
```

Creation refuses existing destinations and repository destinations. Public output
contains only process/task prose and public cases. Private cases and seed remain
in a separate private directory; manifests retain source and content hashes.
The case format matches the existing coordinator's `inputs.decode_case` format,
including exact-byte base64 transport probes. Private generation is deterministic
for the same task/seed; public generation ignores the private seed. Future changes
to oracle, schema, task semantics or generation require a new frozen receipt and
must not overwrite a prior cohort.

Every private task includes hand-selected valid upper bounds, array max+1 cases,
field type and numeric/schema edges, plus 48 seeded requests. Probes exercise
128-element state/data arrays, 64 layers/rows, 32 records/accounts/batches and
32 transfers per batch, full-width encoded inputs, exact expiry/quota/endian
boundaries, duplicate logical keys and full-validation precedence. Raw inputs
cover malformed JSON/UTF-8, duplicate object keys, isolated surrogates, nonfinite
numbers, signed-integer overflow, nesting and the one-MiB boundary. Twelve model
tests include hand-derived byte strings, ordering and state results, together
with independent conservation invariants; generated expectations alone are not
independent acceptance proof. A separate reviewer must review models and generated
probes before any private acceptance claim.

Standard-library parity remains a launch gate. Preparation adds bounded byte
padding/span joining in std_strings, separately named absolute lexical helpers
in std_path, and full decoded UTF-8 string materialization in std_json_view.
Existing relative path contracts stay unchanged. These general operations are
available before application work; timed participants must not reimplement them.
The path task's narrower ASCII component grammar and 256-byte input ceiling are
application schema rules, separate from the general library's lexical policy.
Current maps, sorting, endian/hex, JSON views/builders and integer math cover the
other declared mechanisms, subject to actual dual-language starter/adapter proof.

Readiness remains blocked until equivalent starters, host adapters, library proof,
independent expected-value review, source-quality rubric and private receipt freeze
are complete. No performance, bug-rate or turn-count claim comes from this corpus
or its preparation tests.
