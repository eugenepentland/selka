//! `selka dump-syntax`: the stage-1 syntax oracle of the self-hosting plan.
//!
//! One file's parse leaves the compiler in one framed document: the exact
//! `StoredSyntax` payload the syntax cache would store (`frontend_cache.encodeSyntax`)
//! and the diagnostics the lexer and parser raised, in order. A Selka lexer and
//! parser are checked against it byte for byte.
//!
//! The frame is written with `persist_codec`, so a Selka writer needs only the
//! same few rules: little-endian integers at their stored width, a `u64` count
//! before every slice, a presence byte before an optional, an enum as its tag
//! integer. Its fields in order:
//!
//!   magic       8 bytes, `SLKSYN01`
//!   mode        1 byte: 0 program (`Parser.parse`), 1 module (`Parser.parseModule`)
//!   trusted     1 byte: 1 when the source was parsed with the compiler's reserved
//!               internal spellings allowed (the embedded standard library), else 0
//!   outcome     1 byte: 0 parsed, 1 refused (the payload is empty)
//!   payload     u64 length, then the `StoredSyntax` bytes
//!   diagnostics u64 count, then one `Record` each
//!
//! The same module describes the payload's layout (`layout`), walks a payload
//! without building it (`check`) and names the field a byte belongs to
//! (`fieldAt`), so a corrupted or mismatching payload is reported as
//! `nodes[3].data.@tag` rather than as an offset.
const std = @import("std");
const ast = @import("ast.zig");
const codec = @import("persist_codec.zig");
const diagnostic = @import("diagnostic.zig");
const frontend_cache = @import("frontend_cache.zig");
const lexer = @import("lexer.zig");
const module_syntax = @import("module_syntax.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");

/// The eight bytes every frame opens with; the digits are the frame version.
pub const magic = "SLKSYN01";

/// Which parser entry point produced the payload.
pub const Mode = enum(u8) { program, module };

/// Whether the file parsed. A refused file has an empty payload and at least one error.
pub const Outcome = enum(u8) { parsed, refused };

/// The evidence slots of a diagnostic, grouped to keep `Record` within the field limit.
pub const Notes = struct {
    related: ?diagnostic.Related = null,
    origin: ?diagnostic.Related = null,
    requirement: ?diagnostic.Related = null,
};

/// One diagnostic as the frame stores it. A parser diagnostic carries no
/// obligation and no guest trace; `recordOf` refuses one that does, so a field
/// added to the diagnostic cannot be dropped silently.
pub const Record = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    span: source.Span,
    message: []const u8,
    notes: Notes,
    fix: []const diagnostic.Edit,
    rule: ?[]const u8,
};

/// The whole frame, in stored field order.
pub const Frame = struct {
    magic: [magic.len]u8,
    mode: Mode,
    trusted: bool,
    outcome: Outcome,
    payload: []const u8,
    diagnostics: []const Record,
};

/// Failures `frame` can return: allocation, or a diagnostic it cannot store.
pub const Error = std.mem.Allocator.Error || error{InternalError};

/// The mode a file is parsed in when none is forced: module syntax when it
/// opens with `module`, `import` or `export`, the way `selka fmt` chooses.
pub fn modeOf(bytes: []const u8) Mode {
    return if (module_syntax.usesModuleSyntax(bytes)) .module else .program;
}

/// How a file is parsed when it is dumped.
pub const Options = struct {
    /// The parser entry point; null chooses by `modeOf`.
    mode: ?Mode = null,
    /// Allow the compiler's reserved internal spellings, as for the embedded standard library.
    trusted: bool = false,
    /// Check the stored-syntax v2 encoding of the parse instead of printing the parse (`--store-check`).
    store_check: bool = false,
};

