//! Per-function static cost of the exact Core pass run used by a build.
const std = @import("std");
const ir = @import("ir.zig");
const passes = @import("passes.zig");
const flags = @import("flags.zig");
const promote = @import("promote.zig");

/// Dynamic allocation classification shared with the build-time allocation promise.
/// Internal calls need call-graph traversal; foreign and unresolved calls are conservative.
pub const Allocation = enum { never, may, unresolved };

/// Classify one instruction after ownership has exposed copy-on-write branches.
/// For @noalloc, run debug ownership before release optimization and visit every
/// block and internal callee. Counts are sites that may allocate, never executions
/// or bytes. Runtime scratch and managed heap both count; stack storage does not.
pub fn allocation(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Allocation {
    return switch (inst.op) {
        .list_new => if (inst.data != 0 and inst.data != flags.fill_capacity) .never else .may,
        .list_push => if (inst.data == promote.stack_push) .never else .may,
        .list_copy, .dict_new, .dict_copy, .dict_insert, .dict_remove, .box_make, .str_char, .str_append, .str_append_char, .str_slice, .str_from_view, .list_sort, .buffer_new, .buffer_copy, .buffer_push, .buffer_append => .may,
        // Compound keys may grow the runtime hash/equality scratch stack.
        .dict_find => if (module.compound(function.inst(function.resolve(inst.a)).ty).dict.key.isCompound()) .may else .never,
        .call_indirect => blk: {
            const target = function.inst(function.resolve(inst.a));
            if (target.op == .func_ref and target.data < module.functions.items.len)
                break :blk calleeAllocation(&module.functions.items[@intCast(target.data)]);
            break :blk .unresolved;
        },
        .call => if (inst.a.index() < module.functions.items.len) calleeAllocation(&module.functions.items[inst.a.index()]) else .unresolved,
        else => .never,
    };
}

fn calleeAllocation(callee: *const ir.Function) Allocation {
    return switch (callee.signature.linkage) {
        .internal => .never,
        // Scalar runtime helpers use the extern ABI. Only declarations synthesized
        // by the compiler (no source name span) may use the audited allowlist;
        // source extern declarations remain opaque even with a helper's name.
        .extern_c => if (callee.span == 0 and runtimeAllocationFree(callee.name)) .never else .unresolved,
        .runtime_c => if (runtimeAllocationFree(callee.name)) .never else .may,
    };
}

/// Explicit audited allowlist: an unrecognized runtime helper may allocate.
/// Identity encode retains its argument; reverse changes bytes without growing.
pub fn runtimeAllocationFree(symbol: []const u8) bool {
    const names = [_][]const u8{
        "myl_core_str_eq",                 "myl_core_str_chars",          "myl_core_str_offset",
        "myl_core_str_index_offset",       "myl_core_bytes_index_offset", "myl_core_str_find",
        "myl_core_str_contains",           "myl_core_str_starts",         "myl_core_str_ends",
        "myl_core_str_parse_int",          "myl_core_parse_int_range",    "myl_core_parse_float_range",
        "myl_core_saturating_integer",     "myl_core_bytes_valid_list",   "myl_core_bytes_find",
        "myl_core_bytes_contains_value",   "myl_core_split_ws_start",     "myl_core_split_ws_end",
        "myl_core_text_encode",            "myl_core_text_every",         "myl_core_text_scalar_valid",
        "myl_core_text_ord",               "myl_core_text_bound",         "myl_core_text_search",
        "myl_core_bytes_search",           "myl_core_bytes_find_any",     "myl_core_bytes_utf8_count",
        "myl_core_bytes_utf8_count_range", "myl_core_buffer_capacity",    "myl_core_buffer_range_valid",
        "myl_core_buffer_reserve_valid",   "myl_core_buffer_reverse",     "myl_core_from_hex_valid",
        "myl_core_span_eq",                "myl_core_span_chars",         "myl_core_span_starts",
        "myl_core_span_ends",              "myl_core_span_contains",      "myl_core_octets_compare",
        "myl_core_dict_ordinal",
    };
    for (names) |name| if (std.mem.eql(u8, name, symbol)) return true;
    return false;
}

/// Static sites and exact pass events for one emitted body.
pub const Counts = struct {
    checks: struct { kept: u32 = 0, proved: u32 = 0 } = .{},
    updates: struct { in_place: u32 = 0, tested: u32 = 0, copied: u32 = 0 } = .{},
    allocation: struct { sites: u32 = 0, unresolved_calls: u32 = 0 } = .{},
    rc: struct { retains: u32 = 0, releases: u32 = 0, elided_pairs: u32 = 0, stack_lists: u32 = 0 } = .{},
    inlined_calls: u32 = 0,
    loops: struct { unswitched: u32 = 0, versioned: u32 = 0, vector_plans: u32 = 0, unknown: u32 = 0 } = .{},
    /// Null means LLVM supplied no loop-vectorization remark for this body.
    llvm_vectorized_loops: ?u32 = null,

    /// Sum all known site/event counts; missing LLVM evidence remains unknown.
    pub fn add(self: *Counts, other: Counts) void {
        inline for (.{ "checks", "updates", "allocation", "rc", "loops" }) |group| {
            inline for (@typeInfo(@FieldType(Counts, group)).@"struct".field_names) |name| {
                @field(@field(self, group), name) += @field(@field(other, group), name);
            }
        }
        self.inlined_calls += other.inlined_calls;
        if (other.llvm_vectorized_loops) |count| self.llvm_vectorized_loops = (self.llvm_vectorized_loops orelse 0) + count;
    }
};

/// Names are the specialized Core names, with module qualification when present.
pub const Function = struct { name: []const u8, counts: Counts };
/// Versioned output; filtering also filters totals, so they always sum the rows.
pub const Report = struct { version: []const u8 = "cost-v1", functions: []Function, totals: Counts };

/// Read the transformed instructions and the same per-function events as --stats.
pub fn measure(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result, filter: ?[]const u8) std.mem.Allocator.Error!Report {
    var functions: std.ArrayList(Function) = .empty;
    var total: Counts = .{};
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal or !matches(function.name, filter)) continue;
        const local = functionCounts(module, result, index);
        try functions.append(a, .{ .name = function.name, .counts = local });
        total.add(local);
    }
    return .{ .functions = try functions.toOwnedSlice(a), .totals = total };
}

