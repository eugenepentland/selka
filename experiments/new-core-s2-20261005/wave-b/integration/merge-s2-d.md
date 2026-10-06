# S2-D integration qualification

Package source/evidence: `89f65316` / `62656609`. Integration parent: `746d3b8b`.
The resolved staged merge tree tested before this merge commit is
`eccf30e9e09383072937547bbee1ff4d2ae08b29`. The three wrapper logs retain the
pre-merge `source_commit` and explicitly identify `tested_resolved_merge_tree`
and `merge_package`; subsequent changes add only qualification evidence.

Full S2-T1 `core_text.c` is preserved unchanged from the integration parent.
The temporary weak dictionary hash dependency is replaced by its ordinary
published declaration. Text flags, bytes kind 3, dictionary kind 4, missing-key
trap 9, iteration trap 10 and text traps 11–15 retain their assigned values.
Dictionary child release joins the iterative worklist. Function dispatch and
the copy-in/copy-out mut ABI, fixed-array current-place reads, array equality,
and text cursor/vector lowering are retained. Dictionary index/replacement
dispatch shares the existing array path. The test root includes every lane.
The dictionary as-built design section is §18, after I §16 and F §17.

Fixed arrays directly storing live dictionary views receive the exact refusal
`fixed array storage of live dictionary views`. The added fixture passes on
the old core and demonstrates that a stored view observes a subsequent mapping
value update. Arrays storing ordinary dictionary values remain supported;
the identity analysis refuses exposed aliases combined with persistent views.

| Check | Command | Result / evidence |
|---|---|---|
| Merge wrapper | `python3 experiments/new-core-s2-20261005/wave-b/integration/check_merge.py --stage merge-s2-d` | All three checks pass on the resolved staged tree |
| Build | Wrapper uses `scripts/build-slot.sh build -- /usr/bin/time … zig build core --summary all` | `merge-s2-d-build.txt`: 0.01 s, cached after successful source rebuild |
| Held core gate | Wrapper uses `scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- /usr/bin/time … zig build test-core --summary all` | `merge-s2-d-test-core.txt`: 197/197, 232.75 s, test RSS 205 M, compile RSS 331 M |
| Full conformance | Wrapper runs `conformance.py --set all --jobs 4 --why --mylang zig-out/bin/mylang --core zig-out/bin/mylang-core` with its private cache | `merge-s2-d-conformance.txt`: 1224 matching, 0 mismatching, 316 unsupported / 1540, each mode; 42.57 s |
| Focused leak/verify | `scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py test/core/d_collections.my test/core/d_view_identity.my --jobs 4 --why --leakcheck --verify --mylang zig-out/bin/mylang --core zig-out/bin/mylang-core --cache-dir .mylang-cache/wave-b/merge-s2-d/identity-focused` | `merge-s2-d-identity-focused.txt`: 8 matching, 0 mismatching, 10 precise refusals, each mode; no leak or fact failures |
| Identity old oracle | `scripts/build-slot.sh build -- zig-out/bin/mylang test test/core/d_view_identity.my --json --cache-dir .mylang-cache/wave-b/merge-s2-d/identity-oracle` | `merge-s2-d-identity-oracle.json`: 10/10 pass |
| Guardian | `guardian-check all . --full` and normal merge-commit hook | `merge-s2-d-guardian.txt`: all 88 checks pass |

No compiler source changed after qualification began. `ir.zig`, the integrated
`own.zig` and full T1 text runtime are unchanged from the integration parent.
The coordinator's unstaged `coverage_loops.py` fix is preserved outside this
merge. S2-X qualification begins after the number package merges and the
coordinator confirms the final source freeze.
