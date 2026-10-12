# A03 proposed additional fixture migrations

proposed nonoverlapping reservations for coordinator dispatch; A10 edits none of these sources

- `test/core/counters.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/counters.my:14:13: error[E_SINGLE_OWNER_BORROW]: a borrowed value cannot be stored or returned; make an explicit .copy()
  - Followup: explicit independent copy/local source migration. Native RC/COW counter assertions require separate oracle review.
- `test/core/f1_tbaa.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/f1_tbaa.my:42:17: error[E_SINGLE_OWNER_OVERLAP]: a value cannot be moved or mutated while another argument or iteration borrows it
  - Followup: evaluation-order or lifetime review; extract local result before mutation, preserve observed order, escalate false refusal to A07.
- `test/core/i_live_place.my`
  - i_live_place.my:13:5: error[E_SINGLE_OWNER_MOVED]: 'items' was moved or is unavailable on this path; use .copy() when both values are needed
  - Followup: explicit independent copy/local source migration.
- `test/core/rc_alias_paths.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/rc_alias_paths.my:11:14: error[E_SINGLE_OWNER_BORROW]: a borrowed value cannot be stored or returned; make an explicit .copy()
  - Followup: explicit independent copy/local source migration. Native RC/COW counter assertions require separate oracle review.
- `test/core/v_inline_loops.my`
  - v_inline_loops.my:24:21: error[E_SINGLE_OWNER_MOVED]: 'parent' was moved or is unavailable on this path; use .copy() when both values are needed
  - Followup: explicit independent copy/local source migration.
- `test/core/v_narrow.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/v_narrow.my:4:5: error[E_SINGLE_OWNER_MOVED]: '<collection>' was moved or is unavailable on this path; use .copy() when both values are needed
  - Followup: explicit independent copy/local source migration.
- `test/core/v_trace.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/v_trace.my:31:20: error[E_SINGLE_OWNER_OVERLAP]: a value cannot be moved or mutated while another argument or iteration borrows it
  - Followup: evaluation-order or lifetime review; extract local result before mutation, preserve observed order, escalate false refusal to A07.
- `test/core/v_trap_set.my`
  - /home/epentland/ai/canopy/mylang-memory-20261012-A10/test/core/v_trap_set.my:7:17: error[E_SINGLE_OWNER_BORROW]: a borrowed value cannot be stored or returned; make an explicit .copy()
  - Followup: explicit independent copy/local source migration.
