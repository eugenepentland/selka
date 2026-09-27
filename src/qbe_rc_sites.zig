//! RC-SITES-1: per-site ownership attribution for `--rc-runtime=sites`.
//!
//! A sites build is a counting build: every glue operation calls its counted
//! glue instead of an inline fast path, so the runtime sees each physical
//! ownership event. Its lowered functions also say which call is about to
//! run. Before every direct call into the runtime or into generated glue the
//! unit bumps that call site's `calls` counter and stores the site's address
//! in `myl_rc_site_current`; each event the runtime records then lands in
//! that site's counters as well as in the program totals. The site's
//! identity (unit, pc, callee, static type) travels as one `# myl-rcsite`
//! marker line per site, which the build turns into the C site record and
//! the table the exit report walks (`qbe_build_outputs.zig`).
//!
//! The pass reads and rewrites text only. It runs on a function's text before
//! the position passes, while every instruction still opens with its
//! `storel PC, %position` store, and its markers are appended after them.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const passes = @import("qbe_il_passes.zig");
const runtime = @import("runtime_mode.zig");

/// Failures the pass reports: the emitter's own set.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// The marker word after `# ` on a site line: `# myl-rcsite SITE UNIT PC
/// OPERATION TYPE`, where PC is a decimal pc, `entry` or `exit`, OPERATION the
/// callee (or `rcg_OP` for a type's glue) and TYPE the static type's name in
/// lowercase hex, or `-`. The build driver's `qbe_build_sites.zig` reads the
/// same word.
pub const marker_word = "myl-rcsite ";

/// The runtime global that names the site of the call in flight.
pub const current_symbol = "myl_rc_site_current";

/// What the pass needs besides the text: the unit's function symbol, which
/// every site symbol extends, and the catalog that names a descriptor's type.
pub const Context = struct { unit: []const u8, layouts: *native.Catalog };

/// One function's instrumented text and the marker lines its sites need.
pub const Instrumented = struct { text: []u8, markers: []const u8 };

/// Where in the function a call sits: before the first instruction, at an
/// instruction's pc, or in the shared exit after `@failure`.
const Pc = union(enum) { entry, at: []const u8, exit };

/// Instrument `text` in a sites build; any other build keeps it and names no
/// sites.
pub fn instrumentSelected(a: std.mem.Allocator, text: []u8, context: Context) Error!Instrumented {
    if (!runtime.sites()) return .{ .text = text, .markers = "" };
    return instrument(a, text, context);
}

/// Instrument every direct runtime or glue call in `text`.
pub fn instrument(a: std.mem.Allocator, text: []const u8, context: Context) Error!Instrumented {
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    var markers: std.Io.Writer.Allocating = .init(a);
    errdefer markers.deinit();
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var names: Names = .{ .allocator = scratch.allocator(), .context = context };
    var pc: Pc = .entry;
    var held: ?[]const u8 = null;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (positionStore(line)) |digits| pc = .{ .at = digits } else if (functionLabel(line)) pc = .exit;
        // A `dbgloc` names the call right after it; keep the two adjacent.
        if (std.mem.startsWith(u8, line, " dbgloc ")) {
            if (held) |previous| try writeLine(&out.writer, &first, previous);
            held = line;
            continue;
        }
        if (callee(line)) |name| if (instrumented(name)) {
            const site = try std.fmt.allocPrint(a, "{s}_rcsite{d}", .{ context.unit, count });
            defer a.free(site);
            try writeLine(&out.writer, &first, "");
            out.writer.print(" %rcsite{d} =l loadl ${s}\n %rcsite{d}n =l add %rcsite{d}, 1\n storel %rcsite{d}n, ${s}\n storel ${s}, ${s}", .{ count, site, count, count, count, site, site, current_symbol }) catch return error.OutOfMemory;
            try marker(&markers.writer, &names, .{ .site = site, .unit = context.unit, .pc = pc, .name = name, .line = line });
            count += 1;
        };
        if (held) |previous| try writeLine(&out.writer, &first, previous);
        held = null;
        try writeLine(&out.writer, &first, line);
    }
    if (held) |previous| try writeLine(&out.writer, &first, previous);
    return .{ .text = try out.toOwnedSlice(), .markers = try markers.toOwnedSlice() };
}

/// Append a function's site markers after the rest of its text, once every
/// other pass that reads instruction bodies has run.
pub fn append(a: std.mem.Allocator, text: []const u8, markers: []const u8) Error![]u8 {
    if (markers.len == 0) return a.dupe(u8, text);
    const separator: []const u8 = if (text.len != 0 and text[text.len - 1] != '\n') "\n" else "";
    return std.mem.concat(a, u8, &.{ text, separator, markers });
}

