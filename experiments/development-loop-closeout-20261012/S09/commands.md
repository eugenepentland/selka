# S09 commands and scopes

Run from the S09 worktree at C0. Tool: Zig
`0.17.0-dev.1683+5ceec001b`, executable SHA256
`1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`.

```sh
python3 experiments/development-loop-closeout-20261012/S09/timing_bridge_test.py -v
python3 experiments/development-loop-closeout-20261012/S09/audit_snapshot.py --repository . --output .tmp-s09/source-audit.json
cmp .tmp-s09/source-audit.json experiments/development-loop-closeout-20261012/S09/source-audit.json
ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache TMPDIR=$PWD/.tmp-s09 scripts/build-slot.sh build zig build component-builder test-component-support --summary all
ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache TMPDIR=$PWD/.tmp-s09 scripts/build-slot.sh build python3 selfhost/test_components.py --builder zig-out/tools/selka-components --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
```

The first command tests seven synthetic admission fixtures; the exporter reads
immutable git objects and `cmp` proves exact regeneration. Native support tests
check streaming digests, canonical identity and archive handling. The existing
coordinator suite uses fake toolchain/seed compilation to exercise 18 cache,
corruption, failure and recovery cases; it is not genuine installed stage parity.
Neither native command includes source install, real seed provisioning,
`test_component_native.py`, complete verification or isolated ratio timing.

Logs record statuses and executed counts in the handoff. No CPU pinning applies
to these ordinary build admissions; no timing window or legacy gate is acquired.
Python remains exclusively in developer/qualification paths.
