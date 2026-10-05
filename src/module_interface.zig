//! Module interface artifacts (MODULE-INTERFACE-1): everything a dependent
//! module's check may read about one module, in one versioned, canonical,
//! self-contained serialization, plus the two hashes a per-module build keys on.
//!
//! An interface holds the module's *declaration text*: its header, the import
//! lines that text uses, and every declaration a dependent can reach — each
//! exported declaration and, transitively, every declaration of the same module
//! those name — copied verbatim from the source. A function body is kept only
//! where a dependent reads it: generic templates (instantiated by the user),
//! constants and conversions (evaluated or checked by the user), host and
//! foreign declarations (which have none) and functions the bytecode inliner
//! splices into callers. Every other body is replaced by `pass`, and its facts
//! (effect mask, mutation summary, return origin) travel beside the text so a
//! dependent's check stands them in, as a check summary stands in for an
//! unchanged body. The transitive shape digest of every record the interface
//! reaches, and an interface fingerprint per declaration, make the interface
//! hash change whenever anything a dependent can observe changes, including a
//! foreign record reached only through `list[T]`, `Option[T]`, a dictionary or
//! a union payload. Source positions of the verbatim text are kept apart
//! (`Positions`) and are not part of the interface hash: moving a declaration
//! down a line changes no dependent's check.
const std = @import("std");
const codec = @import("persist_codec.zig");
const summary = @import("semantic_summary.zig");
const effect_set = @import("effect_set.zig");
const source = @import("source.zig");
const embed = @import("embed.zig");

/// Payload version; bump for any layout or meaning change so old artifacts miss.
pub const format_version = "module-interface-v4";
/// File extension of one stored interface.
pub const extension = ".myi";

/// Why a function's body is (or is not) part of the interface text.
pub const Role = enum(u8) {
    /// Body replaced by `pass`; its facts stand in for it.
    declared,
    /// Generic template: a dependent instantiates the body.
    template,
    /// Constant: a dependent evaluates the value.
    constant,
    /// Conversion: checked declaratively where it is used.
    conversion,
    /// `host def` / `extern def`: a declaration with no guest body.
    foreign,
    /// Small leaf the bytecode inliner splices into its callers.
    inlined,
    /// Called, directly or not, by a constant's value, which a dependent
    /// evaluates by running the bodies it calls.
    evaluated,

    /// Whether a function of this role keeps its whole body in the interface.
    pub fn keepsBody(self: Role) bool {
        return self != .declared;
    }
};

/// One function the interface text declares, by stable key.
pub const Function = struct {
    /// `semantic_key` stable identity: `fn\x1f<module>\x1f<owner>\x1f<name>`.
    key: []const u8,
    role: Role,
    exported: bool,
    /// The whole-program facts a dependent's passes read about it.
    fact: summary.Fact,
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
/// reports inside instantiated or inlined bodies.
pub const Positions = struct { origins: []const Origin = &.{} };

/// One module's interface.
pub const Interface = struct {
    module: []const u8,
    /// Modules the declaration text imports, sorted.
    imports: []const []const u8 = &.{},
    /// Canonical mylang declaration text a dependent's check parses.
    text: []const u8,
    declarations: Declarations = .{},
    positions: Positions = .{},
    /// MODULE-COMPILE-1: what a dependent's emission reads about the module's
    /// functions, written by the module's own compile; empty in an interface
    /// built from a check alone (`interfaces emit`). Outside the interface
    /// hash, covered by `emissionHash`.
    emission: Emission = .{},
};

/// The facts a dependent's code generation reads about a module's functions
/// (MODULE-COMPILE-1), and the program-wide marks a link merges.
pub const Emission = struct {
    /// The lowering and emission switches the facts were computed under, as
    /// `configName` spells them; empty when the interface carries none.
    config: []const u8 = "",
    /// Every function the declaration text declares, by checked name, sorted.
    functions: []const EmittedFunction = &.{},
    /// Every function the module's units take as a value, sorted and unique:
    /// the module's share of the program's function-value target set.
    values: []const []const u8 = &.{},
    marks: Marks = .{},
    physical: @import("module_physical.zig").Archive = .{},
};

/// One declared function's emission facts: whether a call to it may allocate
/// (transitively; the root protocol around the call depends on it) and which
/// of its parameters its body writes (the caller's borrow depends on it).
pub const EmittedFunction = struct {
    name: []const u8,
    allocates: bool,
    caller_storage: u16 = 0,
    writes: []const bool,
    stable: []const bool = &.{},
    physical: [32]u8 = @splat(0),
};

/// Whether any unit of the module opens an arena scope (every unit of the
/// program is emitted for arenas then) or needs the text runtime.
pub const Marks = struct { arena: bool = false, text: bool = false };

/// The spelling of one emission configuration an interface's facts hold for.
pub fn configName(allocator: std.mem.Allocator, config: EmissionConfig) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "debug={s} steps={s} frames={s} arenas={s} runtime={s} values={s} cow={s}{s}{s}", .{
        if (config.drop_debug) "dropped" else "kept",
        onOff(config.step_checks),
        onOff(config.frame_checks),
        onOff(config.arenas),
        @import("runtime_mode.zig").identity(),
        onOff(@import("value_semantics.zig").enabled()),
        if (@import("value_semantics.zig").counting()) "counting" else "checked",
        config.native_variants.suffix(),
        config.scalar_policy.suffix(),
    });
}

