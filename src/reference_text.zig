//! Curated prose for the compiler-derived reference.
//!
//! The compiler derives facts; this file carries only what no table can: the
//! handful of syntax examples a reader starts from and the boundaries where
//! selka differs from Python. Every entry is versioned with the executable
//! that embeds it, and every `example` is copied verbatim into a fenced
//! ```selka block in `docs/reference.md`, so `selka doctest .` executes it
//! against the same binary that reports it.

const std = @import("std");

/// One curated entry: a stable id, the boundary it teaches, and one program.
pub const Entry = struct {
    /// Stable query term and report key, unique among the curated entries.
    id: []const u8,
    /// Short headline for the entry.
    title: []const u8,
    /// What the language does, in prose no compiler table can derive.
    summary: []const u8,
    /// Where selka differs from Python, or an empty string when it does not.
    python: []const u8,
    /// A complete guest program that the documentation gate executes.
    example: []const u8,
};

/// Every curated entry, in report order. Each example is a complete program:
/// blocks with a `main` run, declaration-only blocks are type-checked, and the
/// documentation gate appends a neutral entry point when the block has none.
pub const entries = [_]Entry{
    .{
        .id = "stream-output",
        .title = "Printing goes through a Stream parameter",
        .summary = "There is no bare print. A function prints through a `Stream` parameter, and the entry point receives `out` " ++
            "and `err` from the runtime. Helpers that print take the stream explicitly; source effect annotations are retired.",
        .python = "Python's print() reaches an ambient stdout from anywhere. selka makes the stream a parameter, so a function " ++
            "that prints names its stream argument, and a caller can pass a different stream.",
        .example =
        \\func main(out: Stream) -> int:
        \\    print(out, "hello")
        \\    return 0
        ,
    },
    .{
        .id = "function-scoped-locals",
        .title = "Declarations belong to lexical blocks",
        .summary = "A local declaration belongs to its lexical block and may not shadow an active binding. A nested block may " ++
            "update an outer mut binding. Initialize a result before a loop when later code needs it, because the loop may run zero times.",
        .python = "Python scopes assignments to a function. selka rejects out-of-scope names with E_UNKNOWN_NAME and reads " ++
            "on a path that has not initialized the binding with E_UNBOUND.",
        .example =
        \\func main() -> int:
        \\    mut total = 0
        \\    for value in [1, 2, 3]:
        \\        total += value
        \\    return total
        ,
    },
    .{
        .id = "range-comprehension",
        .title = "Collect integer ranges with explicit loops",
        .summary = "`range(end)`, `range(start, end)` and `range(start, end, step)` drive explicit for loops. Collect results " ++
            "into a typed accumulator; comprehensions and generator arguments are retired.",
        .python = "Like Python, a range is half-open and accepts an explicit nonzero step. Bounds evaluate once before the " ++
            "loop, and the loop may execute zero times.",
        .example =
        \\func main() -> int:
        \\    mut squares: int[] = []
        \\    for x in range(0, 4):
        \\        append(mut squares, x * x)
        \\    return squares[3]
        ,
    },
    .{
        .id = "records-instead-of-tuples",
        .title = "Records instead of tuples",
        .summary = "There are no tuples. A `record` declares named fields, `T(field=value)` constructs one, and assignment copies " ++
            "the record's fields. Functions are top-level, there are no methods on classes and no closures, so state " ++
            "travels as a parameter.",
        .python = "Where Python returns a tuple or defines a method, selka declares a record and a top-level function that takes " ++
            "its state as a parameter. A shallow copy still shares any managed field, exactly as in Python.",
        .example =
        \\record Pair:
        \\    left: int
        \\    right: int
        \\
        \\func swap(pair: Pair) -> Pair:
        \\    return Pair(left=pair.right, right=pair.left)
        \\
        \\func main() -> int:
        \\    mut swapped = swap(Pair(left=1, right=2))
        \\    return swapped.left * 10 + swapped.right
        ,
    },
    .{
        .id = "capability-parameters",
        .title = "Capabilities are parameters",
        .summary = "There is no ambient authority. Reading files needs a `Filesystem` parameter, a socket a `Network`, the clock a " ++
            "`Clock`, entropy an `Entropy`, and environment reads an `Environment`; the entry point declares the " ++
            "capabilities it needs and threads them through, and a capability a body never reads is refused.",
        .python = "Python's open() reaches the ambient filesystem from any function. selka passes the capability in, so the " ++
            "authority a program can use is visible in the signatures it calls.",
        .example =
        \\func read_length(fs: Filesystem) -> int:
        \\    match fs.read_text("answer.txt"):
        \\        case Ok(text):
        \\            return strings.char_count(text)
        \\        case Err(_):
        \\            return 0 - 1
        ,
    },
    .{
        .id = "fixed-width-integers",
        .title = "Integers have a fixed width",
        .summary = "`int` is a signed 64-bit integer and `float` is IEEE binary64. Arithmetic overflow traps instead of promoting " ++
            "to a wider or arbitrary-precision value, a condition must be a `bool` rather than a truthy value, a list holds " ++
            "one element type, and a slice has no step.",
        .python = "Python integers are arbitrary precision and every value is truthy or falsy. selka checks the fixed width at " ++
            "run time and rejects a non-bool condition at check time.",
        .example =
        \\func main() -> int:
        \\    mut big = 9223372036854775807
        \\    return big % 10
        ,
    },
    .{
        .id = "core-builtin-spellings",
        .title = "The core builtin spellings",
        .summary = "Bare names answered without an import when nothing shadows them include `len(x)`, `range(end)`, " ++
            "`range(start, end)`, `reversed(x)`, `sorted(xs)`, `sum(xs)`, `min`/`max` (two arguments or one list), `abs`, " ++
            "`round`, `any`, `all`, `list(x)`, `int(x)`, `float(x)`, `str(x)` and `bytes(x)`; `zip(a, b)` and " ++
            "`enumerate(x)` are iteration sources in a `for` loop rather than values. A declared function or local binding " ++
            "of the same name wins, argument counts are checked at each call site, and an operation on text, a list, a " ++
            "dictionary or a set is a function: `append(mut xs, x)` is in the prelude, the rest is in its module " ++
            "(`strings.split(text, \",\")`, `dicts.get(mapping, key, fallback)`), and the method spelling `text.split(\",\")` " ++
            "is refused with `E_METHOD_REMOVED`. Ask `selka reference --query strings.split` for any module function.",
        .python = "Most of these read exactly as they do in Python. There is no bare print (see the Stream entry), no `range` step, " ++
            "no `enumerate(start=...)`, no truthiness, and collections are homogeneous.",
        .example =
        \\func main() -> int:
        \\    mut values = [3, 1, 2]
        \\    mut ordered = sorted(values)
        \\    return sum(ordered) + len(ordered)
        ,
    },
};

