# Netlisp schematic pilot

The language parses the supplied S-expression files, checks a bounded circuit
model, expands the SPI interface, lays out the component groups and writes SVG
while running on its bytecode VM. The Zig host supplies four typed byte-I/O
operations. It does not call Netlisp's parser, circuit evaluator or SVG renderer.

[Open the generated Straps LMX2595 schematic](straps-synth-lmx2595.svg)
([PNG preview](straps-synth-lmx2595.png)).
It contains 30 components, 95 connected pads, four deliberate no-connects and
nine interface signals. The functional hub view uses a dark theme, grouped IC
pins, passive symbols and orthogonal wires, following the local webpage renderer. Per-pin supply
branches display their base rail only when the named host pad and an existing
trunk net establish Netlisp's branch convention. Raw branch names remain in SVG
`data-net` attributes; `data-electrical-net` records the display connection.
Visible references use the webpage’s sequential aliases (`C1`, `R1`, and so on);
component metadata retains source names such as `C_VCCDIG`. Declared no-connects
and interface declarations remain in metadata without a separate legend panel.

## Reproduce

Use the pinned Zig 0.17.0 development toolchain and sibling Guardian checkout:

```sh
zig build -Doptimize=ReleaseFast
zig-out/bin/schematic-svg --project src/schematic/guest \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp > /tmp/straps-synth-lmx2595.svg
python3 tests/schematic_svg.py --runner zig-out/bin/schematic-svg
python3 tests/schematic_layout.py --runner zig-out/bin/schematic-svg
```

After the initial host build, edit any file in `src/schematic/guest/` and rerun
the executable directly. It reloads imports from disk without Zig or Guardian.
The project directory is required; missing/invalid source cannot fall back to an
embedded copy. [Incremental verification and HMR plan](../../docs/experiments/incremental-development.md).

For the live local design, substitute these three explicit input paths:

```sh
zig-out/bin/schematic-svg --project src/schematic/guest \
  ../eda/projects/designs/lib/modules/straps-synth-lmx2595.sexp \
  ../eda/projects/designs/lib/pinouts/lmx2595rhar.sexp \
  ../eda/stdlib/interfaces/spi.sexp > /tmp/current-straps-synth-lmx2595.svg
```

`ReleaseFast` optimizes the Zig interpreter. Guest execution still uses bytecode;
this does not compile the guest to C or native instructions. Debug works too.
Only a successful complete result is published to stdout. Errors have a source
path, line, byte column and stable `SCHEMATIC_<number>` code. The CLI performs no
network access, library discovery or guest filesystem access.

## Implemented language support

Quoted byte literals now produce ordinary `[N]u8` arrays: `"<svg>"`, `"µ"` and
`"\x00\xff"`. They preserve the existing type, borrow, generic and VM rules;
there is no implicit terminator or separate string runtime. UTF-8 length counts
encoded bytes. Supported escapes are `\n`, `\r`, `\t`, `\0`, `\\`, `\"` and
`\xHH`; a literal is limited to 65,536 decoded bytes. Input files use owned
buffers and borrowed views already present in the language.

The application is in [`src/schematic/guest`](../../src/schematic/guest):
`sexpr.my` handles tokenization and nested lists, `circuit.my` constructs and
queries the model, `validate.my` checks the supported declarations and pins,
`ports.my` expands interface declarations, `text.my` handles byte text and XML
escaping, `layout_graph.my` and `layout.my` derive functional groups and positions from
connectivity, and the SVG drawing modules emit the schematic. The wrapper explicitly registers
`length`, `byte`, `put` and `issue`; output remains owned by the caller.
The board trial and this tool share the Zig project-compilation lifecycle.

## Supported subset and limits

This first project pilot supports one parameterless `defmodule` with one
`design-block`, exactly one IC with a supplied 41-pad pinout, and `cap-0402`,
`cap-0603`, `res-0402` and `ind-0402` two-terminal instances. IC family and pinout
identity must match, ignoring ASCII case. Every pad needs a connection or an
explicit IC `nc-ok` reason. Multiple numeric pads in one `pin` form are supported.
The renderer implements a bounded functional hub layout in `.my`. It does not
call Netlisp at runtime or embed a pre-rendered circuit. Layout changes follow
source connectivity; this is not a port of every Netlisp layout mode.

