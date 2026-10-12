# Read-only common CSV compiler audit

Common source commit: `1994cb76e266080d971be6f41e98fba5707234dd`.
Receipt: `experiments/text-gaps-20261012/coordinator/common-001/build-receipt.json`
in the coordinator integration worktree. Actual refs/heads/main remains the
1994cb76e source commit; the checkout named mylang-text-gaps-main-20261012 is
the separate codex/text-gaps-main-final-20261012 integration branch. Later
evidence-only commits there do not advance main. Frozen compiler SHA256:
`0ba1684ea76140b07675bf01b39baafe8a7253ea675bfba8057186f1f9f16a3b`.
Frozen guest: `.tmp/text-gaps/coordinator/common-001/text-runtime`, SHA256
`429854488c74f3bc0a39aa0e0a8216e81bb21362bfad58e573a7fb1a96bc7994`.
Unchanged migrated text fixture SHA256:
`71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754`.

No LLVM source artifact survives in this guest cache; this audit reads the final
native code. `csv-common001-consumer.asm` preserves the relevant disassembly.
The CSV helpers have been inlined into `my.text::kernel`. Consumer calls already
borrow field strings; no owned token/encode materialization remains here. The
byte-score reduction is vectorized. No missed bounded reader inlining was found.

Concrete follow-up: repeated row bounds checks remain. The row[3] access checks
len>=4 at0x104da02. The Some(amount) branch checks row[4], len>=5, at0x104dc51.
After borrowed equality, row[2] checks len>=3 at0x104dc7a; after the groups update,
row[1] checks len>=2 at0x104de56. These latter two are redundant for a stable row:
the earlier successful checked access dominates their execution and proves a
strictly stronger bound. `facts.provableAccess` reasons from explicit branch
edges and known lengths, but does not use an earlier successful implicit checked
list access as a lower-bound fact.

A generic candidate would reuse only an earlier dominating successful access
with a nonnegative constant index >= the later constant index, on the same
resolved stable list. Keep the earlier access and its original trap/location;
do not move a later check earlier across parse failure or conditional branches.
Refuse length changes, owner replacement/transfer, source or ancestor mutation,
unknown aliasing, escaping references and calls without the needed mutation
proof. Dominance must cover all paths, including loop backedges. Preserve
ordinary RC behavior unless a separate ownership proof supports it. Bounded
analysis and identical eager/cold/warm cache results are required. Tests should
cover earlier and later traps, conditional execution, source/ancestor mutation,
break/continue/return and distinct lists. No broad lifetime inference is proposed.

No production edits or builds occurred. This candidate is deferred while the
coordinator tests the narrower runtime ASCII append change; it is not a claimed
performance improvement. Current small CSV versus ZigFast is1.0016 with
CI[0.9661,1.0132], so the target remains unestablished until paired verification.
