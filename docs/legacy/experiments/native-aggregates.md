# Native records, arrays, and boxed variants
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

The C backend executes immutable records, complete construction/conversions,
field access, preserving updates, fixed arrays, checked indexing/replacement,
length queries, and complete enum-indexed tables. Aggregate parameters, return
values, locals, and nested union/result payloads work in single files and modules.
Partial field transfers and non-consuming reads work for records with handling
obligations. Existing static nominal, conversion-accounting, exhaustiveness,
privacy, and result-handling rules still apply before emission.

A native value slot now carries either a scalar/packed value or an aggregate
pointer. Records and arrays use reference-counted immutable field storage.
Small variants retain their packed representation; variants containing aggregate
payloads or exceeding 127 bits use boxed storage. Width is no longer a reason
to reject an otherwise-supported variant. The complete dependency graph is still
checked: external resources, pools, handles, and provider capabilities remain
unsupported. [Ordinary-value borrowing and slices](native-references.md) and
[root allocator buffers](native-buffers.md) extend this backend.

Copies retain storage. Updates create new field storage and retain unchanged
children, preserving previous copies and shared subvalues. Assignment and scope
exit release old values promptly. Partial field transfers detach shared storage
before clearing the moved field. Results can propagate between packed and boxed
representations, with named error identities and caller operands preserved.

Normal release uses an intrusive work list and does not recurse through host
calls or allocate a cleanup stack. All native aggregate allocations also belong
to an allocation registry. On a trap or host failure, including failure while
constructing an object or growing the operand/frame storage, cleanup frees this
registry directly. Temporary values do not become unreachable to failure cleanup.
Native host allocations and physical memory usage are not promised to match VM
allocations or OOM timing. This representation is internal, not a public ABI.

## Validation

`tests/native_cases.py` executes the record, array, conversion, and table examples,
copy-preserving updates, empty records/arrays, negative/large/out-of-range indices,
partial result field transfers, results containing records, mixed packed/boxed
propagation, and variants wider than 127 bits. Module fixtures also compare source
paths and call traces. Both native optimization levels use UBSan; small successful
cases compare every instruction-budget boundary against the VM.

`tests/native_memory.py` prepends a test-only allocator shim to emitted C and runs
the resulting executables with AddressSanitizer and UBSan at -O0 and -O2. It fails
every allocation along a construction/update/call/propagation scenario and checks
that host failures exit with zero outstanding runtime allocation bytes. Normal
exit, bounds traps, step/frame limits, and a 20,000-update loop also release their
allocations. The loop's live-storage peak remains below 64 KiB while retaining an
earlier copy. These are executed measurements of the chosen fixtures, not a
universal memory bound or allocator-cost claim.

Zig tests cover compiler allocation failures and explicit rejection of unsupported
owner payloads. The existing resource tests still require E_NATIVE_FEATURE; ordinary-value
borrowing now has separate native acceptance.

Examples can use the ordinary builder:

```sh
python3 scripts/native.py examples/arrays.my -o .zig-cache/native-arrays
.zig-cache/native-arrays
# 44
```

This completes ordinary aggregate execution in the experimental C route.
Native owned resources/capabilities, pools/arenas, and the other
unfinished roadmap tracks remain pending.
