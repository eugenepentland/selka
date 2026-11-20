//! Counting builds (`selka build --counters`, NEW-CORE-COUNTERS-1..7): what the
//! emitter adds to a unit so the program records, at run time, the checks,
//! copies and element traffic its emitted code executes, each at
//! its own site. Nothing here runs unless `emit_llvm.Options.counters` is set; a
//! build without it emits exactly the text it emitted before counting existed.
//!
//! - A *site* is one emission point: a global record in section `myl_count_sites`
//!   naming the emitting function's record, the source function it came from
//!   (inlining keeps the callee's name), the span's path, line and column, a kind
//!   and a detail (the Core operation that emitted it), then four counters.
//! - A *function record* (section `myl_count_fns`) holds the emitted function's
//!   name and the runtime's per-function counters; the function's prologue makes it
//!   `myl_count_current`, so every allocation, free, growth and runtime copy is
//!   charged to the emitted function that was running (`runtime/core_count.c`).
//! - A copy the runtime performs for a Core copy instruction (`list_copy`,
//!   `dict_copy`, `buffer_copy`, `str_from_view`) also credits the site the emitter
//!   names in `myl_count_copy_site` just before the call.
//! - Every conditional trap the emitter writes (`trapBegin`) counts its executions
//!   at a check site (NEW-CORE-COUNTERS-6), by what it checks: bounds, overflow,
//!   division, shift or other.
const std = @import("std");

/// What one site counts. `runtime/core_count.c` lists the same names in the same
/// order (`myl_count_kinds`), and the JSON report uses them.
pub const Kind = enum(u8) {
    /// A `list_copy`: `c0` copies, `c1` element bytes (credited by the runtime).
    list_copy,
    /// A `dict_copy`: `c0` copies, `c1` entry and hash bytes (credited by the runtime).
    dict_copy,
    /// A `buffer_copy`: `c0` copies, `c1` bytes (credited by the runtime).
    buffer_copy,
    /// A `str_from_view` (an owned text copy or a materialized view): `c0`, `c1` bytes.
    text_copy,
    /// A record, union or array over four words copied with `llvm.memcpy`/`memmove`:
    /// `c0` copies, `c1` bytes. The detail names the operation that copies it.
    record_copy,
    /// A push into a list: `c0` pushes, `c1` element bytes written, `c2` bytes the
    /// growths it caused moved (credited by the runtime).
    list_push,
    /// A whole aggregate element (four words or less) read out of a list: `c0`, `c1` bytes.
    element_load,
    /// A whole aggregate element (four words or less) written into a list: `c0`, `c1` bytes.
    element_store,
    /// A list, text or byte index check, a pop's empty-list or index check, or a substring's
    /// bounds check: `c0` executions.
    bounds_check,
    /// An integer overflow check (arithmetic, negation, `MIN // -1`): `c0` executions.
    overflow_check,
    /// A division or remainder's zero-divisor check: `c0` executions.
    division_check,
    /// A shift's amount check: `c0` executions.
    shift_check,
    /// Any other conditional trap (casts, float conversions, missing keys, fact
    /// verification, assertions, …): `c0` executions.
    other_check,
    /// An executed basic block of an emitted function (one site at each emitted block
    /// entry): `c0` entries, which also charges the function's `blocks` total.
    blocks,
    /// Elements the runtime shifted for a native list `insert`/`remove`/`pop_at`:
    /// `c0` elements moved, `c1` element bytes moved (credited by the runtime).
    element_moves,
    /// One element comparison of the runtime's stable sort, plain or keyed: `c0`
    /// comparisons (credited by the runtime).
    sort_compares,
    /// The elements one sort operation processes, at the sort's site: the list's
    /// length when the sort starts, however it sorts them (the comparison sort, the
    /// integer radix distribution or the keyed decorated sort): `c0` elements.
    elements_sorted,
};

