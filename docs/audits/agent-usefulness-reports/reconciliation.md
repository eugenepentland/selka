# Lineage reconciliation — the accepted integration baseline

Status: **recorded**. This is the step-1 deliverable: one integration worktree
holding the accepted combination of the two lineages, with the commit and the
compiler identity pinned.

## The two lineages

Both grew from `b8f6ec3f1178f12971e7dcb1d2255ab8c055b024`, the W0 baseline commit.

| Lineage | Where | Tip |
| --- | --- | --- |
| agent-usefulness | `.worktrees/agent-usefulness`, branch `agent-usefulness/base` | `99afe619` |
| main checkout | `/home/epentland/ai/canopy/mylang`, uncommitted working tree | snapshot `main-wip-20260920` (`da8800dc`) |

`99afe619`'s parent is `ed6148cf`, a snapshot of the main checkout's working tree
taken at 17:35 on 2026-09-20 — so the two lineages share far more than the base
commit, and everything before that point is common. A second session was editing
the main checkout while it was snapshotted, so `main-wip-20260920` is a
**point-in-time capture, not a frozen branch**; a later reconciliation would need
a fresh snapshot. At the time of writing the main checkout had been quiet for
several hours and its only file changed after the snapshot was
`src/invoke_command.zig`.

## Accepted baseline

| Fact | Value |
| --- | --- |
| Integration worktree | `.worktrees/integration`, branch `integration/agent-usefulness` |
| Accepted commit | `3c76c13d` — "fix: stop native-test-graph recursing into copies of itself, and harden the ABI fact" |
| Its parent | `99afe619` |
| Compiler identity (`compiler_sha256`) | `81a8a7125aa1d0fc57aa3e767dce6e196b159ffb3fa18c3b61a4217b77faf93b` |
| `zig-out/bin/mylang` sha256 (prefix) | `7e2a81139b7c85d2` |
| Zig | `0.17.0-dev.1683+5ceec001b` (`.zigversion`) |
| Native ABI tag | `mylang-qbe-native-v6` |

The base is the agent-usefulness lineage, because it is the side that carries a
whole-tree-verified gate and the aggregate-argument ABI fix. The accepted commit
adds the recursion fix and the ABI hardening on top of it.

## What was adopted from the main lineage, and what was rejected

Adopted:

* `experiments/llvm-backend/**` — the drop-in LLVM arm for the `qbe` tool
  (`qbe_llvm.py`), the only piece of the main lineage with no counterpart here,
  restored with `git checkout main-wip-20260920 -- experiments/llvm-backend`.
  It is what makes a two-backend boundary matrix possible.
* The `str`-as-a-result codec prototype was reviewed and re-implemented here
  rather than merged: its runtime half (`kind == 5` in `co_write`) was real work,
  but its compiler rule was name-based (`record.name == "str"`) while its host
  rule was shape-based, so the two disagreed on a user `list[u32]`; and porting
  its `qbe_codecs_runtime.c` hunk without its `qbe_build_templates.zig` pair would
  have made every codec call fail, because `co_capacity` is a zero-initialised
  static. This tree carries one rule, decided by name, with a test that a
  structurally identical `List<u32>` is not text.
* Three `mylang context` behaviours: the lexically recovered declaration on the
  parse-failed path, the `InvalidBaseline` arm, and the `navigation_partial`
  candidates extraction.

Rejected, with the reason:

* **main's native ABI handling.** `main-wip-20260920` has **no aggregate-argument
  fix**: its `qbe.zig`, `qbe_build_codecs.zig`, `qbe_build_embed.zig`,
  `qbe_build_wire.zig`, `qbe_build_dispatch.zig` and `native_wire.zig` are
  byte-identical to the base, and its `qbe_build_shapes.zig` keeps the pre-fix
  `size > 4096` guess while the emitter passes copyable aggregates by address.
  That is the defect measured in `aggref-abi.md` (`test_one` SEGV, `test_sum`
  6 → 34). This tree records the crossing once, in `qbe_wire.byAddress`, and
  reads it from the manifest.
* **main's `mylang invoke`.** A single `invoke_command.zig` against this tree's
  split contract/execution/schema implementation. main's envelope carries no
  structured trap, no generated JSON Schema and no machine-readable failure
  kind, and its own spec bullet defers the returned-`Result.Err` case as
  unreachable; this tree executes and tests it.
* **main's parser, declaration-hint and classifier files.** `git diff ed6148cf
  main-wip-20260920 -- src/parser.zig velocity/friction/classifier.json
  tests/parser_hints.py src/declaration_hints_test.zig` is empty: main added
  nothing there, and this tree's 19-hint table is a strict superset of the four
  rows both sides share.
* **main's staleness mechanism, budget ladder, `minimum_context_bytes = 1536` and
  two-flag parser** in `mylang context`. This tree's `sourcesChanged` re-reads
  through the provider the project was loaded from and satisfies
  `CONTEXT-CONFIRM-1`, which main's does not; and this tree accepts the
  space-separated forms of all four context flags, not two.
* **main's documentation slugs.** main uses `invoke-command` →
  `docs/tooling/invoke.md`; this tree uses `native-invocation` →
  `docs/tooling/invocation.md`. One page is kept, so nothing had to be repointed.

## Leftovers removed

* Four editor leftovers captured by the branch's base snapshot and present on
  both sides — `src/bytecode_inline.zig.orig`, `src/bytecode_inline_test.zig.orig`,
  `src/qbe.zig.orig`, `src/qbe_test.zig.orig` — lived inside `src/`, where the
  build's asset-identity scan reads them. Deleted.
* `/tmp/.pending` held 1007 session staging directories left by the recursion
  incident; removed. See `recursion-fix.md`.
* `experiments/agent-usefulness-e1/zig-global-cache/` (43 MB) was created inside
  the worktree by the E1 pilot harness; it is ignored by that directory's
  `.gitignore`, was never tracked, and has been deleted.
