# Compiler-derived agent reference

> The Python reference generator was dropped in the Zig-native tooling fold. This
> page is retained as a historical design record; use `selka list-declarations`,
> `selka list-interfaces`, and `selka schema-project` instead.

`scripts/reference.py` writes a small searchable overview and a separate full API
reference from the selected executable. Agents continue to read, search, and edit
ordinary files. Nothing injects reference text into later tool responses.

From the repository root:

```sh
python3 scripts/reference.py --compiler zig-out/bin/selka --output /tmp/selka-reference
cat /tmp/selka-reference/reference.md
rg 'math::|sort::' /tmp/selka-reference/api.md
python3 scripts/reference.py --compiler zig-out/bin/selka --output /tmp/selka-reference --check
```

Successful generation and freshness checking each print three lines: the overview
path, API path, and compiler SHA256. Full reports stay on disk:

- `reference.md`: reported features, exclusions, limits, and API coverage counts.
- `api.md`: concrete signatures, parameter modes, effects, type shapes, and generic
  template contracts. This is labeled schema notation, not source syntax.
- `features.json`: complete `--features` response.
- `schema.json`: complete `schema-project --schema-report` response, including
  compiler identity, source hashes, schema hash, and template provenance.
- `manifest.json`: artifact hashes and the input selection for freshness checks.

The default selection imports every embedded standard module -- `base64`, `hex`,
`json`, `math`, `path`, `pool`, `random`, `sort`, `strings` and `time` -- into a
temporary checked project.
These modules are embedded in the executable; checkout stdlib source files are
never used to infer their APIs. Imported dependencies appear too. This is a small
onboarding selection, not an exhaustive inventory of language builtins or all
standard modules. The full feature report identifies additional reported features.

Choose another set with repeated `--module` arguments:

```sh
python3 scripts/reference.py --compiler zig-out/bin/selka --module time --module random --output /tmp/clock-reference
```

Use `--entry` instead to document a project's reachable public API:

```sh
python3 scripts/reference.py --compiler zig-out/bin/selka --entry examples/corpus/invoice/main.selka --output /tmp/project-reference
```

Project entries retain their absolute location in the manifest. Modules needing
project-supplied dependencies, such as a host `io` module, should be
referenced through an actual project entry. The tool does not invent host stubs or
silently omit imports that fail checking. Invalid module selections or compiler
errors fail generation before replacing artifacts.

`--check` uses the stored selection, verifies every artifact hash and the compiler
digest, then asks that executable for fresh reports and compares them with the
reference. It detects private source changes as well as public schema changes and
writes nothing. A changed executable, moved project, edited artifact, changed
renderer, or modified source requires regeneration. Each file is replaced
atomically, with the manifest last; an interrupted multi-file update is detected
by `--check`. The hashes detect drift, not malicious rewriting of both evidence
and manifest.

Schema output describes the compiler's checked public surface. Generic template
contracts retain their declared ceilings and requirements; inclusion does not
prove every possible specialization. This tool does not add language semantics,
run guest programs, copy an evolving guide into the reference, or claim a speed
improvement without measurements.

Targeted correctness checks (not development-speed evaluations):

```sh
python3 tests/reference_tool.py --compiler zig-out/bin/selka
```
