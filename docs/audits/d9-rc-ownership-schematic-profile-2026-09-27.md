# Qualitative profile of combined schematic ownership overhead

The exact `e5d47d20` production schematic binaries were sampled on reserved CPU2,
with 100 repetitions of the unchanged fixture per actual backend. Each invocation
checks the complete expected SVG and an empty issue file. This is a diagnostic;
it changes no compiler, runtime, workload, accepted GC baseline or threshold.

The host limits perf sampling to 1000 events/second, and raw records show throttling
for every recorded event: 949 QBE and 707 LLVM throttle records. These samples cannot
support unbiased cost fractions, speedup estimates or performance acceptance.
They are retained only to locate code worth inspecting. Exact perf-stat counts
from the separately archived combined diagnostic remain the performance evidence.

The production binaries were stripped. Separate `--keep-symbols` builds from the
same immutable Debug compiler retain byte-identical .text sections at identical
virtual addresses. The symbol map is therefore applicable to the measured
instruction pointers without modifying the original ELF binaries. The archive
records both binary identities and .text hashes/VMA, original samples, nm ranges,
raw perf.data/decoded records and symbolized counts. Both guest symbol builds
ran through build-slot; LLVM manifests retain O3/full LTO.

Among 934 QBE samples mapped to the guest executable, descriptor_find has 154 hits,
native_loan 93, memcpy 72 and walk 56. Among 657 LLVM guest samples, native_loan has 177
and slot_drop 110. These are observed sample counts, not cost percentages. The
remaining guest symbols include sexpr::form, sexpr::at, layout::partPin and
layout::nearest. Source inspection identifies repeated per-leaf dynamic descriptor
lookup inside flat_loan; it still protects actual payload finalizer refusal.
Any future optimization must preserve that condition and registration, arena,
allocation, callback and count-limit behavior. No such change is made here.

Scripts under this directory preserve the executed paths and parameters. Their
scratch paths refer to the original local evidence tree; raw receipts are
self-contained in this archive. Existing source and compiler identities are
shared with the combined ownership diagnostic.

[Raw evidence](../../experiments/d9-rc-ownership-schematic-profile-20260927/README.md).
