# Physical retention without semantic sharing history

The private ABI3 runtime now exposes `myl_rc_native_retain` and
`myl_rc_native_retain_replace`. They acquire the direct physical O/H edges while
preserving payload identity, including pinned values. They neither clone a pinned
payload nor write SHARED. The caller must perform any required semantic SHARE at
its language evaluation point; these APIs cannot replace that event.

Retention checks destination region and rolls back all acquired edges on refusal.
Replacement stages the complete new value, installs it, then retires the former
value. Raw unique resources and finalized recursive bodies are excluded by the
native type validator. The existing pin-aware copy/take APIs are unchanged.

Five new C scenarios cover pinned identity, arena identity and illegal younger
region publication, late ordinary-count failure, replacement refusal and commit,
and a mixed O/H late hold-limit failure. The history suite now has 22 cases. The
reproducible command below passes all 122 runtime scenarios under ASan/UBSan:

```
python3 experiments/d9-rc-history-publication-20260926/check.py
```

The focused `RC semantic publication` Zig selection passes 12 tests, including
its 11 always-run blocks. Guardian passes all 88 checks. Exact logs and source
identities are retained in [the evidence](evidence/d9-rc-physical-retain-checks.json.gz).

This is a runtime API slice. Compiler history/loan propagation and helper caller
classification remain private work; no whole-stage correctness or performance
acceptance is claimed.
