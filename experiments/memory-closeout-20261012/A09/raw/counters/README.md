# Exact counter oracles

These are correctness measurements, with instrumentation enabled. They are not
runtime timing or RSS comparisons. The migrated fixture belongs to A03 and its
source changes are separately committed by that owner.

`support4-explicit-copy.json.gz` records all eight compiler configurations and
sixteen executions (normal plus intentional bounds trap). Compiler source
`66890fbc5135a771e6a423724d13c30018ab717f`, binary SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`, fixture SHA256
`9cb46271d3c63063c96fa8209ad95b61e2e386c4aaf4578a2023f34fe56355fe`.
All executions preserve `100 101 4` output and the expected status/diagnostic.

| Mode, normal exit | List copies | Copied element bytes | Allocations/frees | Allocated bytes | Managed peak bytes | Exit-live bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ordinary default/unoptimized/release | 1 | 800 | 21/21 | 4776 | 3560 | 0 |
| Checked unoptimized/release/verified/optimized-debug/no-facts | 11 | 880 | 31/31 | 5416 | 3560 | 0 |

The ordinary mode retains the ten child lists. The checked modes copy those ten
one-element lists explicitly (80 bytes), in addition to the 100-element list
(800 bytes). Checked emitted and runtime RC counters are all zero. Every checked
normal execution records exactly seven list growths, 1280 growth bytes, 121
main-function pushes, ten calls to `bump`, 400 bytes at its `list_set` record
copy site, and 80 bytes at `bumped`'s explicit child-copy site. Fatal trap runs
still write complete preceding traffic, but intentionally do not unwind owners:
checked trap allocations/frees are 32/29 and exit-live is 1192 bytes. They are not
reported as leak-free executions.

`recursive-before-support4.json.gz` is the old undercount reproducer. The scalar
list copy moves 24 bytes; another 16 bytes are copied inside recursive boxes.
Both checked debug and release report only one copy/24 bytes before the fix.
The missing path bypasses `myl_core_list_copy`, but uses the correctly counted
block allocator. Debug has 13 allocations/frees and 736 allocated bytes; release
has 12 allocations/frees and 704 allocated bytes. Both have managed peak 608 and
exit-live zero. Copy traffic, allocation traffic and managed peak are separate
metrics; no peak observation is subtracted as traffic.

The proposed hook accounts for list shape 7 only, directly after the unique
`core_copy_container` allocation anchor. Boxes and dictionaries are excluded;
ordinary `myl_core_list_copy` retains its existing hook. The registered regression
requires exactly two copies/40 element bytes, original output `8 3 3`, balanced
allocation cleanup and no dictionary copy. The registered focused run passes both tests (five-mode fixture oracle and
debug/release recursive-copy regression), with build exit status 0. `focused.log`
contains its full output; the Zig runner also prints a `failed command` diagnostic
after its explicit 2/2 PASS, while the encompassing build exits successfully.
`hook-build.json` pins the tested compiler and exact modified source hashes.
A separate raw post-hook counter archive is still being collected; final C1 must
rerun the registered tests on the integrated compiler.
