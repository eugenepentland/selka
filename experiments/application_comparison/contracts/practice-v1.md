# Draft matched preparation exercises

Each language receives one small, unrelated utility project containing three
repairs, a concise language-specific guide, and public input/output checks.
The provisional common preparation ceiling remains 20 minutes. These exercises
are construction drafts; review and calibration must precede scoring.

The utility accepts application inputs of up to 256 bytes and writes exactly one
JSON integer plus a newline, with exit status zero for all defined inputs. The
common harness input envelope is at most 2 MiB; inputs above that envelope are
outside this exercise. Within it, more than 256 bytes produces -1. An implementation
may inspect an extra byte to detect overflow, or receive bytes through its host.
Inputs are exact bytes, without whitespace trimming. Operational I/O failures may
exit nonzero.

| Input bytes | Result | Exercise |
| --- | ---: | --- |
| `m` | 42 | Import and call a helper module that multiplies its integer argument by 6; pass 7. |
| `f0` through `f9` | 0 through 9 | Use a fallible digit parser and handle its failure explicitly. |
| `fx`, `f`, `f12`, invalid UTF-8 after `f` | -1 | Preserve failure rather than silently treating it as zero. |
| `d` | 9 | Repair an unresolved identifier by using the existing named constant for nine. |
| Any other input, empty input, or more than 256 bytes | -1 | Defined transport behavior. |

The starter contains exactly three deliberate defects: `m` passes 6 instead of 7,
the failed digit parse returns 0 instead of -1, and the diagnostic branch references
an undeclared identifier instead of the existing constant. In statically checked
languages the unresolved identifier can prevent the entire program from running;
the guide should tell participants to repair that diagnostic first. That difference
is part of onboarding and must be recorded, not disguised as an identical runtime.

Use idiomatic standard-library facilities and local modules only. Keep a separate
correct solution for coordinator verification. Neither solution code nor pilot
task content is included in the participant starter. Preserve the same behaviors
across languages, without adding extra exercises or deliberately awkward APIs.

The public checks cover all ten digits, each command, invalid forms, non-UTF-8,
and oversized transport. Since every valid command is at most two bytes, long
invalid inputs do not independently prove the existence of a size guard. The
guide should explain how to run/check the project and the
relevant import, error-handling and diagnostic rules. It must not contain scored
task solutions, app source, hidden seeds or hidden answers. Retain this guide and
the participant's own practice history during the later task.
