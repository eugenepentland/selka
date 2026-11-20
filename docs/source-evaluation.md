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

This extends the existing constant evaluator, which runs inside the checker. It is not an unrestricted macro system, and it is the only way source runs at tool time: there is no separate command that executes a project without building it. No new source keyword is required.

Supported callees are nongeneric free functions with integer/bool parameters and results. Integer aliases are accepted. Arguments evaluate once, left to right. Bodies may contain scalar bindings and assignments, `_ = expression` discards, return, if/else, while, integer range for, break and continue. Calls may recurse within the nesting/work limits. Imported functions retain normal name and visibility checks, and each call has its own lexical locals.

An unsuffixed integer literal (in any base, `0xFF` or `1_000`) takes the type its context declares: the constant's own type, an annotated binding, a call argument's parameter type, a return type, the local an assignment writes, and the type of the other operand of arithmetic or a comparison. `const MASK: u32 = 4278190080` and `twice(0x10)` therefore need no suffix, and a value outside that type is `E_INTEGER_RANGE`.

Validation walks the entire reachable function syntax, including untaken branches and short-circuit operands. Foreign (`extern func`) functions, capabilities, managed values, resource operations, aggregate construction and unsupported expressions reject. The normal language checker still validates the full program, including unreachable type errors; an invalid program is never built. Constant dependency cycles reject even when short-circuited.

Evaluation shares a fixed 256-level nesting limit and 65,536 work-unit limit across validation, expression/statement execution and name lookup for one constant. Infinite loops and recursion produce located `E_CONSTANT_LIMIT` errors. Invalid arithmetic produces `E_CONSTANT_ARITHMETIC`; forbidden effects/signatures produce `E_CONSTANT_EFFECT` or `E_CONSTANT_TYPE`; unsupported syntax produces `E_CONSTANT_EXPRESSION`. Normal compiler allocation failures propagate and clean up all temporary state. These compile-time budgets are distinct from guest runtime budgets and are not configurable in this stage.

Arithmetic uses the existing fixed-width evaluator, including checked, wrapping, saturating and raw binary64 operations. No target pointer width, host layout or machine addresses enter a computed value. Binary64 operations have the environment requirements specified in [floating-point.md](floating-point.md).

Each compilation evaluates against its complete source and input-module snapshot. Results are cached only within an individual evaluation; no cross-compilation generated-result cache is introduced. Changed imported input source is therefore evaluated anew. A reader folds the value, so the caches key each reader on the value of every constant it reads that runs a function body: an edit of such a body, in any module and however far down the calls, rebuilds the readers when the value changes and leaves them cached when it does not. The module that declares the constant re-reads the text of every module whose bodies it evaluates. Future target-dependent builtins would require an explicit target dependency before they could be admitted.

The final constant getter contains a folded scalar literal. The built program does not rerun the source computation: a regression computes a 1,000-iteration loop during checking, then reads the constant with a ten-step guest budget. Getter calls retain ordinary call/step accounting.

This stage deliberately excludes generated lists and records, schema ASTs, generic function evaluation and arbitrary compile-time I/O. Those require further explicit value/authority/budget design; the one aggregate it admits is a table of `bytes`, described next. Focused tests cover runtime equivalence, allocation failure, changed input modules, lexical isolation, forbidden effects and located limits; a native example verifies the folded result survives native emission.

## Constants that are tables

A module constant may be a table of numbers, held as `bytes`. The initializer is a call of a source function that builds the octets, and the compiler runs it while it checks the program (decision ACM-2, 16 November 2026):

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

The six rules follow. A refusal names the rule's diagnostic; no code was added for them.

