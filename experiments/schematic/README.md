# Netlisp schematic pilot

The language parses the supplied S-expression files, checks a bounded circuit
model, expands the SPI interface, lays out the component groups and writes SVG
while running on its bytecode VM. The Zig host supplies typed byte-I/O operations and named document handles. It does not call Netlisp's parser, circuit evaluator or SVG renderer.

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

To exercise the collector while inspecting the same rendered result:

```sh
zig-out/bin/schematic-svg --gc-stress --gc-report --project src/schematic/guest \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp > /tmp/straps-synth-lmx2595-gc.svg
cmp /tmp/straps-synth-lmx2595.svg /tmp/straps-synth-lmx2595-gc.svg
```

`--gc-stress` collects at managed allocation safepoints. `--gc-report` writes
collection and object counts to stderr, leaving stdout as a clean SVG. Ordinary
runs enable managed collection automatically; neither flag is needed to use GC.

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

Python-style quoted literals create managed Unicode strings. The schematic's
binary I/O helpers use explicit byte literals such as `b"<svg>"`, `b"µ"`, and
`b"\x00\xff"`; these create `[N]u8` arrays with no implicit terminator. Their
length counts encoded bytes and they are limited to 65,536 decoded bytes.
Byte literals may be passed directly to `&[]u8` helper parameters; the compiler
creates the temporary read-only view. The host owns input documents, and guest
text spans identify their file and byte offsets.

The application is in [`src/schematic/guest`](../../src/schematic/guest):
`sexpr.my` handles tokenization and nested lists, `circuit.my` constructs and
queries the model, `validate.my` checks the supported declarations and pins,
`ports.my` expands interface declarations, `text.my` handles byte text and XML
escaping, `layout_graph.my` and `layout.my` derive functional groups and positions from
connectivity, and the SVG drawing modules emit the schematic. The wrapper explicitly registers
`length`, `byte`, `put` and `issue`; output remains owned by the caller.
The board trial and this tool share the Zig project-compilation lifecycle.

## Entry point and named inputs

The host supplies `io.Inputs` with `circuit`, `pinout`, and `interface` document
handles. These are `io.Document` values, so accidentally passing an arbitrary
integer to the parser is a type error. The byte-reading boundary keeps numeric
indices internally; application code does not depend on their ordering.

```python
def main() -> Result[None, int]:
    inputs = schematic_inputs.load()
    circuit = sexpr.parse(inputs.circuit)?
    pinout = sexpr.parse(inputs.pinout)?
    interface = sexpr.parse(inputs.interface)?
    drawing = schematic.build(circuit, pinout, interface)?
    svg.render(drawing)
    return Ok(None)
```

`schematic_inputs.load()` is an application module that obtains the three named
host documents. Parsing receives a document handle. `schematic.build` validates
and assembles one schematic value before SVG output starts. Postfix `?` returns
validation errors immediately. Entry adaptation converts `Ok(None)` to scalar
status zero and `Err(code)` to that code; the schematic host treats a nonzero
status as failure. The general `mylang run` command prints the scalar result.

## Managed application data

The guest now uses GC-managed lists for parsed nodes, parser stacks, parts, pins,
ports, graph edges, nets, placement rows, points and routed segments. Start with
[`main.my`](../../src/schematic/guest/main.my): the application entry point takes
named document handles and no allocator. The rendering pipeline passes one
validated schematic value to the SVG renderer.
There are no collection borrow scopes or resource moves in that pipeline.
Parser and model validation still return errors for malformed circuit data.
Layout functions return their lists directly because allocation no longer needs
an application-level result wrapper.

Collections use ordinary generic types and list syntax:

```python
nodes: list[Node] = []
nodes.append(Node(
    kind=Kind.list,
    span=text.Span(file=file, start=0, end=size),
    next=0,
))
first = nodes[0]
nodes[0].next = len(nodes)
```

Lists grow automatically and assignments share their storage. Records remain
values: changing `nodes[0].next` updates that slot while `first` retains its
previous field values. Functions, classes, conditions, and loops use Python
indentation; declarations use `int`, `list[T]`, and `Result[T, E]` annotations.
The parser and renderer keep byte-oriented host I/O explicit with `b"..."`
literals and `u8` at their boundary. Output helpers return `None`, so writing
SVG needs ordinary calls without placeholder integer results or borrow blocks.

[A small result-flow example](../../examples/gc-default/result-flow/main.my)
shows list construction and result handling separately from the application.

Useful files to inspect:

- [`schematic_inputs.my`](../../src/schematic/guest/schematic_inputs.my): the application input entry point.
- [`io.my`](../../src/schematic/guest/io.my): nominal document handles and byte host declarations.
- [`schematic.my`](../../src/schematic/guest/schematic.my): validation and assembly
  of the single value consumed by rendering.
- [`sexpr.my`](../../src/schematic/guest/sexpr.my): list construction and updates
  while parsing nested forms.
- [`layout_graph.my`](../../src/schematic/guest/layout_graph.my): growing graph
  tables and updating connected groups.
- [`layout.my`](../../src/schematic/guest/layout.my): passing and mutating shared
  lists through placement helpers.
- [`svg.my`](../../src/schematic/guest/svg.my): rendering directly from managed
  model and geometry lists.

The host still owns the I/O session and output bytes. GC changes the guest model
storage; it does not replace deterministic host resource cleanup. This pilot
uses value records inside managed lists, rather than introducing a new mutable
object class hierarchy.

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
