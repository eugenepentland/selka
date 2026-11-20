//! Per-function static cost of the exact Core pass run used by a build.
const std = @import("std");
const ir = @import("ir.zig");
const passes = @import("passes.zig");
const flags = @import("flags.zig");
const promote = @import("promote.zig");
const source_location = @import("source_location.zig");
const copy_sites = @import("copy_sites.zig");
const verify_ir = @import("verify_ir.zig");
const span_forms = @import("span_forms.zig");

/// Dynamic allocation classification shared with the build-time allocation promise.
/// Internal calls need call-graph traversal; foreign and unresolved calls are conservative.
pub const Allocation = enum { never, may, unresolved };

/// Classify one instruction after ownership has made transfers and destruction explicit.
/// For @noalloc, run debug ownership before release optimization and visit every
/// block and internal callee. Counts are sites that may allocate, never executions
/// or bytes. Runtime scratch and managed heap both count; stack storage does not.
pub fn allocation(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Allocation {
    return switch (inst.op) {
        .list_new => if (inst.data != 0 and !flags.isFillCapacity(inst.data)) .never else .may,
        .list_push => if (inst.data == promote.stack_push) .never else .may,
        // A frame block (RB1) copies its parameter once per call when the argument was a slice or bytes.
        .block_frame => .may,
        .list_copy, .dict_new, .dict_copy, .dict_insert, .dict_remove, .box_make, .str_char, .str_append, .str_append_char, .str_slice, .str_from_view, .list_sort, .buffer_new, .buffer_copy, .buffer_push, .buffer_append => .may,
        .dict_find => dictFindAllocation(module, function, inst),
        .call_indirect => blk: {
            const target = function.inst(function.resolve(inst.a));
            if (target.op == .func_ref and target.data < module.functions.items.len)
                break :blk calleeAllocation(module, &module.functions.items[@intCast(target.data)]);
            break :blk .unresolved;
        },
        .call => if (inst.a.index() < module.functions.items.len) calleeAllocation(module, &module.functions.items[inst.a.index()]) else .unresolved,
        else => .never,
    };
}

/// A probe with a compound key may grow the runtime hash/equality scratch stack; a scalar or text key
/// never allocates. The probed dictionary may be a read-only borrowed overlay (`const t = record.table`,
/// a borrowed accessor result), so its table is read through `Module.dictShape`. An operand that is no
/// dictionary is IR the verifier refuses; the classification then stays conservative.
fn dictFindAllocation(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Allocation {
    const shape = module.dictShape(function.inst(function.resolve(inst.a)).ty) orelse return .may;
    return if (shape.key.isCompound()) .may else .never;
}

fn calleeAllocation(module: *const ir.Module, callee: *const ir.Function) Allocation {
    if (@import("build_equality.zig").declaration(module, callee) catch return .unresolved) return .may;
    if (@import("borrowed_provider.zig").declaration(module, callee) catch return .unresolved) return .never;
    if (@import("borrowed_provider.zig").keepalive(module, callee) catch return .unresolved) return .never;
    if (@import("borrow_selection.zig").declaration(module, callee) catch return .unresolved) return .never;
    if (@import("aggregate_provider.zig").marker(module, callee) catch return .unresolved) return .never;
    const allocation_free = runtimeAllocationFree(callee.name);
    return switch (callee.signature.linkage) {
        .internal => .never,
        // Scalar runtime helpers use the extern ABI. Only declarations synthesized
        // by the compiler (no source name span) may use the audited allowlist;
        // source extern declarations remain opaque even with a helper's name.
        .extern_c => if (callee.span != 0) .unresolved else if (allocation_free) .never else if (std.mem.eql(u8, callee.name, "myl_core_text_encode") or std.mem.eql(u8, callee.name, "myl_core_span_encode")) .may else .unresolved,
        .runtime_c => if (allocation_free) .never else .may,
        // A call through an address reaches C the compiler cannot see.
        .extern_address => .unresolved,
    };
}

/// Explicit audited allowlist: an unrecognized runtime helper may allocate.
/// Owned encode and buffer reverse allocate independent storage; borrowed views do not.
/// A span form (`span_forms`) is classified as its text form is: the body a build emits calls the span form
/// of a helper on every borrowed `str`, `bytes` or list parameter, so the two must agree (F19).
pub fn runtimeAllocationFree(symbol: []const u8) bool {
    if (listedAllocationFree(symbol)) return true;
    if (registersAllocationFree(symbol)) return true;
    const text = span_forms.textForm(symbol) orelse return false;
    return listedAllocationFree(text);
}

/// The simulated register bank's reads, writes and log readers (MCU-B1): `registers.simulated()` allocates the whole
/// bank, its table of words and its log, so these only index storage that exists, and a full bank traps instead of
/// growing (`runtime/core_registers.c`). `myl_core_registers_simulated` and `myl_core_registers_script32` (which copies
/// its values into the bank) are not listed: they allocate. `pin32` only sets two words of a slot. The `cpu` operations
/// (MCU-NOC1) record into the bank's event log, allocated with it, and read it.
fn registersAllocationFree(symbol: []const u8) bool {
    const names = [_][]const u8{
        "myl_core_registers_read8",                   "myl_core_registers_read16",                 "myl_core_registers_read32",
        "myl_core_registers_write8",                  "myl_core_registers_write16",                "myl_core_registers_write32",
        "myl_core_registers_poke32",                  "myl_core_registers_write_count",            "myl_core_registers_write_address",
        "myl_core_registers_write_value",             "myl_core_registers_write_width",            "myl_core_registers_pin32",
        "myl_core_registers_cpu_wait_for_event",      "myl_core_registers_cpu_wait_for_interrupt", "myl_core_registers_cpu_send_event",
        "myl_core_registers_cpu_barrier",             "myl_core_registers_cpu_breakpoint",         "myl_core_registers_cpu_interrupts_disable",
        "myl_core_registers_cpu_interrupts_set",      "myl_core_registers_cpu_event_count",        "myl_core_registers_cpu_event_kind",
        "myl_core_registers_cpu_event_writes_before", "myl_core_registers_cpu_interrupts_now",     "myl_core_registers_cpu_write_interrupts_off",
    };
    for (names) |name| if (std.mem.eql(u8, symbol, name)) return true;
    return false;
}

/// The helpers audited by name. Span forms that `span_forms` pairs with a listed helper are not repeated here.
fn listedAllocationFree(symbol: []const u8) bool {
    const names = [_][]const u8{
        "myl_core_str_eq",                 "myl_core_str_chars",            "myl_core_str_offset",
        "myl_core_str_index_offset",       "myl_core_bytes_index_offset",   "myl_core_str_find",
        "myl_core_str_contains",           "myl_core_str_starts",           "myl_core_str_ends",
        "myl_core_str_parse_int",          "myl_core_parse_int_range",      "myl_core_parse_float_range",
        "myl_core_parse_f32_range",        "myl_core_saturating_integer",   "myl_core_bytes_valid_list",
        "myl_core_bytes_find",             "myl_core_bytes_contains_value", "myl_core_split_ws_start",
        "myl_core_split_ws_end",           "myl_core_text_every",           "myl_core_text_scalar_valid",
        "myl_core_text_ord",               "myl_core_text_bound",           "myl_core_text_search",
        "myl_core_bytes_search",           "myl_core_bytes_find_any",       "myl_core_bytes_utf8_count",
        "myl_core_bytes_utf8_count_range", "myl_core_buffer_capacity",      "myl_core_buffer_range_valid",
        "myl_core_buffer_reserve_valid",   "myl_core_buffer_reverse",       "myl_core_from_hex_valid",
        "myl_core_octets_compare",         "myl_core_dict_ordinal",         "myl_core_xc_chars",
        "myl_core_xc_index",               "myl_core_xc_slice",             "myl_core_xc_search",
        "myl_core_view_slice",             "myl_core_text_trim_view",       "myl_core_view_chars",
        "myl_core_span_bytes_trim_view",   "myl_core_view_index",           "myl_core_view_byte",
        "myl_core_owned_same_block",       "myl_core_round_float",          "myl_core_span_bytes_slice_view",
        "myl_core_view_slice_text",        "myl_core_assert_operands",      "myl_core_buffer_clear",
    };
    for (names) |name| if (std.mem.eql(u8, symbol, name)) return true;
    return false;
}

/// Static sites and exact pass events for one emitted body.
pub const Counts = struct {
    checks: struct { kept: u32 = 0, proved: u32 = 0 } = .{},
    updates: struct { in_place: u32 = 0 } = .{},
    /// `frame_copies`: the frame block sites (RB1), which copy a slice or a bytes argument once per call, hidden in the source.
    allocation: struct { sites: u32 = 0, unresolved_calls: u32 = 0, frame_copies: u32 = 0 } = .{},
    ownership: struct { drops: u32 = 0, stack_lists: u32 = 0 } = .{},
    inlined_calls: u32 = 0,
    loops: struct { unswitched: u32 = 0, versioned: u32 = 0, vector_plans: u32 = 0, unknown: u32 = 0 } = .{},
    /// Null means LLVM supplied no loop-vectorization remark for this body.
    llvm_vectorized_loops: ?u32 = null,

    /// Sum all known site/event counts; missing LLVM evidence remains unknown.
    pub fn add(self: *Counts, other: Counts) void {
        inline for (.{ "checks", "updates", "allocation", "ownership", "loops" }) |group| {
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
        const local = try functionCounts(a, module, result, index);
        try functions.append(a, .{ .name = function.name, .counts = local });
        total.add(local);
    }
    return .{ .functions = try functions.toOwnedSlice(a), .totals = total };
}

/// Measure one final body and its exact pass events; query caches use this oracle.
pub fn functionCounts(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result, index: usize) std.mem.Allocator.Error!Counts {
    const function = &module.functions.items[index];
    const events = if (index < result.per_function.len) result.per_function[index] else passes.FunctionStats{};
    var local: Counts = .{
        .checks = .{ .proved = events.counts.proven },
        .updates = .{ .in_place = events.own.in_place },
        .ownership = .{ .drops = events.own.drops, .stack_lists = events.own.promoted },
        .inlined_calls = events.counts.inlined,
        .loops = .{ .unswitched = events.counts.unswitched, .versioned = events.counts.versioned, .vector_plans = events.counts.vectorized, .unknown = @intCast(function.loops.items.len) },
    };
    const known = if (index < result.known.len) result.known[index] else null;
    // The blocks `sites` reads, so the rows are exactly the allocation sites counted here.
    const graph = try reachableBlocks(a, module, function);
    for (function.blocks.items, 0..) |block, b| {
        if (!copy_sites.counted(graph, if (known) |facts| facts.reachable else null, b)) continue;
        for (block.insts.items) |ref| {
            const inst = function.inst(ref);
            if (inst.op == .copy) continue;
            if (inst.check == .exact or (result.emission.verifying and inst.check == .proven)) local.checks.kept += 1;
            if (inst.op == .block_frame) local.allocation.frame_copies += 1;
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
    const format = "{s}: checks {d} kept / {d} proved; updates {d} in place; " ++
        "allocations {d} ({d} unresolved); drops {d}; inlined {d}; vector plans {d}; LLVM vectorized ";
    try out.print(a, format, .{ name, c.checks.kept, c.checks.proved, c.updates.in_place, c.allocation.sites, c.allocation.unresolved_calls, c.ownership.drops, c.inlined_calls, c.loops.vector_plans });
    if (c.llvm_vectorized_loops) |count| try out.print(a, "{d}", .{count}) else try out.appendSlice(a, "unknown");
    try out.print(a, "; unknown loops {d}; unswitched {d}; versioned {d}; stack lists {d}\n", .{ c.loops.unknown, c.loops.unswitched, c.loops.versioned, c.ownership.stack_lists });
}

/// Print legacy stats from the report totals, plus the newly visible site counts.
pub fn stats(a: std.mem.Allocator, out: *std.ArrayList(u8), c: Counts) std.mem.Allocator.Error!void {
    const changes = "selka-core: inlined {d} calls, unswitched {d} loops, versioned {d} loops, proved {d} checks, vectorized {d} loops\n";
    try out.print(a, changes, .{ c.inlined_calls, c.loops.unswitched, c.loops.versioned, c.checks.proved, c.loops.vector_plans });
    const ownership = "selka-core: ownership: {d} updates in place; {d} drops; {d} lists on the stack\n";
    try out.print(a, ownership, .{ c.updates.in_place, c.ownership.drops, c.ownership.stack_lists });
    try out.print(a, "selka-core: cost: {d} checks kept; {d} allocation sites ({d} unresolved calls); {d} unknown loops\n", .{ c.checks.kept, c.allocation.sites, c.allocation.unresolved_calls, c.loops.unknown });
    // Shown only when there are any, so a program without them prints what it printed before.
    if (c.allocation.frame_copies != 0) try out.print(a, "selka-core: frame blocks: {d} sites; each copies its parameter once per call when the argument is a slice or bytes\n", .{c.allocation.frame_copies});
}

/// Add LLVM evidence without changing the two established --stats lines.
pub fn llvmStats(a: std.mem.Allocator, out: *std.ArrayList(u8), counts: Counts, remarks: @import("driver.zig").OptimizationRemarks) std.mem.Allocator.Error!void {
    try out.appendSlice(a, "selka-core: LLVM vectorized ");
    if (counts.llvm_vectorized_loops) |known| try out.print(a, "{d}", .{known}) else try out.appendSlice(a, "unknown");
    try out.print(a, "; {d} unknown loops; remarks {s}; {d} compiles in {d} ns; {d} remark queries reused\n", .{
        counts.loops.unknown, if (remarks.yaml != null) "available" else "unavailable", remarks.processes, remarks.compile_ns, remarks.reused,
    });
}

/// How a static allocating site spends its allocation, named by its Core operation.
pub const SiteKind = enum {
    /// Independent storage of an existing value: a list, dictionary, buffer or text copy.
    copy,
    /// A fresh managed value: a list, dictionary, buffer or box built from nothing.
    construction,
    /// A new storage form made from a scalar or another form, such as a character string.
    conversion,
    /// Storage or scratch that may grow: pushes, inserts, removals, appends and sorts.
    growth,
    /// A call whose target the classification cannot resolve; it may allocate.
    @"unresolved call",
};

/// One static site after the Core passes: where it came from, what did it, and how deep.
/// Its one-line repair hint is `hint(kind)`, written beside it in the JSON document.
pub const Site = struct {
    /// The source function the operation came from; an inlined callee keeps its own name.
    function: []const u8,
    /// The source file of the operation's witness span, kept through inlining.
    path: []const u8,
    /// The one-based source line of that span.
    line: u32,
    /// The one-based source column of that span.
    column: u32,
    /// What the allocation is for, from `siteKind`.
    kind: SiteKind,
    /// The number of recorded loops enclosing the site; 0 outside every loop.
    loop_depth: u32,
    /// On a copy row only: how the copy reads on the page (`copy_sites.Reader`); `null` on every other kind.
    reading: ?copy_sites.Reading = null,

    /// On a copy row only: whether the copy carries the written mark the hidden-copy check reads, false only for a
    /// frame block and an unwritten copy (`null` on every other kind).
    pub fn written(self: Site) ?bool {
        const reading = self.reading orelse return null;
        const kind = reading.implicit orelse return true;
        return kind != .@"frame block" and kind != .unwritten;
    }

    /// The JSON row: the fields in declaration order, `written` on a copy row only, then `hint`, then on a copy
    /// row its `label` and, for an implicit copy, its `implicit` kind (W4).
    pub fn jsonStringify(self: Site, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("function");
        try jw.write(self.function);
        try jw.objectField("path");
        try jw.write(self.path);
        try jw.objectField("line");
        try jw.write(self.line);
        try jw.objectField("column");
        try jw.write(self.column);
        try jw.objectField("kind");
        try jw.write(@tagName(self.kind));
        try jw.objectField("loop_depth");
        try jw.write(self.loop_depth);
        if (self.written()) |marked| {
            try jw.objectField("written");
            try jw.write(marked);
        }
        try jw.objectField("hint");
        try jw.write(hint(self.kind));
        if (self.reading) |reading| {
            try jw.objectField("label");
            try jw.write(@tagName(reading.label));
            if (reading.implicit) |kind| {
                try jw.objectField("implicit");
                try jw.write(@tagName(kind));
            }
        }
        try jw.endObject();
    }
};

/// Versioned `--sites` output: the unchanged function rows and totals, plus the site rows.
pub const SiteReport = struct {
    /// The document version (`cost-sites-v1`).
    version: []const u8 = "cost-sites-v1",
    /// The same emitted-function rows as `cost-v1`, already filtered.
    functions: []const Function,
    /// The same totals as `cost-v1`, already filtered.
    totals: Counts,
    /// One row per allocation or copy site, in emitted-function, block and instruction order.
    sites: []const Site,
    /// The copy rows with no written mark (`"written":false`): frame blocks and unwritten copies.
    hidden_copies: u32 = 0,
    /// The copy rows labelled implicit: `hidden_copies` plus the dictionary-key and `old` capture copies (W4).
    implicit_copies: u32 = 0,
};

/// The one-line hint shared by every site of `kind`.
pub fn hint(kind: SiteKind) []const u8 {
    return switch (kind) {
        .copy => "an independent copy: move the value, borrow a view, or copy once outside the loop",
        .construction => "a new value: construct it once outside the loop or reuse storage",
        .conversion => "a new storage form: convert once outside the loop and keep the result",
        .growth => "storage may grow: reserve capacity up front, or grow once outside the loop",
        .@"unresolved call" => "an unresolved or foreign call may allocate: call a known helper or move it out of the loop",
    };
}

/// The kind of one site. `classified` is `allocation`'s answer for the same instruction, so
/// the site rows always describe exactly the instructions `allocation.sites` counts.
pub fn siteKind(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst, classified: Allocation) SiteKind {
    // A listed copy site (`copy_sites.listed`, the frame block included) is a copy row whatever its callee's
    // allocation class, so the rows name exactly the sites the hidden-copy check reads.
    if (copy_sites.listed(module, inst)) return .copy;
    if (classified == .unresolved) return .@"unresolved call";
    return switch (inst.op) {
        .list_new, .dict_new, .buffer_new, .box_make => .construction,
        .str_char => .conversion,
        .list_push, .dict_insert, .dict_remove, .list_sort, .dict_find, .buffer_push, .buffer_append, .str_append, .str_append_char => .growth,
        .call, .call_indirect => runtimeKind(calleeName(module, function, inst)),
        else => .construction,
    };
}

/// Name an allocating runtime helper the classifier resolved by what it builds. A copy helper is
/// a copy site (`copy_sites.isSite`) before this runs; sort scratch helpers grow, and text and
/// rendered values convert.
fn runtimeKind(symbol: []const u8) SiteKind {
    if (std.mem.indexOf(u8, symbol, "sort") != null or std.mem.indexOf(u8, symbol, "rotate") != null or std.mem.indexOf(u8, symbol, "equal") != null) return .growth;
    for ([_][]const u8{ "str_", "text_", "show_", "render_", "join", "encode", "format" }) |needle| {
        if (std.mem.indexOf(u8, symbol, needle) != null) return .conversion;
    }
    return .construction;
}

// twin-drift-ok: allocation_contract.internalTarget returns only internal callee indexes for
// graph traversal; this names any direct or function-value call target for a site row.
/// The direct or function-value callee's name, or "" when the target is not one.
fn calleeName(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) []const u8 {
    const target: ?usize = switch (inst.op) {
        .call => inst.a.index(),
        .call_indirect => blk: {
            const value = function.inst(function.resolve(inst.a));
            break :blk if (value.op == .func_ref) @intCast(value.data) else null;
        },
        else => null,
    };
    const index = target orelse return "";
    return if (index < module.functions.items.len) module.functions.items[index].name else "";
}

/// The source function of one instruction: through the inliner's ancestry when it was cloned.
fn originName(module: *const ir.Module, result: *const passes.Result, index: usize, b: usize, ref: ir.Ref) []const u8 {
    const frame = result.provenance.instruction(@intCast(index), @intCast(b), ref) orelse return module.functions.items[index].name;
    const function = result.provenance.frames.items[frame].function;
    return if (function < module.functions.items.len) module.functions.items[function].name else module.functions.items[index].name;
}

/// One static site per instruction the allocation classification counts, in emitted-function,
/// block and instruction order. `locator` resolves each instruction's witness span exactly as
/// the counters do, so an inlined callee keeps its source position; `fallback_path` names the
/// entry source when a locator has no path. A block `copy_sites.counted` leaves out (unreachable from the entry, or
/// proved dead by the facts) contributes no rows.
pub fn sites(a: std.mem.Allocator, module: *const ir.Module, result: *const passes.Result, locator: source_location.Locator, fallback_path: []const u8, source: ?[]const u8) std.mem.Allocator.Error![]const Site {
    var rows: std.ArrayList(Site) = .empty;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage != .internal) continue;
        const depth = try loopDepths(a, function);
        const graph = try reachableBlocks(a, module, function);
        const known = if (index < result.known.len) result.known[index] else null;
        var reader: copy_sites.Reader = .{ .arena = a, .module = module, .f = function, .source = source };
        for (function.blocks.items, 0..) |block, b| {
            if (!copy_sites.counted(graph, if (known) |facts| facts.reachable else null, b)) continue;
            for (block.insts.items) |ref| {
                const inst = function.inst(ref);
                if (inst.op == .copy) continue;
                const classified = allocation(module, function, inst);
                if (classified == .never) continue;
                const span = if (inst.span != 0) inst.span else function.span;
                const location = locator.locate(locator.context, span);
                const kind = siteKind(module, function, inst, classified);
                try rows.append(a, .{
                    .function = originName(module, result, index, b, ref),
                    .path = if (location.path.len != 0) location.path else fallback_path,
                    .line = location.line,
                    .column = location.column,
                    .kind = kind,
                    .loop_depth = depth[b],
                    .reading = if (kind == .copy) try reader.read(ref) else null,
                });
            }
        }
    }
    return rows.toOwnedSlice(a);
}

/// The blocks of `function` reachable from its entry (`verify_ir.reachableBlocks`); a malformed graph, which the
/// verifier refuses before any report, counts every block.
fn reachableBlocks(a: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function) std.mem.Allocator.Error![]const bool {
    return verify_ir.reachableBlocks(a, module, function) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidIr => {
            const every = try a.alloc(bool, function.blocks.items.len);
            @memset(every, true);
            return every;
        },
    };
}

/// Select site rows by the `FUNCTION` filter: the row's source function, compared exactly as
/// the function rows are.
pub fn selectSites(a: std.mem.Allocator, sites_in: []const Site, filter: ?[]const u8) std.mem.Allocator.Error![]const Site {
    const chosen = filter orelse return sites_in;
    var rows: std.ArrayList(Site) = .empty;
    for (sites_in) |site| if (matches(site.function, chosen)) try rows.append(a, site);
    return rows.toOwnedSlice(a);
}

/// Render `--sites`: as text, the unchanged `cost-v1` text followed by the site rows;
/// as JSON, one `cost-sites-v1` document whose `functions` and `totals` are unchanged.
pub fn renderSites(a: std.mem.Allocator, report: Report, rows: []const Site, json: bool) std.mem.Allocator.Error![]const u8 {
    var hidden: u32 = 0;
    var implicit: copy_sites.Census = .{};
    for (rows) |site| if (site.reading) |reading| {
        if (site.written() == false) hidden += 1;
        implicit.add(reading);
    };
    const implicit_total = implicit.frame_blocks + implicit.dictionary_keys + implicit.old_captures + implicit.unwritten;
    if (json) {
        const document: SiteReport = .{ .functions = report.functions, .totals = report.totals, .sites = rows, .hidden_copies = hidden, .implicit_copies = implicit_total };
        return std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, document, .{})});
    }
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try render(a, report, false));
    try out.appendSlice(a, "\ncost-sites-v1 (static allocation and copy sites after Core passes)\n");
    // The implicit copies, by kind: what no `copy(` and no named operation on the page shows (W4).
    try out.print(a, "hidden copies: {d}", .{implicit_total});
    if (implicit_total != 0) {
        var kinds: std.ArrayList(u8) = .empty;
        for ([_]struct { n: u32, name: []const u8 }{
            .{ .n = implicit.frame_blocks, .name = "frame block" },
            .{ .n = implicit.dictionary_keys, .name = "dictionary key" },
            .{ .n = implicit.old_captures, .name = "old capture" },
            .{ .n = implicit.unwritten, .name = "unwritten" },
        }) |kind| if (kind.n != 0) try kinds.print(a, "{s}{d} {s}", .{ if (kinds.items.len == 0) "" else ", ", kind.n, kind.name });
        try out.print(a, " ({s})", .{kinds.items});
    }
    try out.appendSlice(a, "\n");
    for (rows) |site| {
        const label: []const u8 = if (site.reading) |reading| switch (reading.label) {
            .written => "  written",
            .@"named operation" => "  named operation",
            .implicit => try std.fmt.allocPrint(a, "  implicit ({s})", .{@tagName(reading.implicit.?)}),
        } else "";
        try out.print(a, "{s}:{d}:{d}  {s}  {s}{s}  loop {d}  {s}\n", .{ site.path, site.line, site.column, site.function, @tagName(site.kind), label, site.loop_depth, hint(site.kind) });
    }
    return out.toOwnedSlice(a);
}