/// One bare name of the prelude, answered with the call a program writes.
pub const Prelude = struct {
    /// The name a program calls with no import and no qualifier.
    name: []const u8,
    /// The call as a program writes it, with the result type.
    call: []const u8,
    /// One sentence on what it does.
    summary: []const u8,
    /// The `selka docs` topic that covers it.
    guide: []const u8,
};

/// The prelude names a reader asks about most, in alphabetical order. The compiler keeps the names (`prelude_names.zig`)
/// but no signatures, since the checker builds each call itself, so each call below is the form the checker accepts
/// today and `reference_test.zig` holds every name against that table and every guide against `selka docs`.
pub const prelude = [_]Prelude{
    .{ .name = "abs", .call = "abs(x: T) -> T", .summary = "The absolute value of an int or a float (the signed minimum int traps R_OVERFLOW).", .guide = "syntax" },
    .{ .name = "all", .call = "all(values: bool[]) -> bool", .summary = "Whether every element is True; stops at the first False.", .guide = "syntax" },
    .{ .name = "any", .call = "any(values: bool[]) -> bool", .summary = "Whether some element is True; stops at the first True.", .guide = "syntax" },
    .{ .name = "append", .call = "append(mut values: T[], own item: T)", .summary = "Adds one element at the end of the list.", .guide = "memory" },
    .{ .name = "bit_and", .call = "bit_and(a: T, b: T) -> T", .summary = "The bits both operands have set, in the declared width of one integer type; integers have no `&` operator.", .guide = "integer-operations" },
    .{ .name = "bit_not", .call = "bit_not(value: T) -> T", .summary = "The complement of every bit of one integer in its own width: `bit_not(0u8)` is `255u8`.", .guide = "integer-operations" },
    .{ .name = "bit_or", .call = "bit_or(a: T, b: T) -> T", .summary = "The bits either operand has set; integers have no `|` operator.", .guide = "integer-operations" },
    .{ .name = "bit_xor", .call = "bit_xor(a: T, b: T) -> T", .summary = "The bits exactly one operand has set; integers have no `^` operator.", .guide = "integer-operations" },
    .{ .name = "bytes", .call = "bytes(values: int[]) -> bytes", .summary = "A byte string made from a list of octet values or from a byte buffer.", .guide = "bytes" },
    .{ .name = "chr", .call = "chr(code: int) -> str", .summary = "The one-character text of a Unicode scalar value.", .guide = "text" },
    .{ .name = "copy", .call = "copy(value: T) -> T", .summary = "An independent copy of a managed value; a plain argument is only borrowed.", .guide = "memory" },
    .{ .name = "enumerate", .call = "for index, item in enumerate(values)", .summary = "A `for` source that pairs each element with its position; it is not a value.", .guide = "syntax" },
    .{ .name = "exchange", .call = "exchange(mut place, value: T) -> T", .summary = "Stores `value` into a field, element or local and returns what it held.", .guide = "memory" },
    .{ .name = "float", .call = "float(x) -> float", .summary = "A number as a float; text is refused (`E_NUMERIC_PARSE`), so parse it with `parse_float`.", .guide = "syntax" },
    .{ .name = "int", .call = "int(x) -> int", .summary = "A number as an int; text is refused (`E_NUMERIC_PARSE`), so parse it with `parse_int`.", .guide = "syntax" },
    .{ .name = "len", .call = "len(value) -> int", .summary = "The number of elements of a list, dictionary or set, or of octets of a str or bytes.", .guide = "syntax" },
    .{ .name = "list", .call = "list(source) -> T[]", .summary = "A new list from a range or a set.", .guide = "syntax" },
    .{ .name = "max", .call = "max(a: T, b: T) -> T", .summary = "The larger of two numbers, or `max(values)` for the largest of a list (an empty list traps).", .guide = "syntax" },
    .{ .name = "min", .call = "min(a: T, b: T) -> T", .summary = "The smaller of two numbers, or `min(values)` for the smallest of a list (an empty list traps).", .guide = "syntax" },
    .{ .name = "ord", .call = "ord(text: str) -> int", .summary = "The Unicode scalar value of a one-character text.", .guide = "text" },
    .{ .name = "parse_float", .call = "parse_float(text: str) -> float?", .summary = "The number the text spells, or None when it is not a number.", .guide = "text" },
    .{ .name = "parse_int", .call = "parse_int(text: str) -> int?", .summary = "The integer the text spells, or None when it is not an integer.", .guide = "text" },
    .{ .name = "print", .call = "print(out: Stream, value)", .summary = "Writes one value and a newline to a stream; there is no bare print.", .guide = "io" },
    .{ .name = "range", .call = "for i in range(start, end, step)", .summary = "A `for` source of integers, half-open; `range(end)` and `range(start, end)` also work.", .guide = "syntax" },
    .{ .name = "repr", .call = "repr(value) -> str", .summary = "The text `print` writes for a value, quotes included for a str.", .guide = "text" },
    .{ .name = "reversed", .call = "reversed(values: T[]) -> T[]", .summary = "A copy from last to first; also a `for` source.", .guide = "syntax" },
    .{ .name = "round", .call = "round(x: float, ndigits: int = 0) -> float", .summary = "The nearest integral float, halves away from zero, or rounded to `ndigits` decimals.", .guide = "syntax" },
    .{ .name = "saturating_add", .call = "saturating_add(a: T, b: T) -> T", .summary = "The sum clamped to the bounds of the integer type instead of trapping.", .guide = "integer-operations" },
    .{ .name = "saturating_mul", .call = "saturating_mul(a: T, b: T) -> T", .summary = "The product clamped to the bounds of the integer type instead of trapping.", .guide = "integer-operations" },
    .{ .name = "saturating_sub", .call = "saturating_sub(a: T, b: T) -> T", .summary = "The difference clamped to the bounds of the integer type instead of trapping.", .guide = "integer-operations" },
    .{ .name = "shift_left", .call = "shift_left(value: T, count: T) -> T", .summary = "Shifts left and discards the high bits; the count is a T below the width (`R_INVALID_SHIFT`).", .guide = "integer-operations" },
    .{ .name = "shift_right", .call = "shift_right(value: T, count: T) -> T", .summary = "Shifts right, copying the sign of a signed integer; the count is a T below the width.", .guide = "integer-operations" },
    .{ .name = "sort", .call = "sort(mut values: T[])", .summary = "Sorts the list in place, ascending and stable.", .guide = "syntax" },
    .{ .name = "sorted", .call = "sorted(values: T[]) -> T[]", .summary = "A new ascending list that leaves the input alone; `key=` and `reverse=` are accepted.", .guide = "syntax" },
    .{ .name = "str", .call = "str(x) -> str", .summary = "The text `print` writes for a value.", .guide = "text" },
    .{ .name = "sum", .call = "sum(values: T[]) -> T", .summary = "The total of a list of ints or floats.", .guide = "syntax" },
    .{ .name = "take", .call = "take(mut place) -> T", .summary = "Moves a value out of a field, element or local and leaves the type's empty value.", .guide = "memory" },
    .{ .name = "unwrap_or", .call = "option.unwrap_or(default: T) -> T", .summary = "The value inside an option, or `default` when it is None.", .guide = "errors" },
    .{ .name = "wrapping_add", .call = "wrapping_add(a: T, b: T) -> T", .summary = "The sum modulo 2 to the declared width: `wrapping_add(250u8, 10u8)` is `4u8`.", .guide = "integer-operations" },
    .{ .name = "wrapping_mul", .call = "wrapping_mul(a: T, b: T) -> T", .summary = "The product modulo 2 to the declared width.", .guide = "integer-operations" },
    .{ .name = "wrapping_sub", .call = "wrapping_sub(a: T, b: T) -> T", .summary = "The difference modulo 2 to the declared width: `wrapping_sub(0u8, 1u8)` is `255u8`.", .guide = "integer-operations" },
    .{ .name = "zip", .call = "for a, b in zip(left, right)", .summary = "A `for` source that walks two lists together and stops at the shorter; it is not a value.", .guide = "syntax" },
};

/// A standard module whose guide is not the general standard-library page.
pub const ModuleGuide = struct { module: []const u8, guide: []const u8 };

/// The `selka docs` topic for each module that has a page of its own; every other module is in `default_module_guide`.
pub const module_guides = [_]ModuleGuide{
    .{ .module = "buffers", .guide = "bytes" },
    .{ .module = "byte_builder", .guide = "bytes" },
    .{ .module = "bytes", .guide = "bytes" },
    .{ .module = "filesystem", .guide = "io" },
    .{ .module = "logging", .guide = "logging" },
    .{ .module = "sets", .guide = "sets" },
    .{ .module = "simd", .guide = "simd" },
    .{ .module = "strings", .guide = "text" },
};

/// The topic that documents every standard module without a row in `module_guides`.
pub const default_module_guide = "stdlib";

/// The `selka docs` topic to read for one standard module.
pub fn moduleGuide(module: []const u8) []const u8 {
    for (module_guides) |row| if (std.mem.eql(u8, row.module, module)) return row.guide;
    return default_module_guide;
}
