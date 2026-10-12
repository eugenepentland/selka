# Exact-sized managed counters through native replay v2

Source `fbfcaa7a923186a8e773c3760f81c10aa345a432`; compiler SHA-256 `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.

Eight native binaries and all fifteen fixed-input configurations pass. Every run
has exact output, zero observed RC events and zero managed exit-live bytes;
emitted LLVM and linked symbols pass the selected-owned structural checks.

The adapter is A10 commit `7b10b6b6f9205993b7f6bdd73be34e32b4ab93ea`.
Both C0 and Support7 use this exact adapter version. It verifies the runtime
against the frozen compiler and identifies the numeric object with explicit
provenance and a unique read-only ELF match. C0 v1 evidence and the initial eight
ordinary C0 native-link failures remain unchanged in their separate directories.

The raw archive preserves native commands, LLVM, source/helper snapshots, counter
documents and symbol audits. This run used two four-source admission leases;
admitted work was 35.623s and queue wait 231.103s.
Those durations describe qualification scheduling, not compiler/runtime benchmarks.

These counts are additional exact-sized timing-input evidence, separate from the
original30 and pinned81+6 census denominators. Allocation and copy traffic,
reallocations, managed peak and exit-live bytes remain separate fields.
Managed peaks are observations, not traffic reductions or RSS. Realloc movement
and concurrent peaks vary across runs. Corrected descriptor-list-copy telemetry
in Support7 must not be interpreted as an allocation increase.

Support7 is a frozen intermediate candidate with release-inventory blockers.
This report does not claim qualified implementation, default promotion or RC
retirement. All uninstrumented timing binaries remain unchanged.
