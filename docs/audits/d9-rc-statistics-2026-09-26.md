# D9 physical RC statistics — 2026-09-26

This slice adds optional per-heap physical traffic counters for the existing
`rc-v1-counting` artifact identity. It does not establish WP-4 acceptance or
change the default GC runtime. Generated guest ownership lowering remains in
progress. The execution adapter must call `myl_rc_stats_report` after cleanup and
before destroying the heap, including its standalone fast-exit path.

Events distinguish successful owner acquisition/release, lifetime hold
acquisition/release, refused count increments, heap/arena allocation, retirement,
allocated clone shells and uniqueness checks. A new allocation's initial owner
is represented by allocation, not acquisition. Failed clone transactions still
count shells they physically allocated. Counter overflow saturates and sets a
diagnostic flag without changing ownership counts.

Validation:

- Four production-allocator scenarios pass with AddressSanitizer and
  UndefinedBehaviorSanitizer: physical traffic, no-ops/refusals, pinned snapshots,
  and per-heap isolation/saturation. An ordinary artifact passes the disabled
  scenario and emits no diagnostic. The counted diagnostic parses as the exact
  versioned JSON record retained in the evidence file.
- Focused Debug Zig run: 12/12 tests (one named statistics test and 11 unnamed
  registration blocks), 10/10 build steps.
- With counting disabled, `cc -std=c11 -O2` emits byte-identical `.text` for
  `native_rc.c` and `native_rc_transfer.c` before and after this change, compared
  against `7c22a772`. Neither object references a statistics function; the
  conditional state field is absent. This establishes no counter-event overhead
  for these objects, not whole-program performance acceptance.

Evidence: [counter record and object hashes](evidence/d9-rc-statistics-2026-09-26.json).
The latest complete joined regression gate remains the separate host/staged
runtime report; this slice has only the focused and sanitizer checks above.
