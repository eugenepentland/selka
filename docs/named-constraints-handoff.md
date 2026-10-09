# Named constraints — implementation handoff

Status: implemented on branch `nc-20260915` (worktree
`selka-worktrees/named-constraints-20260915`). The language brief is
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
zig build (Guardian whole-tree)             88 checks passed
zig build fmt-check                        pass
GUARDIAN_SKIP_CHECKS=1 zig build test-units    905/905 pass
GUARDIAN_SKIP_CHECKS=1 zig build test-cli      79/79 pass
GUARDIAN_SKIP_CHECKS=1 zig build test-docs     0 failed (docs/generics.md 5 run)
selka doc-coverage .                      0 failures
python3 /tmp/nc-probes/run.py <binary>     18/18 review repros
```

Named-constraint focused suites (all green): 46 matching `named constraints`,
17 `namespace`, 10 `generic api`, 34 `schema`, 53 `interfaces`, 38
`structural`, 147 `generic`, and the 11 `QBE emission release partial
allocations` tests.

The end-to-end acceptance fixture is `examples/named-constraints/`:

```text
selka test examples/named-constraints/fake_tests.selka --filter test_checkout   -> pass
selka run  examples/named-constraints/main.selka                               -> exit 0
fake_tests.selka with production.selka absent                                      -> pass
fake_tests.selka with an invalid, unimported production.selka                      -> pass
main.selka with that invalid imported production.selka                             -> E_UNKNOWN_SYMBOL
```

`test/integration.zig` carries the same scenario as
`NAMED-CONSTRAINT-FIXTURE-1`.

## Known pre-existing issues (not caused by this change)

- `selka check <module-file>` reports `E_SYNTAX: expected func` for any module
  file, including `examples/modules/main.selka` at the base commit. Use `run`,
  `test`, or `list-modules` for module projects.

## Review fixes (2026-09-15)

`docs/audits/named-constraints-review-2026-09-15.md` reported eight findings;
all are fixed on this branch:

1. Exported imported constraints index the defining module's symbol table, so a
   mismatched consumer table can no longer panic or misreport privacy.
2. Concrete names inside a named declaration resolve in the declaring scope. A
   consumer type parameter can no longer capture a same-spelled declaration
   type, in universal checking or concrete conformance, including composites.
3. Requirement merging compares resolved identities and subject positions
   (nominal record/template identity, parameter index, array and callback shape)
   instead of source spelling: distinct same-spelled types conflict, while
   alpha-renamed, inline/named and composite equivalents coalesce.
4. Module preflight uses the implied builtin `Set` (`equality` and `integer`
   imply `copy`) and imported definitions supply their `copy` guarantee, so
   standalone and module checking agree. The expanded 16-requirement limit is
   enforced once, after identity-aware coalescing.
5. `generic_api.zig` publishes exported constraints as non-callable
   `constraint` templates and each exported generic parameter's named bound
   spelling, declaring module and expanded promises, under
   `generic-templates-v2`.
6. Standalone programs enforce the constraint declaration namespace (duplicates
   and collisions with records, variants, domains, resources, aliases and
   top-level functions), whether or not either declaration is used.
7. Unused constraint declarations get the full structural validity check, so
   result-bearing or move-only fields reject before any provider exists.
8. The review's 18 repros are kept as a permanent regression suite
   (`test/named_constraints_probes.zig`, driven by `test/integration.zig`, spec
   tag `NAMED-CONSTRAINT-REVIEW-1`).

## Deferred work

- Navigation and source-inventory expansion of constraints is separate; the
  pre-body `interfaces.render` inventory lists the declaration name only.
- Runtime interface values, methods/receivers, constraint inheritance,
  multi-parameter constraints, associated types, fine-grained persistent
  generic-body caching, and optimization policy remain out of scope per the
  brief.

## Branching note

The original feature landed on `main` at `da3aabf`. These review fixes live on
`nc-fixes-20260915`, based on `wave3/base` (`3c0b41f`), which already contains
the feature commit plus wave3 work. The merged main checkout should prefer this
branch.
