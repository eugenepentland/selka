# Scalar collection receiver loans

`scalar.my` repeatedly reads a named list through compiler receiver captures.
The driver compares two preserved Debug compiler installations, builds actual
QBE and LLVM O3/LTO guests, and validates exact output plus balanced physical RC
counts. It also runs five guest regressions, an expected bounds trap, and a callback refusal case on both
sides. LLVM commands never append a QBE backend override.

```sh
TMPDIR="$PWD/.tmp" ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache-rc-collections" \
python3 experiments/d9-rc-read-loans-20260926/run.py \
  --before .tmp/rc-edge-audit/install/bin/mylang \
  --after .tmp/rc-read-loans/install/bin/mylang \
  --work .tmp/rc-read-loans/reproduce \
  --output .tmp/rc-read-loans/reproduce.json
```

`counts.json` records 16 executions. The scalar workload saves 10,100 owner
acquisitions and 10,100 releases per backend, with other counters unchanged.
The before compiler is `6a6f47f01e0f6ec6f67d0d54b73d797ad80364ddddafb2dea946554774fe5280`;
the after compiler is `aa1131661e6c350536f71db7081b4bafd4865e00b29c171b63c906cef3ad2fda`.
The compiler-source base is `a4657841`; runtime fast-path and whole-body
read-only optimizations are not part of this isolated comparison. This is
traffic evidence, not a timing or full performance acceptance claim.

`gc-callback-before.json` preserves the preexisting GC/RC discrepancy for the
callback case without a named snapshot: both GC backends print `91`, whereas
RC prints `7` before and after this slice. The shared regressions use an explicit
snapshot and also pass under GC stress. The discrepancy remains a separate
correctness investigation.
