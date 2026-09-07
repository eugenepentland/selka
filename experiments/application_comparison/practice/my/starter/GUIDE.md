# .my practice guide

Repair this small byte-input utility according to the supplied practice contract
and public checks. Fix the unresolved-name diagnostic first: static checking can
reject the whole project before any input branch runs.

Run the already installed bytecode host with the project directory:

```sh
printf m | /tools/byte_io --project /work
```

When working directly in the language checkout, replace `/tools/byte_io` with
`zig-out/bin/mylang-io` and `/work` with this starter directory. Source files load
from disk on every invocation; changing `.my` does not require rebuilding Zig.
Use the participant `check` tool for the complete public practice cases.

`module name;` names a file's module. `import helper;` resolves `helper.my`;
`export multiply;` makes its function callable as `helper::multiply(argument)`.
Functions declare parameter and return types. `let name = value;` creates an
immutable binding. Names must resolve in their scope; the diagnostic identifies
the source location that needs repair.

A `result` declares success and failure payload types. This exercise's parser
returns `ParsedDigit`; `new ParsedDigit.ok(value)` and
`new ParsedDigit.err(error)` construct its variants. An exhaustive `match`
handles both. `discard` explicitly ignores an unneeded error payload, but the
failure branch must still return the result required by the utility contract.

The `io` host exposes only raw byte count, indexed reads, and byte writes.
`effects(host)` declares and propagates these external effects. Byte literals
use the `u8` suffix; `cast<i64>(value)` explicitly widens a byte for arithmetic.
`discard io::put(...)` acknowledges the host's status value. Returning zero from
`main` commits the buffered output; it is the process status, not the answer.

## Optional main-workflow inspection tools

The main workflow arm also mounts `/tools/compiler` and `/tools/navigate`.
The language-focused arm does not mount them. The installed compiler can check
source, report duplicate candidates, and emit a symbol index without executing the
program:

```sh
/tools/compiler check-project /work/main.my --diagnostics=json
/tools/compiler index-project /work/main.my
python3 -S -B /tools/navigate --compiler /tools/compiler --entry /work/main.my --query parse --relation definition --limit 5 --context-bytes 1024
```

The navigation client supports `definition`, `references`, `callers`, `callees`,
`impact`, and `context`; use `--symbol module::function` for an exact declaration.
Broken source can yield a partial declaration index with no checked relationships.
Navigation impact is not test coverage. Use `check` for the public behavioral suite.
These tools inspect your disk source and do not require rebuilding Zig.
