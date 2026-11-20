//! The functions of one Zig source file, as the edit check identifies them.
//!
//! A function is a `fn` declaration with a body or a `test` block. Its identity inside
//! a file is its name and the position of that name among the file's functions of
//! the same name (`ordinal`); its content is the digest of its tokens, which ignores
//! layout, comments and doc comments, as the compiler identity does
//! (`src/build_identity_rules.zig`). Everything outside the functions (types,
//! constants, imports, `comptime` blocks) is the file's `rest`, digested the same way.
//! Comparing two versions of a file therefore says which functions changed and
//! whether anything other than a function did.
const std = @import("std");
const Ast = std.zig.Ast;

/// One function or test block of a file.
pub const Function = struct {
    /// `name` of a `fn`, or `test:` and the test's name (empty for an unnamed block).
    name: []const u8,
    /// How many functions of the same name come earlier in the file.
    ordinal: u32,
    /// 1-based line of the `fn` or `test` keyword.
    line: u32,
    /// 1-based line of the function's last token.
    end_line: u32,
    /// Digest of the function's tokens.
    digest: Digest,
    /// Whether this is a `test` block.
    is_test: bool,
};

/// A 128-bit token digest.
pub const Digest = [16]u8;

/// The parsed functions of a file, in source order, and the digest of the rest.
pub const File = struct {
    functions: []Function,
    rest: Digest,

    /// Release everything the file owns.
    pub fn deinit(file: *File, gpa: std.mem.Allocator) void {
        for (file.functions) |function| gpa.free(function.name);
        gpa.free(file.functions);
        file.* = undefined;
    }
};

/// Parse `source` and describe its functions; fails on a source that does not parse.
pub fn parse(gpa: std.mem.Allocator, source: []const u8) !File {
    const terminated = try gpa.allocSentinel(u8, source.len, 0);
    defer gpa.free(terminated);
    @memcpy(terminated, source);
    var tree = try Ast.parse(gpa, terminated, .{});
    defer tree.deinit(gpa);
    if (tree.errors.len != 0) return error.ParseError;
    var lines = try LineIndex.init(gpa, terminated);
    defer lines.deinit(gpa);
    var found: std.ArrayList(Function) = .empty;
    errdefer {
        for (found.items) |function| gpa.free(function.name);
        found.deinit(gpa);
    }
    var ranges: std.ArrayList([2]u32) = .empty;
    defer ranges.deinit(gpa);
    var seen: std.StringHashMapUnmanaged(u32) = .empty;
    defer seen.deinit(gpa);
    var test_name: [256]u8 = undefined;
    for (0..tree.nodes.len) |position| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(position));
        const function = describe(&tree, node, &lines, &test_name) orelse continue;
        const name = try gpa.dupe(u8, function.name);
        errdefer gpa.free(name);
        const slot = try seen.getOrPut(gpa, name);
        if (slot.found_existing) slot.value_ptr.* += 1 else slot.value_ptr.* = 0;
        try found.append(gpa, .{
            .name = name,
            .ordinal = slot.value_ptr.*,
            .line = function.line,
            .end_line = function.end_line,
            .digest = function.digest,
            .is_test = function.is_test,
        });
        try ranges.append(gpa, .{ tree.firstToken(node), tree.lastToken(node) });
    }
    const order = struct {
        fn first(_: void, a: Function, b: Function) bool {
            if (a.line != b.line) return a.line < b.line;
            return a.end_line > b.end_line;
        }
    };
    std.mem.sortUnstable(Function, found.items, {}, order.first);
    return .{ .functions = try found.toOwnedSlice(gpa), .rest = restDigest(&tree, ranges.items) };
}

/// The function a node declares, with a placeholder name, or null for other nodes.
/// The name slice points into the tree or `test_name` and is copied by the caller.
fn describe(tree: *const Ast, node: Ast.Node.Index, lines: *const LineIndex, test_name: *[256]u8) ?Function {
    switch (tree.nodeTag(node)) {
        .fn_decl => {
            var buffer: [1]Ast.Node.Index = undefined;
            const proto = tree.fullFnProto(&buffer, node) orelse return null;
            const name_token = proto.name_token orelse return null;
            return .{
                .name = tree.tokenSlice(name_token),
                .ordinal = 0,
                .line = lines.lineOf(tree.tokenStart(proto.ast.fn_token)),
                .end_line = lines.lineOf(tree.tokenStart(tree.lastToken(node))),
                .digest = tokenDigest(tree, tree.firstToken(node), tree.lastToken(node)),
                .is_test = false,
            };
        },
        .test_decl => {
            const name_token = tree.nodeData(node).opt_token_and_node[0].unwrap();
            var text: []const u8 = "test:";
            if (name_token) |token| {
                const trimmed = std.mem.trim(u8, tree.tokenSlice(token), "\"");
                text = std.fmt.bufPrint(test_name, "test:{s}", .{trimmed}) catch "test:";
            }
            return .{
                .name = text,
                .ordinal = 0,
                .line = lines.lineOf(tree.tokenStart(tree.nodeMainToken(node))),
                .end_line = lines.lineOf(tree.tokenStart(tree.lastToken(node))),
                .digest = tokenDigest(tree, tree.firstToken(node), tree.lastToken(node)),
                .is_test = true,
            };
        },
        else => return null,
    }
}