/// Lex and parse `bytes` and return the framed result, owned by `allocator`.
pub fn frame(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8, options: Options) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const mode = options.mode orelse modeOf(bytes);
    var src = try source.Source.init(scratch, path, bytes);
    src.trusted_intrinsics = options.trusted;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const syntax = try parse(scratch, src, mode, &sink);
    const payload: []const u8 = if (syntax) |program| try frontend_cache.encodeSyntax(scratch, program) else &.{};
    const records = try scratch.alloc(Record, sink.items.items.len);
    for (sink.items.items, records) |item, *record| record.* = try recordOf(scratch, item);
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write(Frame, .{
        .magic = magic[0..magic.len].*,
        .mode = mode,
        .trusted = options.trusted,
        .outcome = if (syntax == null) .refused else .parsed,
        .payload = payload,
        .diagnostics = records,
    });
    return writer.bytes.toOwnedSlice(allocator);
}

/// The verdict of `storeCheck`: the line to print and whether the module reassembled to its parse (a module that does not parse is fine).
pub const StoreVerdict = struct { line: []u8, ok: bool };

/// `selka dump-syntax --store-check`: parse `bytes`, encode the module as a stored-syntax v2 entry (`syntax_store.zig`), reassemble the entry
/// and hold it against the parse. The line says how many bodies are lazy and how many functions keep their tree with the declarations.
pub fn storeCheck(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8, options: Options) Error!StoreVerdict {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var src = try source.Source.init(scratch, path, bytes);
    src.trusted_intrinsics = options.trusted;
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const syntax = (try parse(scratch, src, options.mode orelse modeOf(bytes), &sink)) orelse return .{ .line = try allocator.dupe(u8, "store-check refused\n"), .ok = true };
    const found = @import("syntax_store_check.zig").check(scratch, src, syntax) catch |err| return .{ .line = try std.fmt.allocPrint(allocator, "store-check FAILED {s}\n", .{@errorName(err)}), .ok = false };
    return .{ .line = try std.fmt.allocPrint(allocator, "store-check ok nodes={d} statements={d} lazy={d} eager={d} bytes={d}\n", .{ syntax.nodes.items.len, syntax.statements.items.len, found.lazy, found.eager, found.bytes }), .ok = true };
}

fn parse(scratch: std.mem.Allocator, src: source.Source, mode: Mode, sink: *diagnostic.Sink) Error!?ast.Program {
    const tokens = lexer.lex(scratch, src.bytes, sink) catch |err| switch (err) {
        error.SourceError => return null,
        else => |other| return other,
    };
    var reading: parser.Parser = .{ .src = src, .storage = scratch, .tokens = tokens, .sink = sink };
    const result = if (mode == .module) reading.parseModule() else reading.parse();
    return result catch |err| switch (err) {
        error.SourceError => null,
        else => |other| other,
    };
}

fn recordOf(scratch: std.mem.Allocator, item: diagnostic.Diagnostic) Error!Record {
    if (item.provenance.obligation != null or item.stack.len != 0 or item.stack.omitted != 0) return error.InternalError;
    var edits: []const diagnostic.Edit = &.{};
    if (item.provenance.fix) |fix| {
        const all = try scratch.alloc(diagnostic.Edit, fix.count());
        for (all, 0..) |*edit, index| edit.* = fix.at(index);
        edits = all;
    }
    return .{
        .code = item.code,
        .severity = item.severity,
        .span = item.span,
        .message = item.message,
        .notes = .{ .related = item.related, .origin = item.provenance.origin, .requirement = item.provenance.requirement },
        .fix = edits,
        .rule = if (item.provenance.rule) |rule| @tagName(rule) else null,
    };
}

/// A frame read back: the strings and tables belong to the arena passed to `open`.
pub const Opened = Frame;

/// Decode a frame into `arena`-owned values. A wrong magic, a short frame or
/// trailing bytes are `InvalidEncoding`.
pub fn open(arena: std.mem.Allocator, bytes: []const u8) codec.DecodeError!Opened {
    var reader = codec.Reader.init(arena, bytes);
    const opened = try reader.read(Frame);
    if (!reader.done() or !std.mem.eql(u8, &opened.magic, magic)) return error.InvalidEncoding;
    return opened;
}