1. **Types.** A module constant is an integer, `bool`, `float`, `f32`, `str` or `bytes`. Every other type is `E_CONSTANT_TYPE` at the type, and its message says what a constant may be, that a table of numbers is a `bytes` constant read with `bytes.read_u16_le`, `bytes.read_u32_le` and the other fixed-width reads, and that lists are not constants yet. This covers `int[]`, `float[]`, `str[]`, lists of lists, records, options and unions. (A list constant used to be `E_CONSTANT_EXPRESSION` at its initializer; the program was refused then too.)
2. **Value.** A `bytes` constant is a literal, joined literals and constants, an `embed_bytes` call (all as before), or now a call of a source function that returns `bytes`. The function is nongeneric and free, takes integer and `bool` parameters, and may call the scalar functions an integer constant may call. Its body may hold what a scalar function's body holds (bindings, assignments, `if`, `while`, integer `for ... in range`, `break`, `continue`, `_ =` discards) and these forms for the octets, which are the only ones it may use: `mut table = buffers.empty()` (one byte buffer per binding; a binding never takes another buffer), `_ = buffers.append_byte(mut table, value)` or the same call as a statement, and `return bytes(table)`, the last statement on every path. `buffers.append_byte` takes an integer; a value outside 0 to 255 appends nothing, as at run time. The two `buffers` calls are these operations when the module that declares them is the standard library: the copy embedded in the compiler, or a copy read from source beside the entry (`--local-stdlib`, or `selka check src/stdlib/flate.selka`) whose bytes are exactly the embedded text. A module of your own called `buffers` is an ordinary module, and its `empty` is called as the function it is. Fixed-width entries are written one octet at a time with `bit_and` and `shift_right`, least significant octet first for `bytes.read_u32_le`. `binary.put_u32_le` and the `byte_builder` module are not run, because their builder is a record; importing them would also cost every program that imports the module that holds the constant. Any other form in the function is `E_CONSTANT_EXPRESSION` (or `E_CONSTANT_EFFECT` for a statement that is not allowed at all), a function that returns anything but `bytes` for a `bytes` constant, or takes a parameter that is not an integer or `bool`, is `E_CONSTANT_TYPE`, a path that ends without `return bytes(table)` is `E_CONSTANT_RETURN`, and `return table` of the buffer itself is the checker's own `E_TYPE`. The function is also an ordinary function, so the normal checker validates it as any other, and the built program never runs it unless it calls it. A `str` constant stays a literal, a join or an embed.
3. **Budget.** A scalar constant keeps 256 nesting levels and 65,536 work units. A table constant, one whose initializer is a function call that returns `bytes`, has one work limit of 33,554,432 units (2^25) and one size limit of 262,144 octets (2^18), counted once for the whole evaluation across every call and loop; the nesting limit stays 256. `E_CONSTANT_LIMIT` names the limit that was hit, "work limit of 33,554,432 units" or "size limit of 262,144 octets", and for the size it says that larger data belongs in a file read with `embed_bytes`, which has no limit. The figures and the measurements behind them are in "Measured limits" below.
4. **Use.** A `bytes` constant is read and never written: it can be indexed, measured with `len`, sliced, looped over, compared, read with `bytes.read_*` and lent to a `bytes` parameter. `bytes` is immutable already, and a module constant is not a variable, so a write is refused by the rules that already refuse a write to a constant: `TABLE[0] = 1` and `buffers.append(mut TABLE, ...)` are `E_UNKNOWN_NAME`, `own TABLE` is `E_OWN_MARKER` (the read already yields a value) and `copy(TABLE)` is the warning `W_NEEDLESS_COPY`. To get octets that can change, append the table to a buffer: `buffers.append(mut buffer, TABLE)`. The data is never freed, whoever holds it.
5. **Emission.** The checker replaces the initializer with the one `bytes` literal the function computed, exactly as it does for a joined text constant, and Core builds that literal as the static text data `str_const` (the same data `embed_bytes` and `b"..."` use). Reading the constant allocates nothing and does no work beyond returning that data, it is never destroyed, and a function that only reads it passes `@noalloc`. The octets live once in the built program's data, not once per read.
6. **One verdict.** `check`, a debug build, `--release` and `selka test` give the same answer, because the value is a function of the source alone and the typed tree carries the literal. A cached module is not evaluated again: the standard library's `flate` holds two table constants (four CRC-32 tables of 256 entries, 4,096 octets, and 1,360 zero octets), and a cold `check` of a program that imports it takes 0.25 s, where it took 0.05 to 0.10 s with one table of 256 entries and a shorter module: 0.13 s of the difference is running the CRC builder and holding its octets as a typed literal (the same octets written as a `b"..."` literal take 0.11 s in all), the rest is the longer module, and a cached check costs no more than before (see below). Nothing accepted before is refused now (the only change of verdict is the code of a refusal), so no `selka fix` migration is needed. One cached build can still disagree, as it does for a scalar constant today (not a table rule: `experiments/audit-work-20261111/CONSTTAB.md` has the reproduction): if only the body of a function the constant calls changes, in the module that holds the constant, a cached build of a reader in another module whose own text did not change can keep the earlier value until that reader changes or the build runs with `--no-cache`. A change to the constant's own line is always seen.

