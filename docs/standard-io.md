# Buffered I/O, relative paths and files

`std_io`, `std_path` and `std_fs` are reserved guest-language modules. File access
requires an explicit filesystem capability and a provider; path helpers need no
authority. Existing raw resource APIs and scoped-provider request strings remain
compatible. `acquire_resource` additionally consumes an owned u8 buffer, copying
its initialized bytes for the acquisition callback. The request buffer is consumed
on success and failure and never borrowed beyond the callback.

## Owned buffered state

`std_io::reader(file)` and `writer(file)` take a `std_io::File`. Each keeps a
64-byte buffer. These wrappers return owned state in both successful and failed
results: move the returned reader/writer into the next call. Construct states
through these functions and their returned results; manually forged positions or
lengths are outside the wrapper contract and can trigger bounds validation.

- `read(reader, destination)` fills a mutable byte slice until full, EOF or error.
  `Reading.ok` contains `reader` and `progress { length, eof }`. A zero-length
  destination does not call the provider or probe for EOF.
- `read_exact` has the same shape but reports `unexpected_eof` when it cannot fill
  the slice. `Reading.err` retains `reader`, a typed `cause`, and `progress`, the
  number of destination bytes written before the failure. Destination bytes after
  progress remain unchanged. A zero-byte non-EOF provider read is `no_progress`.
- `read_to_end(reader, output, limit)` appends into an already allocated
  `std_bytes::Bytes` buffer. `read_line` stops at LF and excludes that LF; CR is
  ordinary data. Both append after existing output. The limit includes existing
  bytes and must fit the caller's desired output bound. Actual buffer capacity is
  independently enforced. No growth/allocation is performed by these operations.
- `Collected.ok` retains reader/output and distinguishes `eof` from `newline`.
  `Collected.err` retains reader, partial output, cause and the number of new
  bytes appended by that call. The first byte exceeding the length/capacity bound
  remains buffered for retry. An LF exactly at the bound is consumed successfully;
  an exact-fit file is accepted only after EOF has been established.
- `write_all(writer, source)` accepts all source bytes into the buffered writer,
  flushing full blocks as needed. Its progress counts source bytes accepted by
  this call, including bytes still pending in the returned writer. On error,
  retry only the unaccepted suffix using the returned writer.
- `flush(writer)` writes pending bytes with partial-transfer handling. Progress
  counts bytes actually sent by that flush, including on error. The returned
  writer retains the unsent suffix. A zero-byte write is `no_progress`.
- `finish(writer)` flushes and completes the resource. Success consumes it;
  failure retains a writer for retry or explicit dropping. Its progress is the
  number written during that final flush. Dropping a writer releases its resource
  and **does not flush pending bytes**.

`std_io::Error` has a named `Kind` and the original numeric code. Kinds distinguish
unavailable/denied/provider errors, unexpected EOF, no progress, limit, allocation
and invalid path. Provider codes currently follow runtime categories 1 unavailable,
2 denied, 3 failed and 4 resource limit. Actual runtime OutOfMemory propagates as
an execution failure; cleanup still releases opened resources and guest buffers.

## Typed filesystem calls

`std_fs::open(heap, fs, path, mode)` accepts a borrowed path and returns an owned
file or typed error. Modes are read, write_existing, create_exclusive and
truncate_existing. They map to the packaged scoped provider's r:/w:/c:/t: protocol.
Read mode attenuates the supplied capability to read+complete; writing modes
attenuate it to write+complete. Existing missing permissions are never restored.
Invalid paths are rejected before a provider is invoked. Request construction
allocates at most the validated path length plus two bytes.

`read_file(heap, fs, path, output, limit)` opens, reads and releases the file. Its
success owns the output buffer; failure owns partial output, cause and progress.
Unlike the reusable reader API, this convenience function closes on failure.
Allocate output before the call with `std_bytes::create`; allocation failure then
occurs before any file acquisition. `write_file(heap, fs, path, mode, bytes)` opens,
writes, flushes and completes. Its failure reports actual bytes delivered to the
provider and releases the file. Earlier external writes are not rolled back.
These APIs use explicit bounds and synchronous provider calls; VM instruction
limits are not deadlines for a blocked host filesystem operation.

## Paths

`std_path::valid` accepts relative byte paths of 1..4094 bytes with nonempty
slash-separated components. Absolute paths, dot/dot-dot, NUL and backslash are
rejected. It performs no UTF-8 normalization, symlink resolution or filesystem
lookup. The provider separately enforces directory scoping and symlink policy.

`component(path,index)`, `basename`, `dirname` and `extension` return
`std_result::Option<Span>` with byte offsets `{start,end}` into the original path.
A bare name has no dirname. Extension excludes the final dot; dotfiles without
another dot and trailing dots have no extension. Invalid paths return none.
`join(heap,parent,child,limit)` validates both operands and returns a bounded
`std_bytes::Built`. It inserts one slash and never normalizes traversal.

## Validation

```sh
zig test src/root_test.zig --test-filter 'standard IO'
python3 tests/standard_io_native.py --compiler zig-out/bin/mylang --zig /path/to/pinned/zig
```

Source fixtures in `src/stdlib/fixtures/io` exercise partial EOF, provider failure,
stall detection, write retry and preserving the byte beyond a bound. Tests compare
owned-buffer dynamic requests and resource cleanup in VM and compiled execution.
VM allocation failures are swept across execution; native runs use ASan/UBSan,
check provider releases and sweep request/read allocation failure positions.
EOF, byte progress and cleanup are contractual; provider callback timing is not.

[The bounded file-reader example](../examples/standard-io/README.md) runs against
an explicitly granted directory with the packaged byte-I/O runner.
