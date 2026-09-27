# Dictionary-tail component evidence

Run `python3 experiments/d9-rc-dictionary-tail-20260927/verify.py` from the
repository root. The verifier reads only this archive; it does not rebuild or
time programs. See the accompanying
[report](../../docs/audits/d9-rc-dictionary-tail-2026-09-27.md) for limits and
the distance from the Stage 4 acceptance thresholds.

`measurements-final.json.gz` holds all commands, compiler/binary hashes,
manifests, exact output, raw perf strings, median-three counts and separate
physical counters for the final unchanged two-million-update workload.
`measurements.json.gz` is the earlier negative attempt: the real key provenance
was declined, so its timing/counters remained unchanged. The two attempts are
never pooled. The immutable before binaries were reused by hash for the final
comparison; final after builds use a new prefix and cache. Accepted GC build
identities are retained separately.

`emission-native` uses the exact ReleaseFast emitter policy. `native-selection`
and the disassembly tie the changed helper sites to the actual timed QBE binary.
LLVM build manifests explicitly require LLVM O3/full LTO. Default accounted
emission is retained too. The final compiler is a Debug build of the source
base in `identity.json` plus `source.patch.gz`; production source hashes record
the frozen measured state.

Guest, trap and native finalizer drivers preserve actual backend/runtime flags,
uncached results, environment overrides, expected trap codes and cleanup
counters. The original before/first-candidate controls remain separate from the
final replay. Intermediate failed compile/proof/Guardian logs are retained as
development evidence, not counted as passing validation. Guardian feedback is
serialized by the parent integration task.

Drivers preserve workspace paths and private scratch/cache prefixes. To rerun
on this host, restore their input fixtures under `.tmp-rc/dict-tail`, retain the
immutable compiler prefixes, acquire the build slots and reserve CPU 10 before
using the measurement driver. Binary files and caches remain at the paths in
the receipts; they are not duplicated into Git. No source-size reduction,
workload rewrite, default runtime change or full-corpus acceptance claim is
part of this slice.
