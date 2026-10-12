# Integrated configuration qualification

The coordinator explicitly qualifies configuration projection SHA-256
`686631858644a1ce4535ac1f981f3338421ff46e3f0f3ca10d7e5de43c14b655`.
This replaces the old reviewed `7cefed80…` pin after consumer review, not by
computing and automatically accepting the observed digest.

S04 reviewed all 212 configuration files excluding the declarative input-list
file, all list consumers, the strict parser/export agreement, tool/Guardian/build
context, current source/artifact authority, and actual installed producer version2
metadata. Both tooling-units (11 files) and text-scalar-units (7 files) authenticate
through the real writer, provider inventory and v4 action caller with pinned tools.
Absent metadata retains whole-artifact identity. Actual optimize tags are lowercase.

The final exported inventory contains 46 groups, 101 required/registered members
and zero unknown members. Its canonical key is
`48fb1a4ac5d0b3e6d162f4e9b587ba4e4d8adb0e7ef56377f2ad8c61328f7fdf`.
Producer tests declare every copied source/oracle and build_test_inputs.zig itself.
Unrecognized declarations, arbitrary configuration edits and configuration drift
continue to disable projection; all snapshots remain watched during reuse.

Focused coordinator checks passed 74/74, process checks 33/33, retained-session
checks 15/15, follow-up producer/telemetry/stability checks 27/27. Native preparation
passed 41/41 steps and scalar root passed 9/9. Native matching-filter execution
passed, and a nonexistent filter returned the required failure status 1. Logs and final inventory are retained
in this directory. These scoped checks support configuration qualification; S10's
full frozen-candidate gate, performance and edit matrix remain separate acceptance.

Two exploratory combined-suite invocations were invalid: setting PYTHONPATH made
cache tests correctly disable reuse; importing all suites into one process made
the session startup guard reject preloaded helpers, and running child process
fixtures from scripts/ hid the scripts package. The supported independent commands
from repository root pass, using on-disk TMPDIR. No product change was made to
suppress those guards.
