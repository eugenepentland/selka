# Full Lox with checked ownership

`migrated/main.my` is the complete Lox interpreter with both bytecode VM and
tree engines, classes, inheritance, closures, native clock, and object-table GC.
Build it with `--experimental-zero-rc --release`. The migrated `bench.json`
selects checked ownership in its build and test commands. Checked ownership is
opt-in and activates only when the flag is supplied.

```sh
mylang build experiments/lox-eda-zero-rc-20261012/lox/migrated/main.my --experimental-zero-rc --release -o /tmp/lox-zero
/tmp/lox-zero --engine=vm program.lox
/tmp/lox-zero --engine=tree program.lox
mylang test experiments/lox-eda-zero-rc-20261012/lox/migrated --experimental-zero-rc --jobs 4 --max-steps=100000000
```

The original surviving comparison snapshot is preserved in `original.tar.gz`
and bound by `evidence/original-sha256.txt`. `prepare-control.sh DESTINATION`
reconstructs the exact modern syntax control from that archive plus the
SHA-verified syntax migration patch. Historical timing reports do not carry a
per-source hash receipt, so exact historical source identity is not asserted.

The migrated source replaces implicit sharing with explicit copies where
ownership requires independent values. `ObjRef` continues to carry Lox object
identity. Lox’s guest-object mark/sweep GC is unchanged; the zero-RC claim
concerns the host language/runtime managing the interpreter’s storage. Mutable
helpers receive fields directly rather than moving fields
into writeback temporaries. Clock authority is borrowed as `Clock?` through
execution helpers; the public run_source API retains clock and absent-clock
behavior. Owning optional capabilities cannot be stored in Runtime.

Conservative frame publication and AST/state snapshots copy owning values.
These copy costs are retained in comparisons. The VM cache representation and
bytecode are preserved. The source migration increases explicit `.copy()` sites
from 2 to 184 and adds 76 staged scalar/temporary expressions; the exact inventory
is in `evidence/migration-burden.json`. Static site counts describe source
changes, not executed copy counts or allocated bytes.

The final common compiler is source
`e2893d2707cbe057a09abf94e04c4b12d16b7b8b`, binary SHA-256
`6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d`.
Frozen binary paths, hashes and flags are in `evidence/binaries.json`.

Qualification on the frozen source:

- 65/65 native unit tests with checked ownership and leak checking.
- 974/974 full conformance cases per arm: original RC, migrated RC, zero RC,
  checked debug, and checked release with verified facts.
- All 52 smoke cases agree across the three release arms on stdout and Lox GC
  statistics, including stress collection.
- Both engines read the real clock twice and preserve absent-clock tests.
- Release and counted zero-RC LLVM contain no RC calls or mentions; both native
  binaries contain no RC helper symbols. Controls contain 2,153 / 2,122 RC calls.

`evidence/qualification.json` links the raw logs. `audit-counts.py` runs separate
frozen counted binaries on 26 normal smoke workloads and requires zero managed
retain/release/uniqueness traffic in the checked arm and zero exit-live bytes.
The raw `release_unique` counter is reported separately as direct destruction,
not RC traffic: [its kind definition](../../../src/core/emit_count.zig#L30)
means freeing without a count test; [zero-RC emission](../../../src/core/emit_llvm.zig#L3447)
calls `myl_core_drop_owned` before any RC count check. The
[zero-RC counter contract](../../../src/core/count_test.zig#L691) explicitly
requires positive direct destruction with zero retain/release/uniqueness traffic.
All 78 counted smoke arm-runs passed: checked ownership has zero managed RC
traffic in all 26 cases, and all three arms have zero exit-live bytes. Raw
compressed counters and the exact summary are in `evidence/counters/`.
Runtime and RSS comparison measurements are coordinated separately.
