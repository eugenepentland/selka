# Frame-private physical loans

The API3 infrastructure now implements `myl_rc_native_loan` and
`myl_rc_native_unloan`. A loan copies stable inline bytes and acquires one H
hold per managed O or H leaf, including duplicate pointers. It does not clone a
pinned payload, acquire an ordinary owner, set sharing history, or migrate
regions. A failed acquisition releases the entire acquired prefix and clears the
output. The type admission walk excludes raw unique obligations and uniquely
finalized boxed bodies; the pointer visitor also checks the actual allocation.

LOAN16 journal cleanup clears the initialized guard before dropping its held
leaves. Existing frame cleanup restores receiver scopes first. The release walk
uses registration-reserved storage and needs no allocation, including when a
loan is the last lifetime token. Arena loans must be dropped before region
teardown and do not alter the arena header.

This commit emits no compiler loans and does not implement semantic publication.
It remains private infrastructure for the reviewed
[semantic-history contract](d9-rc-semantic-history-design-2026-09-26.md).
In particular, existing physical arena COPY paths still set SHARED because arena
objects do not count O references. Those writes need an explicit audit at the
publication boundary; treating them as semantic history or removing them
unconditionally would each be unsound. No new marker policy is enabled here.

Validation: seven dedicated API scenarios and all 23 production startup/frame
checks pass with ASan and UBSan. Cases cover pinned identity, ownerless lifetime,
mixed and repeated O/H leaves, late count-limit rollback/retry, arrays and active
variant arms, arena cleanup, raw unique admission and scope-before-loan cleanup.
The normal Zig C harness includes the new suite; its focused `RC loan` run passes
13/13. Guardian passes 88 checks. The cumulative full gate belongs to the parent
once the complete runtime/compiler history change is ready.

Run `python3 experiments/d9-rc-loans-20260926/check.py` to repeat sanitizer checks.
Commands, source identities and outputs are in
[evidence/d9-rc-private-loans.json.gz](evidence/d9-rc-private-loans.json.gz).
