# Independent qualification status

C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`. This report is incomplete
while acquisition runs; it does not close DL8 or performance targets.

| Requirement | Current evidence | Verdict |
| --- | --- | --- |
| Baseline source/tools/cache freeze | Full Git tree, pinned Zig SHA/version, affinity, private cache environment | Acquired |
| Compiler artifacts | Debug 238915874 bytes; ReleaseFast 68298856 bytes; exact hashes, ordered chunks and explicit pins | Acquired |
| Authoritative baseline inventory | 45 groups; 95 required/registered actions; zero unknown | Acquired |
| Baseline complete forced execution | Direct verify_cache --force,45selected,stabletrue,status0,1196.052s incl1.139s queue | Passed |
| Final exact candidate complete gate/fmt | C1 a9a3208a4f3edbf17170cfc18d57f5f999af49c3 frozen; retained force→warm2 running | Pending |
| Required test timing coverage | C0 per-group summaries, Python collectors proposed, guest/Guardian individual timing unknown | Partial |
| Retained baseline/final counters | C0startup all-fresh from loaded identity mismatch cancelled143; baseline warm unavailable; C1force→warm2 pending | Not qualified |
| Ordinary useful feedback <=5s and empirical p95 <=15s | No isolated named cohorts yet | Open |
| Independent scalar boundary | S03 eight named tests+wrapper; 115 grammar+ 7754 format oracle rows; cold/RSS pair pending | Partial |
| Golden fixture reduction | S07 retained 604 cases/222 checks; 165 source writes/66752 source bytes; paired latency/RSS pending | Partial |
| Guest discovery/execution | S06 exact nine-member correctness controls; candidate may reject small-workload regression | Partial |
| Snapshot work reduction | S08 accepted cold construction+dirty rejection; unchanged warm counter unchanged; unsafe batch memo rejected | Partial |
| Failure/edit matrix | Existing safety fixtures and worker handoffs; exact integrated independent execution pending | Not qualified |
| Self-hosting DL7 | External port bootstrap/full ownership/strict 36-row ratios incomplete; legacy admission migration not adopted | Open |

The baseline ReleaseFast build took 423.261 seconds including queue under ordinary
build admission. This operational observation is not a cold isolated compilation
or a performance improvement claim. Shared global/native runtime cache state was
not cleared. Gate phases overlap: wall times cannot be summed; per-process RSS is
not concurrent aggregate RSS. Warm/cold/edited improvements remain distinct.

The final review keeps every matrix row and reports passed, failed or unqualified.
Rejected speed candidates and unavailable direct A09 owner scheduling remain
visible. Common exclusive timing admission coordinates bounded windows. No new
scheduled jobs, default rollout, feedback commits or production fixes are made
by S10.
