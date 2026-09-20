# sexpr-port — the EDA S-expression reader, ported to mylang

`/home/epentland/ai/canopy/eda` (the sibling Zig EDA project) parses its design
files with a hand-written S-expression reader under `eda/src/sexpr/`. This
directory is a from-scratch **mylang port** of that reader plus the measurement
harness used to compare the two: line counts, declaration counts, an independent
differential check, and the charts in `evidence/`.

The port exists to answer "what does this program look like in mylang, and how
much source does it take?" — not to replace the Zig reader.

## Layout

```
sexpr/ast.my         Span + recursive Node union + typed accessors   (port of ast.zig)
sexpr/tokenizer.my   bytes -> tokens; SI scales, mm/mil, %, errors   (port of tokenizer.zig)
sexpr/parser.my      tokens -> AST; depth cap, located diagnostics   (port of parser.zig)
sexpr/printer.my     AST -> canonical text; full 72-column layout (printer.zig)
tests/*_test.my      guest tests, discovered by `mylang test`
main.my              CLI: parse a file and print statistics or the rendering
metrics.py           counts lines/declarations for both implementations
reference_parse.py   an independent Python reader for differential checking
compare.py           diffs the mylang CLI against reference_parse.py
charts.py            renders the PNG charts from metrics.json
run_all.sh           runs everything above in order
evidence/            metrics.json, summary.md, comparison charts
```

## Reproduce

```sh
bash experiments/sexpr-port/run_all.sh
```

or piecewise, from the repository root:

```sh
./zig-out/bin/mylang test experiments/sexpr-port
./zig-out/bin/mylang run experiments/sexpr-port/main.my -- <file.sexp>
./zig-out/bin/mylang run experiments/sexpr-port/main.my -- <file.sexp> --render
python3 experiments/sexpr-port/metrics.py
python3 experiments/sexpr-port/compare.py            # three in-repo fixtures
python3 experiments/sexpr-port/compare.py --large    # + ~185 kB sibling EDA files
/home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/sexpr-port/charts.py
```

## Results

All counts are physical source lines, measured by `metrics.py`
(`evidence/summary.md` and `metrics.json` have the full tables).

### Core reader — `ast` + `tokenizer` + `parser`

| measure | Zig | mylang | ratio |
| --- | ---: | ---: | ---: |
| lines | 1276 | 736 | **0.58x** |
| code lines | 918 | 470 | **0.51x** |
| characters | 52558 | 27156 | 0.52x |
| declarations (fn + type) | 57 | 56 | 0.98x |
| inline `test` cases | 30 | — | |

Per module the port is 0.97x (ast), 0.44x (tokenizer) and 0.64x (parser) of the
Zig line count.

### All four modules, including the printer

| measure | Zig | mylang | ratio |
| --- | ---: | ---: | ---: |
| lines | 1702 | 1013 | **0.60x** |
| code lines | 1197 | 611 | **0.51x** |
| declarations (fn + type) | 67 | 68 | 1.01x |
| printer only | 426 | 277 | 0.65x (full layout engine) |

### Tests

| suite | cases | source lines |
| --- | ---: | ---: |
| Zig inline `test` blocks | 37 | 558 |
| mylang guest tests (`tests/*.my`) | 79 | 844 |

### Why the port is shorter

The two implementations differ most in what the *language* makes explicit. On
non-test core lines, the Zig sources mention `allocator` 27 times, `errdefer`
twice and `catch` 8 times — every list build and node slice is arena-threaded
and freed by hand — while the mylang core has no allocator parameter at all: it
spells `Result[...]` 10 times, `match` 17 times and `case Err` 3 times. The
`Node` union, `Span`, the SI scale table and every diagnostic string are the
same; the savings come from GC-managed values, `Result` plus `?` instead of
error-union plumbing, and managed `str` tokens replacing Zig's explicit
`[]const u8` slices threaded through a cursor.

The printer is a full port rather than a subset — 274 lines against Zig's 426,
byte-identical on all 17 goldens — and the AST now uses mylang's multi-field
union cases to mirror Zig's `Node { tag, span, literal }` directly:

```mylang
union Node:
    form(items: list[Node], span: Span),
    atom(text: str, span: Span),
    decimal(value: float, span: Span, literal: Option[str] = None),
    ...
```

Every case carries its first token's span, and a suffixed number keeps its
source spelling in `decimal.literal`, so `100nF`/`220k`/`5%` round-trip. Zig's
project-walk and fuzzer printer tests have no guest analogue; their property is
covered by render/parse idempotence and the 17 goldens. Meanwhile the mylang
test suites are larger than Zig's 558 inline test lines, so total project size
is closer than the module-only table suggests.

### Verification

```
./zig-out/bin/mylang test experiments/sexpr-port        # 79 passed, 0 failed, 7 programs
python3 experiments/sexpr-port/compare.py               # 4 fixtures agree with the reference
python3 experiments/sexpr-port/compare.py --large       # + 3 real ~185 kB EDA files
python3 experiments/sexpr-port/golden_compare.py        # 17/17 byte-identical to the Zig printer
```

`golden_compare.py` is the strongest check: `golden/harness.zig` compiles the
*real* `eda/src/sexpr/printer.zig` (via a symlinked `src`, the sibling repo is
never written) and records its exact bytes for the layout corpus, the in-repo
fixtures and two ~185 kB EDA files; the script then diffs the mylang CLI's
`--render` output byte-for-byte. All 17 goldens pass, including a numeric-formatting stress fixture and the 72-column
boundary cases, so the layout engine — not just the tree — matches.