// ---------------------------------------------------------------------------
// Naming the first difference between two frames.
// ---------------------------------------------------------------------------

fn firstDifferingByte(left: []const u8, right: []const u8) usize {
    const common = @min(left.len, right.len);
    var index: usize = 0;
    while (index < common and left[index] == right[index]) index += 1;
    return index;
}

fn noteEql(left: ?diagnostic.Related, right: ?diagnostic.Related) bool {
    const a = left orelse return right == null;
    const b = right orelse return false;
    return a.span.start == b.span.start and a.span.end == b.span.end and a.role == b.role and std.mem.eql(u8, a.message, b.message);
}

fn recordField(left: Record, right: Record) ?[]const u8 {
    if (!std.mem.eql(u8, left.code, right.code)) return "code";
    if (left.severity != right.severity) return "severity";
    if (left.span.start != right.span.start or left.span.end != right.span.end) return "span";
    if (!std.mem.eql(u8, left.message, right.message)) return "message";
    if (!noteEql(left.notes.related, right.notes.related)) return "notes";
    if (!noteEql(left.notes.origin, right.notes.origin)) return "notes";
    if (!noteEql(left.notes.requirement, right.notes.requirement)) return "notes";
    if (left.fix.len != right.fix.len) return "fix";
    for (left.fix, right.fix) |a, b| {
        if (a.span.start != b.span.start or a.span.end != b.span.end or !std.mem.eql(u8, a.text, b.text)) return "fix";
    }
    const same_rule = if (left.rule) |a| (if (right.rule) |b| std.mem.eql(u8, a, b) else false) else right.rule == null;
    return if (same_rule) null else "rule";
}

fn describePayload(w: *std.Io.Writer, arena: std.mem.Allocator, reference: []const u8, candidate: []const u8) !void {
    const at = firstDifferingByte(reference, candidate);
    const named = (try fieldAt(arena, reference, at)) orelse (try fieldAt(arena, candidate, at));
    const field: []const u8 = if (named) |stop| stop.path else "past both payloads";
    try w.print("payload differs at byte {d} in {s} (reference {d} bytes, candidate {d})", .{ at, field, reference.len, candidate.len });
    if (try check(arena, candidate)) |bad| try w.print("; candidate payload is invalid at {s}", .{bad.path});
}

/// A one-line account of how two frames differ, or null when they are the same
/// bytes. Mode, trust and outcome come first, then the payload (the field path of
/// the first differing byte), then the diagnostics (the first differing record and
/// field). A frame that does not open is reported by its first differing byte.
pub fn difference(allocator: std.mem.Allocator, reference: []const u8, candidate: []const u8) std.mem.Allocator.Error!?[]u8 {
    if (std.mem.eql(u8, reference, candidate)) return null;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    describe(&out.writer, scratch, reference, candidate) catch return error.OutOfMemory;
    const told = try out.toOwnedSlice();
    return told;
}

fn describe(w: *std.Io.Writer, arena: std.mem.Allocator, reference: []const u8, candidate: []const u8) !void {
    const want = open(arena, reference) catch return w.print("reference frame does not open; first differing byte {d}", .{firstDifferingByte(reference, candidate)});
    const got = open(arena, candidate) catch |err| return w.print("candidate frame does not open ({s}); first differing byte {d}", .{ @errorName(err), firstDifferingByte(reference, candidate) });
    if (want.mode != got.mode) return w.print("mode: reference {s}, candidate {s}", .{ @tagName(want.mode), @tagName(got.mode) });
    if (want.trusted != got.trusted) return w.print("trusted: reference {}, candidate {}", .{ want.trusted, got.trusted });
    if (want.outcome != got.outcome) return w.print("outcome: reference {s}, candidate {s}", .{ @tagName(want.outcome), @tagName(got.outcome) });
    if (!std.mem.eql(u8, want.payload, got.payload)) return describePayload(w, arena, want.payload, got.payload);
    const shared = @min(want.diagnostics.len, got.diagnostics.len);
    for (want.diagnostics[0..shared], got.diagnostics[0..shared], 0..) |a, b, index| {
        const field = recordField(a, b) orelse continue;
        return w.print("diagnostic {d} differs in {s}: reference `{s}` at {d}..{d}, candidate `{s}` at {d}..{d}", .{ index, field, a.message, a.span.start, a.span.end, b.message, b.span.start, b.span.end });
    }
    return w.print("diagnostics: reference {d}, candidate {d}", .{ want.diagnostics.len, got.diagnostics.len });
}

