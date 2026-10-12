# A02 combined Support7 runtime preview handoff

- Worker base: `72967fc51e1a2285b535956b6e8d60ce00ea5bbb`.
- Runtime input base: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
- Owned files changed: this evidence directory only. No production changes.
- Change: archive all owner retirement drafts and assemble a separate combined
  runtime without the legacy/owned selector; keep all previous evidence intact.
- Validation: one shared build lease, ticket 957; native capacity 13/13,
  owned ABI/copy/mutation/drop 1/1, absent count-member negative, no active legacy
  source helpers or linked legacy symbols. Exact commands/statuses are in
  `results.json`; complete linked symbol tables are `capacity.nm` and `owned.nm`.
- Harness correction: initial source inventory counted poison declarations;
  preserve initial report, classify those declarations explicitly, retain the
  original passing binaries and runs. No source changes or relabeled reruns.
- Source/compiler/binary/patch hashes: `inputs.json` and `results.json`.
- Scratch assembled source:
  `.tmp/memory-closeout/A02/retirement-combined-support7/native/core_rt.c`.
- Shared requests: A09 should test its counter-source anchors on combined hash
  `ca2ded335995f2d6f76c9900b172d74c20800cbe2885af4f3d39bf72a1eb7ca1`;
  A01 retains task behavior/stress qualification. Earlier A02 fixture migration
  patches remain under `../integration-c749ad5a9/` for coordinator C3 activation.
- Unresolved qualification: C2 promotion, actual production retirement, generated
  LLVM/ABI/cache tests, installed component packaging, affected five-mode guest
  tests, task stress and complete final verification must use their actual final
  artifacts. This evidence alone cannot satisfy milestone 3.
