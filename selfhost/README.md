# Self-hosting stages

The self-hosted compiler owns the frontend through QBE text generation. The
managed runtime, platform adapters, QBE, and a thin Zig launcher remain explicit
bootstrap boundaries; see [`runtime-abi-v1`](../docs/adr/D6-runtime-boundary.md).

## Stage model

1. **Stage 0** is the pinned Zig compiler and launcher. It compiles the first
   `.selka` compiler from clean source and the versioned runtime/resource manifest.
2. **Stage 1** is the compiler artifact produced by stage 0. It compiles the same
   source to produce stage 2.
3. **Stage 2** is the first self-built compiler. It compiles the same clean inputs
   to produce stage 3.
4. **Stage 3** is the reproducibility check. Stage 2 and stage 3 artifacts must be
   equivalent under the documented artifact comparison, and both must pass the
   compiler corpus and diagnostic parity suite.

Every stage records compiler identity, source and ABI hashes, resource manifest,
commands, exit status, output hashes, peak memory, and cold/warm timings. Reuse
receipts are correctness evidence: expected declaration and object reuse counts
must agree as well as outputs.

## Bootstrap rule

All compiler `.selka` code stays inside the exact whitelist in
[`docs/bootstrap-v1.md`](../docs/bootstrap-v1.md). Implementing a broader language
feature does not authorize its use here. Under the one-version delay, stage 0 must
have shipped and exercised a feature for one compatibility release before the
next compiler source may depend on it.

If compiler work needs a construct outside the subset, first record the concrete
workaround and measured cost. Amend the bootstrap contract and its ADR only after
the feature lands independently and the trust chain can still be rebuilt. Do not
hide the dependency in generated source, a host callback, or an unversioned Zig
helper.

The frozen bootstrap lexer is kept in parity with shipped numeric token spellings.
`zig build test-selfhost-numeric` compares prefixed integers, underscores, leading
and trailing decimal points, malformed spellings and adjacent field dots against
the live compiler. This focused fixture check runs in `zig build test`.

## The syntax oracle and the corpus (stage 1)

The Zig lexer and parser are the byte-exact oracle for a Selka lexer and parser
(`docs/audits/selfhost-plan-2026-10-19.md`). Three tools describe them:

- `selka dump-tokens FILE` prints the `tokens-v1` JSON of the lexer.
- `selka dump-syntax FILE [--module | --program] [--trusted]` prints one frame: the
  exact `StoredSyntax` bytes the syntax cache would store and the lexer and parser
  diagnostics, written with `persist_codec` (the layout is in `src/syntax_dump.zig`).
  `--trusted` allows the reserved internal spellings, as the embedded standard library
  needs. `selka dump-syntax --layout` prints the generated description of the payload
  (`src/syntax_layout.txt` is its committed copy, and a unit test fails when `ast.zig`
  changes it without the file); `--diff REFERENCE CANDIDATE` names the first differing
  field path of two frames.
- `selfhost/corpus.json` lists the files a candidate is checked on (the repository's
  `.selka` files, the selka-projects tree when it exists, the declared negative fixtures),
  and `selfhost/tests/syntax_parity.py` runs a candidate lexer (`--lexer CMD`) or parser
  (`--parser CMD`) over it against those two commands. `--self` runs the Zig front end
  as its own candidate; `zig build test-selfhost-syntax` does that over the in-tree corpus
  and tests the harness with deliberately broken candidates.
