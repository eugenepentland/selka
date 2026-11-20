# Documentation gates

Two checks keep this documentation honest, and the default `zig build test` step
depends on both. The first runs every example, so a documented program cannot
drift away from the language it describes. The second requires the examples to
exist in the first place, so a feature cannot be implemented and then quietly go
undocumented.

## Executable examples

`selka doctest` extracts every fenced block of `README.md`, `SPEC.md`
and `docs/**/*.md`, and runs, type-checks or explicitly skips the ones tagged
`selka` or `my`. Leading `# doc:` directives pin the expected stdout, the
expected diagnostic code, or a stated reason for skipping; a block tagged as
prose that still looks like guest source is reported as mis-tagged rather than
silently ignored. `docs/legacy/` is excluded, because its subject was removed
from the language. [Executable documentation
examples](../experiments/doc-examples.md) is the directive grammar and the
current inventory.

```sh
zig build test-docs
zig-out/bin/selka doctest . --filter 'docs/value-semantics.md' --verbose
zig-out/bin/selka doctest . --jobs 4
```

Examples run on a bounded pool of workers, sized from the machine's cores capped
by how many 512 MiB per-test ceilings its free memory holds, unless `--jobs N`
or `SELKA_JOBS` says otherwise; the report is assembled after every unit finishes,
so it reads the same as a one-at-a-time run.

## Feature and export coverage

`selka doc-coverage` reads `src/features.json` and resolves the `doc` pointer of
every implemented feature against the checkout. It fails when the page does not
exist, when no heading carries the pointer's anchor, or when the section under
that heading has no example: a `language` feature needs a fenced `selka` block
the example runner actually executes, and a `tooling` feature needs a command or
transcript block. It then reads every `src/stdlib/*.selka` module and requires each
`export` to be named in that module's section of [the standard library
guide](../standard-library.md), to have a `#` comment directly above its
definition, and each module section to carry a runnable example.

```sh
zig build test-doc-coverage
zig-out/bin/selka doc-coverage .
```

The report prints how many features each page carries, then the standard-module
and export totals, then one line per failure and a failure count. It exits 1
when anything is undocumented, so adding a feature slug without writing its
section breaks the build:

```text
  ! example-feature: doc page 'docs/example-feature.md' does not exist
  ! standard-hex: 'docs/standard-library.md' has no heading with anchor 'hex'
doc-coverage: 2 failures
```

A heading's anchor is its text lowercased with punctuation dropped, spaces
turned into hyphens, and hyphens and underscores kept, which is how GitHub links
to it. A section runs to the next heading of the same or higher level, and a
heading inside a fenced block is not a heading. The rules themselves live in
`src/doc_coverage.zig` with unit tests over small in-memory documents, so the
command and its tests cannot disagree.
