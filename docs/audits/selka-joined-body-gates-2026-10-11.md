# Joined body-language gate integration

The integration tree at 5dfe4c321 combines the aggregate, comprehension, text,
filesystem, ordinary-sequence and schema-11 generic implementations. This change
makes their installed qualification part of the full compiler gate. It does not
claim the newly joined compiler has passed that gate.

The closure driver now requires 4,575 source operations, including genuine
normal and release execution for comprehensions, text and generics. Existing
constant, structural, iteration, chained-comparison and hostile requirements
remain. Runtime accounting checks the actual command flags as well as report
metadata. The generic runner previously always supplied release flags; it now
honors the requested mode, and old reports are not reclassified as normal proof.

The new operations driver requires 3,048 source operations: 372 filesystem
operations covering both guest modes, plus 1,338 sequence operations per mode.
It additionally requires 489 malformed-reply rejections and eight authentic
filesystem replays. Exact inventories, source hashes, schema, runtime flags,
deployment identities, completion and failure counts are checked. Child runners
retain native transcript, diagnostic, trap, warning and mutation validations.
Sequence fixture schemas now match schema 11. No fixture inputs or limits change.

All 130 body Python harness tests pass, as do the qualified seed's check of the
joined body source, Zig formatting, 88 Guardian checks and whitespace checking.
The build graph configures successfully and exposes both new operations targets.
After preflight, only the build step's self-test pattern was broadened to the
same complete body-test pattern already used by preflight. The receipt records
the final build files and all harness files; preflight binds all selfhost source
bytes before and after its checks.

Evidence retains the first failing runtime-flag assertion and its corrected
rerun. Integration conflict records are also retained: the body engine keeps
both print_types and file_operations imports; B7 keeps its promoted classes and
schema 11. All original text/filesystem promotions remain source-identical.

The complete sequence release pure run and the rebuilt generic installed proof
were still pending when this receipt was prepared. The next integrated install
and full gate must also qualify the original B7 entries and generations. Native
semantic passes, Core/LLVM/driver migration, a compiler bootstrap fixed point and
the 1.5-times performance requirement remain open.

[Evidence and source identities](evidence/selka-joined-body-gates-20261011/receipt.json)
include successful and failed preflight runs and all four integration phases.
