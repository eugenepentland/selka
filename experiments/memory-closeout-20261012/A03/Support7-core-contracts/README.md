# Support7 additional core contracts

All 23 additional core files remain in the matrix, plus the separate
`tests/lang/rc_nonheld_captures.my` private-helper main. Across five checked modes,
all 110 counted native builds and 225 executions match their frozen output, exit
and diagnostic contracts and have zero measured RC events and clean LLVM/symbol
audits. The 195 normal/validation exits have zero managed exit-live bytes. The 30
intentional fatal traps retain their measured live storage at abort; these are
not advertised as cleanup successes. Full counters preserve those observations.

Two core files expose public tests instead of a substantive main. Their actual
guest test command runs in each mode with leakcheck enabled. `v_row_cow.my` passes
all eight tests per mode. `m_recursive_values.my` passes seven and reports three
unsupported per mode: two generated equality helpers and one saturating-integer
runtime helper. These are unresolved supported contracts, not exclusions. Across
the ten uninstrumented commands, 75 public test contracts pass and 15 are
unsupported, with zero failed, skipped or cached. No RC-event claim is made for
those uninstrumented commands.

Native output constants and original oracle-file hashes come from frozen C0
`fbfcaa7a923186a8e773c3760f81c10aa345a432`. The five benchmark-shaped sources use
independent Python checksum calculations for `(size, iterations, seed)` values
`(8,12,7)` and `(31,37,19)`, plus missing/invalid-argument exits. Their scalar native
clock is injected as a constant zero, preserving deterministic output and avoiding
a timing claim. This is an explicit test provider, not ordinary benchmark timing
or observed C0 native execution. The original fixture sources remain immutable.

The compiler is full Support7 SHA-256
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`, frozen source
`bed11cf3bf3102ffec44487e431a1573fdf02ad5`. Commands, source/binary hashes, helper
identity, oracle data and full counted reports are archived. This matrix is
separate from the pinned 81-case census and six-case supplement. It closes the
private-main gap; `surface_statements_case_2.my` is already executed through its
importing public-test module in the common guest matrix.
