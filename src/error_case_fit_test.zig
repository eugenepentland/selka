//! `try` and `fail value` convert an error into a case of the enclosing error union only when
//! exactly one case can carry it (`typed.errorCaseFit`). With several, the program is refused with
//! `E_ERROR_CASE_AMBIGUOUS`, so reordering an enum's cases never changes the error a program
//! reports; `fail value` carries the certain repair that names the case chosen until now.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const typed = @import("typed.zig");

const code = "E_ERROR_CASE_AMBIGUOUS";

/// The checked diagnostic of a refused program: its code, message, repair text and note.
const Refused = struct { code: []const u8, message: []const u8, fix: ?[]const u8, note: ?[]const u8 };

/// Check `text` (named `cases.selka`), require it refused, and copy its first diagnostic into `arena`.
fn refused(arena: std.mem.Allocator, text: []const u8) !Refused {
    var compilation = try language.Compilation.init(t.allocator, "cases.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    return .{
        .code = try arena.dupe(u8, item.code),
        .message = try arena.dupe(u8, item.message),
        .fix = if (item.provenance.fix) |fix| try arena.dupe(u8, fix.edit.text) else null,
        .note = if (item.related) |note| try arena.dupe(u8, note.message) else null,
    };
}

/// Build and run `text` natively and return what it printed on standard output.
fn printed(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "cases.selka", text);
    defer compilation.deinit();
    const outcome = try native.run(&compilation);
    try t.expect(!outcome.trapped());
    return arena.dupe(u8, outcome.stdout);
}

const two_cases =
    \\enum AppErr:
    \\    Io(message: str)
    \\    Parse(value: str)
    \\    Other(code: int)
    \\
    \\func parse(s: str) -> int fails str:
    \\    if len(s) == 0:
    \\        fail "empty"
    \\    return len(s)
    \\
;

test "error case fit: try refuses a conversion two cases fit, listing them in declaration order, with no repair" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(), two_cases ++
        \\func run(s: str) -> int fails AppErr:
        \\    const n = try parse(s)
        \\    return n + 1
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expectEqualStrings("`try` cannot convert the error: 2 cases of AppErr can carry this str error (Io and Parse), and the order of " ++
        "the cases must not choose one; match the result and fail with the case you mean, for example `fail AppErr.Io(message=error)` in its " ++
        "`Err(error)` arm", result.message);
    try t.expect(result.fix == null);
}

test "error case fit: fail value refuses a conversion two cases fit and repairs it with the first case, the one chosen until now" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(), two_cases ++
        \\func run(s: str) -> int fails AppErr:
        \\    if len(s) == 0:
        \\        fail "nothing"
        \\    return 1
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.indexOf(u8, result.message, "name the case, `fail AppErr.Io(message=\"nothing\")`. Io is the case the compiler chose until now") != null);
    try t.expectEqualStrings("AppErr.Io(message=\"nothing\")", result.fix.?);
}

test "error case fit: a try that on fail rewrites into a failing match is still refused as a try, with no repair" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(), two_cases ++
        \\func run(out: Stream, s: str) -> int fails AppErr:
        \\    on fail: print(out, "cleanup")
        \\    const n = try parse(s)
        \\    return n
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.startsWith(u8, result.message, "`try` cannot convert the error: 2 cases of AppErr"));
    try t.expect(result.fix == null);
}

test "error case fit: a generic body whose cases coincide only for one instance is refused there, with a note naming the instance" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(),
        \\enum Wrap[T]:
        \\    First(value: T)
        \\    Second(value: str)
        \\
        \\func inner[T](own x: T) -> int fails T:
        \\    fail x
        \\
        \\func outer[T](own x: T) -> int fails Wrap[T]:
        \\    const n = try inner(own x)
        \\    return n
        \\
        \\func main() -> int:
        \\    match outer(3):
        \\        case Ok(v):
        \\            return v
        \\        case Err(_):
        \\            pass
        \\    match outer("s"):
        \\        case Ok(v):
        \\            return v
        \\        case Err(_):
        \\            return 2
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.indexOf(u8, result.message, "2 cases of Wrap[str] can carry this str error (First and Second)") != null);
    try t.expectEqualStrings("in the instance outer[str]: the cases fit for these type arguments", result.note.?);
    // The instance is refused for its type arguments, so naming the first case would repair this instance and not the template.
    try t.expect(result.fix == null);
}

