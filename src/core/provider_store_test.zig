//! Unit bindings have no SSA owner; named provider restrictions still form scopes.
const std = @import("std");
const language = @import("mylang");
const ownership = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

fn lowers(parent: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .bytes = source };
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &entry, .read = Entry.read });
    const unit = &project.compilation;
    var failure: ownership.Failure = .{};
    ownership.checkMode(a, unit.program.?, &failure, true) catch |err| {
        report("{s}: {s}\n", .{ failure.code, failure.message });
        return err;
    };
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    const result = try passes.debug(a, &module);
    try ownership.verifyLowered(&module, &failure);
    try support.verified(a, &module, result.plans);
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC provider stores skip Unit bindings and discarded set insertion" {
    try lowers(std.testing.allocator,
        \\func main() -> int:
        \\    const unit = ()
        \\    mut values = {1, 2}
        \\    values.add(3)
        \\    _ = unit
        \\    return len(values)
    );
    try lowers(std.testing.allocator,
        \\func main() -> int:
        \\    mut values: set[str] = set()
        \\    values.add("x")
        \\    return len(values)
    );
}

// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC provider restrictions borrow a named parent inside their scope" {
    try lowers(std.testing.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.read_only() as frozen:
        \\        if frozen.exists("absent"):
        \\            return 1
        \\        return 0
    );
}

const Entry = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, self.bytes);
    }
};

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .bytes = source };
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &entry, .read = Entry.read });
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkMode(a, project.compilation.program.?, &failure, true));
    try std.testing.expectEqualStrings(code, failure.code);
}

// spec-case: CAPABILITY-FIELD-METHOD-1
// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
// spec-case: NEW-CORE-ZERO-RC-PROVIDER-FIELDS-1
test "zero RC aggregate provider roots cannot copy or invalidate active field scopes" {
    try refuses(std.testing.allocator,
        \\# spec-case: CAPABILITY-FIELD-METHOD-1
        \\import filesystem
        \\
        \\record Store:
        \\    fs: Filesystem
        \\
        \\func main() -> int:
        \\    const root = Store(fs=filesystem.memory())
        \\    const copied = root.copy()
        \\    assert not root.fs.exists("note") and not copied.fs.exists("note")
        \\    return 0
    , "E_ZERO_RC_UNSUPPORTED");
    try refuses(std.testing.allocator,
        \\# spec-case: CAPABILITY-FIELD-METHOD-1
        \\import filesystem
        \\
        \\record Store:
        \\    fs: Filesystem
        \\
        \\func main() -> int:
        \\    const root = Store(fs=filesystem.memory())
        \\    with root.fs.open("note", "w") as file:
        \\        const moved = root
        \\        _ = file.write("still live")
        \\        assert moved.fs.exists("note")
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\# spec-case: CAPABILITY-FIELD-METHOD-1
        \\import filesystem
        \\
        \\record Store:
        \\    fs: Filesystem
        \\
        \\func main() -> int:
        \\    mut root = Store(fs=filesystem.memory())
        \\    with root.fs.open("note", "w") as file:
        \\        root = Store(fs=filesystem.memory())
        \\        _ = file.write("still live")
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-PROVIDER-FIELDS-1
test "zero RC provider construction consumes the old whole binding pin" {
    try lowers(std.testing.allocator,
        \\import filesystem
        \\
        \\record Ports:
        \\    first: Filesystem
        \\    second: Filesystem
        \\
        \\record App:
        \\    ports: Ports
        \\    label: str
        \\
        \\func make(value: int) -> App:
        \\    const ports = Ports(first=filesystem.memory(), second=filesystem.memory())
        \\    return App(ports=ports, label="app-" + str(value))
        \\
        \\func main() -> int:
        \\    mut app = make(1)
        \\    app.label = "changed"
        \\    assert not app.ports.first.exists("missing")
        \\    const moved = app
        \\    assert moved.label == "changed"
        \\    mut replacement = make(2)
        \\    replacement = make(3)
        \\    assert not replacement.ports.second.exists("missing")
        \\    const nested = Ports(first=filesystem.memory(), second=filesystem.memory())
        \\    const final = App(ports=nested, label="final")
        \\    if final.label == "final":
        \\        assert not final.ports.first.exists("missing")
        \\        return 0
        \\    return 1
    );
}
