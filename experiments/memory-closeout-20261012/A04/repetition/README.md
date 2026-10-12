# Independent repetition repair

C0's generated text repetition gathered the same owned source into a list on
every iteration; checked ownership therefore refused an ordinary borrowed text
argument. The committed migration reproducer is `../migrations/repeat_temporary.my`.

The repair keeps repetition as a binary operation, using Core's existing
borrowed-input, independent-result implementation. Text and bytes allocate the
final octets directly. Lists copy each borrowed managed child before moving it
into the result, fulfilling the existing `PY-REPEAT-1` independence contract.
The generated copy is specific to repetition. Ordinary list append still moves
its input. Named `*=` assigns the completed independent result, and empty-list
repetition bypasses the count loop. The native octet length bound includes the
trailing terminator before calculating its signed capacity.

A07 reviewed the complete static ownership path, including use of the current
block after copying an aggregate and the signed/unsigned native size bounds.
Its separate runtime-contract change must admit
`myl_core_octets_repeat_signed` and `myl_core_octets_repeat_unsigned` as fresh
results borrowing their inputs. This directory does not claim full integrated
qualification before those contracts land.

Prototype compiler SHA256:
`077aa182f221694ed29e1757a1a6f249bdd8196018804f8e459747c8c193dff8`.
`lists-01/results.json` records the exact source diff and all five counted modes:
release, unoptimized debug, verified release, optimized debug and release without
facts. Dynamic text children, nested lists and wide record children survive
replacement of their input owners. All five runs pass with zero emitted/runtime
RC, no managed live bytes at exit, and clean LLVM and symbol checks. This fixture
allocates 52–54 whole-program managed blocks (3,424–3,552 cumulative bytes), with
1,856 peak managed bytes. Those are current fixture costs, not a before/after
saving or RSS observation.

`ordinary-01.json` passes all 17 existing `python_expressions.my` guest tests,
including the snapshot-before-`*=` and nested independent-copy assertions. The new
complete repetition fixture also passes in ordinary mode, including operand
evaluation order and mutable parameter/field writeback. Signed maximum and
unsigned maximum nonempty repetitions both report `R_MEMORY_BUDGET` under the
8 MiB runtime ceiling. All source files pass the formatter.

`unsupported_place.my` preserves the existing ordinary and checked-ownership
boundary: `holder.values *= count` is `E_TYPE`, because the current repetition
assignment syntax supports a binding. The supported mutable-field call is
`repeat_in_place(mut holder.values, count)`.

Earlier reports retain rejected exploratory fixtures: `initial.json` lacked an
explicit bytes hint for an empty literal; `initial-02.json` has the expected
unaudited-helper native refusal before A07's contracts; `initial-03.json` confirmed
the existing nested-place assignment boundary. They are not successful runs.

`support4-01/` passes all ten counted lanes and all three negative cases on
integrated source `66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
This compiler includes A07's fresh helper contracts and the byte-kind repair.
Every admitted run has zero RC events, zero managed exit-live bytes and clean
LLVM/symbol audits. `support3-01/` preserves the previous missing-object failures
and interrupted batch; it is not counted as qualification.

For final integration, run `qualify.py --compiler COMPILER --zig ZIG --phase NAME --source-commit SHA`
without `--lists-only`. It owns bounded build admission, publishes exact source
and binary identities, and requires ten counted lanes plus three negative cases.
Compiler/source hashes and raw commands/counters remain in the resulting phase
directory. Build durations are operational observations, not controlled timings.
