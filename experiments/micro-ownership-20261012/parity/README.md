# Ownership micro parity qualification, 2026-10-12

This evidence prepares the eleven canonical `bench/parity/micro` kernels at
base e303d704d37d9cbd90c643ce4f06a4ecb9895718. Workload constants, algorithms,
checked arithmetic and expected bytes are preserved. Canonical sources already
use modern syntax, so `original/` is an exact snapshot. `migrated/` differs only
in dict_count: `keys[index].copy()` obtains the owned string needed by its local
key binding. This is one changed expression in one kernel; ten need no changes.
The copy also runs in migrated RC, isolating migration burden from zero-RC.

An original `mut key = keys[index]` fails E_SINGLE_OWNER_BORROW under checked
zero-RC. Trying an unadorned immutable binding fails E_BINDING_DECLARATION;
trying `const key = keys[index]` also fails E_SINGLE_OWNER_BORROW. Explicit copy
is the smallest accepted local migration. No compiler changes or RC fallback.

Compiler is the archived green gate4034 install, SHA-256
8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa,
production source commit 4034a2fab29e3300b6f70549ce84727d647761db.
All guest builds use --release; zero-RC also uses --experimental-zero-rc.
Counter binaries additionally use --counters (the actual CLI flag).
Counters are compiled separately and not qualified here; parent owns their runs.
Reference Zig ReleaseFast/ReleaseSafe and Rust use freshly built canonical ports
and the standing harness flags; no binary substitution. The manifest records
exact commands, tool versions, source/binary/output/oracle hashes and diagnostics.

Reproduction: source `/home/epentland/.config/mylang/dev-env.sh`, override TMPDIR,
ZIG_GLOBAL_CACHE_DIR and ZIG_LOCAL_CACHE_DIR to private directories below
`.tmp/micro-ownership/parity`, retain shared
MYLANG_SLOT_DIR=/home/epentland/.cache/mylang/slots, MYLANG_DEV_JOBS=4 and
MYLANG_DEV_MAXRSS=8589934592. Run
`scripts/build-slot.sh build python3 experiments/micro-ownership-20261012/parity/prepare.py`.
The script builds with four workers and qualifies each ordinary arm once while
holding that single admission. Qualification durations are scheduling estimates
under shared build load, not performance samples. No RSS/timing/count run here.

## Separate variant inventory

The core eleven are mandatory. Wrapping mylang variants bytes_scan_wrapping and
list_records_wrapping change arithmetic semantics and are excluded from core.
Zig calls_inline, dict_count_getorput, alloc_churn_gpa and Rust dict_count_entry,
alloc_churn_reuse change implementation policy and are also separate variants.
The canonical alloc_churn_arena.my currently has an arena-labelled comment but
its body has no arena wrapper; it is byte-identical to alloc_churn after ignoring
the first comment. It is not an arena arm, and is not silently measured as one.
No actual arena source is built or claimed supported by checked zero-RC.
Variant inventory hashes are recorded separately in inventory.json.

Preparation outcome: all 99 builds succeeded; all 66 ordinary binaries qualified.
The 33 counter binaries remain built for the parent measurement pass. Shared-load
qualification totaled 4.60 seconds; the slowest ordinary run was 0.148 seconds.
Initial preparation stopped when rustc was absent on PATH. The retry explicitly
used ~/.cargo/bin/rustc, as allowed by canonical harness tool discovery. Earlier
ordinary checks were repeated; the archived retry manifest is the final result.
No unresolved core refusals remain.