/// The loops enclosing each block of one function. The builder records structured loops, so
/// the body is every block reachable from `body` without crossing the loop's own header or
/// exit; the header is part of the loop even when the body never reaches the latch.
fn loopDepths(a: std.mem.Allocator, function: *const ir.Function) std.mem.Allocator.Error![]u32 {
    const depth = try a.alloc(u32, function.blocks.items.len);
    @memset(depth, 0);
    if (function.loops.items.len == 0) return depth;
    const seen = try a.alloc(bool, function.blocks.items.len);
    var pending: std.ArrayList(ir.BlockId) = .empty;
    defer pending.deinit(a);
    for (function.loops.items) |loop| {
        const header = loop.header.index();
        if (header < depth.len) depth[header] += 1;
        @memset(seen, false);
        pending.clearRetainingCapacity();
        try pending.append(a, loop.body);
        while (pending.pop()) |block| {
            const b = block.index();
            if (b >= depth.len or b == header or b == loop.exit.index() or seen[b]) continue;
            seen[b] = true;
            depth[b] += 1;
            for (successors(function, block)) |next| if (next) |successor| try pending.append(a, successor);
        }
    }
    return depth;
}

// twin-drift-ok: verify_ir's successors validates one function's graph and returns raw indexes;
// this walks a final body's edges to count enclosing loops and returns block ids.
/// The successor blocks of a block whose last instruction is a jump or branch.
fn successors(function: *const ir.Function, block: ir.BlockId) [2]?ir.BlockId {
    const insts = function.blocks.items[block.index()].insts.items;
    if (insts.len == 0) return .{ null, null };
    const last = function.inst(insts[insts.len - 1]);
    return switch (last.op) {
        .jump => .{ @fromBackingInt(@intCast(@as(u32, @intCast(last.data)))), null },
        .branch => blk: {
            const targets = ir.unpackTargets(last.data);
            break :blk .{ targets.then, targets.otherwise };
        },
        else => .{ null, null },
    };
}
