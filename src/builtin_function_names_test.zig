//! A bare call of a prelude function's name is always the prelude function: a module function or a re-export with that
//! name is refused when its own module uses the name bare (`E_BUILTIN_FUNCTION_NAME`), and accepted when it does not.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const File = language.embedded_project.File;
const Diagnostic = language.diagnostic.Diagnostic;

const code = "E_BUILTIN_FUNCTION_NAME";

const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

/// What a check of a project said: its first diagnostic, the text under it and under its note, and its repair's edits
/// applied to their own spans (each edit's replacement, in order).
const Report = struct {
    first: ?Diagnostic = null,
    at: []const u8 = "",
    note: []const u8 = "",
    edits: []const []const u8 = &.{},
    /// The span text of each edit, so a test can say which spellings the repair rewrites.
    replaced: []const []const u8 = &.{},
};

/// Check the project whose entry is `main.selka`, and report its first diagnostic.
fn checkProject(arena: std.mem.Allocator, entries: []const File) !Report {
    var files: Files = .{ .entries = entries };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        return report(arena, compilation.src, compilation.diagnostics.items.items[0]);
    };
    return .{};
}

fn report(arena: std.mem.Allocator, src: language.source.Source, item: Diagnostic) !Report {
    var edits: std.ArrayList([]const u8) = .empty;
    var replaced: std.ArrayList([]const u8) = .empty;
    if (item.provenance.fix) |fix| {
        try edits.append(arena, fix.edit.text);
        try replaced.append(arena, src.text(fix.edit.span));
        for (fix.more) |edit| {
            try edits.append(arena, edit.text);
            try replaced.append(arena, src.text(edit.span));
        }
    }
    const note = if (item.related) |related| src.text(related.span) else "";
    return .{ .first = item, .at = src.text(item.span), .note = note, .edits = edits.items, .replaced = replaced.items };
}

/// Check and run the project whose entry is `main.selka`, returning `main`'s value.
fn runProject(arena: std.mem.Allocator, entries: []const File) !i64 {
    var files: Files = .{ .entries = entries };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    return (try native.run(&compilation)).value;
}

/// Check one file, and report its first diagnostic.
fn checkOne(arena: std.mem.Allocator, text: []const u8) !Report {
    var compilation = try language.Compilation.init(arena, "shapes.selka", text);
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        return report(arena, compilation.src, compilation.diagnostics.items[0]);
    };
    return .{};
}

fn runOne(text: []const u8) !i64 {
    var compilation = try language.Compilation.init(t.allocator, "shapes.selka", text);
    defer compilation.deinit();
    try compilation.check();
    return (try native.run(&compilation)).value;
}

fn expectRefused(found: Report, at: []const u8, note: []const u8) !void {
    try t.expectEqualStrings(code, found.first.?.code);
    try t.expectEqualStrings(at, found.at);
    try t.expectEqualStrings(note, found.note);
}

fn expectEdits(found: Report, wanted: []const []const u8) !void {
    try t.expectEqual(wanted.len, found.edits.len);
    for (wanted, found.edits) |text, edit| try t.expectEqualStrings(text, edit);
}

test "a private module function with a prelude name that its module calls bare is refused with the rename" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // The probe of audit A (builtin_replaced.selka): before the rule it exited 108.
    const found = try checkOne(arena.allocator(),
        \\func len(n: int) -> int:
        \\    return n + 100
        \\
        \\
        \\func main() -> int:
        \\    return len(1) + f"{len(2)}".len
    );
    try expectRefused(found, "len", "len");
    try t.expect(std.mem.indexOf(u8, found.first.?.message, "reads as the builtin") != null);
    // The declaration, the call and the call inside the f-string hole.
    try expectEdits(found, &.{ "shapes_len", "shapes_len", "shapes_len" });
}

