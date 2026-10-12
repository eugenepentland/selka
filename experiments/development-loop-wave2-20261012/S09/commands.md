# Reproduction and outcomes

Base B0 `c1857310e0bf623545380c8de24515f1b9970021`; private S09 worktree.
External root and cache were read-only. All writes were private fixture temporary
directories or this owned experiment directory.

```sh
source /home/epentland/.config/mylang/dev-env.sh
python3 experiments/development-loop-wave2-20261012/S09/bootstrap_evidence_bridge_test.py -v
python3 experiments/development-loop-wave2-20261012/S09/bootstrap_evidence_bridge.py --root /home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang --cache /home/epentland/.cache/mylang/components --expected-commit dff9304b9cd7bc72e66f9feb20f1b05281d67333 --zig "$ZIG" --output experiments/development-loop-wave2-20261012/S09/external-evidence.json
```

Tests: status 0, 18/18 passed. Diagnostic run: status 0, explicitly partial with
complete=false. Seven selected artifact/producer/seed chains and 60 historical
compressed/uncompressed archives authenticated. It consumed 391 exact input paths
and 1,014,187,527 streamed bytes including final rechecks, within 2 GiB read-work
budget. This is developer diagnostic work, not a timed bootstrap or an action
reuse verdict. No speedup, CPU/RSS or median/p95 claim follows.

The actual seed executable digest is
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.
Tool Zig `0.17.0-dev.1683+5ceec001b`, digest
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.
Observed external host digest
`590fb4260dd4f11fe97efd66f40fc2c4dbf94d7542c84b24bb6b6944585e2ce7`;
its current source recipe/ABI and optimization mode are not qualified by this
adapter. Package modes, flags, seed pin and complete producer key remain bound
inside authenticated receipts; tool-library/runtime closure remains unqualified.

The developer environment supplies worktree-private Zig local cache, on-disk
TMPDIR, shared global cache and shared slot directory. No compiler build, full
verification gate, native bootstrap invocation, timing admission, legacy gate
lock or explicit CPU pinning was needed. Normal commit hooks run whole-tree
Guardian under shared gate admission. Python remains developer-only.

`memory-owner-observation.json` contains a read-only point-in-time Git status,
full HEAD and committed ledger digest. It records an active dirty owner checkout;
it is not a frozen final qualification candidate. No memory or bootstrap source,
manifest, cache artifact or owner ledger was modified.