/// Measure one final body and its exact pass events; query caches use this oracle.
pub fn functionCounts(module: *const ir.Module, result: *const passes.Result, index: usize) Counts {
    const function = &module.functions.items[index];
    const events = if (index < result.per_function.len) result.per_function[index] else passes.FunctionStats{};
    var local: Counts = .{
        .checks = .{ .proved = events.counts.proven },
        .updates = .{ .in_place = events.own.in_place, .tested = events.own.tested, .copied = events.own.copied },
        .rc = .{ .retains = events.own.retains, .releases = events.own.releases, .elided_pairs = events.own.elided, .stack_lists = events.own.promoted },
        .inlined_calls = events.counts.inlined,
        .loops = .{ .unswitched = events.counts.unswitched, .versioned = events.counts.versioned, .vector_plans = events.counts.vectorized, .unknown = @intCast(function.loops.items.len) },
    };
    const known = if (index < result.known.len) result.known[index] else null;
    for (function.blocks.items, 0..) |block, b| {
        if (known) |facts| if (b < facts.reachable.len and !facts.reachable[b]) continue;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op == .copy) continue;
            if (inst.check == .exact or (result.emission.verifying and inst.check == .proven)) local.checks.kept += 1;
            switch (allocation(module, function, inst)) {
                .never => {},
                .may => local.allocation.sites += 1,
                .unresolved => {
                    local.allocation.sites += 1;
                    local.allocation.unresolved_calls += 1;
                },
            }
        }
    }
    return local;
}

/// Select report rows after LLVM remarks have been attached; totals still sum rows.
pub fn select(a: std.mem.Allocator, report: Report, filter: ?[]const u8) std.mem.Allocator.Error!Report {
    if (filter == null) return report;
    var rows: std.ArrayList(Function) = .empty;
    var total: Counts = .{};
    for (report.functions) |function| if (matches(function.name, filter)) {
        try rows.append(a, function);
        total.add(function.counts);
    };
    return .{ .functions = try rows.toOwnedSlice(a), .totals = total };
}

