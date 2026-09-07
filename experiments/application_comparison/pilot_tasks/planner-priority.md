# Add explicit job priority

Extend v1 jobs with an optional `priority` integer from -1000 through 1000. Missing
priority means zero. Booleans, floats, nulls, out-of-range values and duplicate keys
retain the normal schema/transport failure rules. All original required fields
remain required; other extra keys remain invalid.

For `order`, choose the highest-priority currently-ready job after each removal;
break ties by ASCII-smallest ID. Priority never permits running a job before its
prerequisites. Dependency-round `layers`, unlimited-worker timings, makespan,
validation precedence and cycle-blocked reports retain their v1 meaning.

Old inputs must produce exactly their old results. Cover negative/default/tied
priorities, a newly-ready high-priority job, permutations and cyclic graphs. Do not
change the output schema or apply priority sorting to unrelated report arrays.
