//! Canonical prelude identities, ordinary numbers, and runner entry conventions.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
fn run(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "core.my", text);
    defer compilation.deinit();
    const result = compilation.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expect(result == .value);
    try t.expectEqual(expected, result.value);
}
const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "values.my")) return allocator.dupe(u8,
            \\module values
            \\export answer
            \\export maybe
            \\export items
            \\def answer() -> Result[int, int]:
            \\    return Ok(42)
            \\def maybe() -> Option[int]:
            \\    return Some(1)
            \\def items() -> list[int]:
            \\    return [1, 2]
        );
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8, "module main;import values;" ++
            "fn main()->i64{let option:Option<i64>=values::maybe();" ++
            "match option{Option<i64>.some(n)=>{if n!=1{return 1;}},Option<i64>.none=>{return 2;}}" ++
            "let numbers:List<i64>=values::items();if len(numbers)!=2{return 3;}" ++
            "match values::answer(){Result<i64,i64>.ok(n)=>{return n;},Result<i64,i64>.err(e)=>{return e;}}}");
    }
};
// spec: PYTHON-CORE-1
test "prelude List Result and Option keep one identity across modules and spellings" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try language.vm.run(t.allocator, compilation.code.?)).value);
}
// spec: PYTHON-CORE-2
test "unit and checked-result main adapt to scalar status without changing guest call signatures" {
    try run("fn main()->unit{}", 0);
    try run("fn main()->Result<unit,i64>{return Ok(());}", 0);
    try run("fn main()->Result<unit,i64>{return Err(42);}", 42);
    try run("fn main()->Result<i64,i64>{return Ok(42);}", 42);
}

