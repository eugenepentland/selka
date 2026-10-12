# A02 independent constructors and generator folds

The original set and generator public oracles now pass without source changes:18 set tests and8 generator tests, in all five checked-ownership modes. The same oracles and expanded regression also pass ordinary release/debug. This is a focused follow-up qualification; the coordinator still owns the integrated default, retirement, package and full verification milestones.

Base `c3909f2c0fbb97b67acb94714567abe4be33a1ec`; candidate compiler SHA256 `bd1df6820bf43d77432235a27a64a64b95b8afdd28f07ec89b9a38b133f8243e`. Exact inputs, command lines, artifact hashes, counted results and admission receipts are in `summary.json`, `registered.json`, and `raw/*.json.gz`. The compiler consumes A10's independent Support6 owned component pin; final installed-package qualification remains separate.

## Changes

`set(iterable)` copies borrowed aggregate children into independent destination storage. Scalar values require no copy; text iteration already creates each character and keeps its existing path. Explicit `set.add` remains consuming.

String generator extrema keep an owning accumulator. Selected borrowed or unknown strings copy into it, while syntactically fresh strings move. Fresh classification examines only literals, owned calls/invocations, explicit copies and at most64 nested block values; it does not resolve arbitrary locals or change branch-merge rules. Candidate expressions evaluate once; untaken candidates and replaced accumulator values are destroyed. Empty generators keep their traps.

`dict(pair for ...)` reuses complete tuple staging: a fresh whole pair transfers once and splits into both logical fields. A borrowed or unknown pair receives one independent copy first. This fixes the next refusal exposed by the original generator oracle, without permitting arbitrary partial moves.

A07 approved both the contracts and final production diff. Root authored the exact `<fold-accumulator>` source-checker exclusion and test-root import.

## Qualification

- Registered regression:1/1, exercising5 counted native modes and10 empty min/max traps. It covers string/list/set/dictionary/view/record keys, source replacement/destruction, borrowed and fresh extrema, repeated accumulator cleanup, nested generators, single-evaluation side effects, borrowed tuple independence and duplicate-key cleanup.
- Durable native matrix:15/15 checked-ownership cases: expanded fixture + unchanged18-test set oracle + unchanged8-test generator oracle, each release, unoptimized debug, verified release, optimized debug and release without facts. Every case has zero RC events, zero exit-live managed bytes, and clean LLVM/symbol audits.
- Ordinary controls:6/6 across release/debug, preserving the same exact outputs and leak checks. RC events in those legacy controls are recorded rather than interpreted as owned-mode success.
- Source negatives:5/5 each for consuming a borrowed key with explicit add and invalidating a generator's borrowed input. Both remain `E_SINGLE_OWNER_OVERLAP`.
- Shared admission used for all compiler/native work; no runtime timing or RSS claim. Final Guardian result is recorded in the handoff/commit receipt.

## Allocation controls

All values below are whole-program counted release observations on the exact candidate. Input size32 for extrema. Each generator is paired with an equivalent explicit loop using the same source semantics; these are allocation comparisons, not runtime timings.

| Case | Allocations | Managed cumulative bytes | Managed peak | Exit-live |
| --- | ---: | ---: | ---: | ---: |
| Fresh function yield / explicit move loop |96 /96|6144 /6144|256 /256|0 /0|
| Explicit copied yield / explicit move loop |133 /133|8800 /8800|2464 /2464|0 /0|
| Borrowed yield / selected-copy loop |111 /111|7392 /7392|2464 /2464|0 /0|

The fresh pair has32 text-copy events from its string-construction workload in both forms; the generator adds none. Copied-yield and borrowed-yield pairs also agree exactly in text-copy events (64 and42 respectively). All these controls execute zero RC.

The unchanged character-set case has1 allocation,96 cumulative/peak managed bytes and0 text copies under both frozen Support6 and this candidate. This confirms the constructor fix preserves its already-fresh character path. It is not a comparison with the original C0 revision. Managed counters do not measure RSS.

## Preserved failures and limits

The initial investigation lives in sibling `public-constructors-diagnosis/`. Its first handwritten print controls lacked a Stream; corrected controls are separately named and retained. During regression authoring, two test-only assumptions were corrected: dictionary items are typed records rather than tuples, and tuples require whole binding rather than numeric indexing. The initial allocation controls used an obsolete array-comprehension spelling and were replaced by explicit append setup; both input/result versions are archived. None of the A03 source or expected-output oracles changed.

The initial set/extrema candidate passed sets and then exposed dictionary generator staging; that failure is preserved under `raw/before-dictionary-staging/`. No failed case is excluded from the final denominator. The bounded freshness rule may still copy unusual equivalent fresh expressions whose syntax it cannot prove; no general ownership inference was added.

The first Guardian hook found a duplicated test-only release flag constant. The test now imports the existing `e2e_test.optimize_flag`; the final focused receipt passes and the compiler hash is unchanged. Native allocation/oracle evidence was not relabeled from another compiler.
