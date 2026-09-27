# Scalar readiness: deliberately unchecked differential diagnostic

This is **not a production optimization or correctness candidate**. Read
[the proposed proof](../../docs/audits/d9-rc-scalar-readiness-plan-2026-09-27.md)
before interpreting its result.

Private copies of the immutable c71 type-fact QBE append/sieve binaries replace
only `myl_rc_list_plain_ready`'s first six bytes with `mov eax,1; ret`. This
intentionally omits actual native binding, queued-death and other readiness
validation. It is unsafe for arbitrary programs and runtime state. Original
binaries are unchanged. No language/compiler/runtime source was edited.

Alternating full-workload median-three instructions on CPU3 fall 43.8% for append
and 33.0% for sieve; all twelve observations report 100% event running. Exact
stdout and separate ownership counters match for these particular inputs. The
diagnostic still costs about 2.39× / 3.41× accepted GC. These are opportunities to
investigate, not a prediction that a safe compiler candidate has this speedup.
The probe also removes private repeat-cache hint updates. Results remain separate
from production acceptance evidence.

`results.json` records original/copy SHA256, ELF virtual address, file offset,
old/new bytes, commands, full output/counters and raw perf observations.
`probe.py` is the executed local reproduction driver. Original and copied
binaries are not checked in. `append-qbe-ready.asm.gz` and
`append-qbe-repeat.asm.gz` show the queried code; `append-llvm.asm.gz` shows the
actual LLVM full-LTO guest, where the query is inlined. No LLVM differential
patch or new LLVM speedup is claimed.

```sh
python3 experiments/d9-rc-scalar-readiness-audit-20260927/verify.py
```

`--live` also verifies all original and diagnostic files still have their exact
hashes and differ only at the recorded six-byte patch. The GC denominators come
from archival completed rows documented by the preceding type-fact archive.
