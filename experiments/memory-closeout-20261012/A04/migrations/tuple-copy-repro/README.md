# Tuple migration blocker progression

`main.my` is the small tuple.copy panic reproducer from Support5. A01's frontend
shape guard removes that panic in Support6. The current full source candidate is
preserved in `source-support6.my.txt`; its five public tests and original assertions
remain intact. It minimizes source burden by copying whole borrowed tuples and
moving their fresh unpacked children. The C0 source remains in the original
migration snapshot; `sources-support6.json` records both identities.

Support6 source-checks every other assigned file but refuses this one at line 26,
`const number, letter = found.copy()` after narrowing an optional tuple with a
None early return (E_SINGLE_OWNER_BORROW). The tuple source migration remains
unqualified and is not integrated by this evidence commit. A01 owns complete
unpack support; A07 was also given the exact source. No test was removed and
these five tests remain in the 133-test denominator.