fn matches(name: []const u8, filter: ?[]const u8) bool {
    const chosen = filter orelse return true;
    if (std.mem.eql(u8, name, chosen)) return true;
    const separator = std.mem.lastIndexOf(u8, name, "::") orelse return false;
    return std.mem.eql(u8, name[separator + 2 ..], chosen);
}

/// Render text or one JSON document, including totals after every function row.
pub fn render(a: std.mem.Allocator, report: Report, json: bool) std.mem.Allocator.Error![]const u8 {
    if (json) return std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, report, .{})});
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "cost-v1 (static sites after Core passes; LLVM loops unknown without remarks)\n");
    for (report.functions) |function| try row(a, &out, function.name, function.counts);
    try row(a, &out, "TOTAL", report.totals);
    return out.toOwnedSlice(a);
}

fn row(a: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, c: Counts) std.mem.Allocator.Error!void {
    const format = "{s}: checks {d} kept / {d} proved; updates {d} in place / {d} tested / {d} copied; " ++
        "allocations {d} ({d} unresolved); retains {d}; releases {d}; inlined {d}; vector plans {d}; LLVM vectorized ";
    try out.print(a, format, .{
        name,               c.checks.kept,                 c.checks.proved, c.updates.in_place, c.updates.tested, c.updates.copied,
        c.allocation.sites, c.allocation.unresolved_calls, c.rc.retains,    c.rc.releases,      c.inlined_calls,  c.loops.vector_plans,
    });
    if (c.llvm_vectorized_loops) |count| try out.print(a, "{d}", .{count}) else try out.appendSlice(a, "unknown");
    try out.print(a, "; unknown loops {d}; unswitched {d}; versioned {d}; RC pairs elided {d}; stack lists {d}\n", .{ c.loops.unknown, c.loops.unswitched, c.loops.versioned, c.rc.elided_pairs, c.rc.stack_lists });
}

/// Print legacy stats from the report totals, plus the newly visible site counts.
pub fn stats(a: std.mem.Allocator, out: *std.ArrayList(u8), c: Counts) std.mem.Allocator.Error!void {
    const changes = "mylang-core: inlined {d} calls, unswitched {d} loops, versioned {d} loops, proved {d} checks, vectorized {d} loops\n";
    try out.print(a, changes, .{ c.inlined_calls, c.loops.unswitched, c.loops.versioned, c.checks.proved, c.loops.vector_plans });
    const ownership = "mylang-core: ownership: {d} updates in place, {d} tested, {d} copied; " ++
        "{d} retains, {d} releases ({d} pairs elided); {d} lists on the stack\n";
    try out.print(a, ownership, .{ c.updates.in_place, c.updates.tested, c.updates.copied, c.rc.retains, c.rc.releases, c.rc.elided_pairs, c.rc.stack_lists });
    try out.print(a, "mylang-core: cost: {d} checks kept; {d} allocation sites ({d} unresolved calls); {d} unknown loops\n", .{ c.checks.kept, c.allocation.sites, c.allocation.unresolved_calls, c.loops.unknown });
}

/// Add LLVM evidence without changing the two established --stats lines.
pub fn llvmStats(a: std.mem.Allocator, out: *std.ArrayList(u8), counts: Counts, remarks: @import("driver.zig").OptimizationRemarks) std.mem.Allocator.Error!void {
    try out.appendSlice(a, "mylang-core: LLVM vectorized ");
    if (counts.llvm_vectorized_loops) |known| try out.print(a, "{d}", .{known}) else try out.appendSlice(a, "unknown");
    try out.print(a, "; {d} unknown loops; remarks {s}; {d} compiles in {d} ns; {d} remark queries reused\n", .{
        counts.loops.unknown, if (remarks.yaml != null) "available" else "unavailable", remarks.processes, remarks.compile_ns, remarks.reused,
    });
}