// ---------------------------------------------------------------------------
// The layout of the payload.
// ---------------------------------------------------------------------------

/// Every distinct aggregate reachable from the payload type. A declared type
/// keeps its declared name (`source.Span`); an anonymous one (the union inside
/// `ast.Node`) is named by the path from its nearest declared ancestor
/// (`ast.Node.data`), because the compiler's own spelling of an anonymous type
/// carries a number that changes with unrelated edits.
const Entry = struct { ty: type, name: []const u8 };

fn anonymous(comptime name: []const u8) bool {
    return std.mem.indexOf(u8, name, "__struct_") != null or
        std.mem.indexOf(u8, name, "__union_") != null or
        std.mem.indexOf(u8, name, "__enum_") != null;
}

fn collect(comptime list: *[]const Entry, comptime T: type, comptime path: []const u8) void {
    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum" => collectNamed(list, T, if (anonymous(@typeName(T))) path else @typeName(T)),
        .optional => |info| collect(list, info.child, path),
        .pointer => |info| collect(list, info.child, path),
        .array => |info| collect(list, info.child, path),
        else => {},
    }
}

fn collectNamed(comptime list: *[]const Entry, comptime T: type, comptime name: []const u8) void {
    if (comptime known(list.*, T)) return;
    list.* = list.* ++ [_]Entry{.{ .ty = T, .name = name }};
    switch (@typeInfo(T)) {
        .@"struct" => |info| inline for (info.field_names, info.field_types) |field, Field| collect(list, Field, name ++ "." ++ field),
        .@"union" => |info| inline for (info.field_names, info.field_types) |field, Field| collect(list, Field, name ++ "." ++ field),
        else => {},
    }
}

fn known(comptime list: []const Entry, comptime T: type) bool {
    inline for (list) |entry| if (entry.ty == T) return true;
    return false;
}

fn entriesOf(comptime Root: type, comptime root_name: []const u8) []const Entry {
    comptime {
        @setEvalBranchQuota(4_000_000);
        var list: []const Entry = &.{};
        collectNamed(&list, Root, root_name);
        return list;
    }
}

fn nameOf(comptime entries: []const Entry, comptime T: type) []const u8 {
    inline for (entries) |entry| if (entry.ty == T) return entry.name;
    @compileError("type missing from the layout: " ++ @typeName(T));
}

fn writeRef(w: *std.Io.Writer, comptime entries: []const Entry, comptime T: type) std.Io.Writer.Error!void {
    switch (@typeInfo(T)) {
        .int, .float, .bool, .void => try w.writeAll(@typeName(T)),
        .optional => |info| {
            try w.writeAll("?");
            try writeRef(w, entries, info.child);
        },
        .pointer => |info| {
            try w.writeAll("[]");
            try writeRef(w, entries, info.child);
        },
        .array => |info| {
            try w.print("[{d}]", .{info.len});
            try writeRef(w, entries, info.child);
        },
        .@"struct", .@"union", .@"enum" => try w.writeAll(nameOf(entries, T)),
        else => @compileError("persisted field needs a layout rule: " ++ @typeName(T)),
    }
}

fn writeEnumValues(w: *std.Io.Writer, comptime E: type) std.Io.Writer.Error!void {
    const info = @typeInfo(E).@"enum";
    inline for (info.field_names, info.field_values) |field, value| try w.print("  {d} {s}\n", .{ value, field });
}

