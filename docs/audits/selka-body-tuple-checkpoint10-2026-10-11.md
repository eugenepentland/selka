# Installed schema 10 tuple checkpoint

Source commit: `4069e037eda8ff101b90dfcd9af925b888bfbac1`.

The fresh ReleaseFast compiler installation passed 24/24 build steps and
208/208 native body tests, with no failures or skips. Formatting checked 1,071
live Selka files with 209 deliberate exclusions and no failures; its six Python
tests passed. Build Guardian passed 88 checks in diff-scoped mode.

The installed body component passed the original ten collection-extension
fixtures, including `dictionary_generator_pairs`: 90 operations across native,
shadow and selected-component modes. Successful cases compared checking and
typed output exactly, then ran under release fact verification and leak checks.

A separate tuple checkpoint passed eight fixtures and 60 operations in those
same three modes. Its six successful cases cover contextual, nested and list
tuples, tuple literals and swaps, and dictionary generator pairs. Its two error
cases compare exact tuple arity and element diagnostics. Eight genuine schema10
request/reply captures retain their original headers and payload bytes; their
identities, request hashes and reply correlations were verified.

Both runners verified the qualified seed and all seven installed package
identities before and after their work. The compiler SHA256 is
`65b5c4b61ea02208b285376313f9ab868ccbe8771d9405ec9016e8d2e6eff7df`.
The body package key is
`cf54d9d0e4900c5da0f6a398c515995c996985e76fb034f15bdb31312bd3529d`,
and its artifact SHA256 is
`e36e6cde0037156a8c3884794b318c8cc635f51fd27d870c813335bb5d64416a`.

[The evidence receipt](evidence/selka-body-tuple-checkpoint10-20261011/receipt.json)
binds the raw reports, runners, fixture sources, all frames, package receipts,
successful build log and failed initial build log. The first build was
terminated by earlyoom on 11 October at 15:56:55 UTC; the archived journal names
native Zig PID805612. The same source passed on the serial retry.

The strict structural inventory remains unchanged at 30 fixtures and 222
operations. Complete array production and the 13 hostile structural probes are
still pending. This explicit tuple checkpoint does not establish full structural
admission, whole-language checking, bootstrap completion or performance parity.
