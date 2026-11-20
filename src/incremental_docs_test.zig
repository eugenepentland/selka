//! Checked-docs interface mutation walk, without requiring valid function bodies.
const std = @import("std");
const language = @import("compiler.zig");
const incremental = @import("incremental.zig");
const diagnosticPrint = std.debug.print;

const Input = struct {
    bytes: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Input = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        if (self.bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.bytes);
    }
};

fn fingerprint(allocator: std.mem.Allocator, bytes: []const u8, name: []const u8, checked: bool) ![]const u8 {
    var input: Input = .{ .bytes = bytes };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &input, .read = Input.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    const report = if (checked) try incremental.describe(allocator, &compilation, .{ .compiler_sha256 = "test", .target_abi = "test" }) else try incremental.describePartial(allocator, &compilation);
    defer incremental.deinit(report, allocator);
    for (report.modules) |module| for (module.declarations) |declaration| {
        if (std.mem.eql(u8, declaration.name, name)) return allocator.dupe(u8, declaration.interface_sha256.?);
    };
    return error.TestUnexpectedResult;
}

const Mutation = struct { old: []const u8, new: []const u8, changes: bool = true };

fn walk(allocator: std.mem.Allocator, base: []const u8, name: []const u8, mutations: []const Mutation) !void {
    return walkMode(allocator, base, name, mutations, false);
}

fn walkMode(allocator: std.mem.Allocator, base: []const u8, name: []const u8, mutations: []const Mutation, checked: bool) !void {
    const expected = try fingerprint(allocator, base, name, checked);
    defer allocator.free(expected);
    for (mutations) |mutation| {
        try std.testing.expect(std.mem.indexOf(u8, base, mutation.old) != null);
        const changed = try std.mem.replaceOwned(u8, allocator, base, mutation.old, mutation.new);
        defer allocator.free(changed);
        const actual = fingerprint(allocator, changed, name, checked) catch |err| {
            diagnosticPrint("interface mutation rejected: {s} -> {s}: {s}\n", .{ mutation.old, mutation.new, @errorName(err) });
            return err;
        };
        defer allocator.free(actual);
        if (std.mem.eql(u8, expected, actual) == mutation.changes) {
            diagnosticPrint("interface mutation failed: {s} -> {s}\n", .{ mutation.old, mutation.new });
        }
        try std.testing.expectEqual(!mutation.changes, std.mem.eql(u8, expected, actual));
    }
}

test "checked docs function interface walk includes every signature component and excludes prose" {
    try walk(std.testing.allocator,
        \\@requires(first >= 0)
        \\@ensures(result >= 0)
        \\public func sample(first: int, mut second: int[], named third: int = 3) -> int fails str:
        \\    """Document the public sample carefully."""
        \\    return first
    , "sample", &.{
        .{ .old = "first: int", .new = "renamed: int" },
        .{ .old = "first: int, ", .new = "" },
        .{ .old = "first: int, ", .new = "added: int, first: int, " },
        .{ .old = "first: int, mut second: int[]", .new = "mut second: int[], first: int" },
        .{ .old = "public func", .new = "@noalloc\npublic func" },
        .{ .old = "public func", .new = "@deprecated(\"Use the new function instead\")\npublic func" },
        .{ .old = "first: int", .new = "first: i32" },
        .{ .old = "mut second", .new = "second" },
        .{ .old = "second: int[]", .new = "second: i32[]" },
        .{ .old = "named third", .new = "third" },
        .{ .old = "third: int", .new = "third: i32" },
        .{ .old = "= 3", .new = "= 4" },
        .{ .old = "-> int fails", .new = "-> i32 fails" },
        .{ .old = "fails str", .new = "fails int" },
        .{ .old = "@requires(first >= 0)", .new = "@requires(first >= 1)" },
        .{ .old = "@ensures(result >= 0)", .new = "@ensures(result >= 1)" },
        .{ .old = "public func", .new = "func" },
        .{ .old = "return first", .new = "return third", .changes = false },
        .{ .old = "Document the public sample carefully.", .new = "A completely different explanation.", .changes = false },
        .{ .old = "public func", .new = "@allow(\"unused\", reason=\"A documented waiver\")\npublic func", .changes = false },
        .{ .old = "first: int,", .new = "first : int , # layout comment\n    ", .changes = false },
    });
    try std.testing.expect(true);
}

