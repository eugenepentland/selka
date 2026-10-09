# Goals and design principles

Selka aims to make AI-driven software development fast and reliable. Its simple,
explicit language lets agents understand and change code with little surrounding
context, and makes those changes easy for humans to review. Incremental
compilation and testing keep feedback fast, while native execution targets
performance competitive with Rust and Zig.

This is the current statement of intent, agreed on 9 October 2026. The
[current language reference](current-language.md) describes implemented behavior;
dated proposals and experiments retain the history behind individual decisions.

The language is named **Selka** (pronounced **SELL-kuh**), chosen on 9 October
2026 to replace the placeholder `mylang`. Older records use the placeholder;
the [project introduction](../README.md) explains the current tooling names.

## Local reasoning

An agent should be able to answer the important questions about a piece of code
from the code and its nearby declarations:

- What values can this operation change, and what remains unchanged?
- What arguments does it take and what does it return?
- Which expected failures must the caller handle?
- What authority does it need to access files, the network, or other external state?

Value semantics, explicit mutation at declarations and calls, typed boundaries,
named arguments, and explicit failure handling make those answers visible.
Compiler context and interface tools provide the relevant facts when a declaration
is elsewhere in the project.

Reducing the context an agent must retrieve is the same design concern as making
a change easy for a human to review. Human readability and agent development
speed are complementary outcomes of local reasoning. Neither Python familiarity
nor terseness should override a clearer contract.

## Competitive runtime performance

Native execution should compete with Rust and Zig on equivalent work. Runtime
speed is a core goal alongside usability and development speed. Ordinary records,
collections, and functions should compile efficiently without requiring users to
restructure every program around low-level memory management.

Storage sharing, copy elimination, in-place updates, and check elimination are
compiler responsibilities. Performance tools should explain the copies,
allocations, and checks that remain so a programmer can act on measured costs.

Compare the same workload, verify its output, and state the safety settings,
build modes, and timing boundaries. Report gaps as well as successes. The
[benchmark snapshots](benchmarks.md) are evidence of progress, not a general
promise of parity. Changes to the language or runtime should earn their place
through real applications and measurements.

## Fast incremental compilation and testing

A small edit should repeat only the work it affects. Checking, compilation,
linking, and testing all contribute to the time between an edit and useful
feedback; a fast type checker alone is not enough.

Incremental builds, dependency-aware test selection, and reliable reuse of
successful results should make frequent, substantial integration testing
practical. Agents should be able to verify behavior across components without
paying for unrelated work on every turn. Diagnostics should explain mistakes
and make repairs straightforward.

Measure cold work, unchanged work, and representative edits separately. Include
verification time when evaluating the development loop. Current debug builds
reuse compilation units; release builds optimize the whole program, with a
different rebuild cost. See [native builds](tooling/native-build.md) and
[guest tests](tooling/guest-tests.md).

## One way to express each concept

Keep a small, consistent set of language mechanisms and one canonical spelling
for each concept. Avoid equivalent syntactic alternatives, overlapping features,
and implicit behavior that requires special knowledge to interpret. A canonical
formatter removes routine presentation choices.

Explicitness should carry useful information. Mutation markers, named parameters,
and failure declarations explain a contract; redundant declarations and repeated
facts add work. Familiar indentation, expressions, and control flow help readers,
while deliberate departures from Python serve the same local-reasoning goal.

This principle concerns how the language expresses information. Programmers can
still choose different algorithms and data structures for different problems.
The [tour](tour.md) shows the current spelling of the core ideas.

## How progress is judged

| Goal | Evidence to collect |
| --- | --- |
| Local reasoning | Context needed for a realistic edit, repair attempts, correctness of the result, and review effort |
| Runtime performance | Equivalent application and kernel workloads against Rust/Zig, with output and configuration checks |
| Compilation and testing | Cold and incremental build/test latency, work reused, and integration-test cost after representative edits |
| Simplicity | Redundant mechanisms removed, migration friction, and clarity in real programs |

Runtime speed and short build times support the development goal, but neither
alone establishes faster end-to-end agent task completion. Agent studies should
record failures and verification work as well as successful edits. Current
capabilities, experimental proposals, and measured results should be labelled
separately in public documentation.

[Back to the project](../README.md) · [Language tour](tour.md) · [Benchmarks](benchmarks.md)
