# C2 documentation and C3 runtime patch refresh — held, not applied

Prepared against integration `c749ad5a9d2dfef5d5c4d7b9de2a30f03029999f`.
All five A05 runtime inputs and both durable fixture inputs are byte-identical to
the earlier reviewed preview. This directory preserves a new input manifest and
fresh native reruns; it does not replace earlier evidence or claim retirement.
No active production file was changed to create it.

## Stage-specific inputs

- **C2 only:** `C2-held-docs.patch` packages the four previously reviewed held
  pages, with exact original/proposed hashes in `C2-docs-manifest.json`. These are
  the changes from `443478167`, `d4d6c50f2` and `6a0516d8e`; apply this refreshed
  patch or those commits, not both. They teach moves, borrows, explicit copies,
  scoped tasks and the conservative whole-root mutable loan boundary. The prior
  Support5 doctest receipts remain historical; rerun on the common C1 compiler
  and ordinary C2 commands. Thirteen owned library modules already match the
  integrated tree byte-for-byte (`stdlib-status.json`); no library mode selector
  or RC/COW claim remains in these modules.
- **C3 only:** `runtime-retirement.patch` removes active RC branches from
  `core_dict.c`, `core_sort.c`, `core_io.c` and `core_durable.c`. `core_host.c`
  requires no RC deletion; its exact unchanged identity is recorded.
- **C3 coupled fixture:** `fixture-retirement.patch` converts the durable native
  fixture to explicit transfer/drop and retains all assertions in one owned test.
  It touches coordinator-owned `durable_fixture.c` and reserved `durable_test.zig`;
  root must apply them together with the unconditional owned root runtime.

`apply-check.json` records successful textual application checks for all three
patches. `structural-audit.json` records absence of the selected RC/COW helpers
and selectors in the five candidate runtime sources, and retained destruction,
provider and OS resource contracts. This limited source inventory is not a final
preprocessed-runtime, generated-LLVM or installed-package audit.

## Preserved contracts and owner coordination

Dictionary key/value destructor callbacks still use `layout_release` and
`core_layout_release`; those names mean direct destruction in the owned runtime.
Keep the child visitor and dictionary visitor declarations. Scalar-only
`myl_core_dict_copy` returns independent storage and rejects managed descriptors;
managed dictionary copies use compiler-directed explicit child copies through
`core_dict_copy_storage`. Tombstones and entry metadata cleanup remain intact.

Remove `myl_core_s2_sort_keyed`, the old borrowed shallow-copy helper. A07 must
replace its mode selection in Core `build.zig` with `myl_core_owned_sort_keyed`:
two independently owned arguments, ownership mask 3, transferred result. The
owned helper moves values through permutation cycles and directly drops keys.
Its exact registry contract remains unchanged.

Root capabilities own their provider, dependent capabilities own scope bytes and
borrow their parent, and resources borrow their checked provider. Keep
`myl_core_owned_file_scope_end`, `myl_core_owned_cap_scope_end` and the no-op
`myl_core_provider_keepalive` unchanged. Removing `core_io_retain` and its calls
does not remove OS/provider handle completion or release callbacks. Directory
flock ownership, atomic publication/fsync and crash cleanup are unchanged.
A07 and A02 received these dependencies; no new runtime helper is admitted.

## Fresh native preview results

Both previews ran the complete existing durable native fixture, including partial
writes, bounded reads, permissions, failed publication, hidden-directory entries,
partial readdir refusal, actual SIGKILL before/after publication, competing writers
and lock recovery. Both exit 0 with empty stderr under leak checking and no legacy
retain/release/share symbols.

| Preview | Runtime SHA256 | Binary SHA256 |
| --- | --- | --- |
| A05 patch plus current owned runtime | `5ba01cd1b3869181b7d4949bdadfce19cc490297f86713b3b1ca5b4b0b1f809e` | `099f0e6687a11ebc35de404aabe6fcdc02a9d085ef4e9356ea1778c6a1a9c5bc` |
| A05 plus A02 latest nested-extension retirement patch | `041d616cf7c9907e3b2a576c2555359264457960d7e3cd58fa385646b46a70ef` | `6ed0c3049cd1bae4c83256383df95a160ee85f7c31522fc1cb12f5aedd019128` |

Raw source/binary/compiler hashes, native commands and outputs are in
`native-preview-result.json` and `combined-A02-preview-result.json`.
`combined-A02-apply.json` pins A02's exact patch. These previews still define
`MYL_ZERO_RC` for the other owners' unretired runtime files. They qualify native
compatibility of this prepared deletion, not a selector-free installed runtime,
source lifetime checking, the 120-export matrix or a complete gate.

Reproduce the A05 preparation from the worker checkout with the pinned source
checkout and a new evidence/output suffix:

```sh
python3 -B experiments/memory-closeout-20261012/A05/retirement/prepare.py \
  --source-root /path/to/integration \
  --output experiments/memory-closeout-20261012/A05/retirement-NEW \
  --preview .tmp/memory-closeout/A05/retirement-NEW
python3 -B experiments/memory-closeout-20261012/A05/native_runtime.py \
  --source-root /path/to/integration \
  --runtime-overlay "$PWD/.tmp/memory-closeout/A05/retirement-NEW" \
  --zig "$ZIG" --output "$PWD/.tmp/memory-closeout/A05/retirement-NEW/native"
```

The native harness owns build admission; do not wrap it in another lease. After
C2 qualification and coordinated actual C3 application, rerun the registered
native fixture without the retired define, all affected five-mode public APIs and
guest resources, owned keyed sorting, ABI/cache/package audits and the full gate.
Final 120-export qualification still awaits the common compiler.