/// Digest of the tokens `first..=last`, ignoring doc comments.
fn tokenDigest(tree: *const Ast, first: u32, last: u32) Digest {
    var hasher: TokenHasher = .init();
    var token = first;
    while (token <= last) : (token += 1) hasher.add(tree, token);
    return hasher.final();
}

/// Digest of every token that lies in none of `ranges` (inclusive token ranges).
fn restDigest(tree: *const Ast, ranges: [][2]u32) Digest {
    const Order = struct {
        fn less(_: void, a: [2]u32, b: [2]u32) bool {
            return a[0] < b[0];
        }
    };
    std.mem.sortUnstable([2]u32, ranges, {}, Order.less);
    var hasher: TokenHasher = .init();
    var token: u32 = 0;
    var next_range: usize = 0;
    const count: u32 = @intCast(tree.tokens.len);
    while (token < count) {
        while (next_range < ranges.len and ranges[next_range][1] < token) next_range += 1;
        if (next_range < ranges.len and ranges[next_range][0] <= token) {
            token = ranges[next_range][1] + 1;
            continue;
        }
        hasher.add(tree, token);
        token += 1;
    }
    return hasher.final();
}

const TokenHasher = struct {
    first: std.hash.Wyhash,
    second: std.hash.Wyhash,

    fn init() TokenHasher {
        return .{ .first = .init(0), .second = .init(1) };
    }

    fn add(hasher: *TokenHasher, tree: *const Ast, token: u32) void {
        const tag = tree.tokenTag(token);
        if (tag == .doc_comment or tag == .container_doc_comment or tag == .eof) return;
        const spelling = tree.tokenSlice(token);
        var header: [6]u8 = undefined;
        std.mem.writeInt(u16, header[0..2], @backingInt(tag), .little);
        std.mem.writeInt(u32, header[2..6], @intCast(spelling.len), .little);
        hasher.first.update(&header);
        hasher.first.update(spelling);
        hasher.second.update(&header);
        hasher.second.update(spelling);
    }

    fn final(hasher: *TokenHasher) Digest {
        var out: Digest = undefined;
        std.mem.writeInt(u64, out[0..8], hasher.first.final(), .little);
        std.mem.writeInt(u64, out[8..16], hasher.second.final(), .little);
        return out;
    }
};

/// Byte offsets of line starts, for turning a token offset into a 1-based line.
const LineIndex = struct {
    starts: []u32,

    fn init(gpa: std.mem.Allocator, source: []const u8) !LineIndex {
        var starts: std.ArrayList(u32) = .empty;
        errdefer starts.deinit(gpa);
        try starts.append(gpa, 0);
        for (source, 0..) |byte, offset| {
            if (byte == '\n') try starts.append(gpa, @intCast(offset + 1));
        }
        return .{ .starts = try starts.toOwnedSlice(gpa) };
    }

    fn deinit(index: *LineIndex, gpa: std.mem.Allocator) void {
        gpa.free(index.starts);
    }

    fn lineOf(index: *const LineIndex, offset: u32) u32 {
        const after = std.sort.upperBound(u32, index.starts, offset, struct {
            fn order(target: u32, probe: u32) std.math.Order {
                return std.math.order(target, probe);
            }
        }.order);
        return @intCast(after);
    }
};

/// One function that differs between two versions of a file.
pub const Change = struct {
    name: []const u8,
    ordinal: u32,
    reason: Reason,
    is_test: bool,

    /// Why the function is listed.
    pub const Reason = enum { changed, added, removed };
};

/// The result of comparing two versions of a file.
pub const Comparison = struct {
    /// Something outside every function differs (types, constants, imports, `comptime` blocks).
    rest_changed: bool,
    /// The functions that were added, removed or whose tokens differ. Names point into the compared files.
    items: []Change,
};

