# Nested collection receiver loans

`matrix.my` is the existing nested-list matrix workload at diagnostic size
n=12, preserved from the temporary-edge audit. It prints the trace and matrix
sum scaled by 1000. This is a small ownership diagnostic, not the matched
performance corpus or an acceptance workload substitution.

The runner preserves separate Debug compiler installations, builds actual QBE
and LLVM O3/LTO guests, checks exact output, and verifies allocation, owner and
hold balance. It also compares seven semantic regressions and an expected
`R_LIST_BOUNDS` trap after a projected row has been borrowed. LLVM commands do
not include a QBE override.

```sh
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-rc-nested-read-loans-20260926/run.py \
  --before .tmp/rc-nested-reads/before/bin/mylang \
  --after .tmp/rc-nested-reads/after/bin/mylang \
  --work .tmp/rc-nested-reads/reproduce \
  --output .tmp/rc-nested-reads/reproduce.json
```

The source base is `90c0c3321ee36ec08fde1e2ab486f13e641418d5`. Both compilers
include the earlier scalar loans, inert mutation scopes, callback capture
correction and constructor transfer change. This comparison changes only the
nested read-loan compiler proof and its result-publication hook.

Before compiler SHA-256:
`fa8ede10fa1185f74a762bc2feb7e1129e1677661516eaa02618f693e219ba6e`.
After compiler SHA-256:
`f20d716fbaa086a544b8fb298a3abfd2b9f709b928da69fe342352c43a7daf9b`.

`counts.json` preserves exact commands, compiler/source/binary hashes, output,
traps and counters. Additional collection and GC-stress results are compressed
in the linked audit evidence. There is no timing or full performance acceptance
claim in this slice.

`broad.py --compiler PATH --work DIR --output JSON` reproduces the 95-assertion
collection set on both actual backends. It uses source-identical temporary
modules with distinct names and records the original source hashes.