/// Byte offset of counter `c0` (executions) in a site record.
pub const site_count = 48;
/// Byte offset of counter `c1` (bytes) in a site record.
pub const site_bytes = 56;
/// The LLVM type of a site record: function record, origin, path, detail, line, column,
/// kind, padding, then the counters `c0`..`c3` (80 bytes, 8-byte aligned).
pub const site_type = "{ ptr, ptr, ptr, ptr, i32, i32, i32, i32, [4 x i64] }";
/// Runtime counters per function record (`MYL_COUNT_SLOTS` in `runtime/core_count.h`).
pub const function_slots = 40;
/// Byte offset of the calls counter (slot 0) in a function record.
pub const function_calls = 8;
/// Byte offset of the blocks counter (slot 32) in a function record; each emitted
/// block entry adds one there, through the function record its prologue left current.
pub const function_blocks = 8 + 32 * 8;
/// Byte offset of the elements_sorted counter (slot 37) in a function record; a sort
/// operation adds the elements it processes there, through the current function record.
pub const function_elements_sorted = 8 + 37 * 8;

/// One counter site as emitted.
pub const Site = struct {
    /// Index of the emitting function's record in `Table.functions`.
    function: u32,
    /// The source function the operation came from (an inlined callee keeps its name).
    origin: []const u8,
    path: []const u8,
    line: u32,
    column: u32,
    kind: Kind,
    /// The Core operation that emitted the site.
    detail: []const u8,
};

