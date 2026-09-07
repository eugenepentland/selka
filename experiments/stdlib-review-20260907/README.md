# Independent standard-library review, 2026-09-07

These are the original small source probes, Python harnesses and JSON receipts
from the text-library agent's independent review of the owned-container and
buffered-I/O stages. Generated guest C, executable binaries and compiler binaries
are intentionally excluded. `artifacts.json` hashes the retained raw artifacts.
The probes are supplementary review evidence, not a complete language safety
assessment or evidence that the entire final integrated compiler was reviewed.

## Owned containers

`owned-review/runtime-results.json` records one mutation scenario on the VM with
both general and arena backing, plus native C at O0/O2 with undefined-behavior
sanitization: **four executions, all independently expected to return 42**.
The compiler SHA-256 was:

```
e429a2e3d4d1c3edfa19ce0668e0feb3e12b06307bc6a4d8e5b7d7d7d714d1f0
```

`mutations.my` covers a full-buffer append failure, growing capacity while retaining
owned elements, replacing an element, a failed out-of-bounds replacement, an
oversized truncate preserving the length, swap-removal identities, successful
truncate and final extraction. `sanity.my` was also executed successfully on the
VM, returning 42; that initial sanity execution has no separate JSON receipt.

`negative-results.json` records **11 compile rejections** from `probe.py`:

- Direct and generic insertion of an inner-arena owner into an outer buffer.
- Reusing an inserted owned value and reusing a generic `T:storable` value.
- Copying owned buffer elements through read, resize, buffer slices or array slices.
- Containers containing results directly or through arrays, and forwarding a
  result-containing array to a `storable` parameter.

Each case exited 1 with the expected ownership, region, copying or generic
constraint diagnostic. That original negative-check harness did **not** record a
binary hash independently; the hash above belongs specifically to the later
runtime receipt, not a retroactive identity claim for those 11 checks. The
harness retained only the first 800 characters of diagnostic stderr per case.

Code review additionally identified that the new bytecode `storable` flag needed
consistency checks for resource and array contracts. This was communicated to
the collection agent for hardening. These receipts predate that follow-up and do
not claim to verify it.

## Buffered I/O

The three I/O receipts (`result.json`, `read-result.json`, `finish-result.json`)
pin this integrated root compiler SHA-256:

```
e55f312e642112476a189106470a74db4687a83bfcfad9117c46b2787a0cc9f3
```

Each source ran as native C at O0 and O2 under address and undefined-behavior
sanitization: **six executions, all independently expected to return 42**.
No additional VM executions of these three independent probes are claimed.

- `main.my`: 60 previously buffered bytes plus 8 new bytes; the provider writes
  two bytes then fails. The guest verifies progress of four newly accepted bytes
  and 62 pending bytes, retries only the unaccepted suffix and completes. The
  harness checks the exact 68-byte output, without loss or duplication.
- `read_edges.my`: zero-length reads before and after EOF; a four-byte exact read
  receiving only three bytes; preservation of the untouched destination tail;
  and another nonempty read after EOF. The harness verifies exactly two provider
  reads and no writes.
- `finish_retry.my`: flush succeeds but completion fails once. The retained writer
  has no pending bytes and reports the two flushed bytes. Retrying completion
  returns zero new progress and does not write the bytes again.

Every run acquired and released exactly one resource, with zero live resources
at exit. The custom provider asserts that source `std_fs` attenuation passes
permission mask 6 for write mode and mask 5 for read mode. Read-only code review
also checked that the packaged scoped-provider request parser rejects missing
mode permissions before opening, creating or truncating files. It found no
concrete defect in the reviewed read/write progress, buffer rewind or dynamic
request cleanup paths. This is bounded evidence, not an assertion about all
providers, malformed forged wrapper states or later metadata/list changes.

## Harness provenance and rerunning

These scripts are retained unchanged from the review and contain the original
absolute workspace paths. They write scratch artifacts beside themselves, so
**copy a probe directory to a scratch location before rerunning**, then update the
compiler/root paths for the binary being evaluated. I/O harnesses obtain their
base provider from `tests/standard_io_provider.c` (also retained here as
`io-review/provider-base.c`, matching commit `c8a4203`) and apply the shown permission
and completion-failure modifications. A changed provider source or compiler is a
new experiment; do not overwrite these historical receipts with its results.

The toolchain was `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig`.
The tests used a disk-backed temporary directory rather than `/tmp`. The owned
and I/O probes were read-only with respect to their reviewed source worktrees;
all temporary sources, generated artifacts and logs stayed in the text agent's
validation directory.
