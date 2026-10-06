# buffer_write notes

Verified 2026-10-06 with `rows.py verify buffer_write`: PASS for all five arms (old core
--release, new core release, Rust, Zig ReleaseSafe, Go) at all five probes, each equal to
`oracle.py`. The new core accepted `row.my`; there is no `new-core-refusal.txt`.
Calibrated (`rows.py calibrate`, CPU 12, machine load average ~25 at the time, so +-3% noise):
`{"4096": 115, "64": 8794}`.

Argument validation was checked by hand for every arm (SIZE < 2, ITERATIONS 0, SEED 0 and
1000001, negative or non-numeric numbers, 2 or 5 arguments, a wrong case name): status 2,
nothing on stdout or stderr. SEED 1000000 and SIZE 2 are accepted.

## mylang operations used (exactly)

```
buffer = byte_buffer([])            # once per batch
_ = buffer.append_int(v)            # the digits of v, signed decimal
_ = buffer.append_byte(44)          # ','
_ = buffer.append_byte(10)          # '\n' after every 16th value
for c in buffer: ...                # fold; len(buffer)
```

The buffer is a local dropped at the end of `batch_result`. `byte_buffer([])` is the empty
constructor: there is no zero-argument `byte_buffer()` (`E_ARITY: byte conversions require one
argument`), and the docs write it with a typed empty list (`empty: list[int] = []`), though
`byte_buffer([])` is accepted by both compilers and is what I used. The stdlib
`byte_builder` module wraps the same buffer methods; I checked that a `byte_builder` version
is accepted by both compilers and, in the new core, lowers the same way as below. I did not
use it, because the contract says `byte_buffer`.

Both `append_*` methods return `bool`; a bare call is `E_EXPLICIT_DISCARD_REQUIRED`, so each
is written `_ = buffer.append_int(v)`. That is the form `tests/lang/byte_buffer.my` uses.

### Does an append allocate an intermediate `str` or `bytes` per value?

- **Old core: no.** `append_int` lowers to `myl_native_bytes_buffer_append_int`
  (`src/qbe_bytes.zig:262`, `src/native_bytes.c:675`), which writes the digits through a
  20-byte stack array and then `memcpy`s them into the buffer's capacity. As documented in
  `docs/bytes.md` ("build no temporary `bytes`, `str` or formatted text"). Only buffer growth
  (doubling) allocates.
- **New core: yes, one `str` per integer.** `src/core/build_bytes.zig:138` lowers
  `buffer_append_int` as `myl_core_str_from_i64(v)` (a heap-allocated `str`), then
  `myl_core_buffer_range_valid`, then a byte-by-byte loop calling `myl_core_buffer_push` for
  each digit, with a refcount==1 copy-on-write check before every push, then frees the `str`.
  I read this in `.mylang-cache/s4-rows/bin/buffer_write/new.ll` (`batch_result`: `call ptr
  @myl_core_str_from_i64` in the loop, `rc.free` of that `str` in `b11`, `myl_core_buffer_push` in
  `b22`). This contradicts the documented guarantee and costs one allocation, one free and a
  per-digit push call per value. `append_byte` is the same per-byte push with the same
  refcount check, with no allocation. `append_float` is lowered the same way, through
  `myl_core_str_from_f64` (line 139). `byte_buffer([])` builds a list, validates it,
  converts it to a buffer and frees the list, once per batch (negligible).
  This is a performance finding, not a wrong answer: the checksum is right. Reported, not fixed.

## Idioms in the references

- **Rust:** `Vec<u8>` + `write!(buf, "{}", v)` (`std::io::Write`; writes straight into the Vec),
  `buf.push(b',')`.
- **Zig:** `std.ArrayList(u8) = .empty` on `c_allocator`. In this Zig (0.17-dev) the list has no
  `writer()`; the idiom is `list.print(gpa, "{d}", .{v})` (it wraps `std.Io.Writer.Allocating`
  per call), `list.append(gpa, ',')`, `defer list.deinit(gpa)`. I compared it against one long-lived
  `std.Io.Writer.Allocating` with `w.print` / `w.writeByte`: same speed (37-45 ms for both at
  4096x115, CPU 12), so the choice does not matter.
- **Go:** `buf = strconv.AppendInt(buf, v, 10)` and `append(buf, ',')` on a nil `[]byte`
  that grows by `append`.

## Finding: the fold is about half of this row

The contract's fold `h = (h * 131 + c) % MOD` is a serial 64-bit `%` chain over every byte
of the buffer (about 6.5 bytes per value), at an estimated 15 cycles per byte, so a large share
of the row's time is the same in every language and hides the cost of the appending. A
rough check with a Rust variant whose fold is `h += c` instead (not part of the row): about
35 ns per element, against about 85 ns for the real fold at size 4096 (CPU 12, a loaded
machine, so only the order of magnitude). I followed the contract's formula; the coordinator
may want to expect ratios close to 1.0 at size 64 even when the new-core append path is slower.
At size 64 all five arms measured within 72-76 ns per element on CPU 12, which is the same
effect.

## Findings

- Wrong answers: none. No `repro-*.my` was needed.
- New-core refusal: none.
- Old core: nothing rejected; the only friction is the missing zero-argument `byte_buffer()`
  and the mandatory `_ =` on the `bool` result.
- New core: `append_int` goes through a temporary `str` (above).
