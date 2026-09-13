# Portable launchers and planner follow-up preparation

This preparation precedes application timing for fresh exploratory trios on
`planner-input-boundary`, `planner-priority` and `planner-cycle-groups`. It extends
the earlier [library readiness](../legacy/stdlib-application-parity.md); earlier frozen
rotation artifacts and timings remain unchanged.

Both `.my` CLI test launchers accept an explicit executable `MYLANG_IO`, otherwise
use the isolated `/tools/byte_io`, otherwise search ancestors for a built checkout.
An invalid explicit override fails clearly instead of silently selecting another
compiler. Real guest tests cover checkout, shallow relocation and `/work`;
planner stress-driver imports retain their `HOST` and `ROOT` names.

The input repair seed now changes only the application's `std_text::read` budget
from 1048576 to 1048575. This is equivalent to the Python/Zig inclusive-boundary
mutation for nonnegative byte lengths. It never changes the frozen library.
Executable tests verify the seeded defect and exact reversal in all six repair
variants, plus multibyte input just below/at/above the planner byte limit and
malformed JSON at the limit. The initial added test wrongly treated an extra
root key as valid; its retained failure led to a corrected transport-valid,
schema-invalid manifest whose result distinguishes envelope rejection. This was
preparation test authoring, outside participant clocks.

The independent `planner_parity` source review found no missing reusable facility
for the next three tasks:

- Existing `std_text` and `std_json` provide bounded transport and parsing.
- Existing `std_order` compares signed integer primary keys then secondary ranges.
  Application-owned priority/ID descriptors and priority validation remain timed
  application work. A generic mixed-sign composite heap check supplements the
  previous positive-key and ASCII ordering fixtures.
- Python 3.14.4's `/usr/lib/python3.14/graphlib.py` exports `TopologicalSorter` and
  `CycleError`; the latter explicitly documents a single arbitrary cycle witness.
  Inspection/search of Zig `0.17.0-dev.1683+5ceec001b`'s local standard library
  found no complete SCC grouping facility. Complete cyclic component grouping
  therefore remains application work across these pinned standard libraries.
  Existing list, map, ordering and graph-readiness mechanisms stay available.

No compiler or library implementation changes are required. Library/tooling
preparation and verification time remain separate from application time; missing
turn/token/cost telemetry is unknown, never zero. The new versioned readiness
receipt binds the migrated launchers, unchanged installed optimized tools, reviewed
capability matrix and acceptance evidence. Prior receipts are historical input
identities and are not asserted to verify against these changed baseline paths.

Use fresh participants, common 20-minute practice and 30-minute task budgets,
namespace command gateways and build reuse within grading suites. Dispatch each
block sequentially, with language orders Python/`.my`/Zig, `.my`/Zig/Python, and
Zig/Python/`.my`. This rotates position, but does not establish randomization or
remove shared-host effects. Tasks are existing draft specifications, not unseen
scored work. Whole-agent confinement, exact model identity and model usage remain
unverified; these limitations keep every run exploratory.
