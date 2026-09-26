# D9 RC held live views at copied boundaries — 2026-09-26

The public invocation API admits `DictValues[int,int]`. With the H-shaped view
lowering, `invoke` on `{view:{mapping:[["1","7"]]}}` aborted in its native child:
the generic record decoder left the dictionary's fresh O token in a slot whose
registered view shape drops H. The same source now returns `"7"` normally.

The codec identifies H-shaped records through the registered ownership
descriptor. It decodes the mapping into a journaled ordinary owning temporary,
acquires H, publishes the view, then drops the temporary O. A malformed subtree
or allocation refusal leaves the parent view empty. A callback trap can find
every initialized value in the existing codec cleanup journal. Ordinary record
and GC decoding keep their existing paths. Encoding already borrows the live
mapping and needs no change.

The boundary audit found these admitted paths and results:

| Boundary | Result |
| --- | --- |
| `mylang invoke` parameter | Accepted; valid input now returns `7` |
| `mylang invoke` result | Accepted; returns the mapping's key/value pairs |
| Native codec library API | Accepted on QBE and LLVM |
| Ordinary native value API | `UnsupportedSignature` for the managed view |
| Copied `host def` parameter or result | Checker rejects `E_HOST_SIGNATURE` |

The production C harness now has 17 scenarios and passes ASan/UBSan. Six new
scenarios cover H ownership after a successful decode, truncated input, budget
refusal, GC stress, a list containing views, and a callback trap with an
initialized view. The focused Zig wrapper passes 12/12.

Real QBE and LLVM ReleaseFast shared libraries pass five boundary scenarios
apiece with identical counts. Four calls enter the guest: successful input,
successful result, malformed input and output-capacity refusal. Their respective
heap allocation/retirement counts are 6/6, 4/4, 2/2 and 4/4; every owner and hold
also balances. Evidence, source fixtures and reproduction are in
[`experiments/d9-rc-held-codecs-20260926`](../../experiments/d9-rc-held-codecs-20260926).

The audit also found a preexisting description issue: `invoke --describe`
advertises a dictionary as a flat array even though the established JSON decoder
requires `[key,value]` pairs. That schema issue is separate from this ownership
fix and remains reported for follow-up.

Backend evidence correction: the original `libraries.json` LLVM label was
invalid because a later `--qbe` option selected QBE. It remains archived without
modification. New `libraries-corrected.json` executes actual LLVM O3/LTO and QBE;
all five cases pass per backend with the same balanced counts stated above.
