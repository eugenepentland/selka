# D9 WP-4: direct retain of registered plain bytes

This runtime change removes generic ownership traversal from physical retain when
the registered native binding proves that the value has no ownership leaves or
unique obligations. On the unchanged full-size `alloc_churn` workload it reduces
retired instructions by 40.73% on QBE and 41.12% on LLVM. Output and every ownership
counter remain identical. The remaining cost is still 4.44 times accepted GC on
QBE and 4.70 times on LLVM; this is not WP-4 acceptance.

## Admission and preserved behavior

Only `myl_rc_native_retain` changes. An existing immutable native binding must
have `flat.count == 0`. The flat-plan builder checks native types as well as the
sidecar shape: raw unique resources cannot become copyable merely because their
counted shape is `NONE`. It also rejects descriptor hooks, held leaves and ordinary
pointer leaves. No registration or admission rules change.

The fast arm additionally requires nonzero size, disjoint input/output ranges
and an empty pending-death queue. Range comparison uses unsigned address
subtraction without an overflowing end-address addition. Once admitted, a valid
destination region copies the exact bytes. Invalid regions clear the output and
record `MYL_RC_REGION_ERROR`, matching retain's existing empty-output contract.
This deliberately differs from replacement's unchanged-output failure contract.
There is no allocation or count event to remove or bypass.

Cold metadata, zero-size values, same-address/overlapping ranges, queued finalizers
and all ownership-bearing layouts retain the original path. A cold registration
refusal still zeros the requested output extent. A same-address retain remains an
internal invariant failure. A queued finalizer still runs after the source has
been copied; it can mutate the source without changing the retained value. The
existing sticky failure status and native heap/custom allocator APIs are untouched.
No compiler emission, allocator ABI, lifetime shape or public ABI changes occur.

The parent independently reviewed the 18-line production diff and found no
blocker. The earlier plain replacement optimization is already in both arms;
these measurements isolate retain.

## Immutable controls and full-size measurements

The cumulative control is source
`e926d1e13bf61ae3125102b46309225ca963a38d`, real-merged locally as
`8c399ac010c8df7eaf5b2a9cd999e4e625706097`. Its Debug compiler is
`d9-rc-integration/.tmp-rc/install-field-frame-span/bin/mylang`, SHA-256
`aee67f9abfe65b61a960eaf3390082d9c338553e5b086ad1cfc7723b933ab475`.
The immutable candidate is
`d9-rc-mut-argument-astra/.tmp-mut-argument/retain-candidate/bin/mylang`, SHA-256
`4a3350d56d9ed252df75eb2e8b8309710bd615a96d5b16886c928f3852aeff7a`.
Subsequent edits only correct tests and write evidence; the measured production
source is unchanged.

The exact source is `bench/parity/micro/alloc_churn.my`, SHA-256
`d4a37e7fa38f210b45b9cc22c2fb8d88794c9380cdda43808222bf50c7dd78ee`.
It creates one million lists with sixteen integer appends each. Every run prints
`999739` followed by a newline. Runs use CPU 2, interleaved before/after order and
median three retired-instruction samples. LLVM manifests confirm actual LLVM,
optimization 3 and full LTO. Both compilers were built in Debug through build slots.

| Backend | Before instructions | After instructions | After/before |
| --- | ---: | ---: | ---: |
| QBE | 22,914,232,852 | 13,580,231,875 | 0.592655 |
| LLVM | 15,569,232,938 | 9,167,232,485 | 0.588804 |

Median cycles decrease from 4,885,069,890 to 2,813,433,493 on QBE and from
3,000,427,952 to 1,830,146,241 on LLVM. Both arms and backends have exactly four
million allocations and retirements, one million owner acquisitions, five million
owner releases, one million hold acquisitions/releases and sixteen million
uniqueness checks. There are no arena allocations, clones or count refusals.
All samples and build identities are retained, including their small variation.

A separate interleaved median-three residual comparison uses the immutable
accepted-GC corpus binaries, not a rebuilt or adjusted GC baseline:

| Backend | Accepted GC instructions | Candidate instructions | RC/GC |
| --- | ---: | ---: | ---: |
| QBE | 3,060,153,718 | 13,572,232,047 | 4.435147 |
| LLVM | 1,950,409,990 | 9,167,232,442 | 4.700157 |

The candidate's residual profile still includes descriptor lookup, uniqueness,
insertion and allocation. QBE samples attribute about 17.5% to descriptor lookup,
9.4% to shape resolution and 7.7% to local uniqueness, compared with 1.8% to slab
take and less than 0.6% to retirement. LLVM inlines more into the entry function
(42.7%); allocation is about 8.1%, retain 6.2%, slab take 2.9% and retirement 1.0%.
These short profiles are approximate attribution, not acceptance measurements.
The independent compiler proof that removes repeated fresh-root uniqueness must
be composed and measured before choosing an allocator ABI change. No additional
runtime fast path is bundled here.

## Validation

- Four new production C scenarios bring the collection harness to 39 cases.
  Both the unchanged old retain implementation and this candidate pass all 39
  with ASan and UBSan. Controls check adjacent slots in both directions, exact
  invalid-region bytes/status, overlapping region refusal, nested arena regions,
  registered wide plain storage at the byte budget, cold metadata failure,
  zero-size values, same-address invariant failure, queued finalizer ordering,
  O/H count-limit rollback and copying an ownerless held value.
- The focused production wrapper passes 12 tests. The other production sanitizer
  suites pass: contract 22, live holds 12, arenas 10, loan 9, semantic history 35,
  and stats/execution success, trap and fast-exit controls.
- Sixteen paired standalone rows cover both compilers, both actual backends and
  GC stress/counting RC for two drivers. Four new assertions cover mixed plain
  record bits, append across backing growth, an older receiver inside nested
  arenas and zero-size logical elements. The existing broad driver adds 54
  assertions per row. Output and every before/after RC count match. New-driver
  allocations/retirements are 27/27; the broad driver has 1,464/1,464.
- Guardian's unchanged 88 checks pass in the Debug install and an explicit
  whole-tree run. Parent owns the
  serialized full gate and Guardian feedback; this slice changes no ratchet.

## Corrected fixture receipts and separate metadata observation

The first legacy comparison driver did not replace an implicitly added C source,
so it reran the candidate. That receipt is explicitly retained as invalid legacy
evidence. The corrected driver resolves the complete source closure, substitutes
`native_rc_values.c` from `8c399ac0`, records every source hash and prevents the
helper from adding the current file again.

That real comparison exposed two defects in the new test's custom wide-array
metadata. Initially it supplied only `element`, while the generic native unique
walker reads `fields[0]`, causing an ASan null read. Adding the native field alone
then exposed an underspecified sidecar `NONE` shape that had not reserved enough
inline traversal depth. The final fixture supplies consistent native fields and
element metadata plus an explicit array sidecar. Both old and new implementations
then pass all 39 cases. Both rejected receipts are preserved; neither was a
production runtime regression and neither was hidden by weakening the assertion.

Separately, generated native array descriptors currently use `fields[0]` with a
null `element`, while flat admission reads `element`. Such generated arrays
conservatively refuse the flat optimization. The new guest array test therefore
also exercises fallback; this slice does not claim to accelerate all generated
plain arrays. Any metadata optimization needs its own review and measurements.

`experiments/d9-rc-plain-retain-20260927/` contains reproduction scripts, raw
compressed measurements and manifests, source identities, validation logs,
rejected receipts, native retain disassemblies and residual profiles. Private
compiler/binary/cache artifacts remain outside version control.
