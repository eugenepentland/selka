# Selected filesystem bodies and capability records

The producer now checks all nine primitive filesystem access operations and all
six scoped file methods, including text/binary read and write modes. It preserves
native argument checks, result shapes, scoped cleanup and single evaluation of
receiver expressions. Filesystem and Stream fields participate in ordinary
record closure; their structural hash-key policy remains unchanged.

The installed comparison passes 59 unchanged fixtures: 47 accepted and 12 exact
diagnostic cases. All 372 source operations pass across native, shadow and
component modes, including exact typed output and nine runtime fixtures in both
normal and release/facts/leak builds. Original B7 text/write inputs are copied
unchanged into this strict corpus. The field-receiver fixture that previously
stopped at operation 326 now passes checking, typed output and execution.

Four fresh authenticated exchanges cover every access/method family. Their 235
distinct altered outcomes are each rejected as ComponentProtocol in both selected
modes (470 rejections); eight unmodified replays succeed. The durable harness
retains frames, payloads and partial results and verifies deployment/source
identity before claiming completion. Five harness tests and all 88 Guardian
checks pass. Earlier failures remain in the evidence archive.

The filesystem pure suites passed 26 tests per mode before the capability-record
follow-up. That follow-up changed only record_types.my and record_type_tests.my;
its record/hash-policy suites passed 14 tests per mode. The receipt distinguishes
these source snapshots. The final source then rebuilt with the unchanged c4f1ea0b
qualified seed and passed the complete installed filesystem comparison.

The installed native host comes from 8987826f05f0cd4adf2d0523ddb8df4262024935;
the body artifact is e5881022e952a5775a636859e18ca0a94a360c26f94c269dbe1d5a7bd2ce529b
(schema 10). Integrate native prerequisites ed562913ecbe58a89f65a3baeb03a66a91a6e611
and 8987826f before this producer. The source base is 0ce4c813f; the later text,
sequence and schema-11 generic work requires coherent integration and a new full
root gate. This proof uses a Debug native host and both guest build modes. It
does not establish full compiler bootstrap or the 1.5-times performance target.

[The receipt](evidence/selka-filesystem-producer-20261011/receipt.json) binds exact
commands, source and deployment hashes, full logs and the captured reply trials.
