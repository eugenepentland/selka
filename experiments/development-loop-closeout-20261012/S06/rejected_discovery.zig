//! Test discovery for `mylang-core test`: the old runner's rule (NATIVE-TEST-1, interfaces.zig
//! `contractModule`) applied to the checked tree. A function is a test when its unqualified
//! name starts with `test_` or its declaration carries `@test`; a `public` one is always
//! discovered, an unexported `test_` one only when it already has the shape `def() -> bool`,
//! and an unexported `@test` one whatever its shape. It runs when its parameters are all
//! `Stream`s (stand-ins) and it returns `bool` or `Result[bool, E]`; other parameters make it
//! a property test or ask for a capability stand-in, which S1 leaves out. `--filter` is a
//! substring of the qualified name (`module::test_x`), or a glob when it holds `*`, `?` or `[`.
const std = @import("std");
const typed = @import("mylang").typed;

/// What a discovered test returns, which decides how its verdict is read.
pub const Shape = enum {
    /// `bool`: true passes.
    boolean,
    /// `Result[bool, E]`: `Ok(true)` passes, `Ok(false)` and `Err` fail (ERROR-TRACE-3).
    result_of_bool,
    /// Any other result type: the old runner rejects it without a cases file.
    other,
};

/// One discovered test.
pub const Case = struct {
    /// `module::test_x`, the name the old runner prints.
    name: []const u8,
    function: typed.FunctionId,
    shape: Shape,
    /// Parameters other than `Stream`: data parameters make a property test (PROPERTY-TEST-1),
    /// other capabilities get stand-ins (TEST-CAPS-3); the new core runs neither yet.
    other_parameters: usize,
    /// The capability value each leading `Stream` parameter takes: 1 for stdout, 2 for `err`.
    streams: []const i64,
    /// Capability family in parameter order;255 is generated data.
    parameters: []const u8 = &.{},
};

/// A module's name and source text, which says which of its functions are `public` or `@test`.
pub const Module = struct { name: []const u8, text: []const u8 };

/// Every test of `program`, sorted by qualified name. A function name without a module prefix
/// belongs to `entry` (a header-less file). `modules` holds the source of every module whose
/// tests count: the old runner discovers them in the whole project, imports included; a
/// module with no source here has only its defaulting `test_` functions found.
pub fn discover(allocator: std.mem.Allocator, program: typed.Program, entry: []const u8, modules: []const Module) std.mem.Allocator.Error![]Case {
    return within(allocator, program, entry, modules, null);
}

/// `discover` over the functions of the modules named in `only`, or of every module
/// when it is null. A directory run's shared check holds many roots' modules; each
/// root discovers only those its own graph reaches (NEW-CORE-TEST-UNION-1).
pub fn within(allocator: std.mem.Allocator, program: typed.Program, entry: []const u8, modules: []const Module, only: ?[]const Module) std.mem.Allocator.Error![]Case {
    var declarations = try DeclarationIndex.init(allocator, modules);
    defer declarations.deinit();
    var found: std.ArrayList(Case) = .empty;
    for (program.functions) |function| {
        if (function.type_arguments.len != 0 or function.policy.c_abi or function.policy.host != null) continue;
        const split = std.mem.lastIndexOf(u8, function.name, "::");
        const module = if (split) |at| function.name[0..at] else entry;
        if (only) |names| if (!named(names, module)) continue;
        const own = if (split) |at| function.name[at + 2 ..] else function.name;
        const declared = declarations.find(module, own);
        if (!std.mem.startsWith(u8, own, "test_") and !declared.marked) continue;
        const result = typed.typeName(function.signature.return_type, program.records);
        const shape: Shape = if (function.signature.return_type == .bool)
            .boolean
        else if (std.mem.startsWith(u8, result, "Result<bool,") or std.mem.startsWith(u8, result, "Result[bool,"))
            .result_of_bool
        else
            .other;
        var streams: std.ArrayList(i64) = .empty;
        var others: usize = 0;
        const parameters = try allocator.alloc(u8, function.signature.parameter_count);
        for (function.scope.locals[0..function.signature.parameter_count], parameters) |parameter, *family| {
            family.* = if (parameter.ty.capabilityIndex()) |kind| @as(u8, kind) else 255;
            if (parameter.ty == .stream_cap) {
                try streams.append(allocator, if (std.mem.eql(u8, parameter.name, "err")) 2 else 1);
            } else if (family.* > 4) others += 1;
        }
        const defaulting = function.signature.parameter_count == 0 and shape == .boolean;
        const always = declared.public or declared.marked;
        if (!always and !defaulting) continue;
        const name = try std.fmt.allocPrint(allocator, "{s}::{s}", .{ module, own });
        try found.append(allocator, .{ .name = name, .function = function.id, .shape = shape, .other_parameters = others, .streams = try streams.toOwnedSlice(allocator), .parameters = parameters });
    }
    std.mem.sort(Case, found.items, {}, lessByName);
    return found.toOwnedSlice(allocator);
}

