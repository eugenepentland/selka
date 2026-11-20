# Required project import policy (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Enforcement

Policy and configuration identity participates in successful-verdict caches and
in `project-dependencies-v1` and native-test receipts, so a stricter policy
invalidates an earlier pass even in a warm cache. Native test snapshots and the
offline package driver carry the entry project's configuration into their
isolated snapshots, so selected provider graphs and locked package builds
enforce the same policy as the live project.

Evaluation covers every resolved direct import, including imports
whose declarations are unused, and runs before any cached success is returned.
