# EDA project inspector — small baseline v1

Status: implementation contract, pending independent review and cohort freeze.

Use the workflow planner v1 transport rules (UTF-8 JSON stdin, JSON stdout, zero
exit for defined input errors, 1 MiB input limit, at most 64 cases, strict duplicate
key/nonfinite/signed-64-bit integer handling). A request is `{"cases":[board,...]}`;
a response is `{"results":[result,...]}`. Invalid envelopes return
`{"error":"invalid-request"}`. Each board is independent.

## Board schema

A board object has exactly `version`, `unit`, `width`, `height`, `clearance`,
`components`, and `nets`. Version is integer 1. Unit is `um` or `mm`.
Width/height are integers 1..1000000; clearance is integer 0..1000000.
All distances in a board use its unit, converted to integer micrometers (`mm`
multiplies by 1000). Booleans/floats are not integers. Coordinates are signed;
negative placement is valid input that can yield a design finding.

Components is an array of at most 128 objects, each with exactly `id`, `x`, `y`,
`width`, `height`, `pins`. IDs use `[a-z][a-z0-9_-]{0,31}`; x/y are integers in
[-1000000,1000000]; width/height are integers in [1,1000000]. Pins is an array of
at most 32 distinct identifiers. Component rectangles are axis aligned.

Nets is an array of at most 128 objects, each with exactly `id`, `members`.
Members is an array of at most 128 objects with exactly `component` and `pin`,
both identifiers. Net IDs and component IDs occupy separate namespaces.
Empty nets, components with no pins, and unconnected pins are permitted schema.
No extra/missing keys are allowed anywhere.

## Validation phases

Return the first applicable error, completing each phase before the next:

1. Any schema failure (including repeated pins): `{"error":"invalid-board"}`.
2. Duplicate component or net IDs: `{"error":"duplicate-id","components":[...],
   "nets":[...]}` with distinct repeated IDs sorted in ASCII order, including an
   empty array for the unaffected namespace.
3. References to absent components/pins:
   `{"error":"unknown-pin","refs":[{"component":ID,"pin":ID},...]}`.
   Deduplicate references and sort by component then pin.
4. Repeated use of a pin (within one net or across nets):
   `{"error":"reused-pin","refs":[...]}` with the same sorting/deduplication.

Once reference validation succeeds, design-rule findings do not invalidate the
board or suppress the report/SVG.

## Reports and design rules

Successful output is `{"unit":"um","findings":[...],"nets":[...],"svg":TEXT}`.
Every finding has exactly `code` and `subjects` (an array of IDs). Findings sort
by code, then lexicographically by the subjects array. No duplicate finding.

- [EDA-OUTSIDE-1] `outside-board`, subject [component ID]: any rectangle edge exceeds the board;
  an edge exactly on the boundary is allowed.
- [EDA-CLEARANCE-1] `clearance`, subjects [smaller component ID, larger component ID]: compute the
  nonnegative x/y gaps between the closed rectangles. Report when
  `gap_x² + gap_y² < clearance²`, OR when their interiors overlap on both axes.
  Equality passes. Thus positive-area overlap fails even at clearance zero,
  but touching edges/corners pass at zero clearance. Use exact integer arithmetic.
- [EDA-UNDERCONNECTED-1] `underconnected-net`, subject [net ID]: fewer than two members.
- [EDA-UNCONNECTED-1] `unconnected-pin`, subjects [component ID, pin ID]: declared pin in no net.

The net report array sorts by net ID. Each entry is
`{"id":ID,"members":[{"component":ID,"pin":ID},...],"span":N}`.
Members sort by component then pin. Span is the half-perimeter bounding-box wire
estimate over referenced component centers: `(max(cx2)-min(cx2) +
max(cy2)-min(cy2))/2`, rounded UP to an integer micrometer; `cx2=2*x+width` and
similarly for y. Empty nets have span zero. Repeated component centers are allowed.

## Deterministic SVG

The small baseline renders placement and board extent, without routing wires.
The exact string has no newlines and is formed as follows, with decimal integer
attributes and no leading zeros, sorted components, and the fixed attribute order:

`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 W H">`
`<rect x="0" y="0" width="W" height="H" fill="white" stroke="black"/>`
then one element per component:
`<rect id="ID" x="X" y="Y" width="CW" height="CH" fill="none" stroke="black"/>`
then `</svg>`. Dimensions/coordinates are all in micrometers. Restricted identifier
syntax makes IDs safe XML attribute values. Geometry outside the board remains
in the SVG source; the viewBox remains the board extent. Exact SVG serialization
is an intentional export-format contract; arbitrary renderer-equivalent strings
are not accepted in this v1 baseline.

## Scope and freezing

Parsing, unit conversion, validation, name resolution, geometric rules, connectivity,
report serialization and SVG generation all belong to the application. Native
geometry helpers and prevalidated host objects are forbidden. There is no source
size quota. Hierarchy, schematic symbol libraries, routed wires, import versions
and incremental rule invalidation are later product changes. This deliberately
bounded board inspector does not claim to reproduce the existing schematic website.
Freeze the reviewed contract, independent oracle and concrete cases before trials.
