# Mutable-parameter rebinding — 2026-09-26

The new RC regression exposed a GC bug: after `items = other` inside a mutable
list parameter, writing `items[0]` also changed the caller's read-only `other`.
This reproduces under native GC stress on both QBE and LLVM with the accepted
stage3 compiler (`f6bea5d9`, SHA256 `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`)
and with the current experimental compiler. It predates the RC shortcut.

The analysis correctly kept the parameter's caller-borrowed `mut_param` role,
but treated that role as a permanent uniqueness guarantee even after replacing
the local slot. The correction keeps the borrowed role and separately proves
that the original payload contract is still valid. A whole-slot store, move,
drop or reference invalidates the exemption. Direct writes and captured receiver
loads then require ordinary COW checks. Element hoists also decline the obsolete
caller guarantee. The indexed same-slot transfer proof checks the same contract.
The RC shortcut now uses this shared test instead of a separate scan.

The structural tests pass 13 selected tests, including conditional rebinds whose
receiver is a compiler temporary. All six source assertions pass with native GC
stress on both actual backends: direct list writes, nested shared rows, dictionary
values, conditional replacement, caller/callee snapshots and the original failing
regression. A further 35 pending-receiver and callback assertions pass in each
mode/backend combination. Altogether all 164 actual assertions pass (41 each
under GC stress and counted RC, on both backends). RC counters balance and match
across backends. Whole-tree Guardian passes all 88 checks; root integration owns
the complete fresh gate.

Corrected Debug compiler SHA256: `9cd555d25e06ac185a003daf4dc0ee0c46e30c144c38814ed85596ec072e8b4c`.
The [raw evidence](evidence/d9-mut-parameter-rebinding.json.gz) preserves exact
historical controls, commands, source and compiler identities, focused results
and the reusable broader-validation driver. The initial conditional-case failure
was retained in scratch before the captured-receiver check was added.
