# Report latest starts and scheduling slack

This task continues the delayed-dependency planner: `needs` accepts strings
(lag zero) or exact `{"id":ID,"lag":N}` objects with integer lag 0..1000000.
All delayed-dependency validation, input limits, error precedence and error
outputs remain unchanged.

Extend every successful timing entry from `{"id":ID,"start":S,"finish":F}`
to also include integer `latest_start` and `slack`. Add a top-level `critical`
array containing exactly the zero-slack job IDs, sorted in ASCII order. Keep
`order`, `layers`, earliest `start`/`finish`, and `makespan` unchanged.

Use the existing makespan as one common project deadline. `latest_start` is the
latest that a job can start while all jobs still finish by that deadline and
all prerequisite finish-plus-lag constraints hold. `slack` is latest start minus
earliest start. This is not simply the deadline minus that job's finish: a job's
successors may constrain it more tightly. Lags matter in the backward constraints
as well as in earliest timing. Disconnected components share the same deadline.

Zero durations and zero lags are valid. A zero-duration job can be critical.
The empty graph adds `critical:[]` and still has empty timings and makespan zero.
Cycle and other errors acquire no success-only fields. No input fields or
resource constraints are introduced; unlimited parallel workers still apply.

Cover multiple critical paths, positive slack, lag-constrained joins, disconnected
components, zero-duration chains, old string dependencies, permutations and bounds.
