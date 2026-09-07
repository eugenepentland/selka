# Support delayed dependencies

Extend the v1 planner so each `needs` entry may be either an identifier string
(existing behavior, lag zero) or exactly `{"id":ID,"lag":N}`. `id` follows the
existing identifier rules; `lag` is an integer from 0 through 1000000. Booleans,
floats, null, extra/missing object keys and invalid identifiers are schema errors.
Strings and objects may be mixed in one dependency array.

A job may start only after each prerequisite finishes plus that edge's lag.
With unlimited workers, its earliest start is the maximum of those finish-plus-lag
values, or zero for a root. Finish remains start plus duration; makespan remains
the maximum finish. Input job and dependency permutations cannot affect output.

The underlying dependency graph determines `order`, `layers` and cycle blockage;
lags do not change those outputs. A self-dependency remains a cycle even when its
lag and the job duration are zero. Preserve all v1 transport and size limits.

Duplicate dependencies compare decoded prerequisite identifiers, regardless of
string/object representation or lag. For example, `["a",{"id":"a","lag":1}]`
is a duplicate dependency. Preserve validation precedence: schema, duplicate job
IDs, duplicate dependencies, unknown dependencies, then cycles. Error output
shapes and successful output fields remain unchanged. Old string-only inputs
must produce exactly their old results.

Cover mixed entries, zero/maximum lags, branching/joining graphs, zero-duration
jobs, repeated/unknown IDs, malformed objects, permutations and supported limits.
