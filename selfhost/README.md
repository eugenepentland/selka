# Self-hosting stages

The current compiler is progressively self-hosted through independently built
Selka components. Test reachability and cache planning run in Selka; the lexer
and full parser have explicit comparison and component modes across compiler
commands. Declaration indexing, export visibility and re-export identities now
have the same opt-in modes. Their pinned native seed builds without these components. See the
[component guide](../docs/tooling/selfhost-components.md) and
[frontend qualification](../docs/tooling/frontend-adoption-qualification.md).

The complete compiler has **not** compiled itself. Checking, Core lowering,
optimization, LLVM emission, command coordination and much tooling remain in
Zig. The historical QBE port and prototype sources are salvage material, not
evidence of a current staged bootstrap. The current native pipeline and C runtime
boundary are defined by [D6](../docs/adr/D6-runtime-boundary.md).

## Target stage model

These stages describe the future full-compiler bootstrap proof:

1. **Stage 0** is an independently rebuildable pinned native compiler. It compiles the first
   `.my` compiler from clean source and the versioned runtime/resource manifest.
2. **Stage 1** is the compiler artifact produced by stage 0. It compiles the same
   source to produce stage 2.
3. **Stage 2** is the first self-built compiler. It compiles the same clean inputs
   to produce stage 3.
4. **Stage 3** is the reproducibility check. Stage 2 and stage 3 artifacts must be
   equivalent under the documented artifact comparison, and both must pass the
   compiler corpus and diagnostic parity suite.

Every completed stage must record compiler identity, source and ABI hashes, resource manifest,
commands, exit status, output hashes, peak memory, and cold/warm timings. Reuse
receipts are correctness evidence: expected declaration and object reuse counts
must agree as well as outputs.

## Bootstrap rule

Component `.my` code stays inside its independently qualified source profile in
[`docs/bootstrap-v1.md`](../docs/bootstrap-v1.md). Implementing a broader language
feature does not authorize its use by the component's own bootstrap seed.
The future full compiler retains the one-version feature delay from
[D7](../docs/adr/D7-feature-delay.md); independently seeded components follow the
separate qualification rule documented there.

If compiler work needs a construct outside the subset, first record the concrete
workaround and measured cost. Amend the bootstrap contract and its ADR only after
the feature lands independently and the trust chain can still be rebuilt. Do not
hide the dependency in generated source, a host callback, or an unversioned Zig
helper.

The frozen bootstrap lexer is kept in parity with shipped numeric token spellings.
`zig build test-selfhost-numeric` compares prefixed integers, underscores, leading
and trailing decimal points, malformed spellings and adjacent field dots against
the live compiler. This focused fixture check runs in `zig build test`.
