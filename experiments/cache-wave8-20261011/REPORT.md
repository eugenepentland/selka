# Wave 8 — Shared ordinary project test successes

Implementation branch: `codex/selka-cache-wave8`, based on `eb3c86a33`.
The base already contains main `1d202d41b`; no merge was needed. The primary
integration checkout was left untouched.

Native `mylang test` can now reuse eligible successes between worktrees with
separate private caches. Opt in with `--shared-cache-dir DIR` or set
`MYLANG_TEST_SHARED_CACHE` to the same directory for every participating worktree.
Frontend state, mutable indexes, executables and whole-report manifests remain
private. Installation and native use require no Python.

The separate portable identity binds freshly checked reachable code, proven
project-relative source locations, compiler/runtime/toolchain/CPU/planner
identity, execution controls, relevant environment, configuration and cases.
Literal strings remain exact. Embedded input values remain in the checked IR.
Only source locations proven inside the project are normalized.

The store uses `DIR/native-tests-v1`, a checked format marker and bounded,
checksummed success records. Publication is atomic under a short process lock;
checking, compilation and execution hold no shared-store lock. Missing, corrupt,
partial, oversized, symlink and special-file receipts cannot supply a success.
An unusable explicitly configured store is an error. `--force` invalidates and
reruns; `--no-cache` suppresses shared reads and publication, including in workers.

## Qualification

- Final compiler installation passed all 14 build steps and Guardian's 88 checks
  (`install-final.log`).
- Twelve permanent native cross-root tests passed (`portable-final.log`). They
  make 46 direct CLI calls, plus directory workers, using two actual project
  roots and distinct private caches. Receiving private caches are removed before
  transport assertions; reports must identify `shared-receipt-hit` and
  `portable-reachable-ir`.
- The native matrix covers dependency edit/failure/revert with unrelated reuse,
  modes, relevant environment, force/facts/leaks/no-cache, cases/configuration,
  embedded bytes, excluded effects/introspection, exact literal paths, escaping
  symlinks, directory workers, corrupt records, concurrent publishers, and
  invalid shared format before private-manifest replay.
- Three direct portable-key tests passed (`focused-portable-keys-final.log`),
  along with the existing local-settings regression (`focused-local-settings.log`).
- Three CLI/options/worker tests passed (`cli-shared-focused-rerun.log`).
- Two storage tests passed (`store-hardened-green.log`), including permanent lock
  ownership, exact records, partial publication, bounds, symlinks, FIFO refusal,
  and preserving unknown formats.

- Complete repository verification passed: all 42 groups selected, 126/126 gate
  build steps succeeded, including formatting, documentation and application
  recovery. Input snapshots remained stable (`verification.log`,
  `verification-cold.json`).
- Unchanged lookup reused 31 groups, including `application_cache`, and selected
  the 11 freshness-required groups. This duplicate run was deliberately cancelled
  while queued behind another long gate, after the complete gate had passed.
  It acquired no build or gate admission. `verification-warm.json` therefore
  records cancellation status 143, **not a passing warm run**;
  `verification-warm-lookup.json` records the reason and observed selection.
  No warm timing or isolated performance claim is made.

`source-hashes.json` records the 16 changed source/documentation inputs and final
gate compiler SHA-256 `18aac77b0843236b95e93dbc7ef7c8214f7992fc4e58aed4f879e124903e1ee8`.
Gate preparation included the final embedded documentation; the earlier focused
compiler hash is retained separately in that record.
`qualification-summary.json` records the native matrix command, hashes and
scope. Earlier logs retain corrected build and fixture iterations; they are not
the final passing evidence.

## Boundaries

This wave qualifies ordinary zero-argument Boolean tests under the legacy
property policy, with effects limited to managed allocation and mutation.
Generated properties, provider overlays, external native providers/links,
identity introspection, observable error traces, Host/environment authority,
fact verification, leak checking and loader overrides do not share successes.
Unsupported or unknown portability executes normally. Sources, configuration,
policy, cases and assets must remain inside the project root. An unrelated
external source in a merged checked program can conservatively prevent sharing.

Compiler changes or incompatible tools/settings/environment can invalidate all
receipts. Source positions and logical file names remain significant. Existing
private-cache hits take precedence, so enabling sharing does not export old
private results immediately; a forced successful run can populate the store.

Use a stable dedicated local directory with trusted cooperative writers.
Checksums detect damage; they do not authenticate an untrusted writer. Receipts
are disposable, with no power-loss durability or distributed-cache claim.
The existing Python evidence collector does not collect `native-tests-v1`;
clear that namespace only while its users are stopped, preserving active lock
ownership. Waves 9 and 10 remain separate follow-ups for more shared compiler
artifacts and lower warm validation/coordination overhead.
