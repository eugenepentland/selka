# Declaration store format

`scripts/store.py` keeps a project's `.my` source as declarations in one SQLite
file and renders that file back into a complete project directory. It is the
importer and renderer of the [declaration store](declaration-store.md)
experiment; the session server is a later phase.

```sh
python3 scripts/store.py import path/to/project --db store.sqlite --branch base --compiler zig-out/bin/mylang
python3 scripts/store.py render --db store.sqlite --branch base --output rendered
python3 scripts/store.py receipt --db store.sqlite
```

The module is importable: `Store` wraps the database, `Compiler` wraps the
frozen `fmt-module`, `list-declarations`, `fmt-project` and `index-project`
commands. Only the standard library is used. Every failure raises rather than
degrading: the CLI prints one JSON object and exits 2.

## Schema

Schema version `declaration-store-v1`, recorded in `meta` with the SHA-256 and
path of the compiler that performed the import.

```text
meta          key PK, value                      (schema_version, compiler_sha256, compiler_path, created_utc)
declarations  hash PK, kind, module, name, exported, canonical_source BLOB,
              signature, effects_json, doc, source_sha256
names         branch, module, name PK, position, hash                (the current tree of a branch)
module_meta   branch, module PK, header_json                         (path, header, imports, exports, trivia)
edges         branch, from_hash, to_id, kind PK                      (index-project references, optional)
assets        name PK, kind, bytes BLOB, sha256                      (every file that is not a module)
receipts      id PK, parent_id, branch, utc, batch_json, delta_json, snapshot_sha256, sha256
```

A branch is the `names` and `module_meta` rows carrying one label. Assets are
shared by every branch of a store; importing a second tree that reuses an asset
name with different bytes is refused.

## Canonical source

A module is canonicalized by `fmt-module` and then listed with
`list-declarations` on the formatted bytes. A declaration's `canonical_source`
is `formatted[comment_start:end]`, so it carries its attached comments.

Canonical module text contains no blank lines: the formatter normalizes
whitespace, so every gap between two listed ranges is exactly one LF. Comment
handling therefore has no ambiguity left to resolve. A standalone comment that
precedes a declaration attaches to it, whatever blank lines separated them in
the original file, because the formatter has already removed them. The only
comments that do not attach to a declaration are those before the module
header; they are stored verbatim in `module_meta` as `prelude`, and comments
after the last declaration are stored as `trailing`. A comment anywhere else
outside a declaration — between two imports, say — cannot be placed by the
renderer and the import fails closed. No corpus module has one.

`signature` is the declaration text from its first token to the body brace or
terminating semicolon, whitespace collapsed, bounded to 512 bytes.
`effects_json` is the names inside `effects(...)` of that signature, and `doc`
is the attached comment block with markers stripped. All three are spellings
taken from the text, not checked facts.

## Hashing

```text
hash = SHA-256("declaration-store-declaration-v1\n" + module + "\n" + kind + "\n"
               + name + "\n" + ("1"|"0" exported) + "\n" + canonical_source)
```

The digest frames the declaration's identity around its canonical bytes.
Framing is required, not decorative: identical sources recur across modules of
one tree — `fn failure() -> r::Error` appears in `main.my` and `model.my` of
several trial baselines — and the `declarations` row carries `module`, `name`
and `exported`, so a digest over the bytes alone would give one row two
identities. `source_sha256`, the plain SHA-256 of `canonical_source`, is kept
beside it for callers that want pure content identity.

Receipts chain in the study-journal style. Each receipt's `sha256` covers its
parent's `sha256`, the branch, the UTC time, the batch, the delta and
`snapshot_sha256`, which digests every name, position, declaration hash, module
header and asset digest of the branch. `receipt` recomputes the whole chain and
exits 2 if any link is broken.

## Import

`import DIRECTORY --db PATH --branch NAME` walks the directory, refusing
symbolic-link directories, more than 5,000 files, files above 8 MiB or 64 MiB in
total, and nesting deeper than 32.

A `.my` file is a module of the tree when every segment of its relative path is
a valid module identifier and its declared module name equals the dotted path —
the compiler's lexical import layout. Everything else becomes an asset:
`.json`, `.md`, `.txt`, `.c`, `.py` and `.stdout` files by kind, other files as
`binary`, and a `.my` file that is not a module of this tree — a nested project
such as `probes/buffer/main.my`, or a file the parser rejects — verbatim as
`foreign_module`. Assets are therefore every file that is not decomposed into
declarations, which is what makes a rendered tree a drop-in, and it is wider
than the plan's "`.trial-public` and public case files".

