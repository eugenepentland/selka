# Support7 compiler and installed component qualification

This directory records exact intermediate Support7 artifacts, source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`, compiler SHA256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
The compiler remains opt-in for checked ownership. No default or retirement
milestone is claimed; later source revisions require their own qualification.

`qualify_package.py` checks every installed artifact against the coordinator's
frozen installation inventory before and after each command. It checks actual
component manifests, hashes and source hashes in their independent compiler
receipts. Commands use the installed compiler's own bin/../libexec discovery;
MYLANG_COMPONENT_DIR is not set. Native work takes shared admission per command,
and queue duration is kept distinct from any measurement claim.

The pure matrix comprises42 test executions: test-index6 and cache-plan15 in each
of debug/release, with `--experimental-zero-rc --verify-facts --no-cache`. Every
report must have zero failed, unsupported and skipped rows; successful process
status alone is insufficient. Fresh release component builds run the same native
protocol oracles as the actual installed component binaries. Symbol checks cover
the installed artifacts separately. `package-results.json` and compressed raw
records are written only after all12 commands complete and all42 pure tests pass.

The installed components are uninstrumented artifacts built by the independently
qualified Support6 ReleaseFast seed compiler through the explicit owned pin.
Their identities differ from fresh Support7 release builds and A08's counted
component binaries; all identities remain separate. A08 owns the exact Support7
688-run counted protocol qualification. This report does not relabel those runs
or treat their managed counters as process RSS. Existing oracle scripts print
incidental durations; shared-admission correctness runs are not timing evidence.

The first manual native preparation failed because ReleaseFast optimized away
the Debug data symbols expected by v1. `runtime-preparation.log` preserves that
failure. The explicitly approved v2 extractor verifies exact Git runtime bytes
and the actual compiler-build number object inside the frozen RF compiler ELF.
Both C0/Support7 preparation and normal/manual JSON/task counter equivalence
passed; complete frozen evidence is in `../manual-native-v2/validation.json`.
A09 reruns the full15 baseline/candidate workloads with that v2 adapter.

Final package result: all12 commands and42 pure test executions passed. Both
fresh and installed native protocol suites passed; both installed symbol audits
were clean, and every frozen source/artifact identity remained unchanged. This
qualification consumed the installed Support7 components, whose manifests and
full independent compiler/source receipts are preserved under `raw/identities/`.
A08's separate fresh688 counted proof is committed at765988210 and its exact
summary digest is bound in `package-results.json`. No default promotion or active
legacy retirement occurred during these checks.
