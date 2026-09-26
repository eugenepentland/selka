# Private RC ABI3 selector bridge — 2026-09-26

The private loan/history API changes the ownership ABI. Its compiler selector,
native cache identities, manifest validation and statistics records now use
`rc-v3` or `rc-v3-counting`, matching the native ABI3 declaration. ABI1 and ABI2
selectors and ABI2 manifests are rejected. `--rc-runtime[=stats]` remains the
public selector; inherited RC still falls back to GC for explicit legacy sharing,
and GC remains the default. Statistics JSON retains schema version1.

The supplemental golden driver records and verifies the requested runtime against
actual counter records. It accepts an explicit `--runtime-contract` for either
ABI2 or ABI3 and defaults to ABI3. Historical results and immutable ABI2 compilers
remain usable with the explicit ABI2 option; their archived identities are not
rewritten. A wrong runtime record or missing required counter record fails replay.

Validation: runtime-contract units16/16, runtime-mode units13/13, CLI2/2,
Debug install19/19 with Guardian88, formatting2/2, and standalone native statistics
and execution suites with undefined-behavior checks. Six actual golden replays
cover counted RC and legacy GC on QBE and LLVM O3/full LTO; all match unchanged
outcomes, expected runtime identities and balanced counts. Synthetic driver checks
confirm rejection of an ABI2 record requested as ABI3 and a successful guest
without counters, while permitting explicit legacy GC without counters.

[Logs, drivers and exact source/compiler identities](../../experiments/d9-rc-abi3-bridge-20260926/identity.json)
are retained. This is private compatibility infrastructure, not a completed
semantic-history implementation. It must join the runtime and compiler loan
implementation before integration or acceptance claims. No full gate or
performance acceptance is claimed for this isolated bridge.
