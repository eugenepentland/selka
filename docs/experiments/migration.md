# Checked migration to the Python surface

`mylang migrate <file.my>` parses legacy brace source or the familiar brace
variant with the ordinary parser and prints the equivalent
[Python-style](../python-syntax.md) spelling on stdout. `--write` rewrites the
file, `--check` verifies the result, `--allow-partial` keeps going past gaps, and
`--diagnostics=json` reports like every other command. `migrate-project
<main.my>` walks a whole import graph. Migrating Python source returns it byte
for byte, so the tool is idempotent and safe to re-run.

This input:

```mylang
# doc: check
// Scale a measurement and report whether it cleared the threshold.
struct Reading {
    value: i64,
    valid: bool
}
result Scaled {
    ok: i64,
    err: i64
}
fn scale(reading: Reading, factor: i64) -> Scaled {
    if !reading.valid || factor <= 0 {
        return new Scaled.err(1);
    }
    return new Scaled.ok(reading.value * factor);
}
fn main() -> i64 {
    let sample = new Reading { value: 21, valid: true };
    match scale(sample, 2) {
        Scaled.ok(total) => { return total; },
        Scaled.err(code) => { return code; }
    }
}
```

becomes this output, which returns the same 42:

```mylang
# doc: check
# Scale a measurement and report whether it cleared the threshold.
class Reading:
    value: i64
    valid: bool


result Scaled:
    ok: i64,
    err: i64


def scale(reading: Reading, factor: i64) -> Scaled:
    if not reading.valid or factor <= 0:
        return Err(1)
    return Ok(reading.value * factor)


def main() -> i64:
    sample = Reading(value=21, valid=True)
    match scale(sample, 2):
        case Scaled.ok(total):
            return total
        case Scaled.err(code):
            return code
```

## What the mapping changes

| Legacy spelling | Python spelling |
| --- | --- |
| `fn f() -> T { }`, `private fn`, `conversion fn` | `def f() -> T:` with an indented suite |
| `-> unit`, `-> ()`, `return;` | omitted annotation, bare `return` |
| `let x = e;`, `let mut x = e;`, `let x: T = e;` | `x = e`, `x: T = e` |
| `struct S { a: T }` | `class S:` with annotated fields |
| `new S { a: 1 }`, `S { a: 1 }` | `S(a=1)` |
| `new R.ok(v)`, `new R.err(e)` on a result | `Ok(v)`, `Err(e)` |
| `new E.case` without a payload | `E.case` |
| `new E.case(v)` on an enum or union | `E.case(v)` |
| `new Slot<A>.case(v)` on a generic variant | `Slot.case(v)`, with a binding annotation |
| `new [N]T [a, b]` | `[a, b]`, with a binding annotation |
| `new [Kind]T { case: v }` | `{Kind.case: v}`, with a binding annotation |
| `f::<T>(x)` | `f[T](x)` |
| truncating `a / b`, `a % b` | `a // b`, `a % b` when unsigned, else `divtrunc`/`remtrunc` |
| a bare `{ }` scope block | its statements, inlined |
| `enum`/`union`/`result`/`domain` bodies | the same keyword with an indented suite |
| `buffer`/`list`/`pool`/`resource`/`type`/`const` | unchanged apart from the dropped `;` |
| `if/else if/else`, `while`, `for i in a..b` | `if/elif/else`, `while`, `for i in range(a, b)` |
| `match e { P => { } }` | `match e:` with `case P:` suites |
| `&&`, `\|\|`, `!` | `and`, `or`, `not`, parenthesized where precedence differs |
| `true`, `false`, `unit`, `()` | `True`, `False`, `None` |
| `discard e;`, a bare call statement | `_ = e`, the call alone |
| `try e` | `e?` |
| `alias::name`, `Type<A>` | `alias.name`, `Type[A]` |
| `<T: copy>`, `<T: equality + storable>` | `[T]`, `[T: equality + storable]` |
| `"bytes"` | `b"bytes"` |
| `//` comments, `;` | `#` comments in place, dropped |

Four-space indentation, blank lines and comment placement follow the original.
`fmt --check` accepts the output, because the formatter preserves valid Python
layout unchanged.

## What has no Python spelling

These are reported as located `E_MIGRATE_UNSUPPORTED` diagnostics naming the
construct rather than being approximated:

- The explicit storage tier: `borrow … as`, `split … at … as`, `&T`/`&mut T`/`&[]T`
  parameters and results, `read_ref`/`write_ref`/`read_slice`/`write_slice`/`len_slice`,
  `arena … as`, `reset_arena`, `acquire_buffer`/`*_buffer`, `acquire_pool`/`*_pool`,
  `acquire_resource`/`complete_resource`/`restrict_resource`/`*_resource*`,
  `take_field`, `read_field`, `acknowledge` and `update(v) { }`.
- Match expressions.
- A bare `{ }` scope block whose bindings are not unique in its function. A block whose
  names appear nowhere else is inlined, because inlining cannot change which binding a
  later statement reads.

Truncating `/` and `%` never migrate silently. They become `//` and `%` only where an
operand is certainly unsigned — an unsigned literal suffix, `len`, an unsigned cast, an
unsigned parameter or binding, or a call declared to return one — because the two
roundings agree there. Every other occurrence becomes a `divtrunc`/`remtrunc` call, which
keeps the original rounding and is also available to new code.

With `--allow-partial` the rest of the file is still printed and each gap is
marked with a `# MIGRATE: unsupported <construct>` comment plus a warning.

## Checking and reporting

`--check` requires the migrated source to migrate to itself, to type-check when
the original did (and to repeat the original's rejection code when it did not),
and to reproduce the original's result on the VM whenever the file declares a
parameter-free `main`.

`python3 tests/migrate.py --compiler zig-out/bin/mylang --output report.json`
runs `migrate --check` over every source under `examples/`, `src/stdlib/`,
`test/fixtures/`, `src/board_trial/guest/` and `src/schematic/guest/` without
modifying a file, classifying each as converted, unsupported, already Python or
failed. `zig build test-migrate` runs the same driver.

`python3 scripts/migrate_zig_strings.py --compiler zig-out/bin/mylang --report`
classifies the guest sources embedded as Zig multiline string literals inside
`src/*_test.zig` and `test/integration.zig`; `--write` rewrites the convertible
ones. One-line quoted sources are counted but not rewritten, because Python
layout needs a multiline literal.
