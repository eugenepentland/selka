# S3 exit report preparation — not qualified

This coordinator draft assembles the report while application repairs finish.
S3-A and S3-X are still pending. No statement here authorizes S4.

## Final qualification record to fill

| Requirement | Final integrated receipt | Result |
|---|---|---|
| Qualified source commit and explicit old/Core oracle hashes | Pending | Pending |
| A package source, qualification and integration commits | Pending | Pending |
| Uncontended installed Core rebuild | Pending | Must be <=10s |
| Held Core suite and maximum shard/RSS | Pending | Must be <300s; each shard <90s and <=2.5GiB |
| Ordinary debug/release full language sweep | Pending | 1518 per mode, no mismatches/refusals |
| Full leak/verify language sweep | Pending | Status, stdout and diagnostics checked |
| Full old gate: test/test-qbe/test-qbe-build/fmt-check | Pending | All command statuses and build summaries checked |
| Nine-kind strict 200-source fuzz matrix | Pending | 1800 sources, 25800 comparisons |
| Supplementary private split-key 200-source fuzz | Pending | 200 sources, 3000 comparisons |
| All40, seven interleaved rounds, CPU10, sizes4096/64 | Pending | Every row <=1.10 old and Zig ReleaseSafe |
| Natural-loop count-store/load/check and opaque-call audit | Pending | Preserve timed/setup/parent/callee scopes |
| Asset-preserving four-corpus coverage | Pending | All four statuses, every remaining reason |
| Exact S4/retired-arena inventory | Pending | 9 S4 and118 retired-arena names |
| Frozen IR, formats, first64 aggregate positions, main branch | Pending | Unchanged protected contracts |

## Completed implementation and source authority

The requested foundation is `92590700cb0bf5e4dc19cc1f0c836c3a41693f64`.
Wave A stopped for review at `3d0bfd23b73b3a90bd6ce8af4caa8fcba18a51b2`.
The user subsequently authorized continuous B/C/X and clarified the rebuild
rule: only an uncontended `zig build core` rebuild is gated at10seconds.
Bootstrap `8918de74720f0832dabe5802c110cd0518324cf5` changes the default core
shards from4 to8. The qualification suite uses more shards to keep each below
90seconds; the final measured value belongs in the table above.

Package identities and earlier qualification receipts are collected in
`exit-report-preparation.md`. Those historical results do not replace the
fresh final-source exit checks. In particular, the C/M full language receipt
has1518 matches per mode with no mismatches/refusals, but final A/X still owe
their own receipts.

S3-0 freezes three pointer types, nine new operations and trusted runtime-C
linkage. D2 rejects dictionary-view storage and annotation at the declaration,
indexes immediate consumers once and lowers keys membership to a hash probe.
The impossible view-held tests are retired; permitted explicit snapshots and
immediate operations remain tested. No other package changes tests/lang.

T1 implements the remaining text methods with the old grammar and scalar/octet
index distinctions. T2 ports the old Zig float-text algorithm into independent
Core objects and adds mutable bytes, blobs, parsing and formatting. M implements
numeric operations, structural recursive equality/hashing/rendering, aggregate
operations and captured-place publication in source argument order.

C implements capability authority, scoped grants, provider adapters, owned
resources, deterministic stand-ins and copied Host transport. The property
runner matches complete old reports, forks every actual trial and resets
stand-ins. Shared ENV correction `4747ad071803589f99137d2ecf7641203120e09f`
uses grants rather than opaque provider context. Its controlled three-name and
A/B-allowlist probes qualify both cores; the old accidental answer1 is retained
only as rejected historical evidence.

The captured-place probe follows COW-MUT-ARGUMENT-1: rows remain[[1],[2]] and
ticks becomes1. A later whole-root mut argument invalidates earlier interior
publication even if its callee writes only a scalar. All eight formerly refused
mutation cases execute. Two narrower interior-write refusals remain named below.

