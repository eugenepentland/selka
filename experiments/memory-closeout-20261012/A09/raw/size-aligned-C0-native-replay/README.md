# Exact-sized C0 counters through native replay

All **eight native binaries and 15 execution configurations pass**: expected
stdout, zero exit status, empty stderr, zero observed RC events, no managed bytes
live at exit, and clean guest LLVM/linked-symbol audits. The source/compiler
remain C0 `fbfcaa7a923186a8e773c3760f81c10aa345a432` and
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
These are fresh whole-program managed counters for the exact calibrated runtime
inputs. They are not runtime/RSS measurements or final candidate comparisons.

The method is `counted-release-native-replay-v1`, approved by the coordinator
after A10 commit `44a9ccbbc5a179d15b057a369f22f22afb115c06` passed normal/manual
equivalence controls for JSON and parallel code, including equality of entire
counter JSON documents. The adapter verifies runtime fragments byte-for-byte
against the compiler's embedded runtime, extracts the embedded numeric object,
uses the original C0 counter-runtime exporter, and applies the original target,
CPU, runtime and native optimization flags. It consumes the unchanged archived
compiler-emitted release LLVM from the eight failed ordinary builds.

`results.json` embeds the runtime receipt, adapter/compiler/source identities,
each native artifact receipt, strict counter audit, source/helper hashes, exact
arguments/environment/affinity/output and original failed build status.
`summary.json` gives the 15 metric rows. `archive.json` hashes 94 compressed raw
command, output, counter and symbol-audit files. The emitted LLVM/source archive
remains in `../size-aligned-C0`; it was not regenerated. No compiler cache receipt
was repaired, no host trust policy changed, and no uninstrumented timing binary
was replaced. Both complete frozen C0 installations and all 15 uncounted
counterpart hashes were rechecked unchanged after execution.

One counted observation was made per case, not a statistical memory estimate.
Managed peaks are not RSS and are not subtracted as traffic. The old C0 recursive
descriptor-copy instrumentation undercounts some list-copy events/bytes; final
comparisons must distinguish the later telemetry correction from allocations,
reallocations and live-byte observations. `release_unique` is direct destruction,
not RC. Zero RC telemetry alone is supplemented by LLVM and linked-symbol checks;
full runtime ABI/layout qualification belongs to A07.

The 15 cases stay separate from A03's original30/pinned81+6 denominators. Cheap
map repetitions differ across worker configurations, so their raw totals are
comparable only with the same configuration in the candidate arm. Final C1 must
prepare its exact runtime with this same adapter and repeat normal/manual
equivalence controls before pairing. The original eight compiler build failures
remain failures; this additional native method supplies the missing counters.

Eight bounded ordinary build leases used 35.373652428s admitted and
75.878731661s waiting; the longest admitted group took 11.988s. These durations
are scheduling evidence only. No timing lease was used.