/// The sites and function records of one LLVM unit.
pub const Table = struct {
    sites: std.ArrayList(Site) = .empty,
    /// Emitted function names, one record each.
    functions: std.ArrayList([]const u8) = .empty,

    /// Register the record of emitted function `name`; returns its index.
    pub fn function(self: *Table, a: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!u32 {
        try self.functions.append(a, name);
        return @intCast(self.functions.items.len - 1);
    }

    /// Register `site`; returns its index (`@myl.cs.N`).
    pub fn add(self: *Table, a: std.mem.Allocator, site: Site) std.mem.Allocator.Error!u32 {
        try self.sites.append(a, site);
        return @intCast(self.sites.items.len - 1);
    }

    /// The globals: interned strings, every site and function record in its section,
    /// and `@llvm.used`, so no optimization removes a record the runtime reads.
    pub fn render(self: *const Table, a: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
        if (self.functions.items.len == 0) return;
        var strings: std.array_hash_map.String(void) = .empty;
        for (self.functions.items) |name| try strings.put(a, name, {});
        for (self.sites.items) |site| {
            try strings.put(a, site.origin, {});
            try strings.put(a, site.path, {});
            try strings.put(a, site.detail, {});
        }
        for (strings.keys(), 0..) |text, i| {
            try out.print(a, "@myl.cstr.{d} = private unnamed_addr constant [{d} x i8] c\"", .{ i, text.len + 1 });
            for (text) |byte| {
                if (byte < 0x20 or byte >= 0x7f or byte == '"' or byte == '\\') try out.print(a, "\\{X:0>2}", .{byte}) else try out.append(a, byte);
            }
            try out.appendSlice(a, "\\00\"\n");
        }
        const function_record = "@myl.cf.{d} = internal global {{ ptr, [{d} x i64] }} " ++
            "{{ ptr @myl.cstr.{d}, [{d} x i64] zeroinitializer }}, section \"myl_count_fns\", align 8\n";
        for (self.functions.items, 0..) |name, i| {
            try out.print(a, function_record, .{ i, function_slots, strings.getIndex(name).?, function_slots });
        }
        const site_record = "@myl.cs.{d} = internal global {s} {{ ptr @myl.cf.{d}, ptr @myl.cstr.{d}, ptr @myl.cstr.{d}, ptr @myl.cstr.{d}, " ++
            "i32 {d}, i32 {d}, i32 {d}, i32 0, [4 x i64] zeroinitializer }}, section \"myl_count_sites\", align 8\n";
        for (self.sites.items, 0..) |site, i| {
            const strings_of = .{ strings.getIndex(site.origin).?, strings.getIndex(site.path).?, strings.getIndex(site.detail).? };
            try out.print(a, site_record, .{ i, site_type, site.function, strings_of[0], strings_of[1], strings_of[2], site.line, site.column, @backingInt(site.kind) });
        }
        try out.print(a, "@llvm.used = appending global [{d} x ptr] [", .{self.functions.items.len + self.sites.items.len});
        for (0..self.functions.items.len) |i| try out.print(a, "{s}ptr @myl.cf.{d}", .{ if (i == 0) "" else ", ", i });
        for (0..self.sites.items.len) |i| try out.print(a, ", ptr @myl.cs.{d}", .{i});
        try out.appendSlice(a, "], section \"llvm.metadata\"\n");
    }
};

/// The runtime globals a counting unit names.
pub const declarations =
    \\declare ptr @myl_count_function_local(ptr) nounwind
    \\declare ptr @myl_count_site_local(ptr) nounwind
    \\@myl_count_current = external thread_local(localexec) global ptr
    \\@myl_count_copy_site = external thread_local(localexec) global ptr
    \\@myl_count_push_site = external thread_local(localexec) global ptr
    \\@myl_count_move_site = external thread_local(localexec) global ptr
    \\@myl_count_sort_site = external thread_local(localexec) global ptr
    \\
;

/// The runtime calls whose internal work credits a counter site the emitted code names
/// just before the call, and clears after it (`runtime/core_count.c`).
pub const Hook = enum {
    /// No site-carrying runtime call.
    none,
    /// The list rotation behind a native `insert`/`remove`/`pop_at`: the elements it shifts.
    element_moves,
    /// A stable sort entry point, plain or keyed: the element comparisons it performs.
    sort_compares,

    /// The thread-local global holding the site this call credits.
    pub fn global(self: Hook) []const u8 {
        return switch (self) {
            .none => "",
            .element_moves => "@myl_count_move_site",
            .sort_compares => "@myl_count_sort_site",
        };
    }

    /// The counter site kind this hook's operation counts, or null for `.none`.
    pub fn siteKind(self: Hook) ?Kind {
        return switch (self) {
            .none => null,
            .element_moves => .element_moves,
            .sort_compares => .sort_compares,
        };
    }
};

/// The hook a runtime call of C `symbol` carries, or `.none`.
pub fn runtimeHook(symbol: []const u8) Hook {
    if (std.mem.eql(u8, symbol, "myl_core_owned_list_rotate")) return .element_moves;
    if (std.mem.eql(u8, symbol, "myl_core_owned_sort_keyed") or std.mem.eql(u8, symbol, "myl_core_owned_sort_keyed_record")) return .sort_compares;
    return .none;
}

/// The site detail naming the operation a hook measures.
pub fn hookDetail(of: Hook, symbol: []const u8) []const u8 {
    return switch (of) {
        .none => "",
        .element_moves => "list_rotate",
        .sort_compares => if (std.mem.endsWith(u8, symbol, "_record")) "sort_keyed_record" else "sort_keyed",
    };
}

/// The site detail of the plain `list_sort` operation (emitted, not a runtime call).
pub const sort_detail = "list_sort";

/// `counter += amount` on the `i64` at `offset` in `record` (`@myl.cs.N` or `@myl.cf.N`),
/// through the two fresh temporaries `loaded` and `sum`.
pub const Increment = struct { record: []const u8, offset: u32, amount: []const u8, loaded: []const u8, sum: []const u8 };

/// Emit one `Increment`: a load, an add and a store, with no new block.
pub fn increment(a: std.mem.Allocator, out: *std.ArrayList(u8), step: Increment) std.mem.Allocator.Error!void {
    const record = if (std.mem.startsWith(u8, step.record, "%")) step.record else local: {
        const name = try std.fmt.allocPrint(a, "{s}.record", .{step.loaded});
        try out.print(a, "  {s} = call ptr @myl_count_{s}_local(ptr {s})\n", .{ name, if (step.offset == function_calls) "function" else "site", step.record });
        break :local name;
    };
    try out.print(a, "  {s}.at = getelementptr inbounds i8, ptr {s}, i64 {d}\n", .{ step.loaded, record, step.offset });
    try out.print(a, "  {s} = load i64, ptr {s}.at, align 8\n  {s} = add i64 {s}, {s}\n  store i64 {s}, ptr {s}.at, align 8\n", .{
        step.loaded, step.loaded, step.sum, step.loaded, step.amount, step.sum, step.loaded,
    });
}

/// The function prologue: save the caller's record, make `@myl.cf.N` current and count the call.
pub fn prologue(a: std.mem.Allocator, out: *std.ArrayList(u8), record: u32) std.mem.Allocator.Error!void {
    try out.print(a, "  %myl.cnt.saved = load ptr, ptr @myl_count_current, align 8\n  %myl.cnt.active = call ptr @myl_count_function_local(ptr @myl.cf.{d})\n  store ptr %myl.cnt.active, ptr @myl_count_current, align 8\n", .{record});
    try increment(a, out, .{ .record = "%myl.cnt.active", .offset = function_calls, .amount = "1", .loaded = "%myl.cnt.calls", .sum = "%myl.cnt.calls.1" });
}

/// Before a return: the caller's record is current again.
pub const epilogue = "  store ptr %myl.cnt.saved, ptr @myl_count_current, align 8\n";

/// The allocator's inline fast paths in a counting build: the same functions as
/// `emit_llvm.runtime_fast_paths`, but every list allocation and every free goes
/// through the runtime, which counts it. Pushes with room stay inline.
pub const fast_paths =
    \\@myl_core_free_lists = external thread_local(localexec) global [33 x ptr]
    \\declare ptr @myl_core_list_new_slow(i64, i64) nounwind
    \\declare ptr @myl_core_list_grow(ptr, i64) nounwind
    \\define internal ptr @myl_core_list_new(i64 %cap, i64 %size) alwaysinline nounwind {
    \\entry:
    \\  %made = call ptr @myl_core_list_new_slow(i64 %cap, i64 %size)
    \\  ret ptr %made
    \\}
    \\define internal ptr @myl_core_list_reserve(ptr %list, i64 %size) alwaysinline nounwind {
    \\entry:
    \\  %len_at = getelementptr inbounds i8, ptr %list, i64 8
    \\  %len = load i64, ptr %len_at, align 8, !tbaa !5
    \\  %cap_at = getelementptr inbounds i8, ptr %list, i64 16
    \\  %cap = load i64, ptr %cap_at, align 8, !tbaa !5
    \\  %room = icmp ult i64 %len, %cap
    \\  br i1 %room, label %fits, label %grow, !prof !10
    \\fits:
    \\  ret ptr %list
    \\grow:
    \\  %grown = call ptr @myl_core_list_grow(ptr %list, i64 %size)
    \\  ret ptr %grown
    \\}
    \\define internal ptr @myl_core_list_fill_reserve(ptr %list, i64 %size, i64 %index) alwaysinline nounwind {
    \\entry:
    \\  %cap_at = getelementptr inbounds i8, ptr %list, i64 16
    \\  %cap = load i64, ptr %cap_at, align 8, !tbaa !5
    \\  %prefix = icmp ult i64 %index, %cap
    \\  br i1 %prefix, label %fits, label %check, !prof !10
    \\fits:
    \\  ret ptr %list
    \\check:
    \\  %room = call ptr @myl_core_list_reserve(ptr %list, i64 %size)
    \\  ret ptr %room
    \\}
    \\
;
