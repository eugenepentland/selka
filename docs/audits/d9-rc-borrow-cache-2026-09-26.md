# Certified borrowed entry integration

The compiler emits each certified internal entry as a separate native unit with
its own symbol and frame-map metadata. Its source name and positions remain the
canonical function's. Canonical, exported and function-value entries return owned
values. A direct borrowed caller establishes result ownership before releasing
argument anchors. The physical proof and measured schematic savings are recorded
in [the borrowed-entry audit](d9-rc-borrowed-entry-2026-09-26.md).

Caller fragment keys now include each direct callee's complete physical
certificate or its refusal, plus the ownership ABI. Certificates include physical
layouts, accepted control flow and transitive immortal-helper bodies. RC lowers
all physical bodies before certification because the current stand-in record
cannot restore that proof. This conservatively loses frontend stand-in reuse;
ordinary unit-text and native-object caches remain available. Alternate IL is
regenerated and its normal native-object content key includes that complete text.
GC retains its existing keys and stand-in behavior.

Validation on Debug compiler SHA256
`2ad8a929b1cc40a4a79ade1489043fcee664dcd829aa59ea8450c7d7d0668db7`:

- `RC-BORROW` focused root: 21 passed (10 named plus 11 unnamed). Warm and fresh
  outputs match after transitive helper changes, certificate loss and restoration;
  lean outputs also preserve separate alternate metadata.
- Existing GC fragment-cache regression: 12 passed (one named plus 11 unnamed).
- `tests/lang/rc_borrowed_results.my`: four assertions each on QBE Debug and LLVM
  ReleaseFast/O3/full LTO, with `--rc-runtime=stats`. Each exits zero and reports
  1,233 acquires, 1,255 releases, 22 allocations and 22 retirements. Holds are zero;
  both backends report three clone shells and seven uniqueness checks.
- Guardian: all 88 checks passed. The integration gate is owned by the parent
  branch; this focused slice does not claim full WP-4 acceptance.

[Raw logs and identities](evidence/d9-rc-borrow-cache.json.gz) include the precommit
base and exact compiler and guest hashes. The source includes the contract-match
fix `3ec91de8` and preserves the narrowed Option receiver fix `3caa8a01`.