Direct ports and peripheral-direction `port-group` interfaces support explicit
lane `rename` forms. Unknown lanes, duplicate expanded ports and ports with no
connected pad reject. Controller-role inversion, recursive module instantiation,
parameter evaluation, arbitrary component generators and additional component
libraries are not supported. Their relevant unsupported forms reject.

Imports identify dependencies but are not evaluated: the caller supplies the
pinout and interface explicitly. Known documentation, electrical and PCB metadata
(`implements`, `note`, `net-envelope`, `net-class`, `pcb-plan`, `id`, `decouples`,
`i-typ`, `i-max`, and passive specification qualifiers) do not perform electrical
validation. Values are displayed as source text. This SVG is a rendering of the
circuit, not a replacement for Netlisp's electrical checks or design sign-off.

Each document is limited to 1 MiB, 16,384 parsed nodes and 128 nesting levels.
The model allows 128 components, 1,024 pins and 32 expanded ports. Identifier
payloads must be 1–64 bytes with no ASCII whitespace or backslash escapes; display
strings support escaped quotes, backslashes, tabs and line endings. Input must
be UTF-8 with XML 1.0 characters. XML metacharacters and attribute whitespace are
escaped. Output is limited to 4 MiB, with 100 million VM instructions and four
million host calls/work units per CLI invocation. Resource exhaustion rejects;
these ceilings are limits, not a claim that every maximum-sized input finishes.

## Independent evidence and provenance

`tests/schematic_svg.py` parses the emitted XML and compares every component,
value, pad and NC reason with a separate Python fixture reader. It also maps
source references to Netlisp's sequential references and compares all 34 raw
nets against the retained **independent Netlisp `netlist-dump` output**. Source
mutation tests verify changed output and located rejection with empty stdout.
`tests/schematic_layout.py` independently checks physical signal connectivity,
wrong-net pad contacts and bounds, rewires a real DSL endpoint, and rejects a
seeded drawing defect even when the net metadata remains valid. The ordinary
SVG acceptance command also invokes the geometry oracle.
`tests/schematic_reload.py` changes, breaks and repairs this actual guest through
one persistent host, checking that a failed edit retains the last good preview.
The Zig boundary tests exercise invalid input, host index bounds, allocation
failure cleanup, first-error retention and fresh sessions after a VM trap.

The supplied URL returned a sign-in page. Fixtures were copied from the matching
local EDA design on 2026-09-07; `fixtures/manifest.json` records original paths
and SHA-256 hashes. The EDA source was inspected read-only. The independent dump
was produced with:

```sh
../eda/zig-out/bin/netlisp netlist-dump \
  --project-dir ../eda/projects/designs straps-synth-lmx2595
```

The generated file represents the captured local source, not a verified snapshot
of the authenticated website. To refresh it, review source changes, recapture the
three fixtures and their hashes, regenerate the independent Netlisp dump, then
run acceptance before replacing the checked-in SVG.

## Webpage comparison and concurrent verification

The webpage uses inline SVG, rather than canvas. The independently captured
[reference](reference/straps-synth-lmx2595.svg) and Chromium screenshot preserve
the default Functional view from the existing local EDA binary. All 37 visible
IC pin positions and the 884 × 1144 viewBox match that independent reference.
The drawing follows its symbols and palette; wire routing is a bounded `.my`
implementation, not a claim of pixel-identical rendering for arbitrary circuits.
[Provenance](reference/provenance.json) records the source and artifact hashes;
the authenticated production page was not verified.

The [verification trial](verification-trial.md) runs the real disk-loaded guest
with shared successful-result caching and concurrent scheduler clients. Its
baseline and final JSON records identify the guest sources and unchanged runner.
This exercises declared suite dependencies and shared execution; it does not
claim semantic per-function testing or a Git merge trial.

Final validation also runs without a build:

```sh
python3 tests/schematic_reload.py --runner zig-out/bin/schematic-svg
python3 tests/schematic_verification.py --runner zig-out/bin/schematic-svg \
  --output /tmp/schematic-verification.json
```

`reload-trial.json` records the real application’s unchanged runner and successful
edit/failure/repair cycle. Geometry tests exposed and helped fix incorrect passive
placement, RF wire-to-pad contacts, and connections hidden by the chip border.
These were application drawing defects; the language’s static checker did not
prove the layout correct.