/// The switches a module's emission facts depend on: the lowering's `debug`
/// policy, the emission policy and the program-wide arena switch.
pub const EmissionConfig = struct {
    drop_debug: bool,
    step_checks: bool,
    frame_checks: bool,
    arenas: bool,
    native_variants: @import("runtime_contract").native_variants.Policy = .original,
    scalar_policy: @import("runtime_contract").scalars.Policy = .qbe,
};

fn onOff(flag: bool) []const u8 {
    return if (flag) "on" else "off";
}

/// The hash a dependent's code keys on besides the interface hash: the
/// configuration, every declared function's emission facts and the physical
/// archive's record rows, which every dependent restores into its record
/// catalog (and so into its shared metadata part) whatever the runtime
/// (MODULE-EMISSION-RECORDS-1); the function and dependency rows count once a
/// physical body can affect a dependent's RC code generation. The program
/// marks and value targets are link inputs, not a dependent's.
pub fn emissionHash(interface: Interface) [32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("module-emission-hash-v5");
    frame(&hash, interface.module);
    frame(&hash, interface.emission.config);
    count(&hash, interface.emission.functions.len);
    for (interface.emission.functions) |function| {
        frame(&hash, function.name);
        hash.update(&.{@as(u8, @intFromBool(function.allocates))});
        count(&hash, function.writes.len);
        for (function.writes) |flag| hash.update(&.{@as(u8, @intFromBool(flag))});
        count(&hash, function.stable.len);
        for (function.stable) |flag| hash.update(&.{@intFromBool(flag)});
        hash.update(&function.physical);
        var storage: [2]u8 = undefined;
        std.mem.writeInt(u16, &storage, function.caller_storage, .little);
        hash.update(&storage);
    }
    count(&hash, interface.emission.physical.records.len);
    for (interface.emission.physical.records) |row| {
        frame(&hash, row.name);
        frame(&hash, row.bytes);
    }
    if (physicalInputs(interface)) {
        inline for (.{ interface.emission.physical.functions, interface.emission.physical.dependencies }) |rows| {
            count(&hash, rows.len);
            for (rows) |row| {
                frame(&hash, row.name);
                frame(&hash, row.bytes);
            }
        }
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// Whether real physical bodies can affect a dependent's RC code generation.
pub fn physicalInputs(interface: Interface) bool {
    const zero: [32]u8 = @splat(0);
    for (interface.emission.functions) |function| if (!std.mem.eql(u8, &function.physical, &zero)) return true;
    return false;
}

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
    const text = interface.text;
    var cursor: usize = 0;
    var length: usize = 0;
    for (interface.positions.origins) |origin| {
        if (origin.gap == 0) continue;
        const gap_start = @min(@as(usize, origin.text) + origin.len, text.len);
        const gap_end = @min(gap_start + origin.gap, text.len);
        if (gap_start < cursor) continue;
        length += gap_start - cursor + 1;
        cursor = gap_end;
    }
    length += text.len - @min(cursor, text.len);
    count(hash, length);
    cursor = 0;
    for (interface.positions.origins) |origin| {
        if (origin.gap == 0) continue;
        const gap_start = @min(@as(usize, origin.text) + origin.len, text.len);
        const gap_end = @min(gap_start + origin.gap, text.len);
        if (gap_start < cursor) continue;
        hash.update(text[cursor..gap_start]);
        hash.update(&.{0});
        cursor = gap_end;
    }
    hash.update(text[@min(cursor, text.len)..]);
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
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

/// One direct import and the interface hash it had when the module was built.
pub const ImportHash = struct { module: []const u8, hash: [32]u8 };

/// Hash the module's source, resolved embedded inputs and direct semantic
/// imports. Emission and positions dependencies are keyed separately.
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
pub fn hashFact(hash: *std.crypto.hash.Blake3, fact: summary.Fact) void {
    var bits: [2]u8 = undefined;
    std.mem.writeInt(u16, &bits, fact.graph_mask, .little);
    hash.update(&bits);
    std.mem.writeInt(u16, &bits, fact.mutates, .little);
    hash.update(&bits);
    inline for (.{ fact.return_origin, fact.borrow_origin }) |origin| {
        std.mem.writeInt(u16, &bits, origin.positions, .little);
        hash.update(&bits);
        hash.update(&.{@as(u8, @intFromBool(origin.unknown))});
    }
    std.mem.writeInt(u16, &bits, fact.inferred.caller_storage, .little);
    hash.update(&bits);
    const flags = [_]bool{ fact.mutates_unknown, fact.inferred.writes, fact.inferred.external };
    for (flags) |flag| hash.update(&.{@as(u8, @intFromBool(flag))});
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
        try writer.print("  {s} {s}{s} effects=", .{ shown, @tagName(function.role), if (function.exported) " exported" else "" });
        try effect_set.write(writer, function.fact.graph_mask);
        try writer.print(" mutates={b} origin={b}{s}{s}{s}{s} fingerprint={x}\n", .{
            function.fact.mutates,
            function.fact.return_origin.positions,
            if (function.fact.mutates_unknown) " mutates-unknown" else "",
            if (function.fact.return_origin.unknown) " origin-unknown" else "",
            if (function.fact.inferred.writes) " writes" else "",
            if (function.fact.inferred.external) " external" else "",
            function.fingerprint[0..8],
        });
    }
    try writer.writeAll("types\n");
    for (interface.declarations.types) |ty| try writer.print("  {s} fingerprint={x}\n", .{ ty.name, ty.fingerprint[0..8] });
    try writer.writeAll("reexports\n");
    for (interface.declarations.reexports) |entry| try writer.print("  {s} fingerprint={x}\n", .{ entry.name, entry.fingerprint[0..8] });
    try writer.writeAll("shapes\n");
    for (interface.declarations.shapes) |shape| try writer.print("  {s} {x}\n", .{ shape.name, shape.digest[0..8] });
    const emission = interface.emission;
    try writer.print("emission {s}{s}{s}\n", .{ if (emission.config.len == 0) "none" else emission.config, if (emission.marks.arena) " arena" else "", if (emission.marks.text) " text" else "" });
    for (emission.functions) |function| {
        try writer.print("  {s}{s} writes=", .{ function.name, if (function.allocates) " allocates" else "" });
        for (function.writes) |flag| try writer.writeByte(if (flag) '1' else '0');
        try writer.writeByte('\n');
    }
    for (emission.values) |name| try writer.print("  value {s}\n", .{name});
    try writer.print("positions {d} verbatim stretches\ntext\n", .{interface.positions.origins.len});
    try writer.writeAll(interface.text);
    if (interface.text.len != 0 and interface.text[interface.text.len - 1] != '\n') try writer.writeByte('\n');
}

/// The file name one module's interface is stored under.
pub fn fileName(allocator: std.mem.Allocator, module: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ module, extension });
}
