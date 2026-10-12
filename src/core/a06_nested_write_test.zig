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
    try counted(std.testing.allocator, program, "603 12\n");
}

fn counted(parent: std.mem.Allocator, guest_source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "nested.my", .data = guest_source });
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
        try std.testing.expectEqualStrings(expected, ran.stdout);
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

const slot_records =
    \\record Cell:
    \\    value: int
    \\    text: str
    \\record Row:
    \\    inner: Cell
    \\    cells: FixedArray[Cell, 2]
    \\
;

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC list slot nested writeback preserves exact owner and index" {
    try counted(std.testing.allocator, slot_records ++
        \\func main(out: Stream) -> int:
        \\    mut rows = [Row(inner=Cell(value=1, text="inner-" + str(1)), cells=FixedArray[Cell, 2]([Cell(value=2, text="left-" + str(2)), Cell(value=3, text="right-" + str(3))]))]
        \\    const saved = rows.copy()
        \\    rows[0].inner.value = 7
        \\    rows[0].inner.text = "changed-" + str(4)
        \\    rows[0].cells[1].value = 9
        \\    rows[0].cells[0].text = "new-" + str(5)
        \\    out.print(rows[0].inner.value, rows[0].cells[1].value, saved[0].inner.value, saved[0].cells[1].value, saved[0].cells[0].text)
        \\    rows.clear()
        \\    out.print(saved[0].inner.text)
        \\    return 0
    , "7 9 1 3 left-2\ninner-1\n");
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one"), Inner(scalar=2, text="two")]
        \\    rows[0] = replace(rows[1], scalar=7)
        \\    return rows[0].scalar
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one")]
        \\    mut other = [Inner(scalar=2, text="two")]
        \\    rows[0] = replace(other[0], scalar=7)
        \\    return rows[0].scalar
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator, records ++
        \\func change(mut rows: Inner[]) -> int:
        \\    rows.clear()
        \\    return 7
        \\func main() -> int:
        \\    mut rows = [Inner(scalar=1, text="one")]
        \\    rows[0] = replace(rows[0], scalar=change(mut rows))
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC explicit tuple copy owns every managed child" {
    try counted(std.testing.allocator,
        \\func clone(pair: tuple[int[], str]) -> tuple[int[], str]:
        \\    return pair.copy()
        \\func main(out: Stream) -> int:
        \\    const owner = ([2, 3], "label-" + str(4))
        \\    const copied = clone(owner)
        \\    mut original_values, original_text = owner
        \\    original_values.append(9)
        \\    original_text = "changed-" + str(5)
        \\    const values, text = copied
        \\    out.print(values == [2, 3], original_values == [2, 3, 9], text, original_text)
        \\    return 0
    , "True True label-4 changed-5\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC migrated traversal originals still reject invalidation and retained escape" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    mut total = 0
        \\    for value in items:
        \\        total += value
        \\        items[1] = 9
        \\    return total
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut values = {1: 10, 2: 20}
        \\    for key in values:
        \\        values[key] = values[key] + 1
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut items = [1]
        \\    for value in items:
        \\        items.append(value + 1)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func retained() -> bytes:
        \\    const source = b"prefix-data-suffix" + b"!"
        \\    return source.view(7, 11)
        \\func main() -> int:
        \\    return len(retained())
    , "E_ZERO_RC_UNSUPPORTED");
    try refuses(std.testing.allocator,
        \\func escaped() -> ByteView:
        \\    const source = b"prefix-data-suffix" + b"!"
        \\    return source.borrow(7, 11)
        \\func main() -> int:
        \\    return len(escaped())
    , "E_ZERO_RC_VIEW_SIGNATURE");
}
