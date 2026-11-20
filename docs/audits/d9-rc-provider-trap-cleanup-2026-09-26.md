# WP-4 native provider failure cleanup

The native file surface called resource entries that mapped fatal provider
replies directly to `longjmp`. An acquisition error could skip freeing the
unpublished raw Resource record; a read error could skip its temporary provider
buffer. Higher file helpers could additionally retain copied path/input bytes,
partially accumulated reads, or a fresh managed output awaiting completion.

Internal `myl_qbe_resource_try_*` operations now return fatal status values after
cleaning their own scratch. The existing public resource ABI maps those statuses
to the same located traps. File helpers use the internal entries and free all
scratch, end their temporary handles, and abort unpublished counted outputs
before publishing the trap. A GC root keeps a prepared result alive across the
completion callback. Public failed completion still retains its caller's handle
for retry or unique cleanup. No context layout, guest calling convention, or
nonlocal-exit mechanism changed.

The production C fixture exercises 40 cases across GC and RC, using the real
runtime's `setjmp`/`longjmp` path: acquisition OOM and invalid status; invalid
authority; partial reads followed by OOM, oversized length or invalid EOF;
completion OOM after preparing a result; and partial write OOM. The public
resource entries and higher file helpers both participate, including open-handle
methods. Fatal completion also overrides a recoverable UTF-8 error, and fatal I/O releases without completing the handle. Two cases verify failed completion retains a handle for a successful retry. Completion forces collection before refusing. Each case checks the
original trap code, live provider handles, retained caller inputs, root balance,
and final heap accounting. Strict C warnings, ASan and UBSan pass all 40 cases.

The new focused Debug wrapper passes 12/12, and existing IO-12 checks pass 13/13.
The actual QBE capability probe retains its previous counts: success has 360 heap
allocations and retirements, 232 owner acquires and 592 releases; partial invalid
UTF-8 readlines traps with three allocations/retirements and one acquire/four
releases. Both have zero outstanding holds. This validates this cleanup slice;
the joined full regression and WP-4 performance gates remain separate.
