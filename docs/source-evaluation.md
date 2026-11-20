# Bounded source evaluation in constants

Module constants can call ordinary scalar source functions:

```selka
const CHECKSUM: u64 = checksum(10u64)


func checksum(count: u64) -> u64:
    mut value = 0u64
    for index in range(0u64, count):
        value = wrapping_add(value, index)
    return value


func main() -> i64:
    return i64(CHECKSUM)
```

The checker runs the call while it checks the program. It is not an unrestricted macro system, and it is the only way
source runs at tool time: no command executes a project without building it.

- **Callees** are nongeneric free functions with integer and `bool` parameters and results (integer aliases accepted).
  Arguments evaluate once, left to right. Bodies may hold scalar bindings and assignments, `_ = expression`, `return`,
  `if`/`else`, `while`, integer range `for`, `break` and `continue`. Calls may recurse within the limits. Imported
  functions keep the normal name and visibility checks.
- **Literals.** An unsuffixed integer literal takes the type its context declares (the constant's type, an annotated
  binding, a parameter, a return type, the local an assignment writes, the other operand of arithmetic or a comparison), so
  `const MASK: u32 = 4278190080` and `twice(0x10)` need no suffix; a value outside the type is `E_INTEGER_RANGE`.
- **Rejected:** `extern func` functions, capabilities, managed values, resource operations, aggregate construction and other
  expressions. Validation walks all reachable function syntax, untaken branches and short-circuit operands included. A
  constant dependency cycle is rejected even when short-circuited. The checker still validates the whole program.
- **Limits.** One constant gets 256 nesting levels and 65,536 work units, shared across validation, execution and name
  lookup. They are not configurable and are separate from guest runtime budgets.
- **Arithmetic** is the fixed-width evaluator (checked, wrapping, saturating and raw binary64 operations); no target pointer
  width or host layout enters a value. Binary64 needs the environment in [floating-point.md](floating-point.md).
- The built program holds the folded literal and does not rerun the computation. Generated lists and records, schema ASTs,
  generic function evaluation and compile-time I/O are not supported.

| Code | Cause |
| --- | --- |
| `E_CONSTANT_LIMIT` | an infinite loop or recursion, or a limit hit (located) |
| `E_CONSTANT_ARITHMETIC` | invalid arithmetic |
| `E_CONSTANT_EFFECT`, `E_CONSTANT_TYPE` | a forbidden effect or signature |
| `E_CONSTANT_EXPRESSION` | unsupported syntax |

## Constants that are tables

A module constant may be a table of numbers, held as `bytes`. The initializer is a call of a source function that builds the
octets, and the compiler runs it while it checks the program:

```selka
# doc: expect 42
import buffers
import bytes

const SQUARES: bytes = squares(16)


func squares(count: int) -> bytes:
    mut table = buffers.empty()
    for index in range(count):
        _ = buffers.append_byte(mut table, bit_and(index * index, 255))
    return bytes(table)


func main() -> int:
    return int(bytes.read_u8(SQUARES, 5)) + int(bytes.read_u8(SQUARES, 3)) + 8
```

1. **Types.** A module constant is an integer, `bool`, `float`, `f32`, `str` or `bytes`. Any other type is
   `E_CONSTANT_TYPE`: a table of numbers is a `bytes` constant read with `bytes.read_u16_le`, `bytes.read_u32_le` and the
   other fixed-width reads, and lists (`int[]`, `str[]`, lists of lists), records, options and unions are not constants yet.
2. **Value.** A `bytes` constant is a literal, joined literals and constants, an `embed_bytes` call, or a call of a
   nongeneric free source function that returns `bytes` and takes integer and `bool` parameters. Its body may hold what a
   scalar function's body holds plus these forms for the octets, and no others: `mut table = buffers.empty()` (one byte
   buffer per binding), `_ = buffers.append_byte(mut table, value)` (a value outside 0 to 255 appends nothing, as at run
   time), and `return bytes(table)`, the last statement on every path. These `buffers` calls are the operations only when the
   module that declares them is the standard library (the embedded copy, or a `--local-stdlib` copy with the same bytes); a module of your own called `buffers` is an ordinary module. Write
   fixed-width entries one octet at a time with `bit_and` and `shift_right`, least significant octet first for
   `bytes.read_u32_le`. `binary.put_u32_le` and `byte_builder` are not run. A `str` constant stays a literal, a join or an
   embed.
3. **Budget.** A table constant has one work limit of 33,554,432 units (2^25) and one size limit of 262,144 octets (2^18),
   counted once across every call and loop; nesting stays 256. `E_CONSTANT_LIMIT` names the limit hit; for size it says that
   larger data belongs in a file read with `embed_bytes`, which has no limit. A scalar constant keeps 256 and 65,536.
4. **Use.** A `bytes` constant is read and never written: index, `len`, slice, loop, compare, `bytes.read_*`, lend to a
   `bytes` parameter. `TABLE[0] = 1` and `buffers.append(mut TABLE, ...)` are `E_UNKNOWN_NAME`, `own TABLE` is
   `E_OWN_MARKER`, `copy(TABLE)` is `W_NEEDLESS_COPY`. For octets that can change, `buffers.append(mut buffer, TABLE)`.
5. **Emission.** The octets live once in the built program's data. Reading the constant allocates nothing, and a function
   that only reads it passes `@noalloc`.
6. **One verdict.** `check`, a debug build, `--release` and `selka test` give the same answer. One cached build can still
   disagree, as for a scalar constant: if only the body of a function the constant calls changes, in the module that
   holds the constant, a cached build of a reader in another module whose own text did not change can keep the earlier
   value until that reader changes or the build runs with `--no-cache`. A change to the constant's own line is always seen.

| Function body | Code |
| --- | --- |
| any other form | `E_CONSTANT_EXPRESSION` (`E_CONSTANT_EFFECT` for a statement that is not allowed at all) |
| returns anything but `bytes`, or takes a parameter that is not an integer or `bool` | `E_CONSTANT_TYPE` |
| a path that ends without `return bytes(table)` | `E_CONSTANT_RETURN` |
| `return table` of the buffer itself | `E_TYPE` |

A list is refused where it is declared, and the message says what a constant may be:

```selka
# doc: expect-error E_CONSTANT_TYPE
const FIRST: str[] = ["Kor", "Mal"]


func main() -> int:
    return 0
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/source-evaluation.md).
