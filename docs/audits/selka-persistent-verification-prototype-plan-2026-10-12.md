# Persistent verification server prototype and measurement plan

Date: 12 October 2026. Status: proposed experiment; implementation has not started.
Team: one coordinator and three workers. Design baseline:
`67fefe2d6b914e793a2bb79a2906eac909addb19` on
`codex/dl-wave2-20261012-integration`.

Prototype a small local server through which agents can use the existing retained
verification sessions. Measure whether it reduces repeated setup, waiting and
duplicated work enough to justify maintaining it. Keep ordinary builds and
installed compiler commands Python-free; this is an opt-in developer tool.

The first decision is whether shared access to retained sessions helps real agent
workflows. Automatic merging of independently submitted verification requests is
a separate experiment with stricter correctness requirements. A useful outcome
can be to keep the existing session and stop the server experiment.

## What the current evidence supports

The [wave 2 report](../../experiments/development-loop-wave2-20261012/REPORT.md)
and [raw warm captures](../../experiments/development-loop-wave2-20261012/S10/raw/final-warm-summary.json)
establish these starting observations. They are historical context, not the new
prototype's matched baseline.

| Observation | Implication for the experiment |
| --- | --- |
| Complete warm requests took 47.72–56.50 seconds; gate execution occupied 41.33–43.80 seconds | Persistence alone cannot remove most complete-verification time |
| Preparation and lookup took about 8.5–10.9 seconds for one-shot requests and 3.38 seconds for the retained repeat | Automatic access to retained state is a plausible benefit |
| The retained repeat hashed and enumerated nothing, but still made 154,145 metadata observations | Keep live validation; zero hashing does not mean zero checking |
| An incompatible launcher differed in `CODEX_THREAD_ID` and missed all receipts | Actual agent environments may prevent sharing; measure compatibility first |
| Existing checkout locks and native artifact claims already serialize or reuse some matching work | Baselines must preserve these mechanisms; do not manufacture duplicate builds |

