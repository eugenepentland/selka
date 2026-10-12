# Refreshed A02 C3 runtime patch — prepared only

Prepared against integration `c749ad5a9d2dfef5d5c4d7b9de2a30f03029999f`. Neither production runtime file is changed. Apply after coordinator C2 approval with the paired runtime, compiler, counter, cache and command changes. This report does not claim milestone3 or a retired installed package.

`runtime-retirement.patch` is byte-identical to A02's previously reviewed nested-extension refresh (SHA256 `0e41a276536b3599d6ad01f5029487a524d93eee68636de825eea4540b972a65`). Both current integration source hashes match that preview exactly. The fresh manifest pins the current base, before/after files, patch and successful apply check. A scratch application generated the native candidate; production and historical controls were untouched.

## Selected ABI and preserved behavior

The patch selects the existing owned32-byte block layout: kind offset0, length8, capacity16, layout24. There is no count member. Static leaves keep the storage-kind bit; ordinary heap allocation and growth remain allowed.

Seventeen owned function bodies are byte-identical after selecting the existing owned branches. `preserved-owned-bodies.json` pins capacity arithmetic, list allocation/growth/copy, physical identity, rotate/reverse, direct destruction, box-shell cleanup, independent octet/buffer copies and buffer growth. The patch preserves the capacity overflow fixes, deep-copy adapters and all qualified list helper paths; it adds no copying or shrink policy.

The direct-child visitor, `core_dict_children`, `core_layout_release` and `layout_release` remain for owned child cleanup. Their names do not represent memory reference counting. Layout reference counts count child pointers; allocator live counters detect leaks. `myl_core_buffer_snapshot` remains an independent byte copy at the native boundary, not shared/COW storage. Task pending-work synchronization is outside these two files and is preserved.

A07 confirmed the existing emitter/descriptor/owned-copy boundary: the selected ABI is unchanged, `core_owned_copy.c` remains independent recursive copying, and the planned OWN1 external marker concerns artifact provenance rather than C layout.

## Fresh focused validation

The scratch runtime combines A02's two candidates with A05's current four runtime patches and unchanged peer runtime files at the recorded integration revision. Its SHA256 is `041d616cf7c9907e3b2a576c2555359264457960d7e3cd58fa385646b46a70ef`, matching A05's independently tested durable preview.

- Original capacity fixture:13/13 scenarios pass, including preserved growth and all negative length/element-size, header-rounding, multiplication, doubling, terminated-text, list-copy length and memory-budget boundaries.
- New owned native fixture passes header offset/size assertions, independent managed-child copy, in-place order-preserving rotate/reverse, removed-child transfer, zero-sized elements, box-shell transfer and independent buffer-copy checks. The final native live-block count is zero.
- Both binaries contain no legacy retain/release/share/free-block or count-operation symbols. Full `nm` output is retained.
- `offsetof(myl_block, count)` fails compilation as required; exact command and diagnostic are in `count-member-negative.json`.
- A05's separate commit `35a4aa840` qualifies durable short writes, bounds, fsync/readdir errors, SIGKILL, concurrent writers and leases on this same combined runtime. That suite was not redundantly rerun here.

The native harness was run under one shared build lease, ticket954. The absent-count-member compile was under ticket955. `native-results.json` records exact source/compiler/binary identities and commands. The harness intentionally still defines MYL_ZERO_RC for unchanged peer runtime branches in core_text, core_values and core_tasks; the remaining lines are inventoried. This is not a selector-free combined runtime and not generated-guest, cache, package or full-gate qualification. A04 has supplied separate text/values drafts, and A01 owns task retirement.

## Coupled activation and migration requests

- A09: remove exactly five obsolete textual hooks anchored on count_retain, count_release, myl_core_retain_slow, count_release_shared and child->count shared marking. Preserve allocation, copy, reallocation, direct destruction, live/peak instrumentation and reserved zero telemetry fields. The direct-drop `release_unique` category remains valid. A09 is qualifying the paired draft under `A09/retirement/c3-counter-runtime/`.
- A07/root: select owned LLVM layout, emission, cleanup and deep-copy paths, retire count instructions and slowcalls, and use the current direct-destructor ABI. No immutable bootstrap input is changed by this patch.
- A05: apply its dictionary/sort/io/durable counterpart; preserve direct layout callbacks. A04 owns text/value branch removals; A01 owns tasks and must preserve synchronization counters and join semantics.
- A08/A10: invalidate RC artifacts and receipts, select owned ordinary commands, reject retired flags, and qualify installed components separately.
- `capacity-test-migration.patch`: remove the redundant RC ABI test invocation and native selector options, retaining all13 scenarios. The C fixture is unchanged.
- `guest-test-migration.patch`: remove only the experimental flag from A02 list-method, mutable-call, scalar-child and public-constructor registered tests. Preserve all five build modes, negative refusals, RC-zero checks, live-byte checks and structural audits. This patch is based on A02 commit `eb38385d8be205e8604f7b8433778f4a30dc949d` because public-constructor tests were integrated after the runtime base. A10 was notified to avoid duplicate migration edits.

After C3 activation, rerun registered filters `A02 capacity`, `zero RC A02 list methods`, `zero RC A02 interior mut calls`, `zero RC A02 scalar child writes`, and `zero RC A02 public constructors` on the exact installed owned compiler. Run the listed guest assertions through ordinary commands without an experimental flag. Then the coordinator runs the full registered verification and required Guardian gate; these focused preview results cannot replace that gate.
