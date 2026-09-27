# Plain dictionary overwrite result

An existing RC dictionary entry with an eight-byte native plain value now
uses a captured word store after the original runtime admission checks. The
unchanged two-million-update `dict_count` improves 6.74% on QBE and 4.96% on
LLVM O3/full LTO. This retains ordinary descriptor lookup. A separately measured
repeat-lookup variant is rejected because it regresses the mixed-client control.

| Backend | Before instructions | Retained after | After/before | Accepted GC | After/GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 979,547,810 | 913,572,796 | 0.932647 | 661,305,029 | 1.381470 |
| LLVM O3/full LTO | 644,368,015 | 612,383,229 | 0.950363 | 441,034,616 | 1.388515 |

These are median-three retired user instructions on CPU11 at the unchanged
source and size. Each observation has one active cpu_core instruction event
at 100% running. Exact output is identical. The row remains above 1.3: it needs
another 5.8973% QBE / 6.3748% LLVM reduction, approximately 53.88M / 39.04M
instructions. No RSS, whole-corpus, default-transition or Stage4 acceptance
claim is made.

Before is `88f4e47728b1ad33058e847009cbaa2be91fd45f`, immutable Debug compiler
`.tmp-rc/install-dict-loop/bin/mylang`, SHA256
`25dad5001d2ddbf91c266ed19f4272849131adaedf70bb113f9c0864c2025625`.
The retained immutable Debug compiler is
`.tmp-rc/install-dict-word-find/bin/mylang`, SHA256
`4e98e65f77af32f58316c8f7524f84daef02bdd62604025548bc2db6160d4a25`.
All existing before artifacts remain untouched. This slice changes runtime C;
compiler proof and lowering source is unchanged. The measured QBE guest object
is byte-identical before and after; the linked runtime is different.

## Runtime boundary

The private helper is called only by the RC found-entry arm of
`myl_native_dictionary_write`. It returns success for identical source and
destination before checking metadata or region, as the old replacement does.
Otherwise it requires exact native PLAIN kind, size8, a registered descriptor
whose immutable flat plan has zero edges and no hooks, an empty death queue,
and the actual dictionary region no greater than current region depth.

After these checks, two fixed-width `memcpy` operations capture the complete
source before writing any destination byte. This preserves unaligned and
partially overlapping input. Every failed admission delegates to the original
`myl_rc_native_retain_replace`; cold registration, failure status, unchanged
destination on refusal and staged-source finalizer ordering stay there.
Queue state is checked for every hit, including finalizer reentry. No binding
or admission is cached by this change.

Lookup/probe validation, absent-key insertion, backing growth, actual key
ownership, regions, semantic SHARE history, O/H/LOAN handling and GC paths
remain unchanged. Native ABI, dictionary layout, descriptor registration and
allocation classes are unchanged. The [reviewed design](d9-rc-dictionary-plain-overwrite-design-2026-09-27.md)
records the wider refusal and ownership reasoning.

Native inspection confirms the QBE helper is inlined into the write function:
the admitted arm has a word load/store after metadata/queue/region predicates,
and refusal tail-jumps to the original replacement. LLVM full LTO inlines this
into `entry_run`; its disassembly retains the same checks and word store.
The whole-workload saving, normalized by the source's 1,999,000 overwrites,
is approximately33 QBE /16 LLVM instructions per hit. This normalization is
not a dynamically traced helper instruction count.

## Rejected repeat-query experiment

The optional variant used the existing private descriptor identity hint. All
operation predicates still ran on every hit. It reduced dict_count further:
893,582,857 QBE instructions (1.351242 times GC) and 594,406,289 LLVM instructions
(1.347754 times GC). Its immutable Debug compiler is
`.tmp-rc/install-dict-word-repeat/bin/mylang`, SHA256
`a07f5fad8c7ce6904303f531de0b720cc6106df2f4aca765203d8227463e5875`.

A separate 100,000-iteration control alternates float-list append readiness and
integer-dictionary replacement. QBE disassembly confirms both call sites use
the same identity-hint helper, for distinct type descriptors. Median-three
instructions are:

| Backend | Before | Ordinary find | Rejected repeat | Repeat/find |
| --- | ---: | ---: | ---: | ---: |
| QBE | 258,025,259 | 254,725,240 | 260,724,347 | 1.023551 |
| LLVM O3/full LTO | 180,372,413 | 179,572,329 | 183,871,509 | 1.023941 |

Repeat also regresses the original before runtime by1.046% /1.940%. The shared
hint's alternating identity misses explain this result at source level; no
cache-hit sampling is claimed. The repeat call and its comment change were
removed. Both immutable variants, raw observations, source snapshots and
native disassemblies remain in the archive. No new cache or layout was added.

## Validation and evidence

The native collection suite passes47 scenarios under ASan/UBSan on both the
original runtime and retained candidate. Five new scenarios cover overlap and
unaligned/same-backing inputs; no-op/sticky status and invalid-region atomicity;
older-heap/inherited-arena destinations; queued finalizers observing old bytes
and changing the original source; nested replacement, sibling deferral and
metadata rehash; opaque native-PLAIN ownership-shape count refusal; other scalar
widths/records; cold constructor registration failure; and alternating clients.

The pending-finalizer test also runs against a scratch mutant removing only
the queue predicate. It fails its expected publication-order assertion; the
original runtime and retained candidate pass. The mutant never enters production.
The initial fixtures incorrectly assumed FIFO death order and omitted explicit
plain-record metadata registration; their failures and subsequent corrections
are retained. Production code did not change to accommodate those mistakes.

Actual QBE and LLVM pass64 uncached guest assertions: dictionary loop/key/tail
controls in RC, plus the loop controls under GC stress. Twenty-eight paired
Debug executions preserve status, output, non-counter trace and balanced cleanup
for step limits, bounds, growth-budget refusal/success and arena execution.
Four embedding executions enter the loop from a real finalizer while a sibling
death remains queued; both runtimes/backends report the same deferred ordering.
The known unrelated GC timeout was not repeated.

Every full-workload counted run, including the rejected variant, agrees exactly:
2001 O acquisitions /4030 releases, 2001 H pairs, 2029 allocations/retirements,
1001 uniqueness checks and zero clones, arenas or count refusals. The mixed
performance control is uncounted; no separate mixed-counter measurement is
claimed. Full workload output is identical in all production/counting runs.

The final Debug wrapper passes12 tests (one named C suite plus11 unconditional
Zig blocks); full Guardian passes88 checks and formatting passes. An earlier
Guardian run correctly rejected an unverified SPEC claim until its wrapper used
the proper `spec:` coverage annotation. An initial LLVM build command combined
two mutually exclusive backend selectors; it was corrected to explicit LLVM3
and full LTO before timing. Raw logs preserve both failures.

Reproduce the archive integrity and receipt checks with:

```
python3 experiments/d9-rc-dictionary-word-20260927/verify.py
```

Add `--live` to check immutable compiler/native hashes against their retained
paths. The archive preserves54 instruction observations (36 full-workload,
18 mixed), eight counted full-workload runs, manifests, commands, exact sources,
native inspection, controls, sanitizer/Guardian logs and rejected experiments.
