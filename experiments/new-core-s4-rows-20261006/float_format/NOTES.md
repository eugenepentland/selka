# float_format notes

Verified 2026-10-06 with `rows.py verify float_format`: PASS for all five arms (old core
--release, new core release, Rust, Zig ReleaseSafe, Go) at all five probes, each equal to
`oracle.py`. The new core accepted `row.my`; there is no `new-core-refusal.txt`.
Calibrated (`rows.py calibrate`, CPU 12, machine load average ~25 at the time, so +-3% noise):
`{"4096": 40, "64": 2930}`.

## Text equals Python's `repr(x)`, for every value the row can produce

The probes alone sample only some `(k, j % 7)` pairs, so I checked all of them. `100003` is
prime and `700021 = 100003 * 7`, so `size=700021, iterations=1` visits each of the 700021
distinct pairs `(k, m)` exactly once (CRT on `j`), for any seed. Result, every arm vs the
oracle (which also asserts that `repr` has no exponent and has a `.`):
`562841491` for old, new, Rust, Zig, Go, at seeds 1 and 999999. So these all produce
Python's text for all values:
- mylang `str(x)` (both cores);
- Rust `x.to_string()`;
- Zig `std.fmt.allocPrint(c_allocator, "{d}", .{x})`;
- Go `strconv.FormatFloat(x, 'f', -1, 64)`.

Argument validation was checked by hand for every arm (SIZE < 2, ITERATIONS 0, SEED 0 and
1000001, negative or non-numeric numbers, 2 or 5 arguments, a wrong case name): status 2,
nothing on stdout or stderr. SEED 1000000 and SIZE 2 are accepted.

## Idioms

- **mylang:** `x = k + 0.125 * (1 + j % 7)`; int and float mix in arithmetic, and both
  compilers accept it, so no `float()` casts. `text = str(x)` (a fresh `str` per value).
  The fold is `for c in text.encode()` as in `test/core/row_int_format.my`'s `score`; `len(text)`
  for the length (the contract's `len(text)`; text is ASCII so it equals the byte count).
- **Rust:** `x.to_string()` into a `String`, `text.bytes()` for the fold, `text.len()`.
- **Zig:** `allocPrint(c_allocator, "{d}", ...)` then `defer free`; `for (text) |c|`.
- **Go:** `FormatFloat(x, 'f', -1, 64)` (allocates a string per value), index loop over bytes.
- All arms: `h = (h * 131 + c) % MOD` per byte, `part = (part + h + len) % MOD`, as the contract.

## What differs between the arms (fairness notes, no action taken)

- `text.encode()` in the **old core** calls `myl_native_bytes_encode`, which builds a managed
  `bytes` copy per value (an extra allocation the references do not have). The **new core**
  reads the `str`'s data in place: its LLVM IR for `fold` loads straight from the text block
  (the borrowed `encode()` of the new-core plan), no allocation. Both then release the text.
  In the new core the only per-value allocation is `myl_core_str_from_f64` (freed in the batch).
- The per-byte `% 1000000007` fold is a serial dependency chain (an estimated 15 cycles per byte for a
  64-bit `urem` by a constant) of roughly 9 bytes per value, identical in all languages; it
  dilutes differences in the formatting itself (see `buffer_write/NOTES.md` for the measured share
  of the same fold there). That formula is fixed by the contract.

## Findings

- Wrong answers: none. No `repro-*.my` was needed.
- New-core refusal: none.
- Old-core rejections: none for the natural formulation. Nothing in the language forced an
  unnatural form here.
