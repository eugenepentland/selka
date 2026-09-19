# sexpr-port golden harness — the real Zig printer as the oracle

`experiments/sexpr-port/sexpr/printer.my` is a mylang port of the 426-line Zig
S-expression printer in the sibling repo
`/home/epentland/ai/canopy/eda/src/sexpr/printer.zig`. The Zig printer is the
oracle: this directory captures its **exact stdout bytes** for a corpus of
inputs, and `experiments/sexpr-port/golden_compare.py` diffs the mylang
printer's stdout against those bytes.

The `eda` repo is **read-only** here. Nothing in this harness writes to it; the
Zig sources are reached through a symlink placed under `/tmp`.

## Layout

```
golden/harness.zig              root of the Zig reference program (copied to /tmp)
golden/generate_zig_goldens.sh  rebuilds /tmp + writes every golden + manifest.tsv
golden/manifest.tsv             name<TAB>input-path, generated; drives the comparison
golden/<name>.txt               exact Zig printer bytes (no trailing newline)
golden/README.md                this file
golden_compare.py               runs main.my --render and byte-diffs each golden
fixtures/layout/*.sexp          10 hand-written inputs stressing the 72-column layout
```

`golden/` holds both the generator's source and its evidence. The `.txt` goldens
are kept even when large (~140 kB and ~110 kB for the two real EDA boards): they
are the evidence, not fixtures to be regenerated on a whim.

## The verified recipe

Zig 0.17.0-dev, `zig` on `PATH` (`.zigversion` pins `0.17.0-dev.1683+5ceec001b`).
`eda/src/sexpr/printer.zig` imports `../infra/fs.zig`, which reads
`@import("root").process_io`; and Zig 0.17's `main` takes `std.process.Init`. So
the reference program is a root file that declares both and drives the printer:

```sh
mkdir -p /tmp/sexpr-golden
ln -s /home/epentland/ai/canopy/eda/src /tmp/sexpr-golden/src
cp experiments/sexpr-port/golden/harness.zig /tmp/sexpr-golden/
cd /tmp/sexpr-golden
zig run harness.zig -- /abs/path/to/input.sexp > /path/to/golden.txt
```

Two things are non-negotiable for this to compile and link:

* the root file must declare `pub var process_io: std.Io = .failing;` — see
  `harness.zig`, where it is `pub` precisely so `infra/fs.zig` can read it;
* `main` must be `pub fn main(init: std.process.Init) !void`, installing
  `init.io` into `process_io` before anything reads the filesystem.

`harness.zig` reads `argv[1]`, parses with `parser.parse(alloc, bytes)`, prints
with `printer.print(alloc, nodes)`, and writes the returned bytes verbatim to
stdout via `std.Io.File.stdout().writeStreamingAll(init.io, text)`. It appends
**no** trailing newline; `printer.print` only puts `'\n'` *between* top-level
forms.

## Regenerate the goldens

```sh
bash experiments/sexpr-port/golden/generate_zig_goldens.sh
```

The script rebuilds `/tmp/sexpr-golden` from scratch (symlink + harness copy),
compiles the harness once, then runs it over, in order: every
`fixtures/layout/*.sexp`, `fixtures/units.sexp`,
`experiments/schematic/fixtures/{spi,lmx2595rhar,straps-synth-lmx2595}.sexp`,
and two ~185 kB real EDA files
(`lib/modules/poe-pd-flyback-tps23757.sexp` and
`src/boards/remora-rf/remora-rf.sexp`). It rewrites `manifest.tsv` and one
`<name>.txt` per input.

Environment knobs: `EDA_ROOT` (default `/home/epentland/ai/canopy/eda`),
`SEXPR_GOLDEN_TMP` (default `/tmp/sexpr-golden`), and
`SEXPR_GOLDEN_SKIP_LARGE=1` to skip the two big boards. `--help` prints the
header.

## Compare the mylang port

From the repository root:

```sh
python3 experiments/sexpr-port/golden_compare.py            # all 17 goldens
python3 experiments/sexpr-port/golden_compare.py --filter one_over
python3 experiments/sexpr-port/golden_compare.py --update   # no-op reminder
```

For each manifest entry it runs

```sh
./zig-out/bin/mylang run experiments/sexpr-port/main.my -- <input> --render
```

captures stdout, and compares it byte-for-byte with the golden. On a mismatch it
prints the first differing line and column (1-based) with a few lines of unified
context, then a pass/fail summary; the exit status is non-zero if anything
differs.

**Trailing-newline contract.** `main.my` prints through `out.print`, which
appends exactly one `'\n'`; the Zig printer does not. `golden_compare.py`
therefore strips **exactly one** trailing newline from the captured mylang
stdout before diffing, and nothing else. Goldens are written with no trailing
newline for the same reason.

`--update` is accepted only so a caller used to test suites does not have to
special-case the flag: this script **never** writes goldens. Regeneration is
`generate_zig_goldens.sh`'s job.

## Input corpus

`fixtures/layout/` (10 files) isolates the `isShortList` / `estimateWidth`
72-column logic:

| file | what it stresses |
| --- | --- |
| `fits_exactly.sexp` | flat form exactly 72 columns — the last width that stays on one line |
| `one_over.sexp` | the same form at 73 columns — must break and indent |
| `deeply_nested.sexp` | nesting past `estimateWidth`'s depth-3 budget → `null` → multi-line |
| `long_atom.sexp` | an atom wider than 72, bare at top level and as a lone payload |
| `empty_lists.sexp` | `()` is special-cased before the width test |
| `string_escapes.sexp` | raw escaped strings; width counts the escaped spelling |
| `many_toplevel.sexp` | top-level forms joined by one `'\n'`, never indented |
| `single_element.sexp` | one-child forms; nesting alone can still force a break |
| `all_wide_children.sexp` | every child wide → outer breaks though each child fits |
| `mixed_widths.sexp` | small atoms + inline sublist + long string + deep sublist |

## Current state (2026-09-18)

The mylang printer under `sexpr/printer.my` is the full 72-column layout engine,
and the port's `spelled` case carries a suffixed literal's source spelling, so
every golden matches byte for byte:

```
summary: 17/17 passed, 0 failed
```

The corpus covers the layout boundary (a form at exactly 72 columns prints on
one line, one column wider breaks), the depth-3 measure cutoff, indentation,
verbatim strings, `mm`/`mil` measures, SI source spellings and a numeric
formatting stress fixture, plus the four in-repo schematic fixtures and two
~185 kB real EDA files (the last two are skipped when
`SEXPR_GOLDEN_SKIP_LARGE=1`).
