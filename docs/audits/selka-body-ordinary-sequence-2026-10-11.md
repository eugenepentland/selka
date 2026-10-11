# Ordinary sequence body closure

The candidate closes ordinary `sum`, `min`, `max`, `any`, `all` and keyless
`sorted` calls on the native scalar families. It preserves two-value min/max,
source evaluation order, collection key snapshots, empty-list hints, lexical
callee shadowing and the existing generator dispatch. Callback and generic-key
sorting remain an explicit source profile boundary. This slice does not establish
compiler self-hosting, native backend/driver closure or bootstrap performance.

The read-only inventory used the installed native host and source-matched 8aae
body deployment. Of 84 source cases, 68 were native successes and 16 native source
errors. The existing producer refused 83; the user-declared `sum` shadow passed.
The initial direct-view success assumption was corrected from native diagnostics:
`sum(d.keys())` and `sum(d.values())` reject storing a live view, while explicit
`list(...)` snapshots pass. Original failed reports remain in the evidence.

Four focused producer helpers retain native node order and temporary ownership.
They construct the folds and sorted copies in Selka from raw syntax and retained
catalog authorities. Native scalar fold arithmetic uses node-only numeric lowering;
ordinary source binary expressions keep their existing temporary lowering. Reverse
sorting captures the input before evaluating the reverse expression. A native
runtime control that mutates that input proved the sorted copy keeps its earlier
three-item snapshot; its initial four-item assertion and failure are retained.

Two separate native admissions use existing schema-10 node forms. Keyless sorting
requires a writable receiver, unit result, exact list/list/bool argument types and
source/keys reading the same local. Dictionary and set key snapshots require zero
arguments and a canonical list of the exact key element type. Callback key lists,
foreign owners, result types, arities and operands remain rejected. The dedicated
native suites passed 22 list tests and 23 dictionary tests, respectively.

The first authentic 126-case, 378-operation check replay found 12 differences.
Three exposed the dictionary snapshot admission gap. Eight exposed signature notes
stored in `related` instead of native `provenance.requirement`, including a two-note
serialization failure. One exposed an earlier FixedArray literal migration gap in
the inherited producer; its source/receipt is retained for the separate follow-up.
The intended ordinary-builtin FixedArray rejection now uses explicit construction.
No captured request or reply header was edited.

The final selected inventory contains 126 cases: 97 native-valid programs, including
10 expected runtime traps, and 29 source diagnostics. Normal and release admission each passed all 1,338 operations, with 378 additional
check operations and 12 authentic mutated-reply refusals. Five Python harness tests
passed. The Debug host and source-matched package identities are archived in the
receipt. The full pure suite of 97 modules and 567 tests per mode remains pending. Successful
source fixtures must execute with the native tuple; source errors must retain their
ordered diagnostic contract. Release executions include fact and leak checks.
