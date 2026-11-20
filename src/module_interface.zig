//! Module interface artifacts (MODULE-INTERFACE-1): everything a dependent
//! module's check may read about one module, in one versioned, canonical,
//! self-contained serialization, plus the interface and implementation hashes.
//!
//! An interface holds the module's *declaration text*: its header, the import
//! lines that text uses, and every declaration a dependent can reach — each
//! exported declaration and, transitively, every declaration of the same module
//! those name — copied verbatim from the source. A function body is kept only
//! where a dependent reads it: generic templates (instantiated by the user),
//! constants and conversions (evaluated or checked by the user), host and
//! foreign declarations (which have none). Every other body is replaced by
//! `pass`. Declared mutation and return-source contracts travel beside the
//! text; implementation summaries never define a dependent's callable contract. The transitive shape digest of every record the interface
//! reaches, and an interface fingerprint per declaration, make the interface
//! hash change whenever anything a dependent can observe changes, including a
//! foreign record reached only through `list[T]`, `Option[T]`, a dictionary or
//! a union payload. Source positions of the verbatim text are kept apart
//! (`Positions`) and are not part of the interface hash: moving a declaration
//! down a line changes no dependent's check.
const std = @import("std");
const product = @import("product.zig");
const codec = @import("persist_codec.zig");
const summary = @import("semantic_summary.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const embed = @import("embed.zig");

/// Payload version; bump for any layout or meaning change so old artifacts miss.
pub const format_version = "module-interface-v15";
/// File extension of one stored interface.
pub const extension = product.interface_suffix;

/// Why a function's body is (or is not) part of the interface text.
pub const Role = enum(u8) {
    /// Body replaced by `pass`; its declared signature remains authoritative.
    declared,
    /// Generic template: a dependent instantiates the body.
    template,
    /// Constant: a dependent evaluates the value.
    constant,
    /// Conversion: checked declaratively where it is used.
    conversion,
    /// `host def` / `extern def`: a declaration with no guest body.
    foreign,
    /// Called, directly or not, by a constant's value, which a dependent
    /// evaluates by running the bodies it calls.
    evaluated,

    /// Whether a function of this role keeps its whole body in the interface.
    pub fn keepsBody(self: Role) bool {
        return self != .declared;
    }
};

/// Callable facts visible to dependents, obtained exclusively from declarations.
pub const DeclaredFact = struct {
    mutates: []const u16 = &.{},
    return_origin: typed.ReturnOrigin = .fresh,
};

/// One function the interface text declares, by stable key.
pub const Function = struct {
    /// `semantic_key` stable identity: `fn\x1f<module>\x1f<owner>\x1f<name>`.
    key: []const u8,
    role: Role,
    exported: bool,
    /// The declaration contract a dependent may read.
    fact: DeclaredFact,
    /// Interface fingerprint: its declaration, role, facts and kept body, and
    /// those of every declaration it reaches through them, in any module.
    fingerprint: [32]u8,
};

/// One type declaration (record, class, union, enum, alias, domain, resource
/// or constraint) the interface text declares, by module-local name.
pub const Type = struct { name: []const u8, fingerprint: [32]u8 };

/// Everything besides the text that the interface hash covers.
pub const Declarations = struct {
    functions: []const Function = &.{},
    types: []const Type = &.{},
    /// Facade names (`export other.Name`) and the interface fingerprint of the
    /// declaration each names in its defining module.
    reexports: []const Type = &.{},
    /// CHECK-SHAPES-1 transitive shape digest of every catalog record the
    /// interface's declarations reach, own or foreign, by qualified name.
    shapes: []const summary.Shape = &.{},
};

/// One verbatim stretch of the interface text and where it came from.
pub const Origin = struct {
    /// Byte offset in `Interface.text`.
    text: u32,
    /// Byte offset in the module's source.
    source: u32,
    /// Bytes copied verbatim.
    len: u32,
    /// Bytes after them that stand for the gap to the source's next
    /// top-level item, blanked except for newlines: the text maps linearly
    /// onto the source across `len + gap`, and the interface hash skips them.
    gap: u32 = 0,
    /// One-based line and column of `source`.
    line: u32,
    column: u32,
};

/// Where the verbatim parts of the text lie in the module's source. Kept
/// outside the interface hash; a dependent needs them only for positions it
/// reports inside instantiated bodies.
pub const Positions = struct {
    origins: []const Origin = &.{},
    /// Raw source clauses whose normalized positions are hashed in `fact`.
    borrowing: []const source.Span = &.{},
};

/// One module's interface.
pub const Interface = struct {
    module: []const u8,
    /// Modules the declaration text imports, sorted.
    imports: []const []const u8 = &.{},
    /// Canonical selka declaration text a dependent's check parses.
    text: []const u8,
    declarations: Declarations = .{},
    positions: Positions = .{},
};

/// The hash a module's dependents key on: everything but `positions`.
pub fn interfaceHash(interface: Interface) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("module-interface-hash-v1");
    hash.update(format_version);
    frame(&hash, interface.module);
    count(&hash, interface.imports.len);
    for (interface.imports) |name| frame(&hash, name);
    hashText(&hash, interface);
    const declarations = interface.declarations;
    count(&hash, declarations.functions.len);
    for (declarations.functions) |function| {
        frame(&hash, function.key);
        hash.update(&.{ @backingInt(function.role), @as(u8, @intFromBool(function.exported)) });
        hashFact(&hash, function.fact);
        hash.update(&function.fingerprint);
    }
    count(&hash, declarations.types.len);
    for (declarations.types) |ty| {
        frame(&hash, ty.name);
        hash.update(&ty.fingerprint);
    }
    count(&hash, declarations.reexports.len);
    for (declarations.reexports) |entry| {
        frame(&hash, entry.name);
        hash.update(&entry.fingerprint);
    }
    count(&hash, declarations.shapes.len);
    for (declarations.shapes) |shape| {
        frame(&hash, shape.name);
        hash.update(&shape.digest);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// The declaration text without the blanked gaps between items (each is one
/// separator byte instead): blank lines and comments between declarations are
/// positions, not interface.
fn hashText(hash: *std.crypto.hash.Blake3, interface: Interface) void {
    var cursor: usize = 0;
    while (cursor < interface.text.len) {
        const skip = nextSkipped(interface, cursor) orelse break;
        hash.update(interface.text[cursor..skip.start]);
        hash.update(&.{0});
        cursor = skip.end;
    }
    hash.update(interface.text[cursor..]);
}

fn nextSkipped(interface: Interface, cursor: usize) ?source.Span {
    var next: ?source.Span = null;
    for (interface.positions.origins) |origin| {
        if (origin.gap == 0) continue;
        const start = @as(usize, origin.text) + origin.len;
        if (start < cursor or start >= interface.text.len) continue;
        if (next == null or start < next.?.start) next = .{ .start = start, .end = @min(start + origin.gap, interface.text.len) };
    }
    for (interface.positions.borrowing) |span| {
        if (span.end <= span.start) continue;
        if (span.start < cursor or span.end > interface.text.len) continue;
        if (next == null or span.start < next.?.start) next = span;
    }
    return next;
}

/// The digest of an interface's positions section alone.
pub fn positionsHash(interface: Interface) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("module-interface-positions-v1");
    count(&hash, interface.positions.origins.len);
    for (interface.positions.origins) |origin| {
        for ([_]u32{ origin.text, origin.source, origin.len, origin.gap, origin.line, origin.column }) |value| {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, value, .little);
            hash.update(&bytes);
        }
    }
    count(&hash, interface.positions.borrowing.len);
    for (interface.positions.borrowing) |span| {
        count(&hash, span.start);
        count(&hash, span.end);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// One direct import and the interface hash it had when the module was built.
pub const ImportHash = struct { module: []const u8, hash: [32]u8 };

/// Hash the module's source, resolved embedded inputs and direct semantic
/// imports. Positions dependencies are keyed separately.
pub fn implementationHash(module: []const u8, src: source.Source, imports: []ImportHash) [32]u8 {
    std.mem.sort(ImportHash, imports, {}, importBefore);
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("module-implementation-hash-v2");
    frame(&hash, module);
    frame(&hash, src.bytes);
    embed.hashInto(&hash, src.embeds);
    count(&hash, imports.len);
    for (imports) |imported| {
        frame(&hash, imported.module);
        hash.update(&imported.hash);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn importBefore(_: void, a: ImportHash, b: ImportHash) bool {
    return std.mem.lessThan(u8, a.module, b.module);
}

/// Hash one fact field by field, so no padding byte reaches the digest.
pub fn hashFact(hash: *std.crypto.hash.Blake3, fact: DeclaredFact) void {
    hashPositions(hash, fact.mutates);
    switch (fact.return_origin) {
        .fresh => hash.update("fresh"),
        .unknown => hash.update("unknown"),
        .params => |positions| {
            hash.update("params");
            hashPositions(hash, positions);
        },
    }
}

fn hashPositions(hash: *std.crypto.hash.Blake3, positions: []const u16) void {
    count(hash, positions.len);
    for (positions) |position| {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, position, .little);
        hash.update(&bytes);
    }
}

fn frame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    count(hash, bytes.len);
    hash.update(bytes);
}

fn count(hash: *std.crypto.hash.Blake3, value: usize) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}

/// Serialize one interface with its format version.
pub fn encode(allocator: std.mem.Allocator, interface: Interface) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write([]const u8, format_version);
    try writer.write(Interface, interface);
    return writer.bytes.toOwnedSlice(allocator);
}

