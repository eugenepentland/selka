# Support7 ownership and lifecycle review

Pinned source: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
Installed compiler SHA256: `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
The compiler path, fixture/harness hashes, exact commands, artifacts and counters are in `results.json` and `raw/`.

The supplemental fixture passes release, unoptimized debug, verified release, optimized debug and release without facts. It keeps a readonly provider and an open file live across `continue`, `break` and an error return. Each iteration also evaluates fresh min/max inputs and eager optional fallbacks exactly once. The caller then reuses the provider, reads the original file, replaces the provider and confirms independent replacement state.

Expected output is `43 18`, `scope-47 36`, `payload`, `False`, each on a separate line. Counts establish zero native retain/release/share events, zero retain/release/uniqueness-test sites and zero managed bytes at normal exit. Direct destruction sites are positive; `release_unique` is direct cleanup, not an RC event. Compiler and guest stderr are empty. Each LLVM file carries the current `mylang-zero-rc-v2` marker and no legacy RC symbols/count loads/count-tagged stores; linked symbols are clean too.

The registered regression is `zero RC live file scopes and fresh selections clean up across loop exits` in `src/core/zero_rc_test.zig`, embedding `src/core/a07_lifecycle_fixture.my`. This new registration has not yet run through the full repository gate; the same source passed the installed compiler's five native modes above. The prior fixture was preserved; no existing assertion or refusal was replaced.

## Integrated source review

Compared the frozen source to the already qualified A07 aggregate-hardening source `157901e5c6e35447bd32df825147d56074fcedaf`. Relevant later changes are the borrowed-provider context contract, exact text/optional choice markers, the bounded generator accumulator, and the approved early field-read normalization. Home-alias preservation, exact slot transfer, shallow managed-copy refusal and tuple shape validation remain present.

- Source choices validate canonical logical types before either operand is evaluated, loan the first input while evaluating the second, and track both roots through nested selections. Fresh-input choices remain borrowed even when there is no named source root. Managed escape, selected mutation and stored views remain refusals.
- Complete tuple staging still validates initialize-only metadata, exact logical arity/types, hidden unavailable slots and uniqueness before lowering. Provider roots and named Result handling obligations transfer with the fields. A01 owns the full installed tuple/parallel matrix.
- Borrowed provider contexts still accept only bounded flat local parameter-derived bundles; they are read-only and cannot escape. Explicit inliner guards preserve parameter provenance. A05 owns the provider/native callback matrix.
- Exact marker identities and signatures remain compiler-only. The general verifier checks dominance once per marker-bearing function, with temporary arena scratch. A08 owns cache replay/corruption qualification; A04 owns the full choice matrix.
- Existing A07 regressions cover discarded acquire Results, completion failure returning an owner, early success/error propagation, local/ambiguous provider escape, provider replacement, and tuple-dependent resource roots. The added fixture closes the distinct live-scope loop-exit gap.

One separate direct/fresh-IR issue was identified: a context-only marker function can pass local operand validation with an invalid block-tail reference, reaching general-verifier reachability before block references are checked. Cache snapshot/lowering decoders already validate these references; no persisted-cache bypass is claimed. An isolated red/green regression and shared preflight correction are being prepared on an independent exact-`bed11` branch. This issue is not hidden by the native lifecycle pass.

These are semantic/counter/structural results, not timing or RSS measurements. Support7 still uses the explicit checked opt-in ABI. C3 retirement drafts are evidence only; no default or legacy-runtime removal is claimed. Full common verification and final C1/C2/C3 qualification remain the coordinator's gates.
