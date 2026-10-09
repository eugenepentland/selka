# Selka documentation

Start with the [design goals](goals.md), [short language tour](tour.md), and
[benchmark snapshots](benchmarks.md) to see what Selka is for and how it is
progressing. Local reasoning, competitive native performance, fast incremental
compilation and testing, and one way to express each concept guide the design.

Selka was previously called `mylang`. Existing projects can follow the
[rename guide](tooling/selka-rename.md) to update commands and file names.

Writing a program? Read [the one-page primer](primer.md): it is
everything a Python programmer needs for a first program, and every example on
it is run by `selka doctest`. After that, the pages below are the reference,
grouped by what you are doing. The pages under [Compiler records](#compiler-records)
are about developing the compiler itself; nobody writing Selka programs needs
them.

## The guides built into the compiler

The user guides ship inside the `selka` executable, so they are available in a
project that has no copy of this directory:

```console
$ selka docs                 # list the topics
$ selka docs primer          # print the primer (Markdown) to stdout
$ selka docs errors          # fails, try, Result and optional values
$ selka reference --query E_MODULE_NAME   # one feature or error code, from the same executable
```

| Topic | Page |
| --- | --- |
| `primer` | [One-page primer](primer.md) |
| `syntax` | [the language guide](python-syntax.md) |
| `statements` | [statements and bindings](statements.md) |
| `records` | [records, unions and enums](records-and-unions.md) |
| `functions` | [functions and calls](functions.md) |
| `errors` | [results and options](results-and-options.md) |
| `text` | [text and strings](text.md) |
| `bytes` | [managed byte strings](bytes.md) |
| `io` | [printing, files and command-line authority](io.md) |
| `effects` | [capabilities and effects](effects.md) |
| `contracts` | [contracts: requires, ensures and invariants](contracts.md) |
| `modules` | [modules, imports and exports](modules.md) |
| `memory` | [managed collections](managed-memory.md) |
| `sets` | [sets and hashable keys](sets.md) |
| `stdlib` | [the standard library](standard-library.md) |
| `tests` | [guest tests](tooling/guest-tests.md) |
| `build` | [native builds](tooling/native-build.md) |
| `navigation` | [source navigation](tooling/navigation.md) |
| `context` | [focused declaration context](tooling/agent-context.md) |

## Writing programs

- The language: [primer](primer.md), [language guide](python-syntax.md),
  [statements](statements.md), [functions](functions.md),
  [records, unions and enums](records-and-unions.md), [tuples](tuples.md), [sets](sets.md),
  [lambdas](lambdas.md), [matching a variant](match-expressions.md),
  [structured loop exits](structured-loop-exits.md),
  [integer ranges](range-iteration.md), [generics](generics.md) and
  [generic call inference](generic-inference.md),
  [constant length parameters](const-length-generics.md),
  [type aliases](type-aliases.md), [scalar domains](domains.md),
  [contracts](contracts.md),
  [value semantics](value-semantics.md),
  [module constants](module-constants.md) and
  [constant evaluation](source-evaluation.md).
- Values: [results and options](results-and-options.md), [text](text.md),
  [bytes](bytes.md), [integer operations](integer-operations.md),
  [floating point](floating-point.md), [typed JSON](typed-json.md).
- Memory: [managed collections](managed-memory.md) and [value semantics](value-semantics.md).
- The outside world: [I/O](io.md), [capabilities and effects](effects.md),
  [time and randomness](standard-time-random.md),
  [direct C imports](c-ffi.md).
- Larger programs: [modules](modules.md), [local packages](tooling/packages.md),
  [the standard library](standard-library.md), [typed holes](typed-holes.md),
  [checking independent faults](diagnostic-recovery.md).
- What exists today: [current language reference](current-language.md) and
  [the compiler-derived reference](reference.md) (`selka reference --query`).

## Building, testing and tools

- [Native builds](tooling/native-build.md): debug builds one LLVM unit per module,
  `--release` for the optimized whole-program build, the caches, `--report` and
  `--verify-cache`. [Performance](performance.md) says when and how to measure.
- [Guest tests](tooling/guest-tests.md);
  [runtime budgets](tooling/runtime-budgets.md) (memory, steps, time);
  [ownership](tooling/ownership.md) (`--stats`).
- Working in a large project: [source navigation](tooling/navigation.md)
  (`index-project`, `tests-for`), [focused declaration context](tooling/agent-context.md)
  (`context --symbol` / `--at`), [agent-facing inspection](tooling/agent-tools.md)
  (`list-interfaces` and friends), [interface diffs](tooling/api-diff.md),
  [interface files](tooling/interface-files.md) (`selka api`),
  [linting](tooling/lint.md), [import policy](tooling/import-policy.md).
- Compiler behaviour: [caches](tooling/caches.md), [phase timings](tooling/timings.md),
  [work and reuse reports](tooling/work-report.md), [module interfaces](tooling/module-interfaces.md).
- C interop: [direct C imports](c-ffi.md) (`extern func` with `--link FILE.c`).
  Host functions, `selka invoke` and the host applications were retired; their
  pages are in [`legacy/`](legacy/README.md).

## Compiler records

Pages about developing the compiler, kept here for its maintainers. They are
dated records and plans, not descriptions of the language you can rely on:

The [repository contents](publication.md) explain which experiment data is
retained. [Historical audits](audits/README.md) keep their reports and figures;
large raw runs remain in the local development archive.

- Plans and status (written before the new compiler core replaced the QBE back
  end in 2026-10; [`design/`](design/) holds the new core's design records):
  [design and implementation plan](plan.md),
  [progress](progress.md), [performance roadmap](performance-roadmap.md),
  [the velocity loop](velocity-loop.md), [bootstrap subset](bootstrap-v1.md).
- Proposals and handoffs: [concurrency proposal](concurrency-proposal.md),
  [named constraints](named-constraints-proposal.md) (with its
  [implementation plan](named-constraints-implementation.md) and
  [handoff](named-constraints-handoff.md)), [MVP audit](mvp-audit.md).
- Working on the compiler: [where tests live](tooling/test-layout.md),
  [documentation gates](tooling/documentation-gate.md),
  [frontend redesign and migration decisions](audits/frontend-syntax-redesign-2026-10-09.md).
- Directories: [`audits/`](audits/) (dated audits and lane reports),
  [`experiments/`](experiments/) (design records and measurements),
  [`adr/`](adr/) (architecture decisions), [`legacy/`](legacy/) (removed
  features; its examples are not run) and `fixtures/` (files doctest examples
  read).
