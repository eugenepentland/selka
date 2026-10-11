# Root B7 component-generation evidence

This first root gate at `ed8f72c8ca1e9ea0d9aa9750263e876f6b04b17e` exits 1:
137/139 steps succeed, with one failing action. The component coordinator test
still expects body schema 6; the installed manifest correctly reports schema 7.
This archived attempt is not a passing full repository gate.

The completed body checks pass 281 pure tests per mode, 443 normal/edit workflows
with 1,772 comparisons, and 443 release workflows with 886 comparisons. Each
matrix also passes 30 warm-deployment checks, four live-session checks, 22 malformed
requests, 92 forged replies and two expected publication failures. The separate
ReleaseFast-host matrix passes the same 443 release workflows and 886 comparisons.
All matrices report zero failed or skipped cases.

Actual library admission passes 213 operations and four fresh join forgeries.
In each normal/release entry lane, all 349 operations, 35 fresh body exchanges and
15 resource forgeries pass. Seven genuine protocol requests pass capture, native
comparison and replay. All seven actual component entries rebuild through two
generations; all seven binaries are byte-identical between generations within
each lane. The native catalog, later semantic passes, Core/LLVM backend and driver
remain in use. These are component-source results, not full compiler bootstrap or
performance acceptance.

`summary.json` records exact source/artifact identities, reports and counts. The
aggregate Zig result includes 25,667 shard-filter skips; selected Guardian verdicts
record 2,790 passes and zero failures or skips. The root Debug host is
`45699ba209d90d67a6499d0dac05020d9ff4ea15a7da8ea70b7a23c87109e693`;
the ReleaseFast host is
`a26560f02ed810d023baf885c7b16f28fd4494477cdcdd7a994d176099e3439e`.
Both installations authenticate body artifact
`62adeb13f326902fb30b52b371a1b474e81cef1d11387f65d4de39bf49f20606`.

The archive preserves 194 component source files and 194 exact exchange paths
using 51 compressed payloads. `retained-paths.json` maps original paths to stored
payloads and original body correlation headers; all reconstructed frames were
verified against their original size and SHA256. Original gzip-container hashes
are provenance metadata. Run `python3 reconstruct_frame.py ORIGINAL_PATH OUTPUT`
to restore a frame, and `sha256sum -c SHA256SUMS` to verify the archive.

The packaging assertion correction and subsequent optimized qualification belong
to later commits and reports; they do not change this attempt's recorded failure.

After correcting the expected schema to 7, the existing coordinator suite passes
all 25 tests. `b7-packaging-corrected.log.gz` retains that focused result; it is
not a replacement for the next full repository gate.