/// Compare two parsed versions of a file, matching functions by name and ordinal.
pub fn compare(gpa: std.mem.Allocator, old: File, new: File) !Comparison {
    var changes: std.ArrayList(Change) = .empty;
    errdefer changes.deinit(gpa);
    for (new.functions) |function| {
        const before = find(old, function.name, function.ordinal) orelse {
            try changes.append(gpa, .{ .name = function.name, .ordinal = function.ordinal, .reason = .added, .is_test = function.is_test });
            continue;
        };
        if (!std.mem.eql(u8, &before.digest, &function.digest)) {
            try changes.append(gpa, .{ .name = function.name, .ordinal = function.ordinal, .reason = .changed, .is_test = function.is_test });
        }
    }
    for (old.functions) |function| {
        if (find(new, function.name, function.ordinal) == null) {
            try changes.append(gpa, .{ .name = function.name, .ordinal = function.ordinal, .reason = .removed, .is_test = function.is_test });
        }
    }
    return .{ .rest_changed = !std.mem.eql(u8, &old.rest, &new.rest), .items = try changes.toOwnedSlice(gpa) };
}

fn find(file: File, name: []const u8, ordinal: u32) ?Function {
    for (file.functions) |function| {
        if (function.ordinal == ordinal and std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

/// Render a digest as 32 lowercase hexadecimal digits.
pub fn hex(digest: Digest) [32]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

test "functions are found by name and ordinal with layout-independent digests" {
    const gpa = std.testing.allocator;
    const base = "const x = 1;\n\nfn a() u32 {\n    return x;\n}\n\npub fn b() void {}\n\nfn a2() void {}\n";
    const relaid = "const x = 1;\n// a note\nfn a() u32 { return x; }\n\n/// docs\npub fn b() void {}\n\nfn a2() void {}\n";
    const edited = "const x = 1;\n\nfn a() u32 {\n    return x + 1;\n}\n\npub fn b() void {}\n\nfn a2() void {}\n";
    var first = try parse(gpa, base);
    defer first.deinit(gpa);
    var second = try parse(gpa, relaid);
    defer second.deinit(gpa);
    var third = try parse(gpa, edited);
    defer third.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), first.functions.len);
    try std.testing.expectEqualStrings("a", first.functions[0].name);
    try std.testing.expectEqual(@as(u32, 3), first.functions[0].line);
    try std.testing.expectEqual(@as(u32, 7), first.functions[1].line);
    try std.testing.expectEqualSlices(u8, &first.functions[0].digest, &second.functions[0].digest);
    try std.testing.expectEqualSlices(u8, &first.rest, &second.rest);
    try std.testing.expect(!std.mem.eql(u8, &first.functions[0].digest, &third.functions[0].digest));
    try std.testing.expectEqualSlices(u8, &first.functions[1].digest, &third.functions[1].digest);
    try std.testing.expectEqualSlices(u8, &first.rest, &third.rest);
}

test "a change outside every function changes the rest, and same-named functions get ordinals" {
    const gpa = std.testing.allocator;
    const base = "const x = 1;\nfn f() void {}\nconst S = struct {\n    fn f() void {}\n};\ntest \"t\" {}\n";
    const edited = "const x = 2;\nfn f() void {}\nconst S = struct {\n    fn f() void {}\n};\ntest \"t\" {}\n";
    var first = try parse(gpa, base);
    defer first.deinit(gpa);
    var second = try parse(gpa, edited);
    defer second.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), first.functions.len);
    try std.testing.expectEqual(@as(u32, 0), first.functions[0].ordinal);
    try std.testing.expectEqual(@as(u32, 1), first.functions[1].ordinal);
    try std.testing.expect(first.functions[2].is_test);
    try std.testing.expectEqualStrings("test:t", first.functions[2].name);
    try std.testing.expect(!std.mem.eql(u8, &first.rest, &second.rest));
    try std.testing.expectEqualSlices(u8, &first.functions[0].digest, &second.functions[0].digest);
}

test "comparing two versions reports changed, added and removed functions and a changed rest" {
    const gpa = std.testing.allocator;
    var old = try parse(gpa, "const k = 1;\nfn a() void {}\nfn b() void {}\ntest \"t\" {}\n");
    defer old.deinit(gpa);
    var new = try parse(gpa, "const k = 2;\nfn a() void { _ = k; }\nfn c() void {}\ntest \"t\" {}\n");
    defer new.deinit(gpa);
    const result = try compare(gpa, old, new);
    defer gpa.free(result.items);
    try std.testing.expect(result.rest_changed);
    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqualStrings("a", result.items[0].name);
    try std.testing.expectEqual(Change.Reason.changed, result.items[0].reason);
    try std.testing.expectEqual(Change.Reason.added, result.items[1].reason);
    try std.testing.expectEqual(Change.Reason.removed, result.items[2].reason);
}
