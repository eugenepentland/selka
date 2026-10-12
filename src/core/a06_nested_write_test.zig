//! Exact nested field writebacks retain their parent ownership and direct cleanup.
const std = @import("std");
const language = @import("mylang");
const options = @import("core_test_options");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

const records =
    \\record Inner:
    \\    scalar: int
    \\    text: str
    \\record Outer:
    \\    left: Inner
    \\    right: Inner
    \\
;

const program = records ++
    \\func sample(early: bool) -> int:
    \\    mut owner = Outer(left=Inner(scalar=2, text="left-" + str(1)), right=Inner(scalar=4, text="right-" + str(2)))
    \\    owner.left.scalar += 3
    \\    owner.right.scalar = 9
    \\    const snapshot = owner.copy()
    \\    owner.left.scalar = 17
    \\    owner.right.text = "changed-" + str(3)
    \\    if early:
    \\        return snapshot.left.scalar + len(snapshot.right.text)
    \\    owner = Outer(left=Inner(scalar=0, text="replacement-" + str(4)), right=Inner(scalar=0, text="replacement-" + str(5)))
    \\    return snapshot.left.scalar * 100 + snapshot.right.scalar * 10 + len(snapshot.left.text) + len(snapshot.right.text)
    \\func main(out: Stream) -> int:
    \\    out.print(sample(False), sample(True))
    \\    return 0
;

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "nested-write.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s}: {s}\n", .{ diagnostic.code, diagnostic.message });
        return err;
    };
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkMode(arena.allocator(), unit.program.?, &failure, true));
    try std.testing.expectEqualStrings(code, failure.code);
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC nested writeback rejects another field another base and partial moves" {
    // Matching the owner alone would accidentally admit the wrong field.
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    owner.left = replace(owner.right, scalar=7)
        \\    return owner.left.scalar
    , "E_SINGLE_OWNER_BORROW");
    // Matching the field index alone would accidentally admit another owner.
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    mut other = Outer(left=Inner(scalar=3, text="other"), right=Inner(scalar=5, text="other-right"))
        \\    owner.left = replace(other.left, scalar=7)
        \\    return owner.left.scalar
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, records ++
        \\func detach(owner: Outer) -> Inner:
        \\    return owner.left
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, records ++
        \\func observe(inner: Inner, mut owner: Outer) -> int:
        \\    owner.left.scalar = 7
        \\    return inner.scalar
        \\func main() -> int:
        \\    mut owner = Outer(left=Inner(scalar=2, text="left"), right=Inner(scalar=4, text="right"))
        \\    return observe(owner.left, mut owner)
    , "E_SINGLE_OWNER_OVERLAP");
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC nested writeback keeps snapshots and directly cleans early returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "nested.my", .data = program });
    const source = try std.fs.path.join(a, &.{ root, "nested.my" });
    const modes = [_][]const []const u8{
        &.{ "--unoptimized", "--experimental-zero-rc" },
        &.{ "--release", "--verify-facts", "--experimental-zero-rc" },
    };
    for (modes, 0..) |flags, index| {
        const binary = try std.fmt.allocPrint(a, "{s}/nested-{d}", .{ root, index });
        const llvm_path = try std.fmt.allocPrint(a, "{s}.ll", .{binary});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", binary, "--cache-dir", root, "--counters", "--emit-llvm", llvm_path });
        try argv.appendSlice(a, flags);
        const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
        if (built.term != .exited or built.term.exited != 0) report("nested writeback build: {s}{s}\n", .{ built.stdout, built.stderr });
        try std.testing.expect(built.term == .exited and built.term.exited == 0);
        const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
        var environment = std.process.Environ.Map.init(a);
        try environment.put("MYLANG_COUNTERS", path);
        const ran = try std.process.run(a, std.testing.io, .{ .argv = &.{binary}, .environ_map = &environment });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings("603 12\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20));
        const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "live_bytes_at_exit" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", name }));
        }
        for ([_][]const u8{ "retain", "release", "unique_test" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "kinds", name, "count" }));
        }
        try std.testing.expect(field(counts, &.{ "totals", "allocs" }) > 0);
        try std.testing.expect(field(counts, &.{ "kinds", "release_unique", "count" }) > 0);
        const llvm = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, llvm_path, a, .limited(16 << 20));
        try std.testing.expect(zero.emittedClean(llvm));
    }
}
