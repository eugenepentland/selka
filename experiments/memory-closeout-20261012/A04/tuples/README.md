# Complete tuple fixture migration

`tests/lang/tuples.my` now copies borrowed managed tuples before whole unpacking
and moves the resulting owned fields. It transfers a local tuple directly into
the list after its last read, and copies the borrowed tuple directly into the
wrapper record. The Optional payload, generic helpers, ignored fields, tuple
rendering and all five public test functions remain covered.

`originals/` preserves C0, the pre-follow-up source, the earlier pending migration
and the final migrated source. `source-identities-final.json` records hashes,
line/copy burden and every original public conditional/return oracle. All those
oracles are unchanged. Two unused bindings become `_`; no initializer or test
assertion was removed.

The source passes checked and ordinary no-cache checking. `prototype-02/` executes
all five tests in each of five checked build modes and ordinary release: six
native executables, 30 successful Boolean test calls. An appended `main` returns
the failing test's index, so successful exit0 proves every test ran and passed.
All compiler and guest stderr is empty. Each checked run has zero RC events,
zero managed exit-live bytes and clean emitted LLVM/linked symbols; the ordinary
control also exits without managed leaks.

Compiler SHA256 is
`70525285968f79d1bd3e78705b189763ea015d4ac9073676eb0eaa1ed6667d5e`.
The provenance file refers to the exact selection prototype source manifest and
its schema/verifier dependencies; the worker branch commit alone is not that
compiler identity. The initial `prototype-01/` retains warnings from unused
bindings: its guest executions passed, while strict compiler-stderr checks
correctly marked the qualification incomplete. The final migration removes those
warnings without changing the five test oracles.

Run `qualify.py --compiler PATH --source-commit SHA --phase FRESH_NAME` after
sourcing the shared development environment. The harness owns admission. Use
`--default-ownership` for promoted normal commands; ABI/memory audits remain
mandatory. Support7 and the common final candidate still require their own
source/native five-mode rerun. This is intermediate migration evidence, with no
performance, default-promotion or RC-retirement claim.
