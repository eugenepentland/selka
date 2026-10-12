# S04 producer identity and shared wiring contract

`verification_artifacts.py OUTPUT [--qualify LABEL MODE] LABEL PATH ...`
now writes inventory **version 2**: `artifacts` preserves exact absolute native
locations; `producers` contains only explicitly requested, proven closures.
Repeat `--qualify` for tooling-units and text-scalar-units. Modes are the four Zig
optimize tags. Unknown or newly expanded dependency closures produce no metadata;
the action then retains the complete prepared-artifact identity.

`verification_producers.qualified_identity(record, label, artifact_files,
source_files, context)` returns a canonical producer dict, or `None`. The artifact
files must be the exact existing provider projection; source files must be the
coordinator's full live action-input snapshot. Context is existing `common`, with
watched `build_configuration`, `tools`, `options`, and `action_controls`. The
helper authenticates exact artifact bytes/permissions, every transitive source or
embedded input, mode, ABI, interface, and explicit absent external seed. Arbitrary
build/Guardian code and pinned Zig/library content stay in inherited contexts.
Preexisting explicitly reviewed selected providers retain their original artifact
byte projections and broad source recipes. This metadata requirement applies to
the two newly opted-in pure producers; unknown newly claimed narrowing retains
the whole-artifact fallback until its closure is reviewed.

The implementation version is distinct from its interface protocol. Source bytes
participate even when an executable happens to remain byte-identical. Missing,
changed, malformed or incompatible metadata cannot authorize narrow reuse.
Snapshots must stay open and be checked through lookup/execution/publication;
metadata is not mutation authority. A final bytes-equal ABA change still rejects
publication using the existing snapshots.

Coordinator patch requests (shared files; no worker edits):

1. Accept v1/v2 prepared artifact locations; v1 has no qualified native producers.
2. Read v2 metadata while the prepared-artifact snapshot is live. Extend
   `action_payload` with the manifest (or an equivalent enclosing provider record).
   For each nonempty explicit selector, authenticate opted-in tooling-units and
   text-scalar-units with the helper against the full source snapshot and `common`.
   If an opted-in identity is `None`, retain `common['artifacts']` unchanged.
   Otherwise use qualified identity alongside its existing artifact-file
   projection. Existing reviewed providers (memory-budget, component-support,
   component-builder and components) retain their current selected-artifact
   projections plus broad source recipes. Unknown new providers require closure
   review or whole-artifact fallback. Empty selectors continue to project `{}`.
3. Change action identity domain to v4 to distinguish the new fallback contract.
4. Add helper to `COORDINATOR_INPUTS` and its `LOADED_CODE_SHA256` to runtime
   implementation identity. Python source edits must not mix old loaded code and
   new source digests.
5. `build_verification.prepare` passes repeated `--qualify LABEL MODE` for these
   reviewed labels; obtain mode from each compiled binary's root module optimize
   setting, not a hand-maintained label version. Declare the helper and reviewed
   source/embedded files as Run file inputs to prevent a cached writer retaining
   stale metadata. `build.zig` and all arbitrary build code stay broad.
6. Register `scripts/verification_producers_test.py` in the existing verification
   self-test cohort and its declared inputs. Add coordinator tests for manifest
   metadata failures retaining whole artifacts and for source/mode/tool changes.
7. Integrate S03's native root before qualifying text-scalar-units. S10 must run
   the forced/cached edit matrix on the exact integrated inventory.

Compatibility: producer identity can be equal across compatible worktrees;
current action receipts still intentionally carry root/environment identity.
This work does not promise cross-worktree action reuse by dropping those fields.

# Configuration projection audit (C0)

The checked-in pin is `7cefed8043b05279aa8960b33ea742e728f91dfc294d08c6e48d7b4a0a8fd6fc`.
The plan's C0 observation is `c696349b2eee64e99a877a424ba3189667d9e2db5da8d04715c351455a360e92`.
Mismatch safely keeps the complete configuration identity. No pin is refreshed.

Consumers reviewed: `build.zig:addInputManifests` hashes data lists and registers
cohorts; `build_verification.zig:declared/inputLists` exports exact lists and group
contracts; `tests/input_manifest.py` expands declared file/directory recipes;
`tests/test_inputs_coverage.py` checks fixture membership; coordinator
`declared_input_lists/action_configuration` accepts only complete data syntax and
exact exported-list agreement. No list-derived command/flag/tool/runtime policy
consumer was found at C0. Arbitrary configuration code, Guardian closure and
component build wiring remain hashed broadly. The list itself stays watched even
when bytes are projected from action identity; per-group recipes and membership
still authorize affected actions.

Final qualification is coordinator-owned and must repeat this consumer review
following all S03/S04/S07/S09 registration changes and focused regressions. A
computed digest alone is not qualification. S04 requests a final explicit review;
this lane deliberately leaves the pin untouched.
