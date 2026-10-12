# Remaining C1 measurement schedule

This is a scheduling estimate, not a performance result or a frozen C1 identity.
The machine-readable counterpart is `C1-schedule.json`. No final runtime pair has
run. All times below exclude queue wait unless explicitly stated.

After complete final installations are available, allow approximately **20–35
minutes for this evidence subset on a quiet cooperating queue**. This includes
rough preparation/correctness estimates and admission settle overhead. Under
the observed minute-scale waits, **1–3 hours is a more realistic planning range**,
with longer external timing holds still possible. Neither range includes root's
full registered verification, broad library matrices, source repairs, C2/C3
reruns or a cold compiler/seed build. It is not a closeout deadline.

## Artifacts before measurements

Root freezes one source revision and builds separate complete Debug and
ReleaseFast installations, preserving `bin/`, `libexec/` and `tools/` together.
The Debug compiler produces Release guest timing binaries; ReleaseFast measures
compiler work. Record both compiler hashes and every installed component's
source, manifest, receipt and binary hash before consumers start.

A10 confirms both installations can use the same independently pinned RF
component builder (source prefix `5167c588`, compiler SHA-256
`29cfbd13390692757ce3add9cf61d8398eff283760d16cedb3c5b9addaa03e26`). This is a
builder input, not permission to relabel Support6 components as C1. Provisioning
must bind the actual final component sources, seed receipt, toolchain, target
and builder digest; verify reuse from those identities. A10's prior coarse
log/receipt intervals were about 6m20s for cold seed plus components and about
12s for a component rebuild once the seed was available. Host compiler rebuild
cost is additional and has no reliable final estimate yet. Installed protocols
previously took about 29s of work plus 155s queue; final `test-components`, package
ABI audits and the full gate remain required.

## Work after the artifact freeze

| Work | Exact scope | Execution estimate and limits |
| --- | --- | --- |
| Runtime artifact preparation | Eight unique uncounted binaries, exposed as 15 worker/input cases | Ordinary bounded build admission; final native build cost still to observe |
| Runtime comparison | 15 cases × (2 warmup + 9 measured) × 2 arms = **330 launches** | About 5.2–7.2 minutes from sizing scenarios; schedule 5–8 minutes of guest execution, without claiming a final speedup |
| Guest RSS | 15 cases × 3 pairs × 2 arms = **90 separate launches** | About 1.4–2.0 minutes of guest execution; GNU-time child RSS, no timing use |
| Size-aligned counters | Eight distinct counted builds per arm; **30 execution configurations**, 15 per arm | C0 attempted: eight native-link failures block all 15 baseline executions. C1 arm waits for freeze. Same calibrated sources/arguments/checksums, separate from the census |
| Compiler scaling | 16 family/size cells × 5 phases = **80 final compiler calls** | A08 estimates 2–5 minutes, based on accepted C0 cells taking 4–8s each; each command has a 120s timeout |
| Diagnostic compiler gap | Six module/generic inputs × C0/final = **12 source/Core-only commands** | Inputs frozen; still unrun. No native-link or whole-build ratio from this partial scope |
| Cache correctness and compile memory | Existing 44 cache rows plus 12 borrowed-selection and 11 generic-tuple rows, with provider/relocation followups; representative fields64 memory run | Ordinary correctness admission and a separate sampled-memory execution; no estimate for newly added regressions |
| Pinned census | **435 builds, 695 counted executions**, plus **30 original-source checks** | At least 47 ten-call leases; roughly 2–4 minutes of warm admitted work is an extrapolation, not a cold benchmark |
| Four applications | **20 counted binaries, 60 executions**, all five pipelines | Roughly 2–3 minutes from prior bounded batches; exact final costs may differ |

The original 81 cases and six supplements keep their denominators. Size-aligned
counted cases are additional, and their larger-input totals must not be substituted
into the pinned census or compared with smaller old inputs. Counter runs report
managed traffic and live bytes; runtime and RSS remain separate executions.

## Measurement order and admission

1. Validate complete installations, owned component closure and frozen source
   hashes. Prepare eight uncounted binaries, counted supplements, application
   artifacts and cache probes under ordinary admission. Run safety/output checks
   before interpreting performance.
2. Schedule one runtime case per exclusive lease, with an ordinary admission
   barrier between leases. Each paired case keeps identical input, environment,
   workers and affinity. Queue wait stays outside sample time.
3. Interleave A08's bounded five-command scaling cells and diagnostic-only
   windows using the same ordinary barriers. Run the separate RSS matrix in
   its own result directory. No simultaneous compiler or runtime timing lanes.
4. Publish raw samples, exact identities, refusals and regressions. Repeat affected
   cases only when a concrete failure, noisy result or changed artifact requires
   it; a corrected compiler is a new candidate, never a relabeled earlier binary.

The runtime estimate uses one preserved C0 sizing observation per case. The
equal-C0 candidate scenario is 433.014s; replacing only six map observations with
the early prototype sizing observations gives 313.674s. These are scheduling
scenarios, not paired measurements or a prediction of final C1 performance.
Three equal-C0 cheap-map windows exceed 60s, with the longest about 98.1s; inspect
actual C1 execution before starting a full 22-run window. Splitting a window must
preserve all two warmup and nine measured pairs and record the changed schedule.

The 15 runtime, 15 RSS, 16 scaling and two diagnostic windows imply 48 ordinary
barriers. The default five-second settle alone can add about four minutes.
Other admitted jobs may use these gaps. Queue waits across workers overlap and
must not all be added as if sequential wall time. Prior A03 evidence shows the
range: 12 C0 leases used 26.220s admitted plus 296.492s waiting; a later six-lease
Support5 sweep used 5.154s admitted plus 1,168.835s waiting. External cooperating
timing leases have lasted multiple minutes. Admission, rather than tiny census
guest execution, is the main scheduling uncertainty: all 131 C0 counted guest
runs together took 0.173s, with the slowest 14.33ms.

## Preserved baselines and remaining gaps

Read-only validation rechecked all 15 C0 runtime entries, eight unique binaries
and their local source/helper hashes, plus all six installed files in each C0
Debug/RF installation. All match. These baselines need no rebuild.

A08 has nine accepted matched C0 scaling cells: matches16/64/96,
fields16/64/128 and recursive16/64/128, five phases each. Matches128 retains five
parser-limit refusals. Modules16/64 retain ten native-link failures after the
host/native-cache change; modules128 and generics16/64/128 were not attempted
through that known broken native path. The six frozen diagnostic-only inputs
fill frontend/Core coverage after timing is released, without repairing the
immutable C0 compiler or implying a valid native comparison.

The exact-sized counted C0 supplement was attempted after authorization. All
eight unique builds failed with the known native-link staging `FileNotFound`,
blocking all 15 baseline execution configurations. No ownership refusal or
counter result is inferred. `raw/size-aligned-C0` preserves commands, stderr,
emitted LLVM and source snapshots. It used 22.760s admitted plus 40.821s queue.
The compiler and host trust policy were not patched. The C1 supplement uses the
same sources and inputs when available, but a paired allocation comparison at
these exact sizes remains unavailable unless a valid immutable-C0 artifact can
be recovered. The smaller preserved census retains its own valid comparisons.

The RSS preparation defect is already repaired and qualified in commit
`268a77a3e`: old guest-pilot RSS values are explicitly invalid, untouched raw
files remain preserved, and small/large native children retain the same corrected
RSS despite a 256 MiB parent-memory change. No final RSS observation exists yet.
