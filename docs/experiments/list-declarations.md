# Declaration listing

`selka list-declarations <file.selka>` prints one `declarations-v1` JSON document
on stdout for a single module or single-file program. The command is read-only
and parse-only: it loads no imports, resolves no names, runs no checking and
executes nothing.

```sh
zig-out/bin/selka list-declarations examples/modules/main.selka
```

```json
{"version":"declarations-v1","module":"main","header":{"start":0,"end":12},
 "imports":[{"name":"shared.units","alias":null,"bytes":{"start":13,"end":33}}],
 "exports":[{"name":"Measurement","bytes":{"start":34,"end":53}}],
 "declarations":[{"kind":"struct","name":"Measurement","exported":true,
                  "bytes":{"start":54,"end":106},"comment_start":54}]}
```

## Contract

- `module` is the declared module name, or `null` for a single-file program;
  `header` is the byte range of the `module NAME;` statement, or `null`.
- `imports` retains the imported module name, the explicit `as` alias or `null`,
  and the byte range of the import statement.
- `exports` retains each `export NAME;` directive in source order with its byte
  range. A directive sets `exported` on the declaration it names.
- `declarations` is ordered by `bytes.start`. `kind` is one of the stable
  lowercase names `alias`, `const`, `struct`, `enum`, `union`, `result`,
  `domain`, `buffer`, `pool`, `resource`, `fn`, `host_fn` — exactly the
  top-level constructs the parser accepts. `host_fn` is the `host fn` external
  declaration form.
- Every range is zero-based and half-open over the original file bytes. A
  declaration runs from its first token through its terminating `;` or `}`;
  `comment_start` is the start of the contiguous leading `//` lines with no
  blank line before the declaration, and equals `bytes.start` when there are
  none.
- Ranges are disjoint and ordered. The module header, imports, export
  directives and comment-and-declaration ranges account for every byte of the
  file except whitespace and line comments between them.
- Success exits 0. Syntax errors, unknown exports and duplicate exports print
  ordinary located diagnostics (text, or `--diagnostics=json`) and exit 1.
  Usage and I/O failures exit 2. Output has no trailing newline.

## What it does not guarantee

- No checking. A module with type, ownership, effect or export-visibility
  errors still lists; a listed declaration is not a valid one, and a listed
  name is not a resolved symbol. Use `check-project` or `index-project` for
  checked facts.
- Domain member functions, codec entries and pool handle types are not separate
  entries; they are inside their declaration's byte range.
- Kind names are stable, but a future top-level construct adds a new kind.
- Duplicate declaration names are a checking error; if one is exported, the
  first declaration with that name carries the flag.
- Byte ranges follow the file's current bytes, not canonical formatting. Run
  `fmt-module` first when ranges must be stable across formatting.

## Acceptance

`src/declarations_test.zig` covers every kind, comment attachment, export
flags, unresolved and duplicate exports, single-file listings and allocation
failures. `test/integration.zig` checks the CLI contract and the byte
accounting invariant. `tests/list_declarations.py` runs the command over every
`.selka` file under `examples/` and `experiments/`, checks the same invariant, and
compares listed names with `index-project` symbols for representative projects.

This command exists for the [declaration store](declaration-store.md)
experiment's importer. It is tooling around the existing parser and adds no
language behavior.
