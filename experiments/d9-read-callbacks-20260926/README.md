# Receiver evaluation and pin branches

The new `tests/lang/collection_read_callbacks.my` fixture checks ten collection
reads and snapshots across mutation, including negative indices, nested rows,
pinned parameters, dictionary fields and managed values, named snapshots and
nested pin restoration. `run.py` builds actual QBE and LLVM O3/LTO guests in GC
and counted RC. GC runs with collection stress. `broad.py` exercises the
surrounding receiver, temporary and live-view cases under the same four modes.

Run from the repository root after installing a Debug compiler at
`.tmp/rc-read-captures/install`:

```sh
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-read-callbacks-20260926/run.py
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-read-callbacks-20260926/broad.py
```

Exact commands, source/compiler/binary hashes and counts are archived in
[the evidence](../../docs/audits/evidence/d9-read-callback-captures.json.gz).
The original divergent GC baseline remains in the scalar-loan experiment;
its recorded result is not changed by this correction.