test "error case fit: a generic body whose cases coincide for every instance is refused at its declaration" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(),
        \\enum Wrap[T]:
        \\    First(value: T)
        \\    Second(value: T)
        \\
        \\func inner[T](own x: T) -> int fails T:
        \\    fail x
        \\
        \\func outer[T](own x: T) -> int fails Wrap[T]:
        \\    const n = try inner(own x)
        \\    return n
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.startsWith(u8, result.message, "`try` cannot convert the error: 2 cases of Wrap[T] can carry this T error (First and Second) for every instance, " ++
        "and the order of the cases must not choose one; match the result and fail with the case you mean, for example `fail Wrap.First(value=error)` in its `Err(error)` arm"));
    try t.expect(result.fix == null);
}

test "error case fit: a fail in a generic body whose cases coincide for every instance carries the repair of the concrete case" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(),
        \\enum Wrap[T]:
        \\    First(value: T)
        \\    Second(value: T)
        \\
        \\func outer[T](own x: T) -> int fails Wrap[T]:
        \\    fail x
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.startsWith(u8, result.message, "`fail` cannot convert the value: 2 cases of Wrap[T] can carry this T error (First and Second) for every instance, " ++
        "and the order of the cases must not choose one; name the case, `fail Wrap.First(value=x)`. First is the case the compiler chose until now"));
    try t.expectEqualStrings("Wrap.First(value=x)", result.fix.?);
}

test "error case fit: a fail in a generic body offers no edit when an earlier case could carry the error for some instance" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const result = try refused(arena.allocator(),
        \\enum Wrap[T]:
        \\    Early(value: str)
        \\    First(value: T)
        \\    Second(value: T)
        \\
        \\func outer[T](own x: T) -> int fails Wrap[T]:
        \\    fail x
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqualStrings(code, result.code);
    try t.expect(std.mem.indexOf(u8, result.message, "(First and Second) for every instance") != null);
    try t.expect(result.fix == null);
}

test "error case fit: a fail of a concrete error in a generic body, and in a function that fails with a generic union instance, carry the repair" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const in_generic = try refused(arena.allocator(),
        \\enum AppErr:
        \\    Parse(value: str)
        \\    Io(value: str)
        \\
        \\func outer[T](x: T, s: str) -> int fails AppErr:
        \\    fail s
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expect(std.mem.indexOf(u8, in_generic.message, "2 cases of AppErr can carry this str error (Parse and Io), and the order") != null);
    try t.expectEqualStrings("AppErr.Parse(value=s)", in_generic.fix.?);
    // A generic union is built through its bare name, which takes its type arguments from the expected type.
    const instance = try refused(arena.allocator(),
        \\enum Wrap[T]:
        \\    First(value: T)
        \\    Second(value: T)
        \\
        \\func outer(s: str) -> int fails Wrap[str]:
        \\    fail s
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expect(std.mem.indexOf(u8, instance.message, "2 cases of Wrap[str] can carry this str error (First and Second)") != null);
    try t.expectEqualStrings("Wrap.First(value=s)", instance.fix.?);
}

test "error case fit: with one fitting case try and fail still convert, and a two-field case does not fit" {
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const output = try printed(arena.allocator(),
        \\enum AppErr:
        \\    Parse(value: str)
        \\    Located(message: str, line: int)
        \\    Code(value: int)
        \\
        \\func parse(s: str) -> int fails str:
        \\    if len(s) == 0:
        \\        fail "empty"
        \\    return len(s)
        \\
        \\func run(s: str) -> int fails AppErr:
        \\    if len(s) == 1:
        \\        fail "one"
        \\    const n = try parse(s)
        \\    return n
        \\
        \\func main(out: Stream) -> int:
        \\    match run(""):
        \\        case Ok(v):
        \\            print(out, v)
        \\        case Err(e):
        \\            print(out, e)
        \\    match run("x"):
        \\        case Ok(v):
        \\            print(out, v)
        \\        case Err(e):
        \\            print(out, e)
        \\    return 0
    );
    try t.expectEqualStrings("AppErr.Parse(value='empty')\nAppErr.Parse(value='one')\n", output);
}

test "error case fit: a case fit answers its one case only when exactly one case fits" {
    const none: typed.CaseFit = .{};
    var one: typed.CaseFit = .{ .count = 1 };
    one.tags[0] = 2;
    var two: typed.CaseFit = .{ .count = 2 };
    two.tags[0] = 0;
    two.tags[1] = 3;
    try t.expectEqual(@as(?usize, null), none.unique());
    try t.expectEqual(@as(?usize, 2), one.unique());
    try t.expectEqual(@as(?usize, null), two.unique());
    try t.expectEqualSlices(usize, &.{ 0, 3 }, two.kept());
}
