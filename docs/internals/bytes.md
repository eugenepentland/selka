# Managed byte strings: how it works

Implementation detail moved out of the user guide, [bytes.md](../bytes.md). Each heading is the guide's heading.

## Contracts and boundaries

Every byte-string operation is native code over the C runtime's byte routines, which mirror its text routines with a one-byte stride.

## Embedding a file at compile time

The file's content is part of the build's inputs. Editing only an embedded file rechecks and rebuilds exactly the declarations that embed it and the module objects that hold them; an unchanged file reuses every cached result, and deleting or replacing it changes the keys too. `selka test` captures embedded files with the sources, so a test result is reused only while its fixture is unchanged. The `project-dependencies` receipt lists each embedded file with its BLAKE3 digest. Navigation and `selka context` snapshots list the same embedded identities and recheck them before publishing facts, including same-length edits. In the native build each distinct file is one static object, however many times it is embedded, and the work to build it is linear in its size.

Test snapshots deduplicate physical copies before reading them and use the loaded closure's project allowances. Provider replacements capture and recheck their own reachable embedded fixtures, including ones the production graph did not use. The allowances reach the reader before it allocates.

An interface file prints an embedded constant as `embed_bytes("path")`, never as the file's bytes. Repeated calls in one module naming the same path share one read and charge; the same physical file named from different modules has separate module/path identities and charges.

## Counting characters and parsing numbers

ASCII runs advance a word at a time in `bytes.scalar_count`.

## Writing octets in place

None of the append methods allocates a value for the appended fragment, and growth doubles the backing storage, so appending N octets performs `O(log N)` allocations. `append_utf8`, `append_int` and `append_float` build no temporary `bytes`, `str` or formatted text: the integer's digits and the float's canonical spelling are written straight into the buffer's capacity. `buffers.clear` then keeps the capacity, so the 1,000th fill of a reused buffer allocates nothing.

The snapshot `bytes(buffer)` has an explicit copy cost; ownership optimization may reuse storage only when the old value is dead.

## Walking the lines of a file

A slice that is only read is a view of the file buffer and copies nothing (a walk over three lines, a thousand times, allocates 0).