test "a public function with a prelude name is refused when its module uses it bare, as a call or as a value" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const called = try checkOne(arena.allocator(),
        \\public func take(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func main() -> int:
        \\    return take(3)
    );
    try expectRefused(called, "take", "take");
    try expectEdits(called, &.{ "shapes_take", "shapes_take" });
    const passed = try checkOne(arena.allocator(),
        \\func sum(value: int) -> int:
        \\    return value * 2
        \\
        \\
        \\func apply(f: func(int) -> int, value: int) -> int:
        \\    return f(value)
        \\
        \\
        \\func main() -> int:
        \\    return apply(sum, 21)
    );
    try expectRefused(passed, "sum", "sum");
    try expectEdits(passed, &.{ "shapes_sum", "shapes_sum" });
    // A generic function called with its type arguments is called bare too.
    const generic = try checkOne(arena.allocator(),
        \\func max[T: integer](value: T) -> T:
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    return max[int](4)
    );
    try expectRefused(generic, "max", "max");
}

test "the rename picks a name the module does not write and is withheld when a parameter has the name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const collides = try checkOne(arena.allocator(),
        \\func abs(n: int) -> int:
        \\    return 7
        \\
        \\
        \\func shapes_abs() -> int:
        \\    return abs(-3)
        \\
        \\
        \\func main() -> int:
        \\    return shapes_abs()
    );
    try expectRefused(collides, "abs", "abs");
    try expectEdits(collides, &.{ "shapes_abs2", "shapes_abs2" });
    const withheld = try checkOne(arena.allocator(),
        \\func repr(value: int) -> str:
        \\    _ = value
        \\    return "declared"
        \\
        \\
        \\func show(repr: int) -> int:
        \\    return repr
        \\
        \\
        \\func main() -> int:
        \\    return len(repr(42)) + show(1)
    );
    try expectRefused(withheld, "repr", "repr");
    try t.expect(withheld.first.?.provenance.fix == null);
    try t.expect(std.mem.indexOf(u8, withheld.first.?.message, "is not offered because `repr` is also written at") != null);
}

test "the declared take and exchange and the declared repr, once tests that they win, are refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // tests/lang/take_shadowed.selka asserted that these declarations won over the prelude functions.
    const take = try checkOne(arena.allocator(),
        \\func take(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\func exchange(first: int, second: int) -> int:
        \\    return first * second
        \\
        \\
        \\func main() -> int:
        \\    return take(3) + exchange(2, 5)
    );
    try expectRefused(take, "take", "take");
    // tests/lang/repr_shadowing.selka asserted that a declared repr won in concrete and generic calls.
    const repr = try checkOne(arena.allocator(),
        \\func repr(value: int) -> str:
        \\    _ = value
        \\    return "declared"
        \\
        \\
        \\func generic_repr[T: copy](marker: T, value: int) -> str:
        \\    _ = marker
        \\    return repr(value)
        \\
        \\
        \\func main() -> int:
        \\    return len(generic_repr(1, 42))
    );
    try expectRefused(repr, "repr", "repr");
    try expectEdits(repr, &.{ "shapes_repr", "shapes_repr" });
}

test "an extern function with a prelude name that its module calls bare is refused with no rename, since its name is its C symbol" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try checkOne(arena.allocator(),
        \\extern func abs(host: Host, value: i32) -> i32
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return i64(abs(host, -42))
    );
    try expectRefused(found, "abs", "abs");
    try t.expect(found.first.?.provenance.fix == null);
    try t.expect(std.mem.indexOf(u8, found.first.?.message, "declare it in a module of its own and call it as `module.abs(...)`") != null);
}

test "a module function with a prelude name that its module never uses bare is accepted" {
    // Nothing calls it, and a bare `sum` elsewhere in the module is the builtin.
    try t.expectEqual(@as(i64, 6), try runOne(
        \\func sum(values: int[]) -> int:
        \\    _ = values
        \\    return 100
        \\
        \\
        \\func main() -> int:
        \\    const total = 6
        \\    return total
    ));
    // A type spelling is no use of the function: `set` here is only the type.
    try t.expectEqual(@as(i64, 2), try runOne(
        \\func set(count: int) -> int:
        \\    return count
        \\
        \\
        \\func size(values: set[int]) -> int:
        \\    return len(values)
        \\
        \\
        \\func main() -> int:
        \\    const values: set[int] = {4, 5}
        \\    return size(values)
    ));
}