The existing [session contract](../tooling/cache-retention.md#warm-validation)
is sequential, tied to one worktree and startup environment, and guarded against
loaded-code/runtime mutation. It supplies retained snapshots and existing action
receipts. It does not supply a socket, multiple clients or subscriber-aware
cancellation. The [lifecycle evidence](../../experiments/development-loop-wave2-20261012/S02/handoff.md)
qualifies serialized contenders, not shared in-flight subscriber continuation.

## Smallest useful design

Use a same-user Unix socket broker, with one separate `cache_session.py` process
per execution context. Each worker processes requests sequentially. Initially
support verification only, with at most three workers and one active verification
per checkout across all its contexts. Keep existing checkout locks and shared
build/gate admission as the authorities for execution.

Clients submit bounded requests to the broker; the broker routes them to retained
workers; workers invoke the existing verification coordinator and its admitted
commands. Keep working directories, environment changes, signal handling and
output redirection inside the worker process. The broker never edits a worker's
environment between requests.

Distinguish three identities:

| Identity | Contract |
| --- | --- |
| Request | Protocol version, client/request ID and validated command arguments; used for routing and response correlation |
| Execution context | Canonical checkout and directory identity, actual coordinator code generation, complete startup environment, resolved Python/Zig and host identities, and cache locations |
| Verification action | Existing production key over declared sources, tools, producer/ABI/seed/configuration, inputs, membership and execution controls; remains the authority for reuse |

Derive identities from actual inputs through reviewed production helpers. Client
IDs, branch names, HEAD alone or identical argument strings never prove reusable
work. Distinct worktrees have separate workers and mutable Zig caches even if
their commits match. Shared immutable artifacts and receipts retain existing
store, lease and authentication rules.

Measure the context in the executing worker, including CPU affinity, umask,
resource limits, interpreter and tool resolution. Client-supplied environment or
claimed host metadata cannot prove compatibility. Apply supported validated
settings or advertise the actual worker settings and reject mismatches. Record
environment digests and bounded changed-facet names, not raw environment values.

The default client supplies its effective startup environment explicitly; routing
requires an exact compatible context. Preserve the current normalization contract,
including `CODEX_THREAD_ID`. Do not silently substitute the server's environment
to increase hit rates. An explicitly selected named execution environment is a
possible later feature and must be reported as such.

Keep source watching and revalidation in the existing coordinator. An edit before
a new request changes its inputs and invalidation normally. An edit during a live
request, including an edit reverted to its old bytes, retains fail-closed behavior.
Never silently retarget a running request. Compiler generations use their actual
artifact identities. Loaded coordinator, Python or library changes retire the
session and require a newly authenticated worker.
Version the broker's own loaded code/runtime as well; replace its process when
that generation changes rather than hot-reloading live ownership state.

Use a private socket directory and peer credentials, bounded message sizes and
queues, bounded retained entries/watches, capped output and idle worker eviction.
Provisional prototype defaults are three workers, 16 queued requests in total,
a 10-minute idle expiry, and the current session's 16-snapshot/262,144-entry cap
per worker. Measure combined memory and watch use. These are experiment resource
bounds, not newly calibrated production deadlines. A slow reader must not block
verification; report truncated optional output explicitly and preserve verdicts.

## Request ownership and sharing

Implement ordinary `submit`, status, cancel and shutdown first. Every `submit`
represents a distinct verification request. In particular, complete verification
retains every always-fresh check for each independently submitted request.

After basic routing works, prototype an explicit `follow(job_id)` operation.
Following observes the same advertised logical job and its exact input manifest;
it does not request another fresh verification. Return the original execution ID,
source/context identity and observation status. A follower must not present that
result as verification of another worktree or later revision. An attachment is
never an additional timing sample or test execution.

Distinguish pending, authenticated-manifest and terminal job states. Before real
planning and artifact validation finish, a queued job has only a request/context
description. Publish the bound manifest from authenticated planning, then the
terminal result with actual executed coverage and stability. A follower attaching
early must see these transitions; initial HEAD or source hints are not a manifest
or a success claim.

This explicit shared-job workflow lets three agents agree to observe one common
qualification job. Compare it separately from three independent requests: the
work requested is different. The same workflow is also possible by distributing
an existing coordinator result, so report whether the server adds useful behavior.

| Event | Required behavior |
| --- | --- |
| A queued request is canceled | Remove that request without launching work or affecting other requests |
| One subscriber leaves a shared job | Continue while another subscriber still needs it |
| The last subscriber cancels or disconnects | Terminate and reap the owned lineage, release admission/claims, retire the session and reject incomplete publication |
| Cancellation arrives after terminal completion | Stop delivery only; do not invalidate a completed, independently valid receipt |
| Broker or worker crashes | Fail outstanding requests, clean up owned descendants and revalidate normally on restart |
| Worker requires restart | Return an explicit restart/incomplete result; start a fresh authenticated worker for later requests |

Process ownership follows the broker's PID and birth identity rather than the
initiating client's lifetime. Do not fork retained watch authority. Queued work
holds no build/gate slot. Broker restart discards all live subscriptions and
retained authority; persisted receipts still require ordinary validation. Do not
silently retry canceled or potentially effectful work.

Give `follow`, last-subscriber departure and terminal publication one documented
ordering across the broker/worker protocol. A job in cancellation cannot acquire
new subscribers or return to running; queued successors wait for lineage cleanup.
Test publication racing with cancellation and distinguish authoritative completion
from delivery of its acknowledgment.

Use a broker epoch and client request IDs to handle reconnects and lost replies.
Within a live epoch, a repeated ID returns the known job/status; conflicting
arguments are rejected. Expired IDs and a new broker epoch return an explicit
unknown/ambiguous outcome, never an automatic second execution. Any bounded
request-history expiry must preserve that refusal behavior.

Automatic coalescing of independent requests is deferred. Consider it only if
measurement finds repeated eligible work that existing locks/receipts do not
already avoid. It would require exact action identities, explicit pure/cacheable
eligibility and each follower's own current validation. `force`, fresh effects,
filtered qualification, performance captures and long-qualification obligations
must not become reusable by attaching to another request. The current batched
build graph must retain its coverage and parallelism; do not launch a separate
full build for every action to implement sharing.

## Three worker assignments

All workers begin at one newly recorded implementation base in separate clean
worktrees. Recheck current refs and ownership first. No worker creates subteams,
merges peers or starts a full gate independently.

| Worker | Ownership and deliverables |
| --- | --- |
| P01 Service and client | New `scripts/verification_broker.py`, client and protocol/routing tests; socket, context registry, bounded queues, worker reuse and explicit job subscriptions |
| P02 Lifecycle and correctness | New `scripts/verification_broker_worker.py` and adversarial tests; session bridge, process ownership, cancellation/publication boundaries, crash cleanup and isolation evidence |
| P03 Measurement and decision | Harnesses and manifests under `experiments/persistent-verification-prototype-20261012/`; matched baselines, work/latency/resource accounting, admission schedule and independent final report |

The coordinator owns the protocol agreement, integration ledger, existing
`cache_session.py`, `verify_cache.py`, process/store adapters, build registration,
input declarations, configuration qualification and documentation. Workers send
small shared-file patches with caller contracts and tests. No worker changes
compiler ownership semantics, default memory mode, ABI, seed trust, Zig pin,
Guardian implementation or the other teams' branches.

Agree request/context manifests, lifecycle states, worker handshake, log limits,
telemetry schema and cancellation terminal boundary before P01/P02 implementation.
Include worker host settings and manifest-state transitions in that agreement.
P03 independently reviews those contracts before freezing its harness.

## Execution stages

1. **Establish the opportunity.** Record the actual environment/context identities
   of three agent clients. Measure how many requests could use the same retained
   worker without normalization changes. Prepare one compiler/component bundle
   and verify host/seed readiness, native linking, telemetry isolation and exact
   required inventory before queuing expensive captures. Freeze existing
   one-shot and retained baselines, with their normal receipt reuse enabled.
2. **Build routing and persistence.** P01/P02 add the thin broker and isolated
   workers. First demonstrate one client, reconnects and sequential requests;
   then two and three clients with bounded queues. Run focused contract tests.
   P03 compares ordinary submissions before subscriptions are enabled.
3. **Qualify explicit subscriptions and lifecycle.** Prove survivor continuation,
   last-subscriber cancellation, broker death, worker death, publication races,
   context isolation and bounded resources. Keep unsupported sharing disabled.
4. **Freeze and measure.** Integrate once, re-export the inventory, review any
   changed configuration consumers and freeze candidate/harness/tool hashes.
   Run one required complete candidate gate and formatting, plus the bounded
   comparison cohorts below. Keep workers' later edits outside the frozen tree.
5. **Decide.** Publish raw evidence and a keep/iterate/stop recommendation. Expand
   ordinary-edit/tail qualification only for a useful candidate. Propose automatic
   action coalescing separately if the measured opportunity warrants it.

## Measurement matrix

Compare three paths: existing one-shot requests, existing retained sessions, and
the broker. Concurrent baselines use independent clients with the existing locks
and receipt stores intact. Include a manually shared existing retained session
where that represents the same shared-job workflow.

| Cohort | Initial samples and required observations |
| --- | --- |
| Process startup and reconnect | Separate startup-to-ready, first completed request and steady requests; record first-use costs and how many requests amortize them |
| Unchanged complete verification | Five balanced triples after equivalent legitimate priming; compare exact inventory, fresh-action counts, identities, queue, execution and response time |
| One, two and three independent clients | Five balanced cohorts per client count, simultaneous and staggered arrivals; compare per-client latency, cohort makespan, fairness and aggregate work |
| Explicit shared job | One submitter plus two followers; test early/late attachment and cancellation; record one execution with multiple observers, not three fresh verifications |
| Actual compiler development | Six pilot cases: implementation edit/rebuild, relevant native-test edit, guest edit, newly failing transitive dependency, revert, and coordinator-code edit requiring restart; preserve expected verdicts |
| Incompatible contexts | Different worktree, environment/thread ID, compiler/tool, flags/mode, profile and limits remain isolated; record the real three-agent hit rate |
| Cold and recovery behavior | Fresh process with warm disk evidence; private empty verification store; server restart; one justified private cold native-cache case; never clear shared caches |

Use equivalent private stores and the same meaningful edit sequences. Keep source,
compiler/producer, ABI/seed, tools, normalized environment, settings and workload
coverage matched. Record unavoidable transport implementation identity differences
and prime each mode legitimately. Do not rewrite receipt keys, disable baseline
reuse or force every baseline job to create an artificial deduplication win.

Prepare the initial tool/compiler bundles under build admission, outside
steady-request measurements. For an actual compiler-source edit, start the
edit-to-feedback clock before the edit and include its resulting compiler rebuild,
artifact validation and verification. Do not prebuild away the work under test.
Keep compiler and guest optimization modes explicit and matched between paths.
Single-client isolated captures use existing coordinator-owned bounded timing windows with
identical bounds. Complete requests can retain the explicitly named 1800-second
qualification exception; short focused windows start at 300 seconds. Queue time
remains separate. These bounds are not latency targets.

Concurrent captures need particular care: each current verifier owns its own
admission, and timing authority is process-local. Do not place an outer timing
slot around independently admitted clients, which would deadlock or distort the
experiment. Initially report ordinary-admission concurrent runs as operational
observations. An isolated concurrent cohort requires a separately reviewed
coordinator-owned admission contract covering all clients and descendants, with
no raw-lock reservation, environment-marker authority or nested admission. If
that facility is unavailable, leave isolated concurrent speedup unqualified.

Record request acceptance, context routing, startup, worker queue, checkout lock,
shared admission, execution, validation/publication and response as distinct spans.
Link client/request, logical job and actual execution IDs. Count worker starts,
native compilations, actual selected/executed/reused tests, fresh effects, files
and bytes hashed, metadata observations and receipt hits. Record CPU and sampled
process-tree memory with their collection scope; per-process maximum RSS is not
aggregate memory. Include output completeness, cancellations and failures.

Report per-client latency and cohort completion time alongside total executed work.
Never add overlapping spans into wall time. Five samples support a pilot decision,
not p95 qualification. If useful, expand to 20 balanced comparisons, then at least
40 per important edit class for empirical percentiles, still without a claim of
stable population tails. Use focused real workloads rather than repeatedly forcing
the full gate merely to increase the sample count.

## Correctness cases that block adoption

P02 must test cancellation while queued, running and publishing; one subscriber
leaving while another continues; last subscriber departure; broker death before
and after worker registration; worker crash; detached/thread-owned descendants;
PID reuse and neighboring unrelated jobs; source mutation and byte-restored ABA;
symlink/PATH changes; missing input or watcher overflow; runtime/library/code
replacement; malformed/oversized messages; output truncation; slow readers; and
queue/connection churn. Bound each adverse test and prove cleanup/retry behavior.

Every accepted completion must identify its exact execution and coverage. Preserve
negative dependencies, directory membership, transitive imports, effect eligibility,
seed authentication, source stability, claim release and publication rollback.
No lost connection, unknown identity, partial telemetry or cached diagnostic can
create success. Prove all required fresh actions still execute for every distinct
submit, and that a follower never receives a new freshness claim.

Use the repository-pinned Zig, worktree-private local caches and on-disk TMPDIR,
shared global cache, existing retention leases/pins and normal commit hooks.
Keep the final candidate frozen through all captures. Do not change global slot
limits, CPU reservations or hard execution policies as part of this experiment.
Guardian feedback entries remain unnecessary.

## Decision criteria and timebox

These are proposed engineering thresholds for this experiment, not new roadmap
requirements or watchdog policies. Correctness and bounded cleanup are mandatory.

- **Keep the persistence layer** if reconnecting real clients avoid repeated
  startup and show at least 10% lower median end-to-end latency than one-shot
  execution on a named representative workload, while adding no more than 5%
  median or 10% empirical-p95 overhead against the existing retained path once
  sufficient samples exist. A gain only against one-shot mode is reported as
  automatic retained access, not an improvement to retained execution itself.
- **Claim a concurrent performance gain** only with matched work and valid
  measurement scope: at least 15% lower cohort completion time or 20% lower
  aggregate CPU/executed work over the existing concurrent baseline, with no
  unexplained single-client regression. Operational queue observations motivate
  a follow-up; they do not establish an isolated causal speedup.
- **Keep explicit subscriptions** only if survivor/last-subscriber behavior is
  proven and the shared-job workflow is useful. Report its benefit separately
  from independent-request comparisons and from automatic action deduplication.
- **Stop or simplify** if real contexts rarely match, existing locks already
  remove the repeated work, retained sessions provide the same practical benefit,
  or process/watch/memory costs outweigh measured savings. Preserve the findings
  and keep the existing verified path available.

Timebox the first review to two working days of prototype work with three workers.
Aim to have a routing/persistence result and a clear lifecycle status then; this is
a review checkpoint, not a promise of production readiness. Allow roughly another
one to three working days for useful-candidate qualification and shared admission
availability. New concurrent timing authority or automatic action sharing needs a
separate scope/estimate after this evidence. Do not extend the experiment silently
to finish a general-purpose build service.

The final deliverables are an opt-in prototype, exact source/tool/context manifests,
focused correctness evidence, one complete integrated candidate qualification,
raw per-request and cohort measurements, startup/amortization and resource costs,
and an explicit keep/iterate/stop recommendation. The broader development-loop
and self-hosting acceptance requirements remain separately tracked.