`compare.py` parses each fixture twice — once with the mylang port and once with
`reference_parse.py`, an independent Python reader in this directory — and
compares eight node statistics plus a numeric value sum, so SI scaling and
mm/mil conversion are checked, not just tree shape. All seven fixtures agree
including `value_sum`:

| fixture | nodes | notes |
| --- | ---: | --- |
| `fixtures/units.sexp` | 66 | bare `mm`/`mil`, `220k`, `100nF`, `3.3V`, `10%`, vendor atoms |
| `schematic/fixtures/spi.sexp` | 23 | in-repo |
| `schematic/fixtures/lmx2595rhar.sexp` | 167 | in-repo |
| `schematic/fixtures/straps-synth-lmx2595.sexp` | 1031 | in-repo, 6 deep |
| `poe-pd-flyback-tps23757.sexp` | 3021 | sibling EDA repo, 185 kB |
| `remora-rf.sexp` | 3219 | sibling EDA repo |
| `barracuda.sexp` | 4725 | sibling EDA repo |

(The real EDA files quote their dimensions, so `units.sexp` is what exercises
bare `mm`/`mil` end to end; the parser unit tests cover the rest.)

## Speed

`bench/` measures compile and execution speed against a minimal standalone Zig
project that compiles only the sexpr closure. Full tables and caveats:
[`bench/RESULTS.md`](bench/RESULTS.md); raw samples in `evidence/bench*.json`.

Both binaries are verified to produce the identical rendering and census on the
927 KB benchmark input, so the execution numbers compare the same work.

| at ReleaseFast | Zig | mylang | winner |
| --- | ---: | ---: | --- |
| compile, cold project (warm toolchain) | 12.6 s | **2.22 s** | mylang 5.7× |
| compile, warm (nothing changed) | **0.016 s** | 0.081 s | Zig 5× |
| compile, after one-constant tweak | 11.8 s | **0.108 s** | mylang 109× |
| run, census (927 KB) | **3.80 ms** | 274.6 ms | Zig 72× |
| run, render (927 KB) | **5.60 ms** | 314.7 ms | Zig 56× |

A deeper **execution-gap audit** (phase decomposition and per-operation micro-drivers) is in [`../../sexpr-audit/RESULTS.md`](../../sexpr-audit/RESULTS.md): tokenizing is 92% of mylang's run and 193x slower than Zig's, and the generated code costs tens of nanoseconds per trivial operation.

mylang's cold build is codegen-bound (0.04 s frontend, 2.13 s QBE+assemble+link)
while its warm and tweak builds are near-instant cache hits. Its guest mode has
no `ReleaseSafe`, but the compiler itself can be built in either mode; doing so
cuts the guest warm rebuild from 0.72 s to 0.081 s
(`bench/bench_compiler_modes.py`).

## Fidelity and scope

The port is behaviour-faithful for the tokenizer, parser and printer; all 17
Zig goldens are byte-identical. Differences that matter when reading the numbers:

- `decimal.literal` is `None` rather than an absent field: Zig's `Node.literal`
  is optional on every node, the port's is optional only on the case that can
  carry one (`literal: Option[str] = None`). Same information, narrower type.
- A `measure` node keeps only the normalised millimetre value. Zig prints `mm`
  for it and so does the port, so `10mil` renders as `0.254mm` in both; the
  original `mil` spelling is not reconstructed (Zig does not either).
- `LexError` carries `message/offset/line` (no column), matching the frozen
  interface; Zig's `Tokenizer.error_span` also tracks a column.
- Source slices are decoded to `str` only where the AST exposes text
  (`value_text`, `as_text`); a non-UTF-8 token becomes `""` there rather than a
  preserved byte slice. Numeric leaves are parsed from their octets in place
  (`bytes.parse_int`/`parse_float`) and the printer's width measurement counts
  scalars from the range, so neither decodes a spelling. All fixtures are ASCII.
- The 10 000-deep nesting cap is real and trips at exactly depth 10 000
  (`parse error: s-expression nesting is too deep at 1:10001`), but the mylang
  runtime's own call-depth budget (1 024 frames by default) is exhausted first,
  so under default limits a pathologically deep file traps with `R_FRAME_LIMIT`
  before the parser can report its located error. Passing
  `--max-frames=40000` exposes the parser's cap; a Zig binary has the same
  interaction with its native stack but a much larger budget.

Everything else is a direct port, including the operator/atom edge cases that
make vendor KiCad exports tokenize (`PMA3-24323LN+.stp`, `74AHCT1G125GF,132.stp`,
`P$1`), the `m`-only-with-a-unit-letter SI rule, `12.5abc` falling back to an
atom, the 10 000-deep nesting cap, and the located diagnostics.

## Fairness of the line counts

The Zig sources carry `///` doc comments on every `pub` declaration (their
Guardian gate requires it) and inline `test "..."` blocks; the mylang port keeps
its tests in separate `tests/*.my` files. `metrics.py` therefore reports code,
comment and blank lines separately, and reports the mylang guest-test lines as
their own group, so the comparison is not an artefact of where tests live.
`evidence/summary.md` has the full table.
