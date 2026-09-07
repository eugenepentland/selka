# Pin-role stage after language ergonomics changes

This is a separate refactor of the sealed .my pin-role submission 001 from
application-trials/direct-20260907-pin-roles. The original trial sources,
submissions and timing records were preserved.

The app uses the new ordinary-JSON library, call-scoped string literal arguments
and existing try/buffer resizing. Application schemas, identifier rules,
validation order, sorting, geometry, connectivity, role findings and SVG output
remain in .my. No EDA-specific operation was added to the VM.

## Line counts

Physical lines include blanks and comments. Application counts exclude tests,
compiler/runtime implementation and reusable standard-library sources.

| Completed pin-role application | Lines |
| --- | ---: |
| Original .my: main.my + io.my | 1,582 |
| Refactored .my: main.my + io.my | **720** |
| Existing Python: inspector.py | 244 |
| Existing Zig: production section plus root entry alias | 359 |

The .my reduction is **862 lines (54.5%)**. The new application is about
2.95 times the Python application length, down from 6.48 times.

Reusable .my implementation adds 83 lines in src/stdlib/std_json.my
and 46 in src/stdlib/std_text.my: **129 lines**. Counting those with the
application gives **849 lines**. They contain generic document queries and
text I/O, with no board/EDA schema terms.

Compiler implementation is separate: the two new Zig modules
src/json_document.zig and src/standard_library.zig total **87 lines**,
alongside changes to existing checking, lowering, runtime, project loading,
navigation, duplicate discovery and disassembly. Language and cache regression
tests are also separate. This is not a claim that all 862 removed application
lines disappeared without implementation work.

Zig's count includes lines 1–358 of its final src/main.zig plus the one-line
root entry alias. Its remaining test declarations and test-only fixture helpers
are excluded. Python and .my reference counts use the frozen final submissions,
without reformatting them.

## Verification

Run after installing the updated interpreter:

~~~sh
python3 experiments/ergonomics/pin-roles/test_cli.py
python3 experiments/ergonomics/pin-roles/test_roles.py
python3 experiments/ergonomics/pin-roles/test_cli.py --stress
~~~

The Python scripts generate requests, launch the VM and assert results. They
are test drivers, not part of the application or its JSON implementation.

The existing private pack can also be replayed without changing trial records:

~~~sh
python3 experiments/ergonomics/pin-roles/verify_pack.py \
  /path/to/pin-role-pack/hidden/cases.json \
  --output experiments/ergonomics/pin-roles/verification.json
~~~

The verification.json receipt pins application/library source, compiler, host
and pack hashes. All seven groups passed: 142 board cases and four malformed
raw requests. Public/independent checks cover exact SVG output, all 27 three-pin
role combinations, malformed roles, duplicate/escaped keys, Unicode, numeric
limits, depth 64/65, validation precedence, sorting, geometry and connectivity.

The unchanged stress fixture passed: 841,355 input bytes, 57,692,813 output bytes,
64 boards and 8,640 findings per board. Additional cases passed at exactly 1 MiB
input, with 50,000 unique unknown keys and with repeated 100,000-byte keys.
Host/VM limits were not increased.

This is a **coordinator-authored ergonomics refactor**, not another independent
agent trial. Its smaller code size and passing behavior do not establish faster
agent development or fewer production defects. Fresh matched maintenance tasks
are needed to measure those outcomes with the improved language.

[Validation details and aggregate-run limitation](validation.md) distinguish
passing component checks from the remaining temporary-storage timing issue.