// Lane FX item 5: a single file with no import names its functions bare, and the
// checker refused one named like a builtin type (`E_DUPLICATE_NAME`, "conflicts with
// a declared type") although the same file with an import, or checked as a module by
// `selka check`, was accepted. `examples/corpus/packet/inputs.selka` was the case.
test "FX a function named like a builtin type that its module never calls bare is accepted in a file with no import" {
    try t.expectEqual(@as(i64, 4), try runOne(
        \\public func bytes() -> int:
        \\    return 70
        \\
        \\
        \\func str() -> int:
        \\    return 71
        \\
        \\
        \\func float() -> int:
        \\    return 72
        \\
        \\
        \\func dict() -> int:
        \\    return 73
        \\
        \\
        \\func main() -> int:
        \\    const s: str = "x"
        \\    const b: bytes = b"y"
        \\    const f: float = 1.5
        \\    mut d: dict[str, int] = {}
        \\    d["k"] = 2
        \\    return len(s) + len(b) + int(f) + len(d)
    ));
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // A declared type and a function of one name still conflict.
    const clash = try checkOne(arena.allocator(),
        \\record Row:
        \\    x: int
        \\
        \\
        \\func Row() -> int:
        \\    return 7
        \\
        \\
        \\func main() -> int:
        \\    return 3
    );
    try t.expectEqualStrings("E_DUPLICATE_NAME", clash.first.?.code);
    // A bare call is the builtin's, so W6's rule still refuses the function.
    const called = try checkOne(arena.allocator(),
        \\func str() -> int:
        \\    return 7
        \\
        \\
        \\func main() -> int:
        \\    return len(str(5))
    );
    try t.expectEqualStrings(code, called.first.?.code);
}

test "a public function with a prelude name called only with its module's name from another module is accepted and runs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const value = try runProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import zipfile
            \\
            \\
            \\func main() -> int:
            \\    return zipfile.write(2) + sum([1, 2, 3])
        },
        .{ .path = "zipfile.selka", .bytes = "" ++
            \\public func write(count: int) -> int:
            \\    return count * 10
        },
    });
    // `zipfile.write(2)` is the module's function (20) and the bare `sum` is the builtin (6).
    try t.expectEqual(@as(i64, 26), value);
}

test "a qualified call from another module is renamed with the declaration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try checkProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import shapes as s
            \\
            \\
            \\func main() -> int:
            \\    return s.min(4)
        },
        .{ .path = "shapes.selka", .bytes = "" ++
            \\public func min(value: int) -> int:
            \\    return value
            \\
            \\
            \\public func smallest() -> int:
            \\    return min(1)
        },
    });
    try expectRefused(found, "min", "min");
    try expectEdits(found, &.{ "shapes_min", "shapes_min", "shapes_min" });
}

// `strings.ord` shares the prelude's name `ord` and is no second spelling of it: W13 refused the `math` twins this test
// once read (`math.max`), so it reads the text module's function by its qualified name.
test "the standard library's own functions with prelude names are accepted, and are reached by their qualified names" {
    try t.expectEqual(@as(i64, 3), try fixture.value(t.allocator,
        \\import strings
        \\
        \\
        \\func main() -> int:
        \\    const code = strings.ord("c") else Err(_):
        \\        return 0
        \\    return code - 96
    ));
}

test "a re-export of a prelude name is refused when its module uses the name bare, with the uses written qualified" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // Before the rule `sum([1, 2])` here called `helpers.sum` and returned 100.
    const user = try checkProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import helpers
            \\export helpers.sum
            \\
            \\
            \\func main() -> int:
            \\    return sum([1, 2])
        },
        .{ .path = "helpers.selka", .bytes = "" ++
            \\public func sum(values: int[]) -> int:
            \\    _ = values
            \\    return 100
        },
    });
    try expectRefused(user, "helpers.sum", "sum");
    try expectEdits(user, &.{"helpers.sum"});
    // Before the rule `abs(-3)` here called the standard library's `math.abs`, whose result is `int fails str`.
    const library = try checkProject(arena.allocator(), &.{.{ .path = "main.selka", .bytes = "" ++
        \\import math
        \\export math.abs
        \\
        \\
        \\func main() -> int:
        \\    return abs(-3)
    }});
    try expectRefused(library, "math.abs", "abs");
    try expectEdits(library, &.{"math.abs"});
}

