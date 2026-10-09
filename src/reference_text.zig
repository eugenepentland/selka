//! Curated prose for the compiler-derived reference.
//!
//! The compiler derives facts; this file carries only what no table can: the
//! handful of syntax examples a reader starts from and the boundaries where
//! selka differs from Python. Every entry is versioned with the executable
//! that embeds it, and every `example` is copied verbatim into a fenced
//! ```selka block in `docs/reference.md`, so `selka doctest .` executes it
//! against the same binary that reports it.

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
            "and `err` from the runtime. `stream.print` contributes the `output` effect, so every function in the chain " ++
            "that prints carries `effects(output)`; the entry point itself needs no annotation.",
        .python = "Python's print() reaches an ambient stdout from anywhere. selka makes the stream a parameter, so a function " ++
            "that prints says so in its signature and in its effect set, and a caller can pass a different stream.",
        .example =
        \\func main(out: Stream) -> int:
        \\    out.print("hello")
        \\    return 0
        ,
    },
    .{
        .id = "function-scoped-locals",
        .title = "Locals are function-scoped",
        .summary = "An assignment to a name anywhere in the body is one binding, in scope from its first assignment to the end of " ++
            "the function, and a nested block reassigns it rather than shadowing it. Because a loop may run zero times, a " ++
            "name first assigned inside a loop body is not definitely assigned after the loop: initialize it before the loop.",
        .python = "Python binds the name on the executed path and leaves it unbound otherwise. selka rejects a read on a path " ++
            "that may not have assigned the name yet with E_UNBOUND, and a name that is never assigned is E_UNKNOWN_NAME.",
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
        .title = "range() is a comprehension source",
        .summary = "`range(end)` and `range(start, end)` build their integer sequence in a comprehension exactly as they do in a " ++
            "`for` loop, and a comprehension may also walk a list, a string or a dictionary.",
        .python = "The comprehension syntax is Python's, with no step argument and no open-ended form: a range takes one or two " ++
            "arguments, and every loop it drives may execute zero times.",
        .example =
        \\func main() -> int:
        \\    mut squares = [for x in range(4) yield x * x]
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
        \\func swap(pair: Pair) -> Pair effects():
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
            "capabilities it needs and threads them through, and each use shows up in the effect set.",
        .python = "Python's open() reaches the ambient filesystem from any function. selka passes the capability in, so the " ++
            "authority a program can use is visible in the signatures it calls and in the effects it declares.",
        .example =
        \\func read_length(fs: Filesystem) -> int effects(filesystem):
        \\    match fs.read_text("answer.txt"):
        \\        case Ok(text):
        \\            return len(text)
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
            "of the same name wins, argument counts are checked at each call site, and a collection method such as " ++
            "`split`, `append` or `get` comes from the receiver's own table.",
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
