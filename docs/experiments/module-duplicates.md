# Duplicate discovery across modules

`discover-project-duplicates` checks the complete reachable module graph before
running the existing advisory exact/approximate discovery engine:

```sh
zig build run -- discover-project-duplicates examples/module-duplicates/main.my --approximate --timings
```

The example reports price/quote as one exact group and alternate as one near match,
showing the changed literal 3 -> 4. Names and file paths identify each member. Shared
body excerpts use original source text. No code is moved or merged.

The command accepts the same `--min-nodes`, `--population`, `--approximate`,
`--max-work`, and `--timings` options as single-file discovery. The population label
applies to the whole invocation; directory names do not automatically classify
individual modules. All functions in reachable imported modules participate,
including uncalled private helpers. Files outside that graph are not searched.
Invalid imported bodies/types/ownership/effects reject before producing candidates.
Approximate matching retains its work limit and explicit truncation reporting.

The checked module representation already supplies logical-module-qualified nominal
types and resolved callee names to the canonical serializer. Consequently, aliases
for the same imported type/helper normalize to the same identity, while same-named
types and callees in different modules remain distinct. Function IDs and imported
alias spelling do not establish equality. Pure scalar bodies can match across module
boundaries; direct self-recursion retains the existing normalization rule. This
extends the accepted input scope without changing the near-v1 canonical comparison
format; the exact canonical format is now `exact-v29`, which names assertion
statements and their trap messages.

The report explicitly separates structural findings from declaration visibility
and dependency policy. Export lists are not part of body-equivalence comparison;
domain-private contracts retain their existing canonical fact. An exact body match
is not permission to move code through a private boundary, proof that domain intent
is identical, or proof that a proposed shared helper obeys the chosen import policy.
Use interface inspection and `check-policy` when reviewing a concrete refactor.
There is no automatic merge, policy change, or type-validity gate based on similarity.

Project timings report frontend time including loading/import/interface/type work,
discovery time, reachable module count, original source bytes, AST/typed node counts,
canonical bytes, and functions examined. Source-byte counts exclude source-map
separators. These observations are not performance gates or whole-repository counts.

Acceptance checks cross-module exact groups, shared imported identities under
different aliases, distinct nominal types, distinct module-local callees, original
member paths, exhaustive allocation-failure cleanup through checking and discovery,
real CLI population/timing options, deliberately truncated approximate search, and
rejection of invalid dependency bodies without partial discovery output. The example
also executes a non-truncated approximate comparison with the literal edit exposed.

[Module quality reports](module-quality.md) now account for exported interface roots.
Remaining tooling work includes module formatting, broader candidate-index/corpus
scaling review, project native parity, and schema/incremental integration. Generics and the other unfinished roadmap tracks
remain pending.

Approximate search now uses the [near-v3 indexed and banded search](approximate-discovery.md).
This changes budget accounting while preserving header eligibility and similarity.