fn writeEntry(w: *std.Io.Writer, comptime entries: []const Entry, comptime entry: Entry) std.Io.Writer.Error!void {
    const T = entry.ty;
    try w.writeAll("\n");
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            try w.print("{s}: struct\n", .{entry.name});
            inline for (info.field_names, info.field_types) |field, Field| {
                try w.print("  {s}: ", .{field});
                try writeRef(w, entries, Field);
                try w.writeAll("\n");
            }
        },
        .@"union" => |info| {
            const Tag = std.meta.Tag(T);
            try w.print("{s}: union, tag {s} in {d} byte(s)\n", .{ entry.name, @typeName(@typeInfo(Tag).@"enum".tag_type), @sizeOf(Tag) });
            const values = @typeInfo(Tag).@"enum".field_values;
            inline for (info.field_names, info.field_types, values) |field, Field, value| {
                try w.print("  {d} {s}: ", .{ value, field });
                try writeRef(w, entries, Field);
                try w.writeAll("\n");
            }
        },
        .@"enum" => |info| {
            const open_set = if (info.mode == .nonexhaustive) ", non-exhaustive" else "";
            try w.print("{s}: enum, tag {s} in {d} byte(s){s}\n", .{ entry.name, @typeName(info.tag_type), @sizeOf(info.tag_type), open_set });
            try writeEnumValues(w, T);
        },
        else => unreachable,
    }
}

/// The fixed prose every layout description opens with: the encoding rules a
/// Selka writer follows and the command that regenerates the description.
pub const layout_header =
    \\syntax-layout-v1
    \\
    \\The payload is `StoredSyntax` written by `persist_codec`:
    \\  integer     little-endian at its stored width (usize is 8 bytes)
    \\  bool        one byte, 0 or 1
    \\  enum        its tag integer, at the tag's storage width in bytes
    \\  optional    one byte, 0 or 1, then the value when 1
    \\  slice       u64 count, then the items; []u8 is the bytes alone
    \\  array       its items in order
    \\  struct      its fields in the order listed
    \\  union       its tag, then the active variant's payload
    \\A type keeps its declared name; an anonymous one is named by its path from
    \\the nearest declared type. Regenerate with
    \\`selka dump-syntax --layout > src/syntax_layout.txt` after an `ast.zig` change.
    \\
;

/// Write the layout of `Root`, named `root_name`, to `w`.
pub fn writeLayout(w: *std.Io.Writer, comptime Root: type, comptime root_name: []const u8) std.Io.Writer.Error!void {
    const entries = comptime entriesOf(Root, root_name);
    try w.writeAll(layout_header);
    inline for (entries) |entry| try writeEntry(w, entries, entry);
}

/// The layout of the syntax-cache payload, owned by `allocator`. A test compares
/// it with `src/syntax_layout.txt`, so an `ast.zig` change that moves a byte of
/// the payload fails until the description is regenerated.
pub fn layout(allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    return layoutOf(allocator, frontend_cache.StoredSyntax, "StoredSyntax");
}

/// The layout of any persistable type, owned by `allocator`; `layout` for the
/// payload and the tests' own small types.
pub fn layoutOf(allocator: std.mem.Allocator, comptime Root: type, comptime root_name: []const u8) std.mem.Allocator.Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    writeLayout(&output.writer, Root, root_name) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

// ---------------------------------------------------------------------------
// Walking a payload: validation and field paths.
// ---------------------------------------------------------------------------

const max_depth = 32;

/// One step of a field path.
const Segment = union(enum) { name: []const u8, index: usize };

/// What stopped a walk.
pub const Kind = enum {
    /// The walk reached the byte it was asked to locate.
    located,
    /// The payload ends inside a field.
    truncated,
    /// A bool, optional, enum or union byte holds no valid case, or a count exceeds the payload.
    invalid,
    /// Valid fields end before the payload does.
    trailing,
    /// The type nests deeper than the walker's path buffer (a walker bug, not corruption).
    too_deep,
};

/// Where and why a walk stopped; `path` is owned by the allocator given to the walk.
pub const Stop = struct { path: []u8, offset: usize, kind: Kind };