const Entries = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return allocator.dupe(u8, "module main\n\ndef main() -> Result[None, int]:\n    return Ok(None)\n");
    }
};
// spec-case: PYTHON-CORE-2
test "PYTHON-CORE-2 a project with an adapted entry still emits native units" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Entries.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    const manifest = compilation.emitQbe(t.allocator) catch |err| {
        for (compilation.diagnostics.items.items) |diag| debug.print("{s}: {s}\n", .{ diag.code, diag.message });
        return err;
    };
    defer t.allocator.free(manifest);
    // The synthesized wrapper is the entry symbol and names no public export.
    try t.expect(std.mem.indexOf(u8, manifest, "language-schema-v1") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "qbe-units-v1") != null);
}
// spec: PYTHON-CORE-4
test "floating literals operators and comparisons use numeric binary64 semantics" {
    try run("fn add(x:float,y:float)->float{return x+y;}fn main()->i64{let value=add(1.5,2.5)*10.0+2.0;if value==42.0{return 42;}return 1;}", 42);
    try run("fn main()->i64{let zero=-0.0;let nan=0.0/0.0;if zero!=0.0{return 1;}if nan==nan{return 2;}if !(nan!=nan){return 3;}return 42;}", 42);
}
// spec-case: PYTHON-CORE-4
test "floating comparisons and remainder preserve operand evaluation once in source order" {
    try run(
        \\def operand(log: list[int], value: int) -> float:
        \\    log.append(value)
        \\    return float(value)
        \\def main() -> int:
        \\    log: list[int] = []
        \\    if operand(log, 5) > operand(log, 2):
        \\        value = operand(log, 7) % operand(log, 3)
        \\        if value != 1.0:
        \\            return 1
        \\    if len(log) != 4:
        \\        return 2
        \\    return log[0] + log[1] + log[2] + log[3] + 25
    , 42);
}
// spec-case: PY-COLLECTIONS-1
test "Python indexed assignment evaluates RHS before receiver and index exactly once" {
    try run(
        \\def receiver(log: list[int], values: list[int]) -> list[int]:
        \\    log.append(2)
        \\    return values
        \\def index(log: list[int]) -> int:
        \\    log.append(3)
        \\    return 0
        \\def value(log: list[int]) -> int:
        \\    log.append(1)
        \\    return 42
        \\def main() -> int:
        \\    log: list[int] = []
        \\    values = [0]
        \\    receiver(log, values)[index(log)] = value(log)
        \\    if len(log) != 3 or values[0] != 42:
        \\        return 1
        \\    return log[0] * 100 + log[1] * 10 + log[2]
    , 123);
}
// spec-case: PYTHON-3
test "Python payloadless enum values use ordinary dotted members" {
    try run(
        \\enum Kind { atom, group }
        \\def main() -> int:
        \\    kind = Kind.atom
        \\    if kind == Kind.atom:
        \\        return 42
        \\    return 1
    , 42);
}
const PythonModules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import helpers
            \\def main() -> int:
            \\    if helpers.Kind.atom != helpers.Kind.atom:
            \\        return 1
            \\    match helpers.answer([42], "answer", 1.5):
            \\        case Ok(values):
            \\            return values["answer"]
            \\        case Err(code):
            \\            return code
        );
        if (std.mem.eql(u8, path, "helpers.my")) return allocator.dupe(u8,
            \\module helpers
            \\export answer
            \\export Kind
            \\enum Kind { atom, group }
            \\def answer(values: list[int], key: str, number: float) -> Result[dict[str, int], int]:
            \\    if number != 1.5:
            \\        return Err(2)
            \\    return Ok({key: values[0]})
        );
        return error.NotFound;
    }
};
// spec-case: PYTHON-CORE-1
test "Python exported module signatures share builtin types and resolve enum members" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = PythonModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    try t.expectEqual(@as(i64, 42), (try language.vm.runWithOptions(t.allocator, compilation.code.?, .{ .memory = .{ .gc = .{ .stress = true } } })).value);
}
// spec-case: PYTHON-CALL-1
test "Python string and float defaults remain typed and independent across repeated calls" {
    try run(
        \\def length(text: str = "é", scale: float = 2.5) -> int:
        \\    return len(text) + int(scale)
        \\def main() -> int:
        \\    return length() + length() + length(scale=33.5)
    , 40);
}
// spec: PYTHON-CORE-3
test "representable integer literals inherit parameter local and expression contexts" {
    try run("fn widen(x:u8)->i64{return cast<i64>(x);}fn main()->i64{let n:u8=40;return widen(n+2);}", 42);
    try run("fn main()->i64{let n:i8=-128;let wide:u64=18446744073709551615;_ = wide;return cast<i64>(n)+170;}", 42);
    var compilation = try language.Compilation.init(t.allocator, "range.my", "fn main()->i64{let x:u8=256;_ = x;return 0;}");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_INTEGER_RANGE", compilation.diagnostics.items[0].code);
}
// spec-case: PYTHON-CORE-4
test "Python division remainder numeric conversions and generic numbers" {
    try run(
        \\def main() -> int:
        \\    if 5 / 2 != 2.5:
        \\        return 1
        \\    if -5 // 2 != -3 or -5 % 2 != 1:
        \\        return 2
        \\    if 5 // -2 != -3 or 5 % -2 != -1:
        \\        return 3
        \\    if -5.0 // 2.0 != -3.0 or -5.0 % 2.0 != 1.0:
        \\        return 4
        \\    return int(float(-2) + 4.4e1)
    , 42);
    try run(
        \\def adjust[T](unused: T, value: float) -> float:
        \\    _ = unused
        \\    return value + 1.5
        \\def main() -> int:
        \\    return int(adjust(0, 40.5))
    , 42);
}
// spec-case: PYTHON-CORE-1
test "Python contextual Option constructors work in generic functions" {
    try run(
        \\def present[T](value: T) -> Option[T]:
        \\    return Some(value)
        \\def absent[T](value: T) -> Option[T]:
        \\    _ = value
        \\    return None
        \\def main() -> int:
        \\    empty: Option[int] = absent(0)
        \\    _ = empty
        \\    match present(42):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return 1
    , 42);
}
