# Bounded byte block I/O

`mylang-io` supports copied 256-byte blocks alongside its existing scalar calls.
Projects opt in by adding the following exports and declarations to `io.my`:

```my
# doc: skip fragment: declarations appended to an existing host io.my module
export Block
export read_block
export write_block


class Block:
    bytes: [256]u8
    count: i64


host def read_block(offset: i64) -> Block effects(host)


host def write_block(block: Block) -> i64 effects(host)
```

Keep the existing `length`, `byte`, and `put` declarations. The host validates
the bulk signatures before executing any guest code: Block is a plain record
with `bytes` followed by `count`, and its array is exactly `[256]u8`.

`read_block` returns up to 256 bytes starting at an absolute input offset. `count`
is the useful length; the rest is zero-filled. Offset equal to input length
returns count zero; negative or past-end offsets fail the invocation. Binary
bytes, including NUL and invalid UTF-8, are preserved.

`write_block` writes the first `count` bytes, returning how many fit within the
unpublished output budget. Counts outside 0–256 fail the invocation. A short
write is explicit: it may return zero. Guests must decide whether to accept the
prefix or return a nonzero exit. The runner publishes buffered output only when
the invocation completes successfully and returns zero; traps, host failures,
and nonzero exits publish nothing. An allocation or work failure appends no
partial block. This is bounded buffering, not a streaming stdout commit protocol.

For example, a complete copy can use:

```my
# doc: skip needs host capability: the mylang-io byte host and its io.my module
def main() -> i64:
    size = io.length()
    offset = 0
    while offset < size:
        block = io.read_block(offset)
        count = block.count
        if io.write_block(block) != count:
            return 1
        offset += count
    return 0
```

This invokes one length callback and two callbacks per block. Each bulk
callback charges transferred bytes plus one work unit, in addition to the host
registry's one unit per dispatch. Ordinary copied-value count/depth checks and
host effect grants still apply. No guest memory crosses the callback by reference
boundary.

The runner accepts unique decimal flags after its project argument:

```sh
mylang-io --project app --max-input=1048576 --max-output=1048576 \
  --max-steps=10000000 --max-calls=10000 --max-work=4000000
```

Defaults remain 2 MiB input, 128 MiB output, 2 billion VM steps, and 300 million
host calls/work units. Zero input/output capacity is valid; execution budgets
must be positive. Invalid and duplicated flags reject before running the guest.
Input is bounded by its configured limit plus one detection byte. Output remains
bounded by its configured capacity, with fixed-size block copies at the host
boundary; VM metadata and source parsing have their existing separate budgets.

Reproduce the end-to-end comparison with:

```sh
python3 scripts/benchmark_byte_io.py --runner zig-out/bin/mylang-io
```

The [recorded run](experiments/byte-io-bulk-20260907.json) includes all timings,
binary and payload hashes, callback limits, and platform. These timings include
process startup and checking; they do not isolate callback cost or imply results
on another workload or build configuration.