const Halt = error{Halted};

const Walker = struct {
    bytes: []const u8,
    at: usize = 0,
    depth: usize = 0,
    target: ?usize = null,
    segments: [max_depth]Segment = undefined,
    halted: ?struct { segments: [max_depth]Segment, depth: usize, tail: []const u8, offset: usize, kind: Kind } = null,

    fn note(self: *Walker, kind: Kind, tail: []const u8, offset: usize) void {
        self.halted = .{ .segments = self.segments, .depth = self.depth, .tail = tail, .offset = offset, .kind = kind };
    }

    fn record(self: *Walker, kind: Kind, tail: []const u8, offset: usize) Halt {
        self.note(kind, tail, offset);
        return error.Halted;
    }

    fn push(self: *Walker, segment: Segment) Halt!void {
        if (self.depth == max_depth) return self.record(.too_deep, "", self.at);
        self.segments[self.depth] = segment;
        self.depth += 1;
    }

    fn pop(self: *Walker) void {
        self.depth -= 1;
    }

    /// Consume `count` bytes of the field whose last path step is `tail`, stopping
    /// when they run past the payload or contain the byte being located.
    fn take(self: *Walker, count: usize, tail: []const u8) Halt![]const u8 {
        if (count > self.bytes.len - self.at) return self.record(.truncated, tail, self.at);
        if (self.target) |offset| {
            if (offset >= self.at and offset - self.at < count) return self.record(.located, tail, offset);
        }
        const out = self.bytes[self.at..][0..count];
        self.at += count;
        return out;
    }

    fn unsigned(self: *Walker, size: usize, tail: []const u8) Halt!u64 {
        const raw = try self.take(size, tail);
        var value: u64 = 0;
        for (raw, 0..) |byte, index| value |= @as(u64, byte) << @intCast(8 * index);
        return value;
    }

    fn invalid(self: *Walker, tail: []const u8, size: usize) Halt {
        return self.record(.invalid, tail, self.at - size);
    }

    fn enumeration(self: *Walker, comptime E: type, tail: []const u8) Halt!void {
        const Tag = @typeInfo(E).@"enum".tag_type;
        comptime std.debug.assert(@sizeOf(Tag) <= 8);
        const raw = try self.unsigned(@sizeOf(Tag), tail);
        const narrowed = std.math.cast(Tag, raw) orelse return self.invalid(tail, @sizeOf(Tag));
        if (std.enums.fromInt(E, narrowed) == null) return self.invalid(tail, @sizeOf(Tag));
    }

    fn walk(self: *Walker, comptime T: type) Halt!void {
        switch (@typeInfo(T)) {
            .int => if (@bitSizeOf(T) != 0) {
                _ = try self.take(@sizeOf(T), "");
            },
            .float => _ = try self.take(@sizeOf(T), ""),
            .bool => if ((try self.take(1, ""))[0] > 1) return self.invalid("", 1),
            .void => {},
            .@"enum" => try self.enumeration(T, ""),
            .optional => |info| {
                const present = (try self.take(1, "@present"))[0];
                if (present > 1) return self.invalid("@present", 1);
                if (present == 1) try self.walk(info.child);
            },
            .pointer => |info| try self.slice(info.child),
            .array => |info| {
                inline for (0..info.len) |index| {
                    try self.push(.{ .index = index });
                    try self.walk(info.child);
                    self.pop();
                }
            },
            .@"struct" => |info| inline for (info.field_names, info.field_types) |name, Field| {
                try self.push(.{ .name = name });
                try self.walk(Field);
                self.pop();
            },
            .@"union" => |info| {
                const Tag = std.meta.Tag(T);
                const raw = try self.unsigned(@sizeOf(Tag), "@tag");
                const narrowed = std.math.cast(@typeInfo(Tag).@"enum".tag_type, raw) orelse return self.invalid("@tag", @sizeOf(Tag));
                const tag = std.enums.fromInt(Tag, narrowed) orelse return self.invalid("@tag", @sizeOf(Tag));
                inline for (info.field_names, info.field_types) |name, Field| {
                    if (tag == @field(Tag, name)) {
                        try self.push(.{ .name = name });
                        try self.walk(Field);
                        self.pop();
                    }
                }
            },
            else => @compileError("persisted field needs a walking rule: " ++ @typeName(T)),
        }
    }

    fn slice(self: *Walker, comptime Child: type) Halt!void {
        const count = try self.unsigned(8, "@len");
        if (count > self.bytes.len) return self.invalid("@len", 8);
        if (Child == u8) {
            _ = try self.take(@intCast(count), "@bytes");
            return;
        }
        var index: usize = 0;
        while (index < count) : (index += 1) {
            try self.push(.{ .index = index });
            try self.walk(Child);
            self.pop();
        }
    }
};