A fixed-width entry is written one octet at a time, least significant first, and read back with the matching read. This is a CRC-32 table like the one the standard library's `flate.crc32` reads (`flate`'s holds four of them, for taking four octets at a time):

```selka
# doc: expect 42
import buffers
import bytes

const CRC_TABLE: bytes = crc_table()


func crc_table() -> bytes:
    mut table = buffers.empty()
    for index in range(256):
        mut value = index
        for step in range(8):
            if bit_and(value, 1) == 1:
                value = bit_xor(shift_right(value, 1), 3988292384)
            else:
                value = shift_right(value, 1)
        for part in range(4):
            _ = buffers.append_byte(mut table, bit_and(shift_right(value, part * 8), 255))
    return bytes(table)


func main() -> int:
    if bytes.read_u32_le(CRC_TABLE, 4 * 255) != 755167117u32:
        return 1
    return 42
```

A list is refused where it is declared, and the message says what a constant may be:

```selka
# doc: expect-error E_CONSTANT_TYPE
const FIRST: str[] = ["Kor", "Mal"]


func main() -> int:
    return 0
```

### Lists are not constants yet

A list constant (`const FIRST: str[] = ["Kor", "Mal"]`, `const TABLE: int[] = table()`) needs static list data in the built program, and the back end has none: Core builds a list literal with `list_new` and one `list_push` for each element, so each read would allocate and run the pushes again. (The packed list images of the earlier back end went with it.) A list constant is therefore a separate decision, and a table of numbers is a `bytes` constant until it is made.

### Measured limits

Measured with the debug compiler of this repository (the figures count the evaluator's work units). `flate`'s CRC-32 table, when it was one table (256 entries of four octets, an eight-step loop each), took 72,794 units for 1,024 octets, 71 units for each octet, which is over a scalar constant's 65,536: that is why a table has its own work limit. The plainest builder, one `append_byte` in a `for` loop, takes 27 units for each octet, so a table of 65,536 octets takes 1,769,595. The size limit is four octets for each of the 65,536 values of a 16-bit index, the largest table an index of that width needs; 262,144 octets, one more is `E_CONSTANT_LIMIT`. The work limit is 128 units for each octet at that size, nearly twice what the CRC builder spends, so a builder as heavy as it can fill the whole size limit; scalars keep their limit, because one limit for both would make an endless loop in a scalar constant take 512 times as long to be refused. An endless loop in a table function is refused after 12.6 seconds with the debug compiler, a table that grows without end after 0.8 seconds.

What a table costs a check is the typed literal it becomes, one node for each octet (a `b"..."` literal of the same octets costs the same): a cold `check` of a module with a 65,536-octet table takes 2.87 billion instructions, 1.45 billion of them for the literal and 1.4 billion for running the function, against 0.17 billion for a module with a 16-octet table. A cached module is not evaluated again: a `check` of a program that imports `flate`, edited by one line, takes 8 percent fewer instructions with its table constant than with the list `crc_table` rebuilt in every `crc32` call, and the edit build takes 2 percent fewer (the numbers are in the write-up). Bigger data belongs in a file: `embed_bytes` has no limit and costs no nodes.