/// Decode an artifact into storage owned by `allocator` (an arena: a failed
/// decode leaves its partial storage there). A foreign, truncated or trailing
/// payload is null.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) ?Interface {
    var reader = codec.Reader.init(allocator, bytes);
    const version = reader.read([]const u8) catch return null;
    if (!std.mem.eql(u8, version, format_version)) return null;
    const interface = reader.read(Interface) catch return null;
    if (!reader.done()) return null;
    return interface;
}

/// The module name a stable function key names, or null for a foreign key.
pub fn keyModule(key: []const u8) ?[]const u8 {
    var parts = std.mem.splitScalar(u8, key, 0x1f);
    if (!std.mem.eql(u8, parts.next() orelse return null, "fn")) return null;
    return parts.next();
}

/// A stable key as `module::name` or `module::Owner.name`.
pub fn displayKey(allocator: std.mem.Allocator, key: []const u8) std.mem.Allocator.Error![]u8 {
    var parts = std.mem.splitScalar(u8, key, 0x1f);
    _ = parts.next();
    const module = parts.next() orelse "";
    const owner = parts.next() orelse "";
    const name = parts.next() orelse "";
    if (owner.len == 0) return std.fmt.allocPrint(allocator, "{s}::{s}", .{ module, name });
    return std.fmt.allocPrint(allocator, "{s}::{s}.{s}", .{ module, owner, name });
}