The corrected old oracle has SHA256
`d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`, with QBE
`b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
Its qualified source is `65036fe792ef540392d0eb00c41c9ec71c7b2c82`. The final
report must record the actual frozen executable pair and source comparison,
including whether a fresh old install changes the executable identity.

## Float-text cold cost and cache

The first program with fresh runtime-object and Zig global caches takes
3.116963197942823seconds, including0.9655902560334653seconds for the formatter
unit. A distinct next source reuses the object in0.11394167505204678seconds,
with zero formatter compilations. A simulated Zig-version suffix invalidates
the object; that run takes1.0238852428738028seconds, including
0.8814565688371658seconds for the unit. It is not a second installed toolchain.

The recorded executing Zig is `0.17.0-dev.1683+5ceec001b`; the object key is
`714db03fe3fa391c9b5a852fe8b845a55a788be7cbede44ff2b90ac1dbe77348`.
The Blake3 fingerprint includes its domain, executing Zig version, every
target/build option and each complete runtime helper's content digest, separated
by NULs. Options are x86_64-linux-gnu, baseline CPU, ReleaseFast, PIC, disabled
stack check/protector and libc. Unique partial files and atomic publication
protect concurrent compilation; per-program staging reuses the completed
object. Integer-only builds do not pay the float unit. Exact helper SHA256s and
commands are in `wave-b/s3-t2/float-cold-final/{summary,runtime-cache-key}.json`.

## Final performance and count audit

Insert the complete40-row table from the final retained receipt. Each cell pairs
4096/64, with cycles in its registry unit, all four implementations and both
ratios. Checksums, status, counter availability and raw samples must qualify.
Preserve the two retained combined-source size64 misses and the repeat; only
the final measured repaired source may be labeled passing.

Insert a separate40-row static count table, explaining that tagged caller
stores, constant-one initialization/release stores, dynamic reads and saturated
checks differ. Natural innermost loops, exclusive parent blocks, timed nonloop
blocks, pre-timing setup and paths aborting before the stop clock are separate.
Runtime/callee count effects and untagged allocation header stores are unknown,
not dynamically zero. Include all LLVM and assembly details in evidence.

## Coverage and exact exclusions

The inherited S2 baseline is3185/3627 per-corpus qualified-name sums. D2/Wave A
is3213/3595; T1 is3324/3595; T2 is3456/3595; C is3589/3595. D2 removes46names
(6 formerly accepted), adds14 accepted names and admits20 retained names;
there is no accepted-name regression. The ordinary conformance denominator
changes1540to1518 after retiring stored views and adding immediate membership.

The asset-preserving tool preparation separately gives3633/3639 per-corpus and
3410/3416 globally deduplicated names. Restoring original embedded assets clears
four scratch-copy frontend errors. The final report must use fresh final-source
coverage and retain this denominator/context explanation.

The six remaining bodyless declarations are extern abs, floor and
main::runtime_bench_now, plus Host io::length, io::byte and io::put. They yield
11raw occurrences across imports. Linked call sites execute; declarations have
no Core body. Seven flattened example module contexts fail E_MODULE_NAME:
invoice/{catalog,money,pricing}, interface-files/shop/{billing,money},
input-values/config/values and modules/shared/units. These are failures of that
coverage context, not proof that every valid module-headed program is refused.

Nine execution exclusions in migrated/propagation depend on user modules; their
exact names, including truncated spellings, must be reproduced from the final
inventory. The118 retired arena cases comprise five whole modules and85
individual cases. Link the complete127-name final manifest; do not replace it
with a module-only list.

## Remaining limits

Combine the exact admission/runtime/frontend/target boundaries in
`exit-report-preparation.md` and `exit-limit-audit.md` into the final report and
design-note exit record. Distinguish actual refusals, inherited budgets and
optimization fallbacks. Keyed sort's eight-field ceiling is a refusal; private
cursor/character fusion eligibility and stack-promotion budgets have fallbacks.
Preserve the distinction between source scalar extern and internal runtime
Option ABI, between managed classes and value records, and between existing
merged module-source checking and S4's persisted per-module/incremental work.

## Final decision

After all required receipts qualify, record the final source/evidence commit,
Guardian feedback commit, unchanged main/S2 references and absence of pushes.
Supersede the historical Wave B HOLD outstanding list. Stop for the user's
explicit S4 go/stop decision; do not start S4 from this preparation.
