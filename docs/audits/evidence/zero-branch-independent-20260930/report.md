# Independent zero-result branch review (frozen f4b6647d)

**Blocked: confirmed new well-formed SSA miscompile.**

`vendor/qbe/amd64/isel.c:662` admits `zeroarith` from the comparison selected by
`flagi` (line654). `zeroarith` (lines618–627) checks only producer→comparison.
`flagi` (lines500–510) may skip later IR loads/stores/copies. A later load's
address selection can emit flag-setting instructions, so adjacency before the
comparison does not prove preserved flags through the actual branch.

The exact minimized `trailing-address-v4.ssa` computes add64 of x,y, compares the
result to zero, loads the second uint64 from `extern $review_global`, then branches
and stores17/23. Both arms return the independently loaded456. With x=UINT64_MAX,
y=1 the correct marker is23, but f4 emits GOT load/add8/load between the arithmetic
and `jnz`, and observes marker17. The unsigned C oracle uses no undefined signed
arithmetic and returns1 on the wrong marker.

- Parent e66b8035 selector with all other committed QBE sources/headers identical:
  execution exit0, payload456, marker23. Assembly restores cmp0 after the address
  add and load.
- Independently rebuilt frozen f4 selector: execution exit1, payload456, marker17.
- Owner's installed f4 QBE SHA2f7ed7dfad3b4e8a8febd05cf201bfd2dc128ed8b0518fdd299705578a31ab3c:
  same exit1/result. Assembly omits the restoring compare.
- Original production fixture: all130 cases pass. Independent15-function fixture:
  all3754 assertions pass across121 arithmetic pairs. Both omit this tail case.

Recommended narrow repair: refuse zeroarith if any instruction from comparison+1
through the block end is not nop/dbgloc. Reusing `flagi`'s LeavesFlags table alone
would repeat the problem because it classifies IR operations before their address
materialization. Retain the current exact result/width/literalzero/single booluse
and full-width synthetic keepalive checks. Preserve the new negative executable
fixture and assert a cmp remains; retain no-cmp checks on actual admitted branches.

Other scoped checks found no additional issue: equality/ne are symmetric under
operand swapping; compare-derived operand class matches producer class; integer
add/sub final instructions set full-width ZF (including subtraction's neg/add
fallback); synthetic keepalive preserves result liveness and prevents removal.
Actual assembly shows addq/addl/subq/subl instead of LEA for admitted branches.
The independent pressure fixture has48 stack references and folded add followed by
flag-preserving reload moves before jnz; zero separate comparisons. Negative
width/nonzero/boolmultiuser/intervening call/arithmetic/address-use fixtures keep
comparisons and execute correctly. This is scoped inspection/execution, not a
broad backend or performance acceptance claim.

Own worktree source remains exactly f4; no tracked source edits and no copy.c
edits. QBE builds, links and executable suites used build-slot admission; no
reserved timing CPU claim. The review did not invoke a Guardian gate. Raw commands,
source/artifact hashes, assembly and actual outputs are recorded in receipt.json,
assembly-summary.json, tail-regression-receipt.json and control.log.
