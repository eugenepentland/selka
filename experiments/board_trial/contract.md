# Bounded board keepout trial

This is the trial contract, fixed before the guest implementation. It is a
representative rectangular-board policy experiment, not a replacement for the
EDA application's production DRC. Execution stays in the bytecode VM. Agent
repair measurements have not been collected.

## Provenance and scope

The policy is grounded in the current EDA implementation inspected read-only at
commit `c29a0df9f2907c4bda3c84a480606eab9e496d0b`:

- `src/placement/board_keepout.zig`: `Region.coversSide` and `coversLayer` define
  top/bottom/both applicability; `allowsNet` provides explicit net exemptions.
  SHA-256: `77d9fb87cd42f1cecb30845b2b7f0fab058ff7aaf3a4cdf0b6172b6b57eeb2c7`.
- `src/placement/drc_board_keepout.zig`: components, tracks and vias have separate
  block flags; vias cross both faces and ignore the region's face restriction.
  SHA-256: `e4b36a5bcb5c7dfde8f3859584ac3f19ec808764900da1c6cceeb11d0e5c6bd3`.

This trial uses already-resolved integer identities and axis-aligned rectangular
footprints. It omits string net-name resolution, rotated courtyards, polygonal
outlines, sampled tracks, circular vias, clearance and production DRC rendering.
A new standalone Zig baseline will implement this same bounded contract; results
must not be described as executing the complete existing EDA module.

## Input snapshot

`version` is 1. `board` contains an outline rectangle, component IDs, net IDs,
regions and features. Rectangles are `[x, y, width, height]` in **micrometres**.
Coordinates are signed integers in [-1,000,000,000, 1,000,000,000]; extents are
integers in [1, 1,000,000,000]. The right and upper endpoints must also remain in
the coordinate range. These bounds make exact arithmetic sufficient.

IDs use unsigned 64-bit transport values; zero is a logical invalid_id. Negative
or out-of-range transport integers reject before guest construction. Coordinates
use signed 64-bit transport values; logical rectangle bounds are checked below.

At most four component IDs, four net IDs, four regions and eight features appear
in one snapshot. Each region has `rect`, `face` (top/bottom/both), nonempty
`blocks` (component/track/via) and at most four `allow_nets`. Each feature is one
of:

- component: `id`, `face` (top/bottom), `rect`;
- track: `net`, `layer` (front/back/inner), `rect`;
- via: `net`, `rect`.

The guest model uses distinct ComponentId, NetId and Micrometres domains, tagged
feature variants and optional slots in fixed arrays. A Millimetres domain makes
unit-confusion edits checkable. Empty slots represent absent entries without a
parallel length field. Host input conversion validates JSON shape and bounds on
collection sizes before constructing that fixed snapshot; oversized input never
truncates. Logical invalidity remains visible to the guest validator.

## Input validation and deterministic results

Validate the whole snapshot before computing violations, in this order:

1. The outline rectangle is valid.
2. Component IDs are positive and unique, in input order.
3. Net IDs are positive and unique, in input order. The same numeric value may
   occur in the component and net catalogs because their identities are distinct.
4. Each region has valid bounds, at least one blocked family, and every allowed
   net exists. Repeated allowed nets are harmless, matching the admission policy.
5. Every feature has valid bounds and references an existing component or net.

The first failure returns a declared input error: invalid_bounds, invalid_id,
duplicate_component, duplicate_net, empty_blocks, unknown_allow_net,
missing_component or missing_net. Input errors take precedence over geometry
unavailability and produce no partial report.

For valid input, visit features in input order. Count a feature outside the board
once if any part of its rectangle lies outside the outline. Boundary contact
with the board is permitted. Then visit regions in input order and apply:

| Feature | Applicability |
| --- | --- |
| component | component block flag and matching face, or region face both |
| track | track block flag; front matches top, back matches bottom, inner matches only both; admitted nets bypass |
| via | via block flag on any face; admitted nets bypass |

Component placement is never exempted by allowed copper nets. For each applicable
pair, invoke the typed host rectangle-intersection operation. Strict positive
intersection in **both** axes is a violation; touching edges/corners are clear.
Every violating pair counts, including duplicate regions. Features outside the
outline can also violate regions. Return a typed report containing the violation
count and either no first violation or its feature index, kind (outside_board or
keepout) and region index (absent for the board boundary). The first item follows
the traversal order above, with an outside-board item before that feature's
keepout items. Count bounds are therefore 8 + 8*4 = 40.

Geometry returns a declared clear/intersection result or an explicit geometry
failure. Any failure aborts validation with that error; it must not return a
partial successful report. A deterministic unavailable wrapper exercises this
path. Callback counts and cooperative work can be observed separately from VM
instructions. No timing claim treats the rectangle kernel as a realistic heavy
routing benchmark.

## Independent evidence and repair comparison

`oracle.py` implements this contract independently in Python using sets and
coordinate intervals. Development cases are fixed before the guest validator and
Zig baseline. The expected result includes callback count so skipped/extra host
operations cannot hide behind a correct final count. Hand-checked sentinels
anchor the oracle before generated cases are added.

Build the guest and Zig baseline against the same snapshots and oracle. Then
prepare matched repair tasks for identity/unit mixing, a new feature state,
net-exemption changes and boundary changes. Record the diagnostic, patch,
attempt count, independent test outcome, edit scope and elapsed/check time for
both languages. Failed and unfinished attempts remain in the record. Fresh
held-out cases must be unavailable to the repairing agent; the published
development oracle is not a blinded repair study. No comparative reliability
claim is supported until actual attempts and their limitations are recorded.
