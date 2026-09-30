# Random-edit differential tester for module-by-module builds

`edit_fuzz.py` applies a seeded sequence of small source-level edits to a copy of a
mylang project and, after every edit, builds the program twice:

1. incremental: `mylang build main.my --project -o inc --cache-dir=<persistent> --report`
   (module-by-module, early cutoff, symbol-level cutoff);
2. whole: `mylang build main.my --project --whole-program -o whole` in a fresh cache.

Both must succeed with **byte-identical executables**, or both must fail. A missed
invalidation links stale objects, so any other outcome is a finding. It generalizes the
fixed 22-step oracle in `../symbol-invalidation-20260930/oracle.py`.

```
edit_fuzz.py --compiler PATH --work DIR --seed N --steps K
             [--project-kind lox|synthetic] [--source DIR]
             [--gc-runtime] [--json OUT] [--keep-going] [--exclude-kinds K1,K2] [--edits-per-step N]
edit_fuzz.py --compiler PATH --work DIR --replay   REPRO_DIR
edit_fuzz.py --compiler PATH --work DIR --minimize REPRO_DIR
aggregate.py RESULT.json... > tables.md
```

- `--project-kind lox` (default) copies `--source` (default: the Lox port, 18 modules) minus
  its `.mylang-cache`. `synthetic` generates 6-10 modules (plus `main`) in a chain, diamond or
  layered import graph from the seed: enums, unions, records, public and private constants,
  small (inlinable) public functions, private helpers, allocating functions, `mut` parameters
  and functions that call across modules and take imported record and enum types.
- Deterministic for a given seed, project and compiler; the edit list does not depend on
  timing. One JSON line per step goes to stdout (seed, step, kind, file, desc, compiled,
  modules, seconds, matched, verdict, error excerpt); `--json` writes the summary
  (per-kind counts, `compiled` histogram, medians, every row).
- `--edits-per-step N` applies N edits, in possibly different modules, before each comparison
  (default 1); a row's kind is then `a+b`, and every kind in it shares that step's outcome.
- `--exclude-kinds` switches edit kinds off (for example to keep hunting past a known bug's
  trigger); `run_matrix.sh COMPILER OUTDIR [STEPS]` runs the standard matrix (Lox and
  synthetic, seeds 1-3, RC and `--gc-runtime`).
- Run heavy loops through the shared-box wrapper, for example
  `scripts/build-slot.sh build python3 edit_fuzz.py ...`.

## What one step does

`choose_edit` draws an edit kind from the `WEIGHTS` table at the top of the file. A kind is a
small function `(rng, project) -> (file, description) | None` that mutates a *clone* of the
project model and returns `None`, touching nothing, when it does not apply (then another kind
is drawn). Kinds parse mylang source with a few regular expressions: top-level declaration
extents by indentation, one-line `def` signatures, and a string/comment mask so literals are
found only in code.

| kind | edit |
|---|---|
| `int-literal`, `float-literal` | change a literal inside a function body |
| `insert-statement` | `_ = K`, or a local that is then read, before a random statement |
| `wrap-return` | `return E` becomes `tmp = E` / `return tmp` |
| `add-private-fn`, `add-public-fn` | new `(n: int) -> int` function at a random top-level position; may call an earlier added function (adding an import when the graph stays acyclic) |
| `remove-added`, `rename-added` | remove or rename a symbol this tool added (with its use statements or all uses) |
| `add-default-param` | defaulted trailing `fz_pN: int = 0` on a public function (read by `_ = fz_pN`) |
| `change-default` | change an integer default of any parameter |
| `helper-call` | a small public function's `return E` becomes `return fz_help_N(E)` with a new private helper |
| `const-value`, `add-const` | change a `const` (same type) / add a public or private const |
| `record-field-add`, `record-field-remove`, `change-field-default` | add a defaulted field to a record, remove one this tool added, change a field default |
| `start-alloc`, `stop-alloc` | a function builds and discards a small list/str (changes its RC facts) / undo |
| `use-added` | a function starts using a tool-added function or const, in another module when needed |
| `toggle-visibility` | `public` <-> `private` for a tool-added symbol |
| `comment`, `whitespace`, `move-function` | pure text edits; move a function within its file |
| `noop` | rebuild an unchanged tree (must recompile nothing) |

Function picks prefer small public functions 40% of the time (inline candidates). Only
modules reachable from `main.my` are edited. Names this tool introduces are `fz_*`/`FZ_*`.

## Verdicts

- `match`: both built, executables identical.
- `both-failed`: the edit does not compile; both builds agree. The edit is reverted and
  the incremental build of the reverted tree must reproduce the last good executable
  (`revert-check` row), so an error state cannot poison the cache silently.
- `binary-differs`, `incremental-failed`, `whole-failed`: **findings**. The run stops (unless
  `--keep-going`) and saves `repro-seedN-stepK-mismatch/` in `--work`: the original project,
  every applied and reverted edit as a unified diff (`edits/NNN-*.patch`), `timeline.json`,
  both executables and `replay.sh COMPILER WORKDIR [--gc-runtime]`, which replays the whole
  sequence and prints MATCH/MISMATCH after every state.
- `crash`: exit status other than 0/1, a timeout, `host failure` or `panic` text.
- Warnings take a build off the module path: an edit that leaves a warning anywhere (for
  example `W_UNUSED_BINDING`) makes `--report` omit `module_build` and the build runs on the
  whole-program path, which would make every later comparison vacuous. Such an edit is
  recorded (`engaged: false`, with the first diagnostic line) and reverted like a failed edit.
  Kinds are written to avoid warnings.

`--minimize REPRO_DIR` delta-debugs the edit list (a failed edit and its revert are one
unit) with an incremental build after every patch and the whole-program comparison at the end
only, and writes `minimal/` beside the work directory.

## Self-test

`sabotage.sh` wraps a real compiler (`REAL_MYLANG=...`) and corrupts the incremental
executable once a `start-alloc` edit exists. `edit_fuzz.py --compiler ./sabotage.sh ...` must
find a mismatch, save a reproducer that `replay.sh` reproduces, and `--minimize` shrinks
it to the one `start-alloc` patch. That is how the mismatch path was checked; the 4f97aa7a
compiler itself produced no mismatch (see `results-4f97aa7a.md`).
