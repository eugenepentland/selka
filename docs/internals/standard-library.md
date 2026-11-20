# Standard library: how it works

Implementation detail and measurements moved out of the user guide, [docs/standard-library.md](../standard-library.md), word for word. Headings match the guide's, so an anchor here is the guide's anchor. This folder is not part of the published site.

## Functions the compiler supplies

A hundred and twenty-three of the library's functions are declared `builtin func`: a signature
and its documentation comment with no body, because the compiler supplies every call. They
are the list, dictionary, set, text, bytes and buffer operations that were methods once
(`lists.pop`, `dicts.get`, `strings.upper`, `strings.strip`, `lists.exchange`), the function homes of the methods text,
bytes, a byte buffer and a set still answer (`strings.strip_chars`, `bytes.index`,
`sets.update`: each is its method's own operation, so a program that moves from the method
to the function runs the same code), the nine `simd` lane operations, the
`parallel.map` family, the scalar text helpers (`strings.char_count`, `strings.chars`,
`lists.stride`) and two private `testing` counters. A call is the operation however it
is spelled: the module's name, an import alias (`import strings as s`), another module's
re-export (`export strings.upper`), keyword arguments or explicit type arguments. A
`strings`, `bytes` or `buffers` operation is also a function value, which runs the same
operation; a `simd` operation or a scalar text helper is not one
(`E_BUILTIN_FUNCTION_VALUE`): call it directly, or pass a named function that calls it.
`selka list-interfaces` lists each one as `export builtin function`. Only the
library declares a `builtin func`; in a program's own module it is refused
(`E_BUILTIN_DECLARATION`). The library's own sources call these functions as a program
does: they are written in the function forms and are refused a method form or a second spelling
(`E_METHOD_REMOVED`, `E_REMOVED_SPELLING`) like any program, with no waiver: the bounded search that
`strings.find` and `strings.rfind` convert to `int?` is the library's own private home
(`find_offset`, `rfind_offset`), not a method.

## byte_builder

