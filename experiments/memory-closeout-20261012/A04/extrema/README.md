# List extrema preserve borrowed selection through a scalar index

The list-only implementation of `min` and `max` now carries the selected integer
index through its loop and reads the borrowed element from the input at the end.
It preserves the strict comparison, first-equal selection, input evaluation once,
and initial checked read that reports an empty list at the source call site.
It introduces no copies or runtime helpers. The two-argument implementation and
ownership merge rules are unchanged. A09 supplied the exact production patch;
A07 reviewed the final borrow provenance and negative cases. The coordinator
provided the SPEC extension and focused test-root registration.

The prototype is source `4ab84724d45de3710f2e1b4ba20b7fab8f4082a3` plus the exact
production/SPEC diff recorded in `prototype-01/results.json`. Its compiler SHA256
is `8a6905b47120f6b279e53fe30cb05951da6d862380826a327a4cd9051e420beb`.
`prototype-01/source-and-trap-identity.json` expands the run's short source label
to that full Git identity and hashes the recorded diff. Source, binary, LLVM,
command, stdout/stderr and counter identities remain in the raw results.

Support6 (`5167c588be79dd43d21d5013c36db15110bf239b`, compiler SHA256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`)
refuses the unchanged complete fixture at `return min(words).copy()` with
`E_SINGLE_OWNER_MOVED` for a generated `<collection>`. This baseline is a source
refusal, not an execution or performance measurement.

## Qualification

The focused build passes four new Core ownership tests and eight existing unit
tests (one matching named extrema test and seven unnamed unit blocks). The
existing test includes ordinary scalar/text `noalloc` behavior and empty traps.
See `focused-tests.json` and its complete log. The command exits zero despite an
existing build-runner `failed command` trailer following its passing test report.

`prototype-01` passes 23 native lanes and three negative source cases:

- The complete dynamic-text/scalar fixture passes all five checked modes plus an
  ordinary release control. It covers Unicode ordering, duplicate elements,
  independent copies surviving owner mutation/clear, singleton inputs, NaN and
  signed-zero selection, list-expression evaluation once and existing left-to-right
  two-scalar argument evaluation.
- Copying a selected text view before destroying its parent passes all five
  checked modes. All ten normal-return checked lanes have zero observed RC,
  zero managed exit-live bytes and clean LLVM/linked-symbol audits. The ordinary
  complete-fixture control also has zero managed exit-live bytes.
- Both empty-list cases pass five checked modes and an ordinary control. All 12
  fatal executions report `R_LIST_BOUNDS`, index zero, length zero, at the exact
  `main.my:3:16` call site. All ten checked trap binaries have clean structural
  audits and no observed RC.
- Borrowed selection return refuses with `E_SINGLE_OWNER_BORROW`; a selected view
  used after parent element replacement or parent move refuses with
  `E_ZERO_RC_VIEW_INVALIDATED`.

Fatal-trap counters are retained, not treated as leak-free normal exits. The
empty `str[]` leaves its 32-byte allocated empty-list header live at fatal exit
in every lane, including the ordinary control. Empty `float[]` leaves 32 bytes in
unoptimized debug and release without facts; its other lanes allocate no managed
storage. The existing runtime trap writes its diagnostic, flushes and calls
`os_exit`/`_exit` without unwinding local managed owners. This patch does not change
that process-termination contract. No normal-return lane has this outstanding
storage; the report makes no general fatal-unwind cleanup claim.

## Reproduction and remaining work

Run the focused command in `focused-tests.json` through shared build admission.
Run `qualify.py` directly after sourcing the shared environment; it owns its
bounded build leases. Example for a fresh integrated artifact:

```bash
python3 -B experiments/memory-closeout-20261012/A04/extrema/qualify.py \
  --compiler /absolute/frozen/compiler/bin/mylang \
  --source-commit FULL_SOURCE_SHA --phase integration-new
```

The initial run additionally used `--prototype-diff` and `--baseline` pointing to
Support6. After promotion, use `--default-ownership`; explicit opt-in flags and
ordinary controls are then omitted while independent structural/counter audits
remain enabled. Use a fresh phase name; historical evidence is not overwritten.

These are semantic, counter and structural checks, not paired timing, RSS or
compile-scaling results. The selected-index loop remains linear in input length
and stores a fixed number of scalar locals; no quantitative speed claim is made.
Final integrated C1/C2/C3 artifacts must rerun affected qualification. Different-root
two-string extrema and `Optional.unwrap_or` remain separate public-contract
blockers assigned to A04/A07 for a bounded provenance design; this list patch does
not qualify or weaken their joins. The unrelated pending tuple migration is not
part of this change.
