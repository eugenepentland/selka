# Named constraints — implementation handoff

Status: implemented on branch `nc-20260915` (worktree
`mylang-worktrees/named-constraints-20260915`). The language brief is
`docs/named-constraints-proposal.md`; the frozen interface plan is
`docs/named-constraints-implementation.md`.

## Supported boundary (V1)

- `constraint NAME[SUBJECT] = REQUIREMENTS` is a contextual top-level
  declaration; the right-hand side reuses the `+` requirement grammar
  (builtins `copy/equality/integer/codec/storable`, `field(...)`, `op(...)`).
  The right-hand side may not reference another constraint, including itself.
- Named bounds apply to function type parameters: `T: Prices`,
  `T: contracts.Prices`, and combinations such as
  `T: Prices + codec + field(tag: bool)`. Subjects are exactly one bare binder.
- A named bound expands into the same `requirements.Parameter` model as an
  inline bound: builtin `Set` plus field/operation requirements. Subject
  occurrences substitute by type-parameter identity through scoped aliases,
  including inside supported composite signatures (`list[P]`, callbacks,
  fixed arrays). Named and inline spellings accept and reject the same
  operations, and independently declared equivalent names satisfy the same
  forwarding obligations.
- Fields and operations coalesce when identical; conflicting same-name
  members, duplicate resolved bundle identities, and expansion beyond the
  16-requirement limit reject with located diagnostics.
- Constraints participate in the module declaration namespace and explicit
  exports with a distinct kind; private/import/visibility/shadowing and
  exported-signature exposure rules use the existing diagnostics. A constraint
  is not a value type (`x: Prices`, `Prices[int]` reject with a kind error).
- Unused invalid constraint declarations are checked: bad subjects, nested
  named references, no-copy structural fields, and unknown signature types all
  reject before any provider exists.
- Constraints and named references survive AST copying, project relocation,
  formatting, declaration listing, the in-memory syntax cache, and the
  persistent parsed-syntax cache (frontend format version bumped to v2).

## Verification performed

All commands run in the worktree with the pinned Zig (0.17.0-dev.1683).

```text
zig build                                  guardian run-all: 88 checks passed
zig build fmt-check                        pass
GUARDIAN_SKIP_CHECKS=1 zig build test-units    884/885 pass (1 pre-existing failure)
GUARDIAN_SKIP_CHECKS=1 zig build test-cli      76/76 pass
GUARDIAN_SKIP_CHECKS=1 zig build test-docs     0 failed (docs/generics.md 5 run)
mylang doc-coverage .                      0 failures
```

Named-constraint focused suites (all green): 32 tests matching
`named constraints`, plus 46 `interfaces`, 143 `generic`, 32 `structural`, and
the 11 `QBE emission release partial allocations` tests.

The end-to-end acceptance fixture is `examples/named-constraints/`:

```text
mylang test examples/named-constraints/fake_tests.my --filter test_checkout   -> pass
mylang run  examples/named-constraints/main.my                               -> exit 0
fake_tests.my with production.my absent                                      -> pass
fake_tests.my with an invalid, unimported production.my                      -> pass
main.my with that invalid imported production.my                             -> E_UNKNOWN_SYMBOL
```

`test/integration.zig` carries the same scenario as
`NAMED-CONSTRAINT-FIXTURE-1`.

## Known pre-existing issues (not caused by this change)

- `managed_lists_test.test.bytecode rejects managed metadata on an ordinary
  aggregate` fails at the base commit too (verified in a clean worktree), so
  `zig build test` cannot be fully green. `zig build` (the Guardian install
  gate) is green.
- `mylang check <module-file>` reports `E_SYNTAX: expected def` for any module
  file, including `examples/modules/main.my` at the base commit. Use `run`,
  `test`, or `list-modules` for module projects.

## Deferred work

- Public checked-schema/tooling exposure: `src/generic_api.zig` ignores
  `TypeParameter.named_requirements`, so an exported generic's named bound
  spelling and expanded contract are not yet in the checked template schema or
  navigation output. `interfaces.render` (the pre-body inventory) does list
  exported constraint declarations. Adding the expanded contract needs a
  schema version bump and a designed agent-facing shape.
- The interface-time `validateBounds` limit count counts each bundle's declared
  items without cross-bundle coalescing, so a bound whose bundles overlap could
  be rejected there but accepted by the semantic `resolveBounds`. The semantic
  path is authoritative for compilation.
- Runtime interface values, methods/receivers, constraint inheritance,
  multi-parameter constraints, associated types, fine-grained persistent
  generic-body caching, and optimization policy remain out of scope per the
  brief.

## Environment note

The shared checkout `/home/epentland/ai/canopy/mylang` was being modified and
`git stash`-ed by an unrelated concurrent agent, so this work was isolated in
`mylang-worktrees/named-constraints-20260915` (branch `nc-20260915`) based on
`4d21b85`. It must be rebased/merged when the main checkout stabilizes.