/// A canonical, line-oriented rendering of one interface for review and diffs.
pub fn render(allocator: std.mem.Allocator, interface: Interface) std.mem.Allocator.Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    renderTo(allocator, &out.writer, interface) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

fn renderTo(allocator: std.mem.Allocator, writer: *std.Io.Writer, interface: Interface) (std.Io.Writer.Error || std.mem.Allocator.Error)!void {
    try writer.print("{s} {s}\n", .{ format_version, interface.module });
    try writer.print("interface-hash {x}\n", .{interfaceHash(interface)});
    try writer.print("positions-hash {x}\n", .{positionsHash(interface)});
    try writer.writeAll("imports");
    for (interface.imports) |name| try writer.print(" {s}", .{name});
    try writer.writeAll("\nfunctions\n");
    for (interface.declarations.functions) |function| {
        const shown = try displayKey(allocator, function.key);
        defer allocator.free(shown);
        try writer.print("  {s} {s}{s}", .{ shown, @tagName(function.role), if (function.exported) " exported" else "" });
        try writer.writeAll(" mutates=");
        for (function.fact.mutates, 0..) |position, i| {
            if (i != 0) try writer.writeByte(',');
            try writer.print("{d}", .{position});
        }
        try writer.print(" origin={s}", .{@tagName(function.fact.return_origin)});
        if (function.fact.return_origin == .params) {
            for (function.fact.return_origin.params, 0..) |position, i| {
                try writer.writeByte(if (i == 0) '(' else ',');
                try writer.print("{d}", .{position});
            }
            try writer.writeByte(')');
        }
        try writer.print(" fingerprint={x}\n", .{function.fingerprint[0..8]});
    }
    try writer.writeAll("types\n");
    for (interface.declarations.types) |ty| try writer.print("  {s} fingerprint={x}\n", .{ ty.name, ty.fingerprint[0..8] });
    try writer.writeAll("reexports\n");
    for (interface.declarations.reexports) |entry| try writer.print("  {s} fingerprint={x}\n", .{ entry.name, entry.fingerprint[0..8] });
    try writer.writeAll("shapes\n");
    for (interface.declarations.shapes) |shape| try writer.print("  {s} {x}\n", .{ shape.name, shape.digest[0..8] });
    try writer.print("positions {d} verbatim stretches\ntext\n", .{interface.positions.origins.len});
    try writer.writeAll(interface.text);
    if (interface.text.len != 0 and interface.text[interface.text.len - 1] != '\n') try writer.writeByte('\n');
}

/// The file name one module's interface is stored under.
pub fn fileName(allocator: std.mem.Allocator, module: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ module, extension });
}
