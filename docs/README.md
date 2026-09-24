# mylang documentation

New to the language? Read [the one-page primer](primer.md) first: it is
everything a Python programmer needs for a first program, and every example on
it is run by `mylang doctest`. After that, the pages below are the reference,
grouped by what you are doing. The pages under [Compiler records](#compiler-records)
are about developing the compiler itself; nobody writing mylang programs needs
them.

## The guides built into the compiler

The user guides ship inside the `mylang` executable, so they are available in a
project that has no copy of this directory:

```console
$ mylang docs                 # list the topics
$ mylang docs primer          # print the primer (Markdown) to stdout
$ mylang docs errors          # Result, Option and `?`
$ mylang reference --query E_MODULE_NAME   # one feature or error code, from the same executable
```

| Topic | Page |
| --- | --- |
| `primer` | [mylang in one page](primer.md) |
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
| `arenas` | [managed arenas](arenas.md) |
| `stdlib` | [the standard library](standard-library.md) |
| `tests` | [guest tests](tooling/guest-tests.md) |
| `build` | [native builds](tooling/native-build.md) |
| `navigation` | [source navigation](tooling/navigation.md) |
| `context` | [focused declaration context](tooling/agent-context.md) |

## Writing programs

- The language: [primer](primer.md), [language guide](python-syntax.md),
  [statements](statements.md), [functions](functions.md),
  [records, unions and enums](records-and-unions.md), [tuples](tuples.md),
  [lambdas](lambdas.md), [matching a variant](match-expressions.md),
  [structured loop exits](structured-loop-exits.md),
  [integer ranges](range-iteration.md), [generics](generics.md) and
  [generic call inference](generic-inference.md),
  [constant length parameters](const-length-generics.md),
  [type aliases](type-aliases.md), [scalar domains](domains.md),
  [contracts](contracts.md),
  [module constants](module-constants.md) and
  [constant evaluation](source-evaluation.md).
- Values: [results and options](results-and-options.md), [text](text.md),
  [bytes](bytes.md), [integer operations](integer-operations.md),
  [floating point](floating-point.md), [typed JSON](typed-json.md).
- Memory: [managed collections](managed-memory.md), [arenas](arenas.md).
- The outside world: [I/O](io.md), [capabilities and effects](effects.md),
  [bulk byte I/O](byte-io-bulk.md), [time and randomness](standard-time-random.md),
  [direct C imports](c-ffi.md).
- Larger programs: [modules](modules.md), [local packages](tooling/packages.md),
  [the standard library](standard-library.md), [typed holes](typed-holes.md),
  [checking independent faults](diagnostic-recovery.md).
- What exists today: [current language reference](current-language.md) and
  [the compiler-derived reference](reference.md) (`mylang reference --query`).

## Building, testing and tools

- [Native builds](tooling/native-build.md): QBE by default, `--release` for the
  optimized LLVM build, caches and `--report`. [Performance](performance.md)
  says when and how to measure.
- [Guest tests](tooling/guest-tests.md) and
  [benchmarks with reviewed baselines](tooling/benchmark-plan.md);
  [runtime budgets](tooling/runtime-budgets.md) (memory, steps, time).
- Working in a large project: [source navigation](tooling/navigation.md)
  (`index-project`, `tests-for`), [focused declaration context](tooling/agent-context.md)
  (`context --symbol` / `--at`), [agent-facing inspection](tooling/agent-tools.md)
  (`list-interfaces` and friends), [interface diffs](tooling/api-diff.md),
  [linting](tooling/lint.md), [import policy](tooling/import-policy.md).
- Compiler behaviour: [caches](tooling/caches.md), [phase timings](tooling/timings.md),
  [work and reuse reports](tooling/work-report.md).
- Embedding and hosts: [calling one export](tooling/invoke.md),
  [invocation](tooling/invocation.md), [packed host calls](tooling/packed-host-calls.md),
  [the byte runner](tooling/byte-runner.md).

## Compiler records

Pages about developing the compiler, kept here for its maintainers. They are
dated records and plans, not descriptions of the language you can rely on:

- Plans and status: [design and implementation plan](plan.md),
  [progress](progress.md), [performance roadmap](performance-roadmap.md),
  [the velocity loop](velocity-loop.md), [bootstrap subset](bootstrap-v1.md).
- Proposals and handoffs: [concurrency proposal](concurrency-proposal.md),
  [named constraints](named-constraints-proposal.md) (with its
  [implementation plan](named-constraints-implementation.md) and
  [handoff](named-constraints-handoff.md)), [MVP audit](mvp-audit.md).
- Working on the compiler: [where tests live](tooling/test-layout.md),
  [documentation gates](tooling/documentation-gate.md).
- Directories: [`audits/`](audits/) (dated audits and lane reports),
  [`experiments/`](experiments/) (design records and measurements),
  [`adr/`](adr/) (architecture decisions), [`legacy/`](legacy/) (removed
  features; its examples are not run) and `fixtures/` (files doctest examples
  read).
