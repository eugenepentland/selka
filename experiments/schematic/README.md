# Netlisp schematic pilot

The language parses the supplied S-expression files, checks a bounded circuit
model, expands the SPI interface, lays out the component groups and writes SVG
while running on its bytecode VM. The Zig host supplies four typed byte-I/O
operations. It does not call Netlisp's parser, circuit evaluator or SVG renderer.

[Open the generated Straps LMX2595 schematic](straps-synth-lmx2595.svg).
It contains 30 components, 95 connected pads, four deliberate no-connects and
nine interface signals. Identical net labels connect terminals. Per-pin supply
branches display their base rail only when the named host pad and an existing
trunk net establish Netlisp's branch convention. Raw branch names remain in SVG
`data-net` attributes; `data-electrical-net` records the display connection.
Component references retain the source names such as `C_VCCDIG`.

## Reproduce

Use the pinned Zig 0.17.0 development toolchain and sibling Guardian checkout:

```sh
zig build -Doptimize=ReleaseFast
zig-out/bin/schematic-svg --project src/schematic/guest \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp > /tmp/straps-synth-lmx2595.svg
zig build test-schematic -Doptimize=ReleaseFast --summary all
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
escaping, and `svg.my` draws the schematic. The wrapper explicitly registers
`length`, `byte`, `put` and `issue`; output remains owned by the caller.
The board trial and this tool share the Zig project-compilation lifecycle.

## Supported subset and limits

This first project pilot supports one parameterless `defmodule` with one
`design-block`, exactly one IC with a supplied 41-pad pinout, and `cap-0402`,
`cap-0603`, `res-0402` and `ind-0402` two-terminal instances. IC family and pinout
identity must match, ignoring ASCII case. Every pad needs a connection or an
explicit IC `nc-ok` reason. Multiple numeric pads in one `pin` form are supported.
The renderer uses simple named-net rows grouped by `rough` declarations; it is
not Netlisp's existing automatic wiring/layout algorithm.

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