fn writeLine(w: *std.Io.Writer, first: *bool, line: []const u8) Error!void {
    if (!first.*) w.writeByte('\n') catch return error.OutOfMemory;
    first.* = false;
    w.writeAll(line) catch return error.OutOfMemory;
}

const positionStore = passes.positionStore;
const functionLabel = passes.functionLabel;

/// The symbol a direct call instruction calls, or null for any other line.
fn callee(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimStart(u8, line, " ");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;
    const at = std.mem.indexOf(u8, trimmed, "call $") orelse return null;
    const rest = trimmed[at + "call $".len ..];
    const stop = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
    return rest[0..stop];
}

/// Whether a callee can record ownership events: the runtime's and the
/// generated glue's entries, except guest functions (they name their own
/// sites), traps and the prologue helpers a later pass may delete.
fn instrumented(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "myl_")) return false;
    if (std.mem.startsWith(u8, name, "myl_f_")) return false;
    if (std.mem.startsWith(u8, name, "myl_qbe_fail_")) return false;
    inline for (.{ "myl_qbe_heap", "myl_qbe_root_mark" }) |skipped| {
        if (std.mem.eql(u8, name, skipped)) return false;
    }
    return true;
}

/// One site's identity, as its marker line spells it.
const Site = struct { site: []const u8, unit: []const u8, pc: Pc, name: []const u8, line: []const u8 };

fn marker(w: *std.Io.Writer, names: *Names, site: Site) Error!void {
    const glue = glueCall(site.name);
    const descriptor = if (glue) |parts| parts.descriptor else descriptorIn(site.line);
    const ty = if (descriptor) |symbol| try names.typeOf(symbol) else null;
    w.print("# {s}{s} {s} ", .{ marker_word, site.site, site.unit }) catch return error.OutOfMemory;
    switch (site.pc) {
        .entry => w.writeAll("entry") catch return error.OutOfMemory,
        .exit => w.writeAll("exit") catch return error.OutOfMemory,
        .at => |digits| w.writeAll(digits) catch return error.OutOfMemory,
    }
    if (glue) |parts| {
        w.print(" rcg_{s} ", .{parts.operation}) catch return error.OutOfMemory;
    } else w.print(" {s} ", .{site.name}) catch return error.OutOfMemory;
    if (ty) |name| {
        for (name) |byte| w.print("{x:0>2}", .{byte}) catch return error.OutOfMemory;
        w.writeByte('\n') catch return error.OutOfMemory;
    } else w.writeAll("-\n") catch return error.OutOfMemory;
}

/// A descriptor symbol: `myl_t_` and a SHA-256 digest in lowercase hex.
const descriptor_length = "myl_t_".len + 64;

/// A generated glue entry's descriptor symbol and operation name.
fn glueCall(name: []const u8) ?struct { descriptor: []const u8, operation: []const u8 } {
    const infix = "_rcg_";
    if (!std.mem.startsWith(u8, name, "myl_t_") or name.len <= descriptor_length + infix.len) return null;
    if (!std.mem.eql(u8, name[descriptor_length..][0..infix.len], infix)) return null;
    return .{ .descriptor = name[0..descriptor_length], .operation = name[descriptor_length + infix.len ..] };
}

/// The first descriptor a runtime call passes, which names the static type
/// its operation works on.
fn descriptorIn(line: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, line, "$myl_t_") orelse return null;
    const rest = line[at + 1 ..];
    if (rest.len < descriptor_length) return null;
    return rest[0..descriptor_length];
}

/// Descriptor symbols to type names, filled once per function on first use.
const Names = struct {
    allocator: std.mem.Allocator,
    context: Context,
    map: std.StringHashMapUnmanaged([]const u8) = .empty,
    filled: bool = false,

    fn typeOf(self: *Names, symbol: []const u8) Error!?[]const u8 {
        if (!self.filled) try self.fill();
        return self.map.get(symbol);
    }

    fn fill(self: *Names) Error!void {
        self.filled = true;
        const records = self.context.layouts.records;
        const total = typed.Type.record_base + records.len;
        for (0..total) |index| {
            const ty: typed.Type = @fromBackingInt(index);
            const symbol = descriptors.symbol(self.allocator, self.context.layouts, ty) catch |err| return translate(err);
            try self.map.put(self.allocator, symbol, typed.typeName(ty, records));
        }
    }
};

fn translate(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