fn named(modules: []const Module, name: []const u8) bool {
    for (modules) |module| if (std.mem.eql(u8, module.name, name)) return true;
    return false;
}

fn lessByName(_: void, a: Case, b: Case) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

/// What the source says about one `def`: whether it is `public` and carries `@test`.
const Declared = struct { name: []const u8 = "", public: bool = false, marked: bool = false };

/// Immutable source declaration lookup. The last source for a module wins,
/// while the first declaration in that source wins, matching the linear scan.
const DeclarationIndex = struct {
    allocator: std.mem.Allocator,
    modules: std.StringHashMapUnmanaged(usize) = .empty,
    tables: []std.StringHashMapUnmanaged(Declared),

    fn init(allocator: std.mem.Allocator, sources: []const Module) std.mem.Allocator.Error!DeclarationIndex {
        const tables = try allocator.alloc(std.StringHashMapUnmanaged(Declared), sources.len);
        @memset(tables, .empty);
        var index: DeclarationIndex = .{ .allocator = allocator, .tables = tables };
        errdefer index.deinit();
        for (sources, tables, 0..) |source, *table, position| {
            const scanned = try scan(allocator, source.text);
            defer allocator.free(scanned);
            for (scanned) |declared| {
                const slot = try table.getOrPut(allocator, declared.name);
                if (!slot.found_existing) slot.value_ptr.* = declared;
            }
            try index.modules.put(allocator, source.name, position);
        }
        return index;
    }

    fn deinit(self: *DeclarationIndex) void {
        for (self.tables) |*table| table.deinit(self.allocator);
        self.allocator.free(self.tables);
        self.modules.deinit(self.allocator);
    }

    fn find(self: *const DeclarationIndex, module: []const u8, name: []const u8) Declared {
        const position = self.modules.get(module) orelse return .{};
        return self.tables[position].get(name) orelse .{};
    }
};

/// The top-level function lines of `text`, each with its visibility and test markers.
fn scan(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const Declared {
    var found: std.ArrayList(Declared) = .empty;
    errdefer found.deinit(allocator);
    var marked = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) {
            marked = true;
            continue;
        }
        const public = std.mem.startsWith(u8, line, "public ");
        if (public) line = std.mem.trimStart(u8, line["public ".len..], " \t");
        const length: usize = if (std.mem.startsWith(u8, line, "func ")) 5 else if (std.mem.startsWith(u8, line, "def ")) 4 else continue;
        const rest = std.mem.trimStart(u8, line[length..], " \t");
        const end = std.mem.indexOfAny(u8, rest, "([ \t") orelse rest.len;
        try found.append(allocator, .{ .name = rest[0..end], .public = public, .marked = marked });
        marked = false;
    }
    return found.toOwnedSlice(allocator);
}

