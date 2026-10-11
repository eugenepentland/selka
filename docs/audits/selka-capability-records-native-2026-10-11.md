# Capability-containing records in selected body values

The unchanged filesystem source comparison reached operation 326 before the
selected checker rejected a `Ports` record carrying `Filesystem`. The native
compiler accepted the program. An authenticated request/reply capture isolates
the refusal as `P_BODY_PROFILE: record field type is outside the admitted body
closure`. The fixture also checks that a receiver-producing function runs once
per filesystem call.

The native record policy now accepts the already-admitted Filesystem and Stream
leaves in ordinary value schemas, including through recursive record/list
dependencies. Its structural hash-key policy still rejects those capabilities.
Open handles stay outside ordinary value-record closures, and retained field
and declaration identities remain authoritative.

All 24 selected native record tests passed in both Debug and ReleaseFast
(17 named tests plus seven root initializer tests in each run), with zero
failures or skips. New cases cover direct native record construction, recursive
capability closure, and hash-key rejection; the prior unsupported-leaf case now
uses an open File handle. All 88 whole-tree Guardian checks passed.

[The receipt](evidence/selka-capability-records-native-20261011/receipt.json)
binds source hashes, exact focused commands, logs, and the earlier captured
producer failure. The preserved capture predates this native fix. A matching
producer rebuild and unchanged full filesystem comparison remain required;
these native tests alone do not establish installed source acceptance, full
bootstrap, or a performance ratio.