test "FR78 a bare call whose arguments cannot be the declared function's stays the prelude's, and every other use is renamed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    // The round-4 file server's shape: `flush(out)` passes a `Stream` to a function declared on `int`, so it is the builtin's.
    // The callback and `flush(1)` may be the function's and follow the rename; the note points at the first of them.
    const probe = try checkOne(arena.allocator(),
        \\func flush(n: int) -> int:
        \\    return n
        \\
        \\func apply(callback: func(int) -> int, value: int) -> int:
        \\    return callback(value)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, "hi")
        \\    flush(out)
        \\    return flush(1) + apply(flush, 1)
    );
    try expectRefused(probe, "flush", "flush");
    try expectEdits(probe, &.{ "shapes_flush", "shapes_flush", "shapes_flush" });
    try t.expect(std.mem.indexOf(u8, probe.first.?.message, "with every use but the bare call at shapes.selka:9:5, whose arguments cannot be this function's: it stays the prelude's `flush`") != null);
    try t.expect(std.mem.indexOf(u8, probe.first.?.related.?.message, "may be this function's, so the rename follows it") != null);
    try t.expectEqual(@as(i64, 2), try runOne(
        \\func shapes_flush(n: int) -> int:
        \\    return n
        \\
        \\func apply(callback: func(int) -> int, value: int) -> int:
        \\    return callback(value)
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, "hi")
        \\    flush(out)
        \\    return shapes_flush(1) + apply(shapes_flush, 1)
    ));
    // Too many arguments for the declared `print`, and text for a declared list: both stay the prelude's (the message counts them).
    const several = try checkOne(arena.allocator(),
        \\func print(n: int) -> int:
        \\    return n
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, "hi")
        \\    print(out, "a", "b")
        \\    return print(2)
    );
    try expectEdits(several, &.{ "shapes_print", "shapes_print" });
    try t.expect(std.mem.indexOf(u8, several.first.?.message, "every use but the 2 bare calls whose arguments cannot be this function's, the first at shapes.selka:5:5") != null);
    // Every call fits the declared `len` (a list parameter, a list literal), so each is renamed, as before FR78.
    const both = try checkOne(arena.allocator(),
        \\func len(xs: int[]) -> int:
        \\    return 7
        \\
        \\func count(ys: int[]) -> int:
        \\    return len(ys) + len([4])
    );
    try expectEdits(both, &.{ "shapes_len", "shapes_len", "shapes_len" });
    try t.expect(std.mem.indexOf(u8, both.first.?.message, "with every use)") != null);
    // A call that fits neither function (text for `int` and for the builtin's `Stream`) stays the prelude's: the program's own
    // type error remains for `check` to name, as it did under the old rename.
    const neither = try checkOne(arena.allocator(),
        \\func flush(n: int) -> int:
        \\    return n
        \\
        \\func main(out: Stream) -> int:
        \\    flush("x")
        \\    return flush(0)
    );
    try expectEdits(neither, &.{ "shapes_flush", "shapes_flush" });
    try t.expect(std.mem.indexOf(u8, neither.first.?.message, "every use but the bare call at shapes.selka:5:5") != null);
}

test "FR78 a re-export whose module also calls the prelude's function bare is refused with the repair withheld, saying why" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try checkProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import helpers
            \\export helpers.flush
            \\
            \\func main(out: Stream) -> int:
            \\    print(out, "hi")
            \\    flush(out)
            \\    return flush(0)
        },
        .{ .path = "helpers.selka", .bytes = "" ++
            \\public func flush(n: int) -> int:
            \\    return n
        },
    });
    try expectRefused(found, "helpers.flush", "flush");
    try expectEdits(found, &.{});
    try t.expect(std.mem.indexOf(u8, found.first.?.message, "is not offered because the bare call at main.selka:6:5 has arguments `helpers.flush` cannot take") != null);
}

