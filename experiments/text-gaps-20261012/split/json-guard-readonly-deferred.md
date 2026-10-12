# Deferred read-only JSON native observations

Status: not implemented; no production edits, native builds, timing or new
worktree occurred for this investigation. The JSON owner is independently
screening source-only paired items() iteration and an explicit nonnegative
quoted-byte index guard. This document does not claim performance improvement.

## Exact frozen identity

Receipt in the JSON worker tree:
`experiments/text-gaps-20261012/json-guard/build-receipt.json`.
Base source `1994cb76e266080d971be6f41e98fba5707234dd`;
guard source `207053908abe44f572fba3d846403340b5a73899`.
Compiler SHA256 `887583f8ad93eb58cababe756b31364435155f32b1a39077ade947c7080c55f5`.
Library-source SHA256 `f9adac86925b7359c52e8cd31aed550c9999c35c1674bf5b3cf57f27e811cfed`.
Frozen runtime guest `.tmp/text-gaps/json-guard/text-runtime`, SHA256
`f7eef5db66041492897a77b5fd982a4482b4f4177b5028c35646fa583d49ed0f`.
All paths above are beneath
`/home/epentland/ai/canopy/mylang-text-gaps-json-final-20261012`.
Unchanged migrated text.my SHA256
`71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754`.
The audit reads final native disassembly and existing sources, not a newly
compiled approximation. A later edited library does not change this identity.

## Rediscovered dictionary entries

write_object iterates `for key in fields`, writes the quoted key and colon,
then accesses fields[key]. Its body is inlined into my.json::write_value.
Native0x10501f8 calls myl_core_dict_ordinal to select the live insertion-order
entry. After writing the key,0x1050248 calls myl_core_str_hash on that stored
key, followed by SIMD probe/string equality or myl_core_dict_find at0x1050373,
rediscovering the same entry before reading its value. This happens three times
per retained result object in json_job. Reusing the existing entry would remove
real work for arbitrary read-only dictionary serializers; no workload-specific
lookup or checksum rewrite is proposed. Its contribution requires measurement.

The existing paired .items() library API may remove the lookup directly, but
validateViews currently refuses an unknown parameter dictionary identity.
Source-only screening must keep those checks intact. A compiler alternative is
deferred pending that result.

## Bounded ordinal-origin reuse outline

Resolve a later dict_find(D,K) through forwarding copies only. Require K to be
a direct non-transferred dict_entry_key(D,E), with the identical resolved D.
Require E to originate in the exact compiler-authorized runtime_c declaration
myl_core_dict_ordinal(D,j), i64 return, parameters{typeof(D),u64}, and zero
owned/consumes/views masks. Require existing facts or its loop guard to prove
0<=j<dict_len(D) at the ordinal call. Preserve the call and key read; replace
only the later pure probe with a forwarding copy of E.

Use E, never the dense ordinal j: runtime ordinal scans live physical entries
when tombstones exist. Source shape/liveness must remain unchanged; insertion,
remove/reinsert, clear or parent replacement invalidates this proof. The exact
key SSA identity excludes arbitrary equal-looking or changed keys. Reject
transferred dict_take_key reads, unresolved phis and unknown origins.

Existing facts.shape/probePrecedes can prove instruction order and dominance.
Existing fuse_slice_key.updated can conservatively reject source/borrow-parent
mutation or transfer anywhere in the function, including loop backedges.
Reject opaque source escapes, wrappers and unknown mutation aliases rather than
adding lifetime inference. Unrelated output-buffer mutation is acceptable only
under the existing source-stability proof. Recompute ordinal each iteration;
never carry an earlier iteration's slot through a phi. Dominance must cover all
paths and backedges. Bound candidate/work counts, e.g.32 candidates/4096 slots.
Current probes lacks Module, so exact callee/ownership verification would require
a separately coordinated API/pass change. No declaration or span ABI is needed.

Positive regressions should cover stable key iteration, insertion order,
tombstones and copied forwarding keys. Negative regressions should cover live
remove/reinsert, growth, ancestor replacement, owning/opaque calls, captured
aliases, early exits and distinct dictionaries. Preserve first failing check,
trap ancestry, evaluation order and cold/warm cache output. No RC fallback or
escaping borrowed values should be introduced.

## Quoted-byte normalizer cost

my.json::write_quoted has borrowed encode data, but calls
myl_core_span_bytes_index_offset at0x10504f8 for every scanned byte, followed by
another returned-offset<len check at0x10504fd. The loop already has offset<len
and a nonnegative0++ induction. fuse_encode replaces the original byte-index
normalizer with a trusted str/i64->u64 runtime span helper; its opaque result
currently prevents the subsequent direct access from inheriting the input bound.

A generic proved-valid input could use the original index directly and let the
existing list-access facts discharge its check. Outside0<=index<byte_len proof,
retain negative-index normalization and invalid-offset/trap behavior exactly.
A bounded compiler intrinsic or existing facts rewrite would need exact trusted
signature checks and normal cache/provenance qualification. No such compiler
change is implemented here; the explicit source lower-bound experiment belongs
to the JSON owner. Quote/escape/control/Unicode semantics must remain unchanged.

## Other observations

write_quoted already borrows its string encode; no per-quote encode copy was
found. dumps allocates a buffer and returns an independent owned decoded text;
json_job subsequently scores it. The final UTF-8 validation and owned result
cannot simply be removed by assuming serialization output or benchmark use.
Any separate ownership/buffer-transfer proposal would need a general checked
contract and standalone dumps independence, so it is not proposed as a shortcut.
