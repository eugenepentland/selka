# S10 final handoff

C0: fbfcaa7a923186a8e773c3760f81c10aa345a432.
Qualified C1: a9a3208a4f3edbf17170cfc18d57f5f999af49c3.
Initial evidence commit: 3b558178c9e3b706c28ce56bfac1d0dc89bfaaad; final evidence
commit follows via coordinator message. Own files are exclusively this experiment
(harnesses, inventory/matrix/report and raw evidence). No production patch requests
or source fixes were made. No peer worktree source edits, push/main merge, new
scheduler/default or Guardian FEEDBACK changes.

C0 direct forced complete gate passed 45 groups/95 members; C1 retained forced complete
and two unchanged requests passed 46 groups/101 members with stable inputs. All three
C1 reports independently pass review.py, which checks exact action/member metadata,
zero unknown/missing coverage and actual status/stability. The normal complete
inventory includes formatting. Whole-tree Guardian commit hooks passed 88 checks;
the gate's default diff-scoped Guardian behavior is separately visible in logs.

C1 force total 1012.058 s/queue 6.416 s/gate 985.953 s; warm totals 73.310/101.175 s,
queues 0.435/0.512 s, gate 65.862/91.618 s,35 reused 11 fresh. Both warm requests: zero
hashing/enumeration,175816 metadata observations. Two operational samples establish
no stablep95, baseline comparison or latency improvement. Parallel admitted RF
build is recorded without causal inference. Ordinary 5 s/15 s targets and reduced
unchanged-run floor remain unqualified/not demonstrated.

Native parity: C0 broad 1541→C1 broad 1532+scalar 9; eight named tests and one wrapper
moved exactly once. Core 1025,CLI 270,tooling 28,memory 7,component 10 unchanged; golden
2→4 adds isolation assertions while 222 checked/382 explicit skips stay unchanged.
Known Python telemetry 11 members/286 selected=286 timed complete;90 members unknown.
C1 bounded process/coordinator/snapshot/profile/producer safety fixtures passed;
final-matrix.md maps all 14 required rows and preserves unqualified live/timing proof.

C0 retained startup changed loaded implementation identity and selected all groups;
supported cancellation returned 143 after 335.428 s, no new success receipts, all
admission slots released. raw/C0-retained/status.json marks this incomplete; the
copied old successful report is explicitly stale-prior. S08's read-only marshal
reproducer explains possible equal-code hash variability, while actual startup
contributors remain incompletely reproduced. No C0 warm qualification is claimed.

S06 rejected candidate:20 isolated fixed-order repetitions under timing FIFO ticket 3,
30 s bound, binary SHA checked before/after. Median ratios candidate/C0:8 tests 1.1344,
1024 tests 0.8555,16384 tests 0.5855,shared 128 roots 1.0385. Raw records retain small/shared
regressions; neither stablep95 nor whole guest-loop speed is established. S07
source preparation reduces 222 writes/90182 bytes→165 writes/66752 bytes, preserving
cases. S08 cold/dirty deterministic reductions are distinct from unchanged warm.

Tools are pinned Zig0.17.0-dev.1683+5ceec001b, executable SHA
1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f.
Full C0/C1 tool contracts are byte-identical 20348-file snapshots, decompressed SHA
2356f544e2c429342b96fbc4a3725b143f28502acd53f886b55ddae3ef49ffa6.
Source trees, ABI/flags/cache environment/affinity and all command/report statuses
are archived. Private local/project/evidence tiers never clear shared global or
runtime stores. C0/C1 cold construction states differ; no paired cold cost claim.

| Artifact | SHA-256 | Bytes |
| --- | --- | --- |
| C0 Debug |7755a47e1e3f3eae11073effa41f4716fa7a99c818a4d836b8965c549fd0b57f |238915874 |
| C0 ReleaseFast |fef6fc25c6452099e2e2f443a706676b5c39c7a2546bcdf686b1b2507b79eb8f |68298856 |
| C1 Debug |e018f4dc02cba5020dcdb9c74a8bdd4354d11b49d2dfaacf5030b0aa82f176f3 |239001890 |
| C1 ReleaseFast |75935fabfbde64f8045d0aaba92122b304d344bee06839699b7b21563dcae9b1 |68298936 |

Versioned artifact store leases and explicit chunk pins protect all four frozen
binaries; JSON artifact records archive ordered chunks/pin IDs. S10.prune-keep
protects C0/live store, committed integration.prune-keep protects C1. C1 RF prefix
.tmp/frozen-final-release survives; only its inactive private Zig cache moved to
ignored.tmp/s 10-final-release-cache after build exit 0. RF build 463.526 s includes
queue and is operational only. Both live C1 artifact hashes and source HEAD stayed
stable; source tree was clean when freeze released. Prepared artifact bytes:
765518171(C0),791425272(C1); no paired cold compile/RSS inference.

Final retained controller invokes existing cache_session→verify dispatch directly;
that coordinator owns admission. Significant builds used shared build slots;
standalone fixture used bounded timing admission after own gate released. Root
confirmed A 09 has no addressable session, so common FIFO admission coordinated
windows; direct scheduling unavailable is recorded. Baseline/final admission queues
remain separate from held execution. No nested admission or private raw locks.

Remaining: full live edit/cold/second-worktree/subscriber matrix, matched cold
compile/link/RSS/fd/retained-memory costs, complete guest/Guardian test timings,
qualified hard-budget headroom, ordinary feedback/p95 and unchanged latency.
DL7 full compiler ownership/seed bootstrap/parity and every required 1.5× median/p95
ratio remain open. Coordinator integrates evidence-only commits and validates the
production source diff against C1 before delivery; no missing requirement is hidden.