test "checked docs record and enum interface walk covers last defaults docstrings and payloads" {
    try walk(std.testing.allocator,
        \\@invariant(first >= 0)
        \\public record Sample:
        \\    """The original record documentation."""
        \\    first: int = 1
        \\    second: str = "two"
    , "Sample", &.{
        .{ .old = "first: int", .new = "first: i32" },
        .{ .old = "first: int", .new = "renamed: int" },
        .{ .old = "= 1", .new = "= 2" },
        .{ .old = "second: str", .new = "second: bytes" },
        .{ .old = "second: str", .new = "renamed: str" },
        .{ .old = "public record", .new = "record" },
        .{ .old = "public record", .new = "# Record rationale\npublic record", .changes = false },
        .{ .old = "public record", .new = "# lint: allow unused reason=\"A documented waiver\"\npublic record", .changes = false },
        .{ .old = "\"two\"", .new = "\"three\"" },
        .{ .old = "first >= 0", .new = "first >= 1" },
        .{ .old = "The original record documentation.", .new = "Reworded documentation for a record.", .changes = false },
        .{ .old = "    \"\"\"The original record documentation.\"\"\"\n", .new = "", .changes = false },
        .{ .old = "first: int", .new = "first : int", .changes = false },
    });
    try walk(std.testing.allocator,
        \\public enum Choice:
        \\    """Choose one of the supported values."""
        \\    empty
        \\    item(value: int = 1, label: str = "label")
    , "Choice", &.{
        .{ .old = "empty", .new = "none" },
        .{ .old = "    empty\n", .new = "" },
        .{ .old = "    empty\n", .new = "    empty\n    another\n" },
        .{ .old = "value: int", .new = "renamed: int" },
        .{ .old = "item(value", .new = "entry(value" },
        .{ .old = "value: int", .new = "value: i32" },
        .{ .old = "label: str", .new = "label: bytes" },
        .{ .old = "= 1", .new = "= 2" },
        .{ .old = "\"label\"", .new = "\"renamed\"" },
        .{ .old = "Choose one of the supported values.", .new = "A revised explanation of the enum.", .changes = false },
    });
    try std.testing.expect(true);
}

test "checked docs generic interface walk includes type parameters and requirements" {
    try walk(std.testing.allocator,
        \\public func identity[T](value: T) -> T:
        \\    return value
    , "identity", &.{
        .{ .old = "[T]", .new = "[T, U]" },
        .{ .old = "[T]", .new = "[T: copy]" },
        .{ .old = "value: T", .new = "value: T[]" },
    });
    try std.testing.expect(true);
}

test "checked docs generic type and constant mutation walk" {
    try walk(std.testing.allocator,
        \\public record Box[T]:
        \\    value: T
    , "Box", &.{
        .{ .old = "[T]", .new = "[T, U]" },
        .{ .old = "[T]", .new = "[T: storable]" },
        .{ .old = "value: T", .new = "value: T[]" },
    });
    try walk(std.testing.allocator, "public const number: int = 4\n", "number", &.{
        .{ .old = "= 4", .new = "= 5" },
        .{ .old = ": int", .new = ": i32" },
        .{ .old = "public const", .new = "const" },
        .{ .old = "= 4", .new = "= 4 # a comment", .changes = false },
    });
    try std.testing.expect(true);
}

test "checked docs checked function and record hashes match their declared boundaries" {
    try walkMode(std.testing.allocator,
        \\public func sample(value: int = 3) -> int fails str:
        \\    """The sample's current explanation."""
        \\    return value
        \\func main() -> int:
        \\    return 0
    , "sample", &.{
        .{ .old = "fails str", .new = "fails int" },
        .{ .old = "= 3", .new = "= 4" },
        .{ .old = "public func", .new = "func" },
        .{ .old = "The sample's current explanation.", .new = "A revised but equally useful description.", .changes = false },
        .{ .old = "return value", .new = "return 42", .changes = false },
        .{ .old = "public func", .new = "@allow(\"unused\", reason=\"A documented waiver\")\npublic func", .changes = false },
    }, true);
    try walkMode(std.testing.allocator,
        \\public record Sample:
        \\    """The original record documentation."""
        \\    first: int = 1
        \\    second: str = "two"
        \\func main() -> int:
        \\    return 0
    , "Sample", &.{
        .{ .old = "= 1", .new = "= 2" },
        .{ .old = "\"two\"", .new = "\"three\"" },
        .{ .old = "public record", .new = "record" },
        .{ .old = "The original record documentation.", .new = "A reworded description of this record.", .changes = false },
        .{ .old = "    \"\"\"The original record documentation.\"\"\"\n", .new = "", .changes = false },
        .{ .old = "first: int", .new = "first : int", .changes = false },
    }, true);
    try std.testing.expect(true);
}
