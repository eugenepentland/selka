# Exact scalar append/fold instruction attribution

Read-only analysis of the completed readiness experiment's actual full-input
binaries. No binary patching, new timing or new compiler implementation.

`identity.json` records the binary/input hashes, exact address ranges, static
common-path instruction counts and authoritative complete hardware medians.
The `.asm` files are slices of GNU objdump output. Accepted GC binaries are
stripped, so their printed nearest PLT labels are not source function names;
absolute addresses and full binary hashes identify the inspected code.

QBE executes 39+44 common instructions per appended/folded element in RC, versus
20+17 in accepted GC. Across16 million elements that explains1.328B/592M of the
measured1.334581018B/592.295027M instructions. LLVM executes28+7 in RC versus
13+19/8 in GC (the latter fold is the successful checked vector reduction),
explaining560M/246M of566.708819M/246.274722M. All common paths contain no calls.
Cold growth, setup, cleanup and exceptional loop edges account for the small
remainder. The original experiment retains every raw hardware observation;
these counts are static attribution, not substitute performance evidence.

See `docs/audits/d9-rc-readonly-list-loop-design-2026-09-27.md` for the proposed
bounded lifetime proof enabling the existing guarded read-loop version. No
production optimization is included here.

Run `python3 experiments/d9-rc-append-residual-20260927/verify.py --live` to
recheck input/binary identities and reproduce each disassembly slice.