/// Case-sensitive shell-style matching of `pattern` against `name`. A pattern with no
/// wildcard is a plain substring, so `parse` selects every module's `test_parse*`.
pub fn matches(pattern: []const u8, name: []const u8) bool {
    if (std.mem.indexOfAny(u8, pattern, "*?[") == null) return std.mem.indexOf(u8, name, pattern) != null;
    var p: usize = 0;
    var n: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (n < name.len) {
        if (p < pattern.len and pattern[p] == '*') {
            p += 1;
            star = p;
            retry = n;
            continue;
        }
        const width = token(pattern[p..], point(name[n..]));
        if (width != 0) {
            p += width;
            n += widthAt(name[n..]);
        } else if (star) |restart| {
            retry += widthAt(name[retry..]);
            n = retry;
            p = restart;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn widthAt(bytes: []const u8) usize {
    if (bytes.len == 0) return 0;
    return @min(bytes.len, std.unicode.utf8ByteSequenceLength(bytes[0]) catch 1);
}

fn point(bytes: []const u8) u21 {
    return std.unicode.utf8Decode(bytes[0..widthAt(bytes)]) catch bytes[0];
}

fn token(pattern: []const u8, character: u21) usize {
    if (pattern.len == 0) return 0;
    if (pattern[0] == '?') return 1;
    if (pattern[0] != '[') return if (point(pattern) == character) widthAt(pattern) else 0;
    const negated = pattern.len > 1 and pattern[1] == '!';
    const first: usize = if (negated) 2 else 1;
    const search = first + @intFromBool(first < pattern.len and pattern[first] == ']');
    const end = std.mem.indexOfScalarPos(u8, pattern, search, ']') orelse return if (character == '[') 1 else 0;
    return if (classContains(pattern[first..end], character) != negated) end + 1 else 0;
}

fn classContains(pattern: []const u8, character: u21) bool {
    var i: usize = 0;
    while (i < pattern.len) {
        const low = point(pattern[i..]);
        i += widthAt(pattern[i..]);
        if (i + 1 < pattern.len and pattern[i] == '-') {
            i += 1;
            const high = point(pattern[i..]);
            i += widthAt(pattern[i..]);
            if (character >= low and character <= high) return true;
        } else if (character == low) return true;
    }
    return false;
}

// spec: NEW-CORE-TEST-DISCOVERY-INDEX-1
test "S06 declaration index preserves first declaration and last module semantics" {
    var index = try DeclarationIndex.init(std.testing.allocator, &.{
        .{ .name = "app", .text = "public func test_old() -> bool:\nfunc test_duplicate() -> bool:\npublic func test_duplicate() -> bool:\n" },
        .{ .name = "peer", .text = "@test\nfunc marked() -> bool:\nfunc test_duplicate() -> bool:\npublic func test_duplicate() -> bool:\n" },
        .{ .name = "app", .text = "public func test_new() -> bool:\n" },
    });
    defer index.deinit();
    try std.testing.expect(!index.find("app", "test_old").public);
    try std.testing.expect(index.find("app", "test_new").public);
    try std.testing.expect(index.find("peer", "marked").marked);
    try std.testing.expect(!index.find("peer", "test_duplicate").public);
    try std.testing.expect(!index.find("missing", "test_new").public);
    try std.testing.expect(!index.find("app", "missing").marked);
}

fn indexAllocationFailures(allocator: std.mem.Allocator) !void {
    var index = try DeclarationIndex.init(allocator, &.{
        .{ .name = "one", .text = "public func test_one() -> bool:\n@test\nfunc marked() -> bool:\n" },
        .{ .name = "two", .text = "public func test_two() -> bool:\n" },
    });
    defer index.deinit();
    try std.testing.expect(index.find("one", "marked").marked);
    try std.testing.expect(index.find("two", "test_two").public);
}

// spec-case: NEW-CORE-TEST-DISCOVERY-INDEX-1
test "S06 declaration index releases partial allocations and propagates exhaustion" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, indexAllocationFailures, .{});
}

fn discoveryFunction(name: []const u8, result: typed.Type, id: usize) typed.Function {
    return .{ .name = name, .id = @fromBackingInt(@intCast(id)), .declaration = .{ .start = 0, .end = 0 }, .scope = .{ .body = @fromBackingInt(@intCast(0)) }, .signature = .{ .return_type = result } };
}

// spec-case: NEW-CORE-TEST-DISCOVERY-INDEX-1
test "S06 indexed discovery preserves selected visibility shapes and sorted function identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const functions = [_]typed.Function{
        discoveryFunction("app::test_default", .bool, 0),
        discoveryFunction("peer::test_public_wrong", .i64, 1),
        discoveryFunction("app::test_private_wrong", .i64, 2),
        discoveryFunction("app::marked", .bool, 3),
        discoveryFunction("app::ordinary", .bool, 4),
    };
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &functions, .main = @fromBackingInt(@intCast(0)) };
    const modules = [_]Module{
        .{ .name = "app", .text = "func test_default() -> bool:\nfunc test_private_wrong() -> int:\n@test\nfunc marked() -> bool:\nfunc ordinary() -> bool:\n" },
        .{ .name = "peer", .text = "public func test_public_wrong() -> int:\n" },
    };
    const all = try discover(arena.allocator(), program, "entry", &modules);
    const selected = try within(arena.allocator(), program, "entry", &modules, modules[0..1]);
    try std.testing.expectEqual(@as(usize, 3), all.len);
    try std.testing.expectEqual(@as(usize, 2), selected.len);
    try std.testing.expectEqualStrings("app::marked", selected[0].name);
    try std.testing.expectEqual(@as(typed.FunctionId, @fromBackingInt(@intCast(3))), selected[0].function);
    try std.testing.expectEqualStrings("app::test_default", selected[1].name);
    try std.testing.expectEqual(Shape.other, all[2].shape);
}
