# RC plain projections and schematic correctness

A plain inline result can point into a parent that owns managed fields. RC
publication previously released that parent without preserving the plain result.
Cleanup cleared the old operand bytes, so later reads observed zero record
fields or enum tags. This broke nested element reads and made schematic source
validation misclassify a parsed string as the first enum case.

`codex/d9-rc-schematic` now copies borrowed plain aggregate bytes into the
instruction's scratch storage before consuming its inputs. Scalar values are
already loaded; canonical owned call results already have independent storage.
Those paths keep their existing ABI and storage behavior.

With the Debug compiler SHA-256
`72b208f4ea556dc80ebe8d96f50c897763fe63d07f48b7ca8f40dbc96cfa78c4`,
the unchanged required schematic fixture, changed-net, and changed-value cases
all produce their expected SVG hashes on QBE and LLVM. LLVM uses the mandated
O3/full-LTO flags from `experiments/perf-gc-dict-20260925/scripts/pc.py`.
[QBE evidence](../../experiments/d9-rc-plain-projection-20260926/qbe.json) and
[LLVM evidence](../../experiments/d9-rc-plain-projection-20260926/llvm.json)
record exact build commands, binary hashes and output validation. The companion
source inventory hashes every schematic source/provider file. The prior failure
was `Err(17)` at source offset 2205 with no SVG; diagnostic GC/RC parser dumps
matched before validation, isolating the ownership boundary.

The fixture and changed-value runs both retire all 56,314 heap allocations and
balance 6,434,873 owner acquires plus initial allocation owners against 6,491,187
releases. Changed-net has 6,435,027 acquires and 6,491,341 releases. Holds balance,
counters are unsaturated, and both backends produce identical counter records.
These are correctness/counter observations, not performance acceptance.

The existing 14 element-access and 12 aggregate tests pass uncached on both
backends. A focused Zig regression checks that the plain snapshot precedes
parent release; CLI guest regressions separately exercise record and enum
projections. Guardian's 88 checks pass without ratchet changes. The parent owns
the combined full gate. Separate contract-result tests remain failing and are
being investigated; this patch does not claim to fix them.
