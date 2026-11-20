# WP-4 RC foundation regression gate, 2026-09-26

The experimental integration `codex/d9-rc-integration` passed the full gate at
`3e0c140075e4c7e34c815bba8a0d7a3422fbba87`. GC remains the default.
This is a foundation regression result, **not RC guest or performance acceptance**.
Main remains `b292660a`; the original dirty checkout and devspeed branch were untouched.

| Check | Result |
|---|---|
| `zig build test --summary all` | 94/94 steps; 2,153 executed, 21,826 skipped of 23,979 total |
| `zig build test-qbe --summary all` | 51/51 steps; 436 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check` | Exit 0 |
| Whole-tree Guardian at commit | 88 checks; no baseline relaxation |

Commands ran serially under `../.d9-closeout-gate.lock` through
`scripts/build-slot.sh gate`, with a worktree-local Zig cache and on-disk TMPDIR.
Sources were frozen throughout. The Debug compiler SHA-256 is
`88a52a9595a2d86980ae0a2e39fce1f466de9a70830a057f12a041774d3071c4`.
[Machine-readable results and compressed logs](evidence/d9-rc-foundation-gate-2026-09-26.json)
retain the exact command outputs and hashes.

The joined work includes shared RC metadata/lifetime interfaces (`72765ec0`),
transactional copies and unique close ordering (`56005888`), the production
allocator and collection adapters (`4f975415`), compiler physical shape and call
contract foundations (`0362693f`, metadata `c48f4763`), versioned artifact/cache
selection (`26b3ab27`, `8d684889`) and command normalization (`148d425f`).
The native context ABI is v9 because appending the heap's private RC state changes
fields following the embedded heap. GC/arena/literal prefixes remain 16 bytes;
counted heap allocations use 32 bytes.

Two real C wrappers cover 12 lifetime/transfer and nine production storage/collection
scenarios, including a million-node chain, a wide DAG, holds, count overflow,
allocation failure, immediate reuse, dictionary dead entries and canonical view
backing. Focused tests also check cache separation, manifest mismatch refusal,
LLVM helper signatures, command precedence and child inheritance. Agent C runs
used ASan/UBSan; the full integration gate runs the normal repository checks.

RC emission and execution are still incomplete. Review identified raw host resource
pointers that must stay outside ordinary count metadata, iterative pinned-copy and
arena rollback work, host/codec temporary ownership, and cleanup planning as pending.
The experimental selector does not imply those programs are accepted. The subsequent
metadata index, expanded transform tests and fixes will receive joined validation
when integrated. WP-4 still requires complete correctness, measured borrow-related
count reduction, instruction geomean at most 1.0× GC with no program above 1.3×,
and lower median peak RSS. WP-5 remains after WP-4.