`export NAME;` directives set the `exported` flag and their source order is kept
in `module_meta`. A root module is marked as an entry when `fmt-project --check`
could load its graph on the original tree, whether or not that tree was
canonical; the renderer re-checks exactly those entries.

Edges come from `index-project` on the entry when the project checks, keyed by
the store hash of the source declaration and the qualified id of the target;
local references are dropped. They are an optional convenience and an import
never fails because the index does not build.

An existing database is refused unless the branch is new; the import then adds
that branch to the same store. Every import commits a receipt.

## Import derivation

A qualified reference is `alias::name`. The store finds them with a token scan
that mirrors the compiler lexer — whitespace, `//` comments and quoted byte
literals with backslash escapes are skipped — and then takes every identifier
followed by `::` and an identifier, excluding `name::<T>` turbofish and `.name`
member positions. On the 394 corpus modules the scan resolves every
qualification it finds to a declared import, so it is exact for this corpus, not
merely conservative. `index-project` edges are stored when available but are not
used to derive imports, because unreachable and unchecked modules must render
too.

The rendered import block is the module names those aliases resolve to, sorted
by module name, with the declared alias preserved and `as` omitted when the
alias equals the last segment. An alias with no declared import is taken to name
its own module, which is the `import foo;` default-alias case. A declared import
that no declaration references is dropped, as the plan specifies. Seventeen
corpus modules have such an import; dropping one leaves the file in the tree but
outside the reachable graph, so `fmt-project` and `check-project` see fewer
modules. The round-trip suite compares both verdicts and diagnostic sets, and
they agree on every corpus project.

## Render

`render --db PATH --branch NAME --output DIRECTORY` refuses a non-empty output
directory and writes each module as

```text
prelude comments
module NAME;
imports, derived and sorted
export NAME;  for every exported declaration
declarations in position order, each with its attached comments
trailing comments
```

with exactly one LF between blocks and a final LF. Exports keep the source order
recorded at import; declarations exported later append to that list. Assets are
written back at their original relative paths, `.trial-public` included, so the
tree is a file-for-file drop-in.

Output is verified before the command succeeds: `fmt-module --check` on every
rendered module and `fmt-project --check` on every recorded entry. Any
difference is a hard failure and the directory is left for inspection.

## API

`Store` exposes what the session server needs: `declaration(branch, "module::name")`,
`list_branch`, `module_meta`, `assets`, `create_branch(source, target)`,
`replace(branch, id, source, if_match)`, `add(branch, module, source, after=)`,
`remove(branch, id, if_match)`, `commit(branch, batch, delta)`, `head`,
`verify_chain` and `render_branch`. `replace` and `remove` compare the caller's
`if_match` against the branch head and raise without touching the branch when it
differs. `replace` keeps the declaration's name and exported flag; renaming is
an add and a remove. A source that is not exactly one top-level declaration is
rejected.

## Round-trip guarantee

For an unedited import, each rendered module equals the `fmt-module` output of
the original module, except for the import block. Three levels are reported:

- `exact` — rendered bytes equal the formatted original.
- `imports-normalized` — equal after replacing only the original's import
  statements with the derived block.
- `fully-normalized` — equal only after re-rendering the original's own listing,
  which additionally moves export directives.

`tests/store_roundtrip.py --compiler zig-out/bin/mylang` runs every
`my-baseline` directory and the practice starter of
`development-velocity-20260908/development-001`, the development-velocity
runtime and starters, and every project under `examples/` and `experiments/`
with a module-header entry. Per project it asserts the byte comparison above,
that re-importing the rendered tree yields identical declaration names,
positions and hashes and identical asset digests, that the rendered tree has the
same file set as the original, that `check-project --diagnostics=json` gives the
same exit status and the same set of code and message pairs, and that
declaration, comment-line and asset counts are unchanged.

130 projects pass. 85 are byte-exact, 45 need import normalization, none needs
export normalization. `tests/store_api.py --compiler zig-out/bin/mylang` covers
the API contracts above. Neither is wired into `zig build`.

## Limits

- Diagnostic **locations** are not compared, only codes and messages. Dropping
  an unused import and reordering imports move later bytes.
- Import order is not preserved. A tree whose imports are not already sorted
  renders with a different import block; the declared order stays in
  `module_meta` for a reader who wants it.
- An unused declared import is dropped, which can remove a module from the
  reachable graph. The file remains in the rendered tree.
- A `.my` file that is not a lexical module of the tree round-trips as bytes,
  not as declarations. Nested projects under a project root are the case that
  occurs.
- Hashing is over source text. A caller's identity does not survive a callee
  rename; reference hashing in the Unison style is out of scope.
- The store is trusted local tooling. It bounds its inputs and refuses symbolic
  links, but it is not a hostile-filesystem sandbox.
