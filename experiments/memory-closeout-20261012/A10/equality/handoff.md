# Parked equality feature — not integrated

The coordinator changed the endpoint to the full verification gate on 12 October.
This feature and its cache defect remain unfinished; the patch is preserved for a
later session and must not be counted as qualified implementation or RC retirement.

Base b0fbca298 is root 7489e1833 plus approved context-preflight cd4f5183. Owned
changes are stored in `unintegrated-equality.patch`, with source hashes and raw
receipts in `inventory.json`. The patch adds exact compiler-only borrowed equality
(T,T)->Bool, canonical stack-image lowering, finite descriptor/type/layout checks,
and native-scratch may-allocation classification. It does not change the legacy
ordinary default. Source helpers cannot claim compiler authority through a prefix.

The existing runtime comparator synchronously reads both operand graphs. Its work
stack and pair memo use native realloc/calloc and are freed on success and unequal
early completion. Dictionary traversal uses readonly hash/probe callbacks; no
operand pointer escapes or becomes an owner. Borrowed stack images require no
managed boxes. IEEE NaN remains nonreflexive even when comparing one owner to itself.

Prototype validation: four initial registered tests passed, then five including
layout overflow and zero-length-array controls passed. Native coverage included
all five modes, recursive managed text, dictionaries/lists, owner replacement,
NaN, RC0/live0, and LLVM/symbol audits. Original seven value_equality tests plus
two recursive/deep/NaN tests passed in all five modes (45 native outcomes); the
ordinary control passed seven tests. These are intermediate prototype identities
recorded in raw receipts, not a final candidate qualification.

Reference and component cold/warm execution passed after disabling leakcheck for
receipt-only tests. The first harness incorrectly expected receipts while
MYL_CORE_LEAKCHECK=1 deliberately forced execution; that failed expectation is
preserved separately. Shadow mode remains a real ComponentShadowMismatch. Traced
cached/eager Core is byte-identical (38,316 bytes); only recursive Node type and
function digests differ, including the preexisting owned_copy adapter. canonical_ir
memoizes a closed cyclic root digest and reuses it inside another root from that
cycle, making hashes depend on query order. A08 independently identified this.
The drafted focused cyclic order test has not executed: its build stopped first
on a separate obsolete Build.pathFromRoot package-options API. No canonical fix
has been applied. The temporary trace instrumentation was restored before parking.

Next owner: A08/coordinator for bounded canonical cycle hashing and its query-order
regression; A10 for equality integration after that is fixed and the full native,
shadow/reference/component, malformed-marker and final verification checks rerun.