test "a re-export of a prelude name that its module never uses bare is accepted, and a re-exported len never captures len" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const helpers: File = .{ .path = "helpers.selka", .bytes = "" ++
        \\public func sum(values: int[]) -> int:
        \\    _ = values
        \\    return 100
        \\
        \\
        \\public func len(value: int) -> int:
        \\    return value + 100
    };
    try t.expectEqual(@as(i64, 103), try runProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import helpers
            \\export helpers.sum
            \\
            \\
            \\func main() -> int:
            \\    return helpers.sum([1]) + 3
        },
        helpers,
    }));
    // The parser decides a bare `len(...)` from the file's own declarations, so `len(xs)` is the builtin here.
    try t.expectEqual(@as(i64, 2), try runProject(arena.allocator(), &.{
        .{ .path = "main.selka", .bytes = "" ++
            \\import helpers
            \\export helpers.len
            \\
            \\
            \\func main() -> int:
            \\    return len([7, 8])
        },
        helpers,
    }));
}

/// N4: one name's three cases. Called bare in its own module, it is refused with the rename; called only with its module's
/// name from another module, it is accepted and runs; re-exported and called bare, the re-export is refused.
fn expectFloatName(arena: std.mem.Allocator, name: []const u8) !void {
    const own = try std.fmt.allocPrint(arena, "func {s}(x: float) -> float:\n    return x + 100.0\n\n\nfunc main() -> int:\n    return int({s}(1.0))\n", .{ name, name });
    const refused = try checkOne(arena, own);
    try expectRefused(refused, name, name);
    const renamed = try std.fmt.allocPrint(arena, "shapes_{s}", .{name});
    try expectEdits(refused, &.{ renamed, renamed });
    const library = try std.fmt.allocPrint(arena, "public func {s}(x: float) -> float:\n    return x + 100.0\n", .{name});
    const caller = try std.fmt.allocPrint(arena, "import lib\n\n\nfunc main() -> int:\n    return int(lib.{s}(1.0)) + int({s}(2.5))\n", .{ name, name });
    // `lib.NAME(1.0)` is 101 and the bare call is the prelude's: `sqrt(2.5)` is 1, `floor` and `trunc` 2, `ceil` 3.
    const builtin: i64 = if (std.mem.eql(u8, name, "sqrt")) 1 else if (std.mem.eql(u8, name, "ceil")) 3 else 2;
    try t.expectEqual(101 + builtin, try runProject(arena, &.{ .{ .path = "main.selka", .bytes = caller }, .{ .path = "lib.selka", .bytes = library } }));
    const reexport = try std.fmt.allocPrint(arena, "import lib\nexport lib.{s}\n\n\nfunc main() -> int:\n    return int({s}(1.0))\n", .{ name, name });
    const exported = try std.fmt.allocPrint(arena, "lib.{s}", .{name});
    const found = try checkProject(arena, &.{ .{ .path = "main.selka", .bytes = reexport }, .{ .path = "lib.selka", .bytes = library } });
    try expectRefused(found, exported, name);
    try expectEdits(found, &.{exported});
}

test "N4 sqrt, floor, ceil and trunc are prelude names: refused bare, accepted qualified, a bare re-export refused" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectFloatName(arena.allocator(), "sqrt");
    try expectFloatName(arena.allocator(), "floor");
    try expectFloatName(arena.allocator(), "ceil");
    try expectFloatName(arena.allocator(), "trunc");
    // A local named like one of them stays a local, and a bare call beside it is still the prelude operation.
    try t.expectEqual(@as(i64, 5), try runOne(
        \\func main() -> int:
        \\    const floor = 3
        \\    return floor + int(ceil(1.5))
    ));
}
