# Entries and count in the Lox read probe

This source experiment passes a readonly `list[Entry]` and scalar count to the
read probe at the six production call sites: VM globals, two tree globals paths,
class methods, hashed class methods, and instance fields. The original public
`table.get(Table, key, hash)` body remains intact. `get_entries` intentionally
duplicates that body with `t.entries` and `t.count` replaced by its parameters.
The preparation evidence verifies both text equivalences.

The open-addressing layout, linear probing, hash masking, wraparound, empty and
tombstone handling, returned `Option[Value]`, and checked index/arithmetic
expressions stay identical. No insertion, deletion, collection, allocation,
cache, compiler, or runtime algorithm changes. Callers project readonly fields
without mutating their owner during a read. Existing snapshot/COW and native
root protocol apply normally.

The exact control is the frozen 80-test final-sweep source at
`codex-lox-ownership-inline-20261003/.tmp-lox-sweep/qualified`, rather than a
fresh reconstruction from an evolving canonical migration. `control-source.json`
records all 37 files. The compiler is the separately reviewed CFG-corrected
combined compiler, SHA256
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`, built from
the lowering lane including fix commit `323c4ae4`.

## Static mechanism and rejected alternatives

The ownership hypothesis was negative: control `table.get` already emits zero
retain, loan, drop, take, or unloan calls. Splitting the carrier instead changes
unowned materialization and the optimizer's handling of a fixed readonly list.
The helper SSA falls from 388 to 380 lines and removes one 32-byte copy in the
inlined tombstone path. Native optimized code then avoids copying the complete
Entry on an ordinary successful/colliding probe; its key is read directly and
the tombstone path materializes the Entry only after finding `NO_OBJ`.
LLVM also proves the loop's index remains in bounds for the immutable entries
parameter. Source checks remain; QBE retains its ordinary bounds fallback.

| Static decoded instructions | Control get | Initial entries probe |
| --- | ---: | ---: |
| LLVM O3/full LTO | 104 | 72 |
| QBE | 196 | 186 |

These are whole function static counts, including cold traps, not executed
instruction counts or performance results. An initial message counted every
objdump address line, including multi-line instruction byte continuations, and
reported 106→74 and 200→191. `emission.json` corrects this by counting decoded
instruction lines with mnemonics. Both sets of underlying assembly are kept in
`evidence/`, with hashes. Caller SSA grows slightly to prepare separate entries
and count arguments; central measurements must assess the complete guest.

`intermediate-wrapper.patch` preserves the first table-only forwarding wrapper
prototype; `intermediate-direct.patch` preserves direct runtime calls to that
helper. Its source/binaries stay immutable. The final arm restores the original
public `get` body to retain that API's native frame behavior, so the duplication
is deliberate. `rejected-local.patch` merely hoists `entries = t.entries` in
the original function. It increases SSA from 388 to 832 lines and ownership
glue sites from zero to ten and is rejected without timing.

## Qualification and reproduction

The final source contains 81 tests. The new snapshot regression keeps both a
Table and its separately saved entries alive across overwrites, deletion,
tombstone reuse and growth of a collision chain wrapping through slot zero.
It checks empty reads, nil values, missing keys, the old snapshots and the live
table. The full fixture passes 81/81 in all four modes: LLVM test `--release`
and QBE `--mode ReleaseFast`, each using RC or native `--gc-stress`. Each uses
`--max-steps 1000000000 --timeout-ms 120000`; test optimization flags are
separate from guest LLVM O3/full LTO build flags.

`final-source.json` freezes all 37 files including the new regression.
`final-table-entries.patch` applies to the exact control. Preparation refuses a
different baseline or existing destination and verifies all final hashes.
Earlier intermediate arm qualification is separately labelled and does not
replace final-arm evidence. Build and validation receipts describe exact final
artifacts; native-stressed full corpus observations intentionally omitted from
the bounded validation are explicitly listed as unrun.

`qualification.json` records **324 passing unit tests** and **712 exact paired
comparisons** in `validation-final.json.gz`: all 13 RC smoke corpus cases,
15 focused programs in both evaluators, and 23 error programs per evaluator.
RC and native GC guest variants run ordinarily and with Lox stress; native GC
variants run focused/error cases under native stress. The **104 omitted native
corpus smoke observations** are explicitly unrun, rather than a full native
corpus pass. All binary, compiler, final module and complete source hashes were
verified again after qualification. The source descriptor's historical
`qualification: pending` field marks its freeze before tests; these separate
completed receipts provide the final status without rewriting the freeze.

```bash
lane=experiments/lox-table-read-20261003
scratch="$PWD/.tmp-lox-table-read-replay"
control=/home/epentland/ai/canopy/mylang-worktrees/codex-lox-ownership-inline-20261003/.tmp-lox-sweep/qualified
compiler=/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang
python3 "$lane/prepare.py" --baseline "$control" --dest "$scratch/source"
python3 "$lane/build.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler" --name final-table-entries --runtime rc
python3 "$lane/build.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler" --name final-table-entries --runtime gc
python3 "$lane/test.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler" --label final
```

All compilation and test commands use `scripts/build-slot.sh`, private caches,
outputs, and TMPDIR. Run `validate.py` through that wrapper with a binary
manifest like the archived one, the unchanged 13-case corpus, and
`regressions.json`. It compares exact status/stdout/stderr, including Lox
collector statistics, for both engines ordinarily and with Lox stress;
native GC stress artifacts run focused/error cases. This lane does no timing;
root owns central comparison and acceptance.