fn render(allocator: std.mem.Allocator, walker: *const Walker) std.mem.Allocator.Error!Stop {
    const halted = walker.halted.?;
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    for (halted.segments[0..halted.depth], 0..) |segment, position| {
        switch (segment) {
            .name => |name| out.writer.print("{s}{s}", .{ if (position == 0) "" else ".", name }) catch return error.OutOfMemory,
            .index => |index| out.writer.print("[{d}]", .{index}) catch return error.OutOfMemory,
        }
    }
    if (halted.tail.len != 0) out.writer.print("{s}{s}", .{ if (halted.depth == 0) "" else ".", halted.tail }) catch return error.OutOfMemory;
    return .{ .path = try out.toOwnedSlice(), .offset = halted.offset, .kind = halted.kind };
}

fn walkPayload(allocator: std.mem.Allocator, comptime Root: type, payload: []const u8, target: ?usize) std.mem.Allocator.Error!?Stop {
    var walker: Walker = .{ .bytes = payload, .target = target };
    walker.walk(Root) catch {
        const stopped = try render(allocator, &walker);
        return stopped;
    };
    if (walker.at == payload.len) return null;
    walker.note(.trailing, "@trailing", walker.at);
    const trailing = try render(allocator, &walker);
    return trailing;
}

/// Walk `payload` as `Root` without building it. Null when it is exactly one
/// valid value; otherwise where it stops being one, with the field path. The
/// verdict agrees with `persist_codec.Reader.read` followed by `done`.
pub fn checkAs(allocator: std.mem.Allocator, comptime Root: type, payload: []const u8) std.mem.Allocator.Error!?Stop {
    const stop = try walkPayload(allocator, Root, payload, null);
    return stop;
}

/// The field path of the byte at `offset` of a valid `Root` payload, or why the
/// payload stops being valid first. Null when `offset` is past the end.
pub fn fieldAtAs(allocator: std.mem.Allocator, comptime Root: type, payload: []const u8, offset: usize) std.mem.Allocator.Error!?Stop {
    const stop = try walkPayload(allocator, Root, payload, offset);
    return stop;
}

/// `checkAs` for the syntax-cache payload.
pub fn check(allocator: std.mem.Allocator, payload: []const u8) std.mem.Allocator.Error!?Stop {
    return checkAs(allocator, frontend_cache.StoredSyntax, payload);
}

/// `fieldAtAs` for the syntax-cache payload.
pub fn fieldAt(allocator: std.mem.Allocator, payload: []const u8, offset: usize) std.mem.Allocator.Error!?Stop {
    return fieldAtAs(allocator, frontend_cache.StoredSyntax, payload, offset);
}

test "the walker halts with Halted where a payload runs out" {
    var walker: Walker = .{ .bytes = &.{ 1, 2, 3 } };
    try std.testing.expectError(error.Halted, walker.walk(u64));
    try std.testing.expectEqual(Kind.truncated, walker.halted.?.kind);
    var complete: Walker = .{ .bytes = &.{ 1, 0, 0, 0 } };
    try complete.walk(u32);
    try std.testing.expectEqual(@as(usize, 4), complete.at);
}