`byte_builder` assembles an immutable byte string in one mutable `byte_buffer`
([in-place octet methods](bytes.md#writing-octets-in-place)) whose backing
storage grows by doubling, so `append`, `append_range`, `append_byte`,
`append_spaces`, `append_text`, `append_int` and `append_float` write each
fragment's octets straight into that capacity and no fragment allocates a value
for itself: `append_text` builds no temporary encoded `bytes`, and `append_int`
and `append_float` no temporary text or byte value at all. `append_float` writes
the canonical spelling `str(value)` prints, built on the runtime's own stack. `finish` publishes the buffer as an immutable snapshot
with `bytes(buffer)`, which copies the current octets into independent owned
storage. `finish` may allocate but does not mutate the builder;
when the assembled octets are only going to a stream,
`write(out, builder.buffer)` writes the buffer's own storage instead and skips
that copy.

## byte_format

Output that Zig writes with `w.print("<rect x=\"{d:.1}\" y=\"{d:.1}\"/>", .{ x, y })` is one call here too, onto a
[`byte_builder`](#byte_builder). `byte_format.shortest(mut builder, x)` is Zig's `{d}` of a float: the shortest digits that
round-trip, never scientific, with no `.0` after a whole number (`100.0` is `100`, `-0.0` is `-0`; `byte_builder.append_float`
keeps the `.0`). `byte_format.decimal(mut builder, x, decimals)` is Zig's `{d:.N}`: `decimals` digits from the shortest digits,
rounded half up, so `6.475` at two decimals is `6.48` (`strings.format_float` and an f-string round the exact binary value and
print `6.47`); it answers `False` and appends nothing for `decimals` outside 0 to 17. Both agree with the pinned Zig toolchain's
output on a captured set of 294 values at 0, 1, 2, 3 and 6 decimals (`tests/lang/byte_format_templates.selka`).

## dicts

The dictionary probes answer the two questions a caller otherwise spells as a
membership test plus a second index. `dicts.find(mapping, key)` returns the value
stored under `key`, or `None` when the mapping has no entry for it. A managed value
comes back as an independent copy: the generic body must also accept a directly recursive
record (`next: Node?`), and the checker does not lend those, so the copy stays until it does.
`dicts.get` declares `from mapping, fallback`: its result may borrow either input.
`dicts.setdefault` declares `from mapping`: its result borrows the stored entry. `dicts.add(mut mapping, key, delta)` adds
an integer to the entry under `key`, starting from zero. `dicts.append_to(mut
mapping, key, own item)` appends to the list stored under `key`, starting a list
with `item`. Both read the `key` (a name, field or element) and copy it only when the
mapping has no entry for it, so a call that finds its key allocates nothing; `append_to` takes
the `item` `own`, so a named binding the caller owns is given away and a borrowed name is copied at the call, and
`dicts.setdefault(mut mapping, key, fallback)` answers the stored value or
stores the fallback and answers that (it reads a `key` written as a name, field or element and copies it only when
the mapping has no entry for it), and `dicts.update(mut mapping, other)` copies
every entry of another mapping in, replacing the keys it already holds. `dicts.add`
and `dicts.setdefault` probe once, `dicts.append_to` grows the stored list in place
(two probes, linear in the number of appends), and the mapping keeps owning its
storage.

## sort

The concrete `sort_ints`, `sort_floats` and `sort_strs` wrappers delegate to the
same stable merge engine as `sorted` and `values.sort()`, returning a new list and
leaving the input untouched. That engine keeps the ascending runs a list already
has, reverses strictly descending ones, extends short runs by insertion and merges
through one scratch buffer of at most half the list, with a comparison compiled
for each element type, so an ordered or reversed list sorts in linear time.
Not-a-number follows every ordered float, equal values and signed zeros retain
their input order, and text compares its stored Unicode scalar values directly.
`compare_strs` and `min_str` therefore allocate no temporary encodings. A generic
sort over an arbitrary element type needs an integer key function or a comparison
function, because the language has no ordering contract: `copy`, `equality`, `integer`,
`codec` and `storable` are the only generic requirements.

`sort_by_key` is a thin forwarder to Python's keyed sort: it returns
`sorted(values, key=key)`, which computes each element's key exactly once, in
list order, and gathers the elements into the new list with the native keyed sort
(see [keyed sorting](../python-syntax.md#keyed-sorting) for `key=`, `reverse=` and
the `float`, `str`, `bytes` and recursively ordered record keys the method and `sorted` accept). A key
function that traps on several elements reports the first of them in list order;
before the keyed sort existed, `sort_by_key` asked for keys in the order a
recursive merge first needed them. Sorting NaNs last is a deliberate
regularization: the earlier comparator treated a NaN as tied with every value,
so its position could depend on merge boundaries rather than one ordering
contract.

`sort_by_compare(mut values, compare)` sorts a list in place by a comparison of two elements, for an order that no
single `int`, `float` or `str` key gives: jq's order across types of value, or an `ORDER BY` of several keys with a direction
each. `compare` is a top-level function that takes two elements and returns an `int`: negative when the first element goes
before the second, zero when neither does, positive when the second goes first (the answers of `compare_strs` and
`time.compare`). The result is the one order the comparison gives, and the sort is stable: elements that compare equal keep
their input order. The elements are lent to `compare` and never copied; the sort moves each one once. It holds two lists
of positions beside the list, so a list of a million records needs 16 MB more, and it takes about as long as a merge sort
written by hand over a list of indexes. `T` needs `copy` as `sort_by_key` does, which no element type that cannot be lent
to a function (a resource, a result) has.

## parallel

A callback may take read-only trailing arguments after its item:
`parallel.map(values, callback, a, b)` calls `callback(item, a, b)` for every item,
with one to five arguments. Each argument is the same for every item. Sema selects the
variant of the argument count: `map_with1`, `map_with2`, `map_with3`, `map_with4` or
`map_with5` in `parallel.selka`. An argument is a scalar (`int`, `float`, `bool`, and
the other scalar types) or a managed value (a list, text, bytes, record or dictionary),
which is lent to every item and not copied. A list, text or bytes held in a plain
parameter is refused (`E_SLICE_ESCAPES`): write `copy(...)` around it, or declare the
parameter `own`; a local, an `own` parameter and a record parameter go in as they are.
A `mut` argument is `E_TASK_MUT`, and an `own` marker on an argument and a fallible
callback are `E_PARALLEL_MAP_ARGS`. The same rule governs the list itself: a list in
a local is passed as it is, and one in a plain parameter has to be copied or declared
`own` (both cases, with examples, are in [Limits](concurrency.md#limits)).

## pool

**`pool.get` returns a copy.** The record comes out whole, with every list, dictionary and text it holds, on each
call, and `pool.set` copies the record in again; the checker does not lend the result. A record that holds a list of
200,000 integers, read 2,000 times, cost about 0.35 ms a
read in a release build, and the same loop over a list kept outside the pool cost 0.17 s in all. Nothing reads or
writes one field of a pooled record in place: the functions above are all there are, and none takes a field. So keep
in the pool the small record that says what the entry is (a name, a kind, a few numbers), and keep the large or
growing data in lists beside it, subscripted by `handle.index`. A field that changes often belongs in such a list
too, since changing it through the pool is a `get`, the change and a `set`, two copies of the whole record.

## Time limits on a connection

`connect` and the reads and writes of the `Connection` it returns wait as long as the peer takes, so a peer that accepts
and then never answers stalls the program. `connect_within(net, limits)` connects the same way within the time limits of
a `Timeouts` record, all in milliseconds: `connect_ms` bounds the connect, and `read_ms` and `write_ms` bound each later
`read_resource` that waits that long for a byte and each `write_resource` that waits that long to send one. A limit that
runs out is an ordinary failure with the error code `timed_out()` (7): `Connected.err` for the connect, `Read.err` or
`Written.err` for a transfer, which leaves the connection open, so a caller may wait again or close it. It is not the
code of a refused or unreachable endpoint (3), which fails at once, and a peer that closed is a read's end of stream, as
before; `describe(timed_out())` reads `timed out: the endpoint did not answer within the time limit`. A field left at
0 (the default) or below has no limit, so `connect_within(net, Timeouts())` is `connect(net)`, and a limit above one
day is one day. The runtime keeps the limits on the socket (a nonblocking connect waited on with `poll`, then
`SO_RCVTIMEO` and `SO_SNDTIMEO`): no thread, no signal, and no `Clock` of the program's. On a stand-in Network nothing
blocks, so the limits have nothing to bound and `connect_within` answers as `connect` does.

`receive_buffer_bytes` asks the kernel for a receive buffer of that size (`SO_RCVBUF`, set before the connect, since
the window a connection advertises is fixed then); 0, the default, keeps the system's. Linux doubles the number for its
own bookkeeping, keeps at least about 2 KiB and at most `net.core.rmem_max`, and stops growing the buffer by itself. It
bounds what can wait unread at this end: a peer that writes to a reader that never reads has its sends stop being
taken after this buffer and the writer's own send buffer are full. The writer's buffer is the writer's kernel's
(`net.ipv4.tcp_wmem`, up to 4 MiB by default), so on loopback a writer to a 4 KiB reader stops after about 2.9 MB
instead of 4.2 MB: fewer bytes, not a few kilobytes. A test that checks how a server treats a stalled reader sets the
reader's buffer small and counts what the server queues itself. An older spelling such as
`network.Timeouts(read_ms=1500)` keeps the system's buffer.

## Event loop

One thread can serve many connections with a `Poller`: `open_poller(net)` binds
the listening endpoint a `net.host("IP:PORT")` narrowing names (the same
`--allow-listen` grant as `listen`), and the runtime keeps the listener and every
accepted connection inside that one resource. A program names a connection by the
small integer id `accept` returns, so connections live in a `dict[int, State]`
instead of as resources, and the loop function holds exactly one resource local.
Nothing blocks except `wait`, which waits at most `timeout_ms` milliseconds. The
design is in the event loop note (`docs/design/event-loop-2026-10-18.md`).

**Memory goes back to the system when the loop idles.** A program keeps the memory it frees while it works, so
that a request that frees and allocates a few tens of kilobytes does not fault the same pages in again; after a
burst of deletes its resident size stays at the peak. `wait` hands that memory back when it is about to block with
nothing ready and either its limit is a second or more (or none) or the waits before it found nothing for a second;
it does so once after at least 256 values of about a kilobyte or more were freed and the free memory is 1 MiB or more,
and a busy loop never does. A server that stored and deleted 12 MB of values holds about 3 MB a second later.
Values of about a kilobyte or less are kept in 64 KiB chunks that are only reused, never returned.

**A `Poller` holds as many connections as the process may open descriptors**
(accepted and dialled together), less 64 kept for the rest of the program, and at
most 1,048,576: plan for that number, not for a count of your own.
`network.connection_limit(own poller, mut outcome)` reports it: `outcome.value` is the
limit and `outcome.extra` the number open. Where the hard descriptor limit is 524,288
the limit is 524,224, and `ulimit -n 2000` makes it 1,936. The poller raises the soft
descriptor limit to the hard one when it opens (a program this one starts, with
`process`, gets back the soft limit this one started with), and its table starts at 1,024 slots
(what an idle poller has always held) and doubles as connections arrive, at about 50
bytes a slot besides the kernel's own socket. At the limit `accept` answers
`OUTCOME_FULL` (so does an `accept` that the process has no descriptor for) and the
poller stops reporting the listener, so a further client still connects, in the
kernel's backlog, and waits unanswered until a slot frees. A second poller on the same
address fails to open (`err(3)`), and the blocking `Listener` cannot be added to a
poller. What a program can do at the limit is free slots: close the connections that
have gone quiet (`set_idle_timeout`, then `close_connection` on each `EVENT_IDLE`), or
close the least recently active client itself when `connection_limit` shows the table
nearly full. Either makes room, and the poller reports the listener again so that the
waiting client is accepted.

## hashes

`hashes.sha256(data: bytes) -> str` returns 64 lowercase hexadecimal digits.
The runtime hashes the octets of `data` in place (a `bytes` parameter or a slice is read
without a copy, and the padding is built in two 64-byte blocks of its own). It uses the
x86 SHA extensions when the CPU has them, chosen when the first hash runs, and portable C
otherwise; both give the same digest. Until 8 November 2026 this was a Selka
implementation at about 250 MB/s; the runtime's SHA-NI path runs at about 2 GB/s and its
portable path at about 340 MB/s (1 KB, 64 KB and 16 MB inputs, release build,
`experiments/native-sha256-20261108/REPORT.md`). The 32 raw octets of the digest, as `bytes`,
are `hashes.sha256_bytes(data)` and `hashes.sha256_text_bytes(text)` (once the methods `data.sha256()` and
`text.sha256()`), and
`hashes.blake3_bytes(data)` and `hashes.blake3_text_bytes(text)` answer the raw BLAKE3 octets
(`hashes.blake3` answers a `Digest`). Each hashes in place, a text's UTF-8 octets with no
encoded copy, and the `bytes` ones also take a `byte_buffer`.

## BLAKE3 digests

`hashes.blake3(data: bytes) -> Digest` and `hashes.blake3_text(text: str) -> Digest` return the 32-byte
[BLAKE3](https://github.com/BLAKE3-team/BLAKE3) digest of the octets of `data` (or of the UTF-8 octets of `text`,
with no encoded copy). The hash runs in the runtime, over the octets in place (a `bytes` parameter or a slice is
hashed without a copy), at the speed of Zig's `std.crypto.hash.Blake3`: within 2% of it at 1 KiB, 64 KiB and 16 MiB
on this machine's AVX2 CPU (`experiments/incremental-engine-20261030/L1/REPORT.md`). The 32 raw octets, as `bytes`,
are `hashes.blake3_bytes(data)` and `hashes.blake3_text_bytes(text)`.

## SHA-1 for protocols that require it

`hashes.sha1(data: bytes) -> str` returns the 40 lowercase hexadecimal digits of the SHA-1 digest of `data`, and
`hashes.sha1_bytes(data: bytes) -> bytes` its 20 octets, the form a protocol encodes. SHA-1 is broken for collisions:
use it only where a protocol names it, such as the WebSocket handshake of RFC 6455 or Git's object names, and never to
protect anything; `sha256` and `blake3` are the hashes to choose. It is written in Selka and reads whole blocks of `data`
in place, at about 1,100 executed blocks per 64 octets, which suits a handshake's few dozen octets and not bulk data.

## flate

`zlib_decode` checks the header (the deflate method, the check bits) and the Adler-32 of the result and refuses a stream
that asks for a preset dictionary. `gunzip` skips the optional name, comment, extra field and header check of each
member, checks its CRC-32 and size, decompresses several members one after another to their concatenation and ignores
zero bytes after the last one; any other trailing data is refused. `crc32` and `adler32` return the checksums as
non-negative integers below 2^32, the same values zlib gives. A 34 MB gzip file (an edit-check coverage map) decompresses in
about two seconds in a debug build.

## Inflating in pieces

The one-shot functions take all the compressed bytes and return all the plain ones, so a `.tgz` costs its decompressed size
in memory. An inflater takes the compressed bytes a piece at a time and holds the 32 KiB window of the last output and
what one piece needs, never the whole result: a gzip file of 1 GiB of zeros inflates in about 6 MB. `flate.inflater(limit)`
starts a raw stream, `flate.zlib_inflater(limit)` a zlib stream and `flate.gzip_inflater(limit)` gzip data, one member or
several, each member's CRC-32 and size checked. The `Inflater` is a value: pass it with `mut`. `limit` is the most plain bytes
the whole stream may produce, and `9223372036854775807` says no limit.

## persistent_memo

For native persistence, replace the stand-in and zero limit with a real narrowed
`Filesystem` and positive entry limit. Directory ownership serializes readers,
writers and eviction. Each record binds the actual callable's reachable code,
source schemas and execution context, exact tagged input, canonical byte encoding
and checksum. A malformed record is a miss; provider failures remain errors.
Lowered entry limits trim the directory deterministically. Entry count and
per-entry size bound retention; there is no TTL or ambient file freshness rule.

## durable

Each completed artifact is synchronized before its digest enters a synchronized
journal replacement. Recovery validates the request, callable identity, every
committed artifact and the chain of state snapshots before skipping work.
Changed input, implementation, schemas, output name or limits rejects the old
journal. Corrupt committed evidence fails closed; preserve it for diagnosis or
start a new directory. Uncommitted artifacts and abandoned temporary files are
collected while holding the directory lease. Committed progress is retained.

The complete CSV application is in
`test/fixtures/application-cache/application.selka`.
Its developer qualification driver runs cold, warm, edit, corruption and crash
cases against independently calculated output.
