//! Core IR → LLVM IR text (docs/design/new-core-ir.md §7).
//!
//! Each IR block becomes one LLVM block, split after every emitted check: the
//! check branches to a cold trap block and the block continues in a fresh
//! label. Phis therefore name the label each predecessor *ends* in, so a
//! function is rendered in two passes: block bodies first (recording each
//! block's exit label), then the blocks with their phis in front.
//!
//! The runtime ABI (src/core/runtime/core_rt.c): list and string blocks have a
//! 32-byte header `{u32 count, u32 kind, i64 len, i64 cap, i64 reserved}` and
//! their data at offset 32; traps carry pointers to private, unit-local site records.
const std = @import("std");
const zero_rc = @import("zero_rc.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const index_keys = @import("index_keys.zig");
const vector = @import("vector.zig");
const c_abi = @import("c_abi.zig");
const flags = @import("flags.zig");
const elements = @import("elements.zig");
const emit_dict = @import("emit_dict.zig");
const emit_release = @import("emit_release.zig");
const emit_bytes = @import("emit_bytes.zig");
const emit_text_split = @import("emit_text_split.zig");
const emit_text = @import("emit_text.zig");
const text_builder = @import("build_text.zig");
const emit_fn = @import("emit_fn.zig");
const emit_number = @import("emit_number.zig");
const internal_linkage = "internal";
const emit_cap = @import("emit_cap.zig");
const emit_values = @import("emit_values.zig");
const emit_constants = @import("emit_constants.zig");
const emit_count = @import("emit_count.zig");
const origins = @import("inline_origins.zig");
const emit_homes = @import("emit_homes.zig");
const emit_state = @import("emit_state.zig");
const effects = @import("effects.zig");
const fuse = @import("fuse.zig");

/// A source line and column for a span start.
pub const Location = struct { line: u32, column: u32, path: []const u8 = "" };

/// Resolves span starts to lines and columns without tying the emitter to the front end.
pub const Locator = struct {
    context: *const anyopaque,
    locate: *const fn (*const anyopaque, u32) Location,
};

/// Optimizer output retained together through every native emission path.
pub const Analysis = struct {
    facts: []const ?facts.Facts = &.{},
    vectors: []const []const vector.Plan = &.{},
    provenance: ?*const origins.Table = null,
    /// The final IR's effect summaries (`effects.zig`); computed here when null.
    effects: ?*const effects.Summaries = null,
};

/// What the emitted module needs from its caller.
pub const Options = struct {
    locator: Locator,
    /// Fallback source path for hand-built IR and header-less files.
    source_path: []const u8,
    /// Parameter names of `main`, which select stdout or stderr for a `Stream`.
    /// What the C entry needs to know about `main`.
    main: Main,
    /// Per function, the facts a release build computed (empty in debug builds):
    /// element ranges become `!range` metadata on list loads.
    analysis: Analysis = .{},
    /// Verify mode: every proven check is emitted anyway, every fact interval and
    /// unreachable block is asserted, and a failure traps `R_CORE_FACT`. No `nsw`,
    /// `!range` or other fact-derived promise reaches LLVM, so it cannot fold the asserts away.
    verify: bool = false,
    /// The target description (`target.zig`): vector width and available intrinsics.
    target: @import("target.zig").Target = @import("target.zig").current,
    /// A counting build (`--counters`, `emit_count.zig`): every function and counted
    /// site gets a record, and the program writes the counts at exit. Off, nothing
    /// in the emitted text changes.
    counters: bool = false,
};

/// `main` as the C entry calls it.
pub const Main = struct {
    /// Parameter names, which select stdout or stderr for a `Stream`.
    parameters: []const []const u8 = &.{},
    /// When `main` returns a `Result`, the tags of its `Ok` and `Err` cases (the
    /// checker's order): the entry reports an `Err` (RESULT-MAIN-1/2).
    result: ?MainResult = null,
    /// Checked capability family per parameter; 255 means ordinary data.
    capabilities: []const u8 = &.{},
    /// Whether the entry reads its runtime options from `MYLANG_OPTIONS` before calling
    /// `main` (`myl_core_start`, NATIVE-ARGV-1): a program's entry does, a test executable's does not.
    runtime_options: bool = false,
};

/// The case tags of `main`'s `Result` return type.
pub const MainResult = struct { ok_tag: u32, error_tag: u32 };

/// Trap kinds, in the order the runtime's code table lists them. `list_empty` is a
/// pop of an empty list (`R_LIST_BOUNDS`, operation `pop`); `trace` marks an
/// error-trace site, which never traps; `assertion` is a failed `assert` or contract clause (its
/// `width` is the `typed.AssertionKind`, its `operation` the message).
pub const TrapKind = enum(u8) {
    overflow,
    division_by_zero,
    list_bounds,
    float_conversion,
    cast,
    fact,
    list_empty,
    trace,
    assertion,
    missing_key = 9,
    iteration_mutation = 10,
    text_bounds = 11,
    text_separator = 12,
    text_step = 13,
    byte_range = 14,
    text_scalar = 15,
    text_substring = 16,
    invalid_shift = 17,
    list_value = 18,
    list_pop_index = 19,
};

/// `prefix` without the `.N` counters earlier `fresh` names appended: a block that
/// continues after many checks is named from its base label, not from the chain of
/// every label before it, which LLVM refuses past a length (NEW-CORE-S5-LABELS-1).
fn freshBase(prefix: []const u8) []const u8 {
    var base = prefix;
    while (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const suffix = base[dot + 1 ..];
        if (suffix.len == 0 or dot == 0) break;
        for (suffix) |byte| if (!std.ascii.isDigit(byte)) return base;
        base = base[0..dot];
    }
    return base;
}

const Site = struct { kind: TrapKind, location: Location, width: u16, operation: []const u8, function: []const u8 };

/// The counter kind of a conditional trap of `kind` in a counting build (NEW-CORE-COUNTERS-6).
fn checkKind(kind: TrapKind) emit_count.Kind {
    return switch (kind) {
        .list_bounds, .list_empty, .list_pop_index, .text_bounds, .text_substring => .bounds_check,
        .overflow => .overflow_check,
        .division_by_zero => .division_check,
        .invalid_shift => .shift_check,
        else => .other_check,
    };
}

/// The bit of a site's `width` that marks an unsigned overflow, division or cast, whose
/// operands the runtime prints unsigned (`MYL_CORE_SITE_UNSIGNED` in `runtime/core_rt.c`).
const unsigned_site: u16 = 0x100;

/// `  %x = getelementptr inbounds i8, ptr p, i64 0`: a new name for the same block.
const zero_trap_line = "  call void @myl_core_trap(ptr @myl.site.{d}, i64 0, i64 0) #2{s}\n  unreachable\n";

const same_pointer = "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n";

/// The `data` of an `unreachable` that asserts a uniqueness claim (`own.unique_assert`).
const unique_assert = 1;
/// The `data` of a `release` of a statically unique block (`own.unique_release`).
const unique_release = 1;
/// The `data` of a `release` of a value that may be `undef` (`own.empty_release`).
const empty_release = 2;
/// The `data` of an `unreachable` asserting a stack list's room (`promote.capacity_assert`).
const capacity_assert = 2;
/// The `data` of a push into a stack list (`promote.stack_push`).
const stack_push = 1;
/// The size class marking a block that lives in a stack frame (`runtime/core_rt.c`).
const stack_kind = "-16777216";

/// Header offsets of list and string blocks.
const len_offset = 8;
const cap_offset = 16;
const data_offset = 32;

const Out = std.ArrayList(u8);

/// Why emission stopped: a construct the builder admitted but this emitter cannot lower yet.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// The end of an LLVM `c"..."` constant: a NUL, the closing quote and the line end.
const nul_terminator = "\\00\"\n";

/// `  %x = icmp eq type value, 0`: a divisor's zero test.
const zero_test_line = "  {s} = icmp eq {s} {s}, 0\n";

/// `  %x = or i1 %a, %b`: two failure conditions merged.
const or_line = "  {s} = or i1 {s}, {s}\n";
/// `  %x = icmp pred type value, constant`: one side of a range test.
const bound_line = "  {s} = icmp {s} {s} {s}, {d}\n";

/// `  %at = getelementptr inbounds i8, ptr list, i64 offset` then `  %x = load i64, ptr %at`: one header field.
const header_load_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8\n";
const header_pointer_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n";

/// TBAA access tags and the count's `!range` (docs/design/new-core-s1.md §6, R-2):
/// the reference count, the header's length and capacity, and element, field and
/// box data are three types no access of another aliases, so LLVM may move or fold
/// count updates across data accesses. Fixed node numbers, emitted with the module.
const tbaa_count = "!tbaa !3";
const tbaa_header = "!tbaa !5";
const tbaa_data = "!tbaa !7";
/// A count is never 0 while its block is reachable: `[1, 0)`, i.e. 1 through saturated.
const count_range = "!range !8";
/// The first `!range` node number free for fact intervals (after the element tags and count branch weight).
const first_range_node = 23;

/// The TBAA tag of one list element scalar by its LLVM storage type (NEW-CORE-F1-TBAA-1):
/// each is a child of `myl.data`, so it aliases the generic tag and no other child.
const ElementTag = struct { storage: []const u8, tag: []const u8 };

/// Element data tagged by scalar type. Only the list operations' element accesses use
/// these (`FunctionEmitter.element_tags`): an element's bytes at one offset always hold
/// the same scalar for the life of its block, since a list's element type is fixed. A
/// union's tag and payload, every whole-value copy (`llvm.memcpy`), and every access that
/// is not a list element (homes, boxes, return slots, dictionary entries) keep the
/// generic `myl.data`, which aliases every child. Reuse of a freed block for a list of
/// another element type is ordered by the compiler barrier in `myl_core_free`.
const element_tags = [_]ElementTag{
    .{ .storage = "double", .tag = "!tbaa !12" },
    .{ .storage = "i64", .tag = "!tbaa !14" },
    .{ .storage = "i32", .tag = "!tbaa !16" },
    .{ .storage = "i16", .tag = "!tbaa !18" },
    .{ .storage = "i8", .tag = "!tbaa !20" },
    .{ .storage = "ptr", .tag = "!tbaa !22" },
};

/// The element tag of LLVM storage type `storage`, or the generic tag for any other type.
fn elementTag(storage: []const u8) []const u8 {
    for (element_tags) |entry| if (std.mem.eql(u8, entry.storage, storage)) return entry.tag;
    return tbaa_data;
}

/// The TBAA scaffold and the count range, as numbered above.
const tbaa_metadata =
    \\!1 = !{!"myl.tbaa"}
    \\!2 = !{!"myl.count", !1, i64 0}
    \\!3 = !{!2, !2, i64 0}
    \\!4 = !{!"myl.header", !1, i64 0}
    \\!5 = !{!4, !4, i64 0}
    \\!6 = !{!"myl.data", !1, i64 0}
    \\!7 = !{!6, !6, i64 0}
    \\!8 = !{i32 1, i32 0}
    \\!9 = !{!"branch_weights", i32 1, i32 2000}
    \\!10 = !{!"branch_weights", i32 2000, i32 1}
    \\!11 = !{!"myl.data.double", !6, i64 0}
    \\!12 = !{!11, !11, i64 0}
    \\!13 = !{!"myl.data.i64", !6, i64 0}
    \\!14 = !{!13, !13, i64 0}
    \\!15 = !{!"myl.data.i32", !6, i64 0}
    \\!16 = !{!15, !15, i64 0}
    \\!17 = !{!"myl.data.i16", !6, i64 0}
    \\!18 = !{!17, !17, i64 0}
    \\!19 = !{!"myl.data.i8", !6, i64 0}
    \\!20 = !{!19, !19, i64 0}
    \\!21 = !{!"myl.data.ptr", !6, i64 0}
    \\!22 = !{!21, !21, i64 0}
    \\!23 = !{!"branch_weights", i32 32, i32 1}
    \\
;
/// `  %x = load i64, ptr %at` of one data word (a union's tag word or payload word).
const word_load_line = "  {s} = load i64, ptr {s}, align 8, " ++ tbaa_data ++ "\n";
/// A union's tag word loaded from memory, then its tag byte.
const tag_load_line = word_load_line ++ "  {s} = trunc i64 {s} to i8\n";
/// Whether a union's tag byte names case `k`.
const case_test_line = "  {s} = icmp eq i8 {s}, {d}\n";
/// Non-tearing count reads after task publication; unordered preserves loop hoisting.
const count_load_line = "  {s} = load atomic i32, ptr {s} unordered, align 8, " ++ tbaa_count ++ ", " ++ count_range ++ "\n";
/// The header field loads of a list or string, tagged as header data.
const header_tagged_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8, " ++ tbaa_header ++ "\n";

/// `  %x = getelementptr inbounds i8, ptr %p, i64 0`: a second name for the same pointer.
const identity_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n";

/// One instruction line of the shape `  %x = op type a, b`.
/// Extract one constant-index aggregate component from a register value.
const extract_value_line = "  {s} = extractvalue {s} {s}, {d}\n";

const binary_line = "  {s} = {s} {s} {s}, {s}\n";

/// Render `module` as one LLVM IR module, including the C `main` entry.
/// Scratch uses the caller's allocator; arena callers retain its backing pages.
pub fn emitModule(allocator: std.mem.Allocator, module: *const ir.Module, options: Options) Error![]u8 {
    return emitModuleWithScratch(allocator, allocator, module, options);
}

/// Retain only the completed module in `allocator`; release scratch to `backing`.
pub fn emitModuleWithScratch(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: Options) Error![]u8 {
    return render(allocator, backing, module, options, null);
}

/// Functions and cross-unit ABI decisions for one independent LLVM module.
pub const Selection = struct {
    functions: []const u32,
    exported: []const bool,
    symbols: []const ?[]const u8,
    entry: bool = false,
    source_path: []const u8,
    constants: *const emit_constants.Catalog,
};

/// Retain only the completed unit in `allocator`; release scratch to `backing`.
pub fn emitUnitWithScratch(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: Options, selection: Selection) Error![]u8 {
    return render(allocator, backing, module, options, selection);
}

fn render(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, given: Options, selection: ?Selection) Error![]u8 {
    // This unit's names, block bodies, metadata and normalization buffers die
    // before linking. The caller supplies reclaiming backing independently of
    // its result arena, so scratch pages need not live until that build ends.
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    return allocator.dupe(u8, try renderScratch(scratch.allocator(), module, given, selection));
}

fn renderScratch(allocator: std.mem.Allocator, module: *const ir.Module, given: Options, selection: ?Selection) Error![]u8 {
    var options = given;
    if (options.analysis.effects == null) {
        const summaries = try allocator.create(effects.Summaries);
        summaries.* = try effects.analyze(allocator, module);
        options.analysis.effects = summaries;
    }
    var state: ModuleState = .{ .allocator = allocator, .module = module, .options = options, .local = .{ .selection = selection }, .debug = .{ .fallback = if (selection) |chosen| chosen.source_path else options.source_path } };
    var body: Out = .empty;
    if (selection) |chosen| {
        for (chosen.functions) |index| try renderFunction(&state, &body, index);
    } else for (module.functions.items, 0..) |_, index| try renderFunction(&state, &body, @intCast(index));
    if (selection == null or selection.?.entry) try state.emitEntry(&body);
    var out: Out = .empty;
    try out.appendSlice(allocator, "; generated by mylang-core\n");
    if (module.zero_rc) try out.appendSlice(allocator, "; mylang-zero-rc-v2\n");
    try out.appendSlice(allocator, "source_filename = \"");
    try escaped(allocator, &out, if (selection) |chosen| chosen.source_path else options.source_path);
    try out.appendSlice(allocator, "\"\n");
    try state.emitPrelude(&out, body.items);
    try out.appendSlice(allocator, body.items);
    try state.emitSites(&out);
    if (options.counters) try state.count.render(allocator, &out);
    try state.emitStrings(&out);
    try out.appendSlice(allocator, metadata);
    try out.appendSlice(allocator, tbaa_metadata);
    try out.appendSlice(allocator, state.meta.ranges.items);
    try out.appendSlice(allocator, state.layouts.text.items);
    if (selection == null) try emit_values.descriptors(allocator, module, &out);
    try out.appendSlice(allocator, call_attributes);
    if (state.local.zeros != 0) try out.print(allocator, "@myl.zeros = private constant [{d} x i8] zeroinitializer, align 8\n", .{state.local.zeros});
    try state.debug.finish(allocator, &out);
    if (module.zero_rc and !zero_rc.emittedClean(out.items)) return error.UnsupportedInstruction;
    if (selection) |chosen| return chosen.constants.finish(allocator, out.items);
    return out.toOwnedSlice(allocator);
}

fn renderFunction(state: *ModuleState, body: *Out, index: u32) Error!void {
    const function = &state.module.functions.items[index];
    if (function.signature.linkage != .internal) {
        if (state.local.selection != null) {
            _ = try emit_values.adapterNamed(state.allocator, body, function, .{ .symbol = state.functionName(index), .linkage = state.linkage(index) });
        } else try state.declareExtern(index);
        return;
    }
    var emitter: FunctionEmitter = .{ .state = state, .function = function, .index = index };
    if (index < state.options.analysis.vectors.len) emitter.vectors.plans = state.options.analysis.vectors[index];
    try emitter.emitFunction(body);
}

/// Module-wide numbering: `!range` nodes (after the fixed TBAA nodes; `!0` is the
/// trap branch weight) and vector loops.
const Metadata = struct {
    ranges: Out = .empty,
    range_count: u32 = first_range_node,
    vector_count: u32 = 0,
};

const Literal = struct { original: u32, raw: bool };
const Local = struct {
    selection: ?Selection = null,
    strings: std.ArrayList(Literal) = .empty,
    dictionaries: std.ArrayList(ir.Type) = .empty,
    zeros: u32 = 0,
};

const ModuleState = struct {
    allocator: std.mem.Allocator,
    module: *const ir.Module,
    options: Options,
    sites: std.ArrayList(Site) = .empty,
    externs: Out = .empty,
    /// The C symbols already declared in `externs`.
    declared: std.ArrayList([]const u8) = .empty,
    meta: Metadata = .{},
    /// The `alloca`s of the function being emitted, placed in its entry block.
    allocas: Out = .empty,
    /// Element layouts of lists and boxes whose elements hold blocks.
    layouts: Layouts = .{},
    /// DWARF line tables for trap frames (`Traps.dwarf_lines`).
    debug: Debug = .{},
    /// Selection and first-use numbering local to this LLVM module.
    local: Local = .{},
    /// Counter sites and function records of a counting build (`emit_count.zig`).
    count: emit_count.Table = .{},
    /// Per internal function already asked: the parameter its callers may pass in its `%ret`, or
    /// `emit_homes.none` (`FunctionEmitter.sharedArgument`).
    shares: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    fn contains(self: *ModuleState, index: u32) bool {
        const selected = self.local.selection orelse return true;
        return std.mem.indexOfScalar(u32, selected.functions, index) != null;
    }

    fn linkage(self: *ModuleState, index: u32) []const u8 {
        const selected = self.local.selection orelse return internal_linkage;
        return if (selected.exported[index]) "hidden" else internal_linkage;
    }

    fn functionName(self: *ModuleState, index: u32) []const u8 {
        if (self.local.selection) |selected| if (selected.symbols[index]) |name| return name;
        return self.module.functions.items[index].name;
    }

    fn originalSymbol(self: *ModuleState, index: u32) ![]const u8 {
        const function = &self.module.functions.items[index];
        return if (function.signature.linkage == .internal) symbol(self.allocator, self.functionName(index)) else std.fmt.allocPrint(self.allocator, "@{s}", .{c_abi.symbol(self.functionName(index))});
    }

    fn dependency(self: *ModuleState, index: u32) !void {
        if (self.contains(index)) return;
        const function = &self.module.functions.items[index];
        if (function.signature.linkage != .internal) return self.declareExtern(index);
        const name = try self.originalSymbol(index);
        for (self.declared.items) |known| if (std.mem.eql(u8, known, name)) return;
        try self.declared.append(self.allocator, name);
        const abi = inOutAbi(self.module, function.signature);
        const sret = returnsThroughSret(self.module, function.signature, abi);
        try self.externs.print(self.allocator, "declare hidden fastcc {s} {s}(", .{ try self.returnType(function.signature, abi), name });
        if (sret) try self.externs.print(self.allocator, "ptr noalias sret({s}) align 8", .{try self.memoryType(function.signature.ret)});
        for (function.signature.params, 0..) |param, i| try self.externs.print(self.allocator, "{s}{s}", .{ if (i == 0 and !sret) "" else ", ", try self.llvmType(param) });
        try self.externs.appendSlice(self.allocator, ") nounwind\n");
    }

    /// The LLVM return type of an internal function: `void` when the result travels through
    /// `sret` or is the final value of its one in-out parameter.
    fn returnType(self: *ModuleState, signature: ir.Signature, abi: InOutAbi) ![]const u8 {
        if (abi.whole or self.module.passedInMemory(signature.ret)) return "void";
        return self.llvmType(signature.ret);
    }

    fn declareExtern(self: *ModuleState, index: u32) !void {
        if (try @import("borrow_selection.zig").declaration(self.module, &self.module.functions.items[index])) return;
        const function = &self.module.functions.items[index];
        return self.external(function, self.functionName(index));
    }

    fn external(self: *ModuleState, function: *const ir.Function, name: []const u8) !void {
        if (try @import("aggregate_provider.zig").marker(self.module, function)) return;
        if (self.local.selection == null and try emit_values.adapter(self.allocator, &self.externs, function)) return;
        // Several signatures of one runtime function (`myl_core_list_sort` over lists of different
        // elements) are one declaration.
        const symbol_name = c_abi.symbol(name);
        if (std.mem.eql(u8, symbol_name, flags.str_eq_symbol)) return;
        for (self.declared.items) |known| if (std.mem.eql(u8, known, symbol_name)) return;
        try self.declared.append(self.allocator, symbol_name);
        const returns = try self.llvmType(function.signature.ret);
        try self.externs.print(self.allocator, "declare {s}{s}{s} @{s}(", .{ if (emit_values.generated(function)) "hidden fastcc " else "", if (function.signature.ret == .bool) "zeroext " else "", returns, symbol_name });
        var first = true;
        const c_function = function.signature.linkage == .extern_c;
        for (function.signature.params, 0..) |param, i| {
            if (function.signature.linkage == .extern_c and !c_abi.passes(param)) continue;
            const span = i < 64 and function.signature.views & (@as(u64, 1) << @intCast(i)) != 0;
            const extension = if (c_function) c_abi.argumentExtension(param) else "";
            try self.externs.print(self.allocator, "{s}{s}{s}{s}", .{ if (first) "" else ", ", if (span) "ptr, i64" else try self.llvmType(param), if (extension.len == 0) "" else " ", extension });
            first = false;
        }
        // The runtime's string helpers only read their arguments, so LLVM may merge and hoist calls.
        try self.externs.appendSlice(self.allocator, if (flags.readsOnly(c_abi.symbol(function.name))) ") nounwind willreturn memory(argmem: read)\n" else ") nounwind\n");
    }

    /// A `!range` node for `[lo, hi]` in a `bits`-wide integer.
    fn rangeNode(self: *ModuleState, bits: u16, range: facts.Interval) ![]const u8 {
        self.meta.range_count += 1;
        try self.meta.ranges.print(self.allocator, "!{d} = !{{i{d} {d}, i{d} {d}}}\n", .{ self.meta.range_count, bits, range.lo, bits, range.hi + 1 });
        return std.fmt.allocPrint(self.allocator, ", !range !{d}", .{self.meta.range_count});
    }

    /// The `@myl.layout.N` constant for elements of `ty` (a managed type), emitted once.
    fn layoutSymbol(self: *ModuleState, ty: ir.Type) ![]const u8 {
        for (self.layouts.types.items, 0..) |known, i| {
            if (known == ty) return std.fmt.allocPrint(self.allocator, "@myl.layout.{d}", .{i});
        }
        var parts: LayoutParts = .{};
        try layoutParts(self.allocator, self.module, ty, 0, 0, &parts);
        const index = self.layouts.types.items.len;
        try self.layouts.types.append(self.allocator, ty);
        const name = try std.fmt.allocPrint(self.allocator, "@myl.layout.{d}", .{index});
        try emit_release.emit(self.allocator, &self.layouts.text, name, @max(1, self.module.size(ty)), .{ .refs = parts.refs.items, .guards = parts.guards.items, .zero_rc = self.module.zero_rc });
        return name;
    }

    /// Register a trap site for an operation sub-emitter.
    fn site(self: *ModuleState, s: Site) !u32 {
        try self.sites.append(self.allocator, s);
        return @intCast(self.sites.items.len - 1);
    }

    fn literal(self: *ModuleState, index: u32, raw: bool) ![]const u8 {
        for (self.local.strings.items, 0..) |*known, i| {
            if (!std.mem.eql(u8, self.module.strings.items[known.original], self.module.strings.items[index])) continue;
            known.raw = known.raw or raw;
            return std.fmt.allocPrint(self.allocator, "@myl.str.{d}", .{i});
        }
        const local = self.local.strings.items.len;
        try self.local.strings.append(self.allocator, .{ .original = index, .raw = raw });
        return std.fmt.allocPrint(self.allocator, "@myl.str.{d}", .{local});
    }

    /// The LLVM spelling of a Core type.
    fn llvmType(self: *ModuleState, ty: ir.Type) ![]const u8 {
        return switch (ty) {
            .void => "void",
            .bool => "i1",
            .i8, .u8 => "i8",
            .i16, .u16 => "i16",
            .i32, .u32 => "i32",
            .i64, .u64, .cap => "i64",
            .f64 => "double",
            .str, .bytes, .byte_buffer, .capability, .resource => "ptr",
            .str_view => "{ ptr, i64 }",
            _ => switch (self.module.compound(ty)) {
                .list, .box, .dict, .@"fn" => "ptr",
                .array => |array| if (self.module.passedInMemory(ty)) "ptr" else std.fmt.allocPrint(self.allocator, "[{d} x {s}]", .{ array.n, try self.llvmType(array.elem) }),
                .record => |fields| blk: {
                    // Over four words a value lives in memory (a stack slot): its SSA value is the pointer.
                    if (self.module.passedInMemory(ty)) break :blk "ptr";
                    var text: Out = .empty;
                    try text.appendSlice(self.allocator, "{ ");
                    for (fields, 0..) |field, i| try text.print(self.allocator, "{s}{s}", .{ if (i == 0) "" else ", ", try self.llvmType(field) });
                    try text.appendSlice(self.allocator, if (fields.len == 0) "}" else " }");
                    break :blk text.items;
                },
                .@"union" => blk: {
                    if (self.module.passedInMemory(ty)) break :blk "ptr";
                    const layout = self.module.unionLayout(ty);
                    break :blk switch (layout.form) {
                        .niche => "ptr",
                        .scalar => std.fmt.allocPrint(self.allocator, "{{ i8, {s} }}", .{try self.llvmType(layout.payload)}),
                        .words => std.fmt.allocPrint(self.allocator, "{{ i8, [{d} x i64] }}", .{layout.payload_words}),
                    };
                },
            },
        };
    }

    /// `[S x i8]`: the memory image of a value of `ty`, for `sret` and argument slots.
    fn memoryType(self: *ModuleState, ty: ir.Type) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "[{d} x i8]", .{self.module.size(ty)});
    }

    /// Bytes between consecutive list elements of type `ty`.
    fn stride(self: *ModuleState, ty: ir.Type) u32 {
        return @max(1, self.module.size(ty));
    }

    fn emitPrelude(self: *ModuleState, out: *Out, body: []const u8) !void {
        try out.appendSlice(self.allocator,
            \\%myl.site = type { i32, i32, i32, i32, ptr, ptr, ptr }
            \\declare void @myl_core_trap(ptr, i64, i64) noreturn nounwind cold
            \\declare ptr @myl_core_args(i32, ptr) nounwind
            \\declare i32 @myl_core_exit(i64) nounwind
            \\declare void @myl_core_start() nounwind
            \\declare void @myl_core_s2_unsupported(i32) noreturn nounwind cold
            \\declare ptr @myl_core_dict_new(i64, ptr) nounwind
            \\declare i32 @llvm.cttz.i32(i32, i1 immarg) nounwind readnone
            \\declare void @myl_core_span_split_fill(ptr, i64, ptr, i64, ptr, i64) nounwind
            \\declare ptr @memchr(ptr, i32, i64) nounwind willreturn memory(argmem: read)
            \\declare zeroext i1 @myl_core_str_eq(ptr, ptr) nounwind
            \\declare i32 @myl_core_str_hash(ptr) nounwind
            \\declare void @llvm.memset.p0.i64(ptr, i8, i64, i1) nounwind
            \\declare i64 @myl_core_dict_hash(ptr, ptr) nounwind
            \\declare i64 @myl_core_dict_find_span(ptr, ptr, i64) nounwind
            \\declare i64 @myl_core_dict_find(ptr, ptr, i64) nounwind willreturn memory(argmem: read)
            \\declare ptr @myl_core_dict_set(ptr, i64, ptr) nounwind
            \\declare ptr @myl_core_dict_insert(ptr, i64, ptr, ptr, i1 zeroext) nounwind
            \\declare ptr @myl_core_dict_remove_parts(ptr, i64, i32)
            \\declare ptr @myl_core_dict_remove(ptr, i64) nounwind
            \\declare ptr @myl_core_dict_copy(ptr) nounwind
            \\declare ptr @myl_core_dict_clear(ptr) nounwind
            \\declare i64 @myl_core_dict_entries(ptr) nounwind willreturn memory(argmem: read)
            \\declare zeroext i1 @myl_core_dict_live(ptr, i64) nounwind willreturn memory(argmem: read)
            \\declare ptr @myl_core_ir_str_char(ptr, i64) nounwind
            \\declare i64 @myl_core_ir_str_width(ptr, i64) nounwind
            \\declare i32 @myl_core_ir_str_code(ptr, i64) nounwind
            \\declare ptr @myl_core_ir_str_append(ptr, ptr) nounwind
            \\declare ptr @myl_core_ir_str_append_char(ptr, ptr, i64) nounwind
            \\declare ptr @myl_core_ir_str_slice(ptr, i64, i64) nounwind
            \\declare ptr @myl_core_ir_str_from_view(ptr, i64) nounwind
            \\declare { i64, i64 } @myl_core_ir_str_slice_span(ptr, i64, i64) nounwind
            \\declare ptr @myl_core_ir_str_from_span(ptr, i64, i1 zeroext) nounwind
            \\declare ptr @myl_core_s2_sort_in_place(ptr, i64, i1 zeroext) nounwind
            \\declare ptr @myl_core_list_copy(ptr, i64) nounwind
            \\declare zeroext i1 @myl_core_str_parse_int(ptr, ptr) nounwind
            \\declare zeroext i1 @myl_core_span_parse_int(ptr, i64, ptr) nounwind
            \\declare void @myl_core_print_i64(i64, i64) nounwind
            \\declare void @myl_core_print_u64(i64, i64) nounwind
            \\declare void @myl_core_print_bool(i64, i1 zeroext) nounwind
            \\declare void @myl_core_print_str(i64, ptr) nounwind
            \\declare void @myl_core_print_view(i64, ptr, i64) nounwind
            \\declare void @myl_core_print_sep(i64) nounwind
            \\declare void @myl_core_print_end(i64) nounwind
            \\declare ptr @myl_core_box_new(i64) nounwind
            \\declare preserve_mostcc void @myl_core_err_trace_origin_preserve_most(ptr) nounwind cold
            \\declare preserve_mostcc void @myl_core_err_trace_append_preserve_most(ptr) nounwind cold
            \\declare void @myl_core_assert_fail(ptr) noreturn nounwind cold
            \\declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg)
            \\declare void @llvm.memmove.p0.p0.i64(ptr nocapture writeonly, ptr nocapture readonly, i64, i1 immarg)
            \\declare void @myl_core_release_child_pending(ptr, ptr) nounwind
            \\declare void @myl_core_release(ptr) nounwind
            \\declare void @myl_core_main_error_i64(i64) nounwind cold
            \\declare void @myl_core_main_error_u64(i64) nounwind cold
            \\declare void @myl_core_main_error_bool(i1 zeroext) nounwind cold
            \\declare void @myl_core_main_error_str(ptr) nounwind cold
            \\
        );
        if (self.options.counters) try out.appendSlice(self.allocator, emit_count.declarations);
        try out.appendSlice(self.allocator, task_bridge);
        if (self.module.zero_rc) try out.appendSlice(self.allocator, "declare void @myl_core_drop_owned(ptr) nounwind\ndeclare void @myl_core_box_drop_shell(ptr) nounwind\n");
        const prelude = if (self.options.counters) emit_count.fast_paths else runtime_fast_paths;
        const paths = if (self.module.zero_rc) try zero_rc.fastPaths(self.allocator, prelude) else prelude;
        try fastPaths(self.allocator, out, paths, body, self.layouts.text.items);
        try out.appendSlice(self.allocator, self.externs.items);
        var number: Out = .empty;
        try emit_number.prelude(self.allocator, &number);
        try fastPaths(self.allocator, out, number.items, body, self.layouts.text.items);
        try emit_bytes.prelude(self.allocator, out);
        if (self.module.zero_rc) zero_rc.stripRcDeclarations(out);
    }

    fn emitSites(self: *ModuleState, out: *Out) !void {
        for (self.sites.items, 0..) |s, i| {
            const path = if (s.location.path.len != 0) s.location.path else self.options.source_path;
            try out.print(self.allocator, "@myl.path.{d} = private constant [{d} x i8] c\"", .{ i, path.len + 1 });
            try escaped(self.allocator, out, path);
            try out.appendSlice(self.allocator, nul_terminator);
            try out.print(self.allocator, "@myl.op.{d} = private constant [{d} x i8] c\"", .{ i, s.operation.len + 1 });
            try escaped(self.allocator, out, s.operation);
            try out.appendSlice(self.allocator, nul_terminator);
            try out.print(self.allocator, "@myl.fn.{d} = private constant [{d} x i8] c\"", .{ i, s.function.len + 1 });
            try escaped(self.allocator, out, s.function);
            try out.appendSlice(self.allocator, nul_terminator);
            try out.print(self.allocator, "@myl.site.{d} = private constant %myl.site {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, " ++
                "ptr @myl.op.{d}, ptr @myl.fn.{d}, ptr @myl.path.{d} }}\n", .{ i, @backingInt(s.kind), s.location.line, s.location.column, s.width, i, i, i });
        }
    }

    /// String constants are immortal blocks: the count is saturated (D4), so no release frees them.
    fn emitStrings(self: *ModuleState, out: *Out) !void {
        for (self.local.strings.items, 0..) |literal_info, i| {
            const bytes = self.module.strings.items[literal_info.original];
            const block_type = try std.fmt.allocPrint(self.allocator, "{{ i32, i32, i64, i64, i64, [{d} x i8] }}", .{bytes.len + 1});
            try out.print(self.allocator, "@myl.str.{d} = private unnamed_addr constant {s} ", .{ i, block_type });
            const cached = text_builder.metadata(bytes);
            const kind = (if (literal_info.raw) (cached.kind & ~@as(u32, 255)) | 3 else cached.kind) | @as(u32, if (self.module.zero_rc) 1 << 23 else 0);
            const first: i64 = if (self.module.zero_rc) kind else -1;
            const second: u32 = if (self.module.zero_rc) 0 else kind;
            try out.print(self.allocator, "{{ i32 {d}, i32 {d}, i64 {d}, i64 {d}, i64 {d}, [{d} x i8] c\"", .{ first, second, bytes.len, bytes.len, cached.meta, bytes.len + 1 });
            try escaped(self.allocator, out, bytes);
            try out.appendSlice(self.allocator, "\\00\" }, align 32\n");
        }
    }

    /// `int main(argc, argv)`: build the arguments `main` asks for, call it, release
    /// the arguments (`main` borrows them) and exit with its status. A `main` returning
    /// a `Result` reports an `Err` with its trace first (RESULT-MAIN-1/2, ERROR-TRACE-2).
    fn emitEntry(self: *ModuleState, out: *Out) !void {
        const entry = &self.module.functions.items[self.module.entry];
        try self.dependency(self.module.entry);
        // `dwarf_lines`: the C entry has a subprogram too (named `myl.entry`, which trap
        // frames never print), or inlining `main` into it would drop every location.
        var at: []const u8 = "";
        var scope: []const u8 = "";
        if (self.options.target.traps == .dwarf_lines) {
            const node = try self.debug.subprogram(self.allocator, "myl.entry", .{ .line = 1, .column = 1, .path = self.options.source_path });
            scope = try std.fmt.allocPrint(self.allocator, function_scope, .{node});
            at = try std.fmt.allocPrint(self.allocator, instruction_location, .{try self.debug.location(self.allocator, .{ .line = 1, .column = 1 }, node)});
        }
        try out.print(self.allocator, "define i32 @main(i32 %argc, ptr %argv) uwtable{s} {{\nentry:\n", .{scope});
        if (self.options.main.runtime_options) try out.appendSlice(self.allocator, "  call void @myl_core_start()\n");
        var arguments: Out = .empty;
        var owns_args = false;
        var cleanup: Out = .empty;
        for (entry.signature.params, 0..) |param, i| {
            if (i != 0) try arguments.appendSlice(self.allocator, ", ");
            if (param == .capability) {
                try arguments.appendSlice(self.allocator, try emit_cap.entry(self, out, &cleanup, i));
            } else if (param == .cap) {
                if (try emit_cap.token(self, out, i)) |token| {
                    try arguments.appendSlice(self.allocator, token);
                    continue;
                }
                const name = if (i < self.options.main.parameters.len) self.options.main.parameters[i] else "";
                try arguments.print(self.allocator, "i64 {d}", .{@as(u8, if (std.mem.eql(u8, name, "err")) 2 else 1)});
            } else if (param.isCompound() and self.module.compound(param) == .list and self.module.compound(param).list == .str) {
                try out.appendSlice(self.allocator, "  %args = call ptr @myl_core_args(i32 %argc, ptr %argv)\n");
                try arguments.appendSlice(self.allocator, "ptr %args");
                owns_args = true;
            } else return error.UnsupportedEntry;
        }
        if (owns_args) try cleanup.appendSlice(self.allocator, if (self.module.zero_rc) "  call void @myl_core_drop_owned(ptr %args)\n" else "  call void @myl_core_release(ptr %args)\n");
        const release_args = cleanup.items;
        const ret = entry.signature.ret;
        const callee = try symbol(self.allocator, entry.name);
        const tail = if (self.options.target.traps == .dwarf_lines) "notail " else "";
        if (ret == .void) {
            try out.print(self.allocator, "  {s}call fastcc void {s}({s}){s}\n{s}  %s = call i32 @myl_core_exit(i64 0)\n", .{ tail, callee, arguments.items, at, release_args });
        } else if (ret == .i64) {
            try out.print(self.allocator, "  %r = {s}call fastcc i64 {s}({s}){s}\n{s}  %s = call i32 @myl_core_exit(i64 %r)\n", .{ tail, callee, arguments.items, at, release_args });
        } else if (self.options.main.result != null and self.module.kind(ret) == .@"union" and !self.module.passedInMemory(ret)) {
            try out.print(self.allocator, "  %r = {s}call fastcc {s} {s}({s}){s}\n", .{ tail, try self.llvmType(ret), callee, arguments.items, at });
            return self.resultEntry(out, ret, release_args);
        } else return error.UnsupportedEntry;
        try out.appendSlice(self.allocator, "  ret i32 %s\n}\n");
    }

    /// The rest of the entry for `%r`, a `Result` returned by `main`: `Ok(code)` exits
    /// with `code` (`Ok(None)` with 0); `Err(value)` writes `error: VALUE` and the
    /// trace, releases the value and exits with it when it is an integer, else 1.
    fn resultEntry(self: *ModuleState, out: *Out, ret: ir.Type, release_args: []const u8) !void {
        const shape = self.options.main.result.?;
        const cases = self.module.compound(ret).@"union";
        if (shape.ok_tag >= cases.len or shape.error_tag >= cases.len) return error.UnsupportedEntry;
        const ok_type = cases[shape.ok_tag];
        const error_type = cases[shape.error_tag];
        if (ok_type != .void and ok_type.integer() == null) return error.UnsupportedEntry;
        if (error_type != .bool and error_type != .str and error_type.integer() == null) return error.UnsupportedEntry;
        const layout = self.module.unionLayout(ret);
        var helper: FunctionEmitter = .{ .state = self, .function = &self.module.functions.items[self.module.entry], .index = self.module.entry };
        self.allocas = .empty;
        var body: Out = .empty;
        if (layout.form == .niche) {
            try body.print(self.allocator, "  %failed = icmp {s} ptr %r, null\n", .{if (layout.empty_case == shape.error_tag) "eq" else "ne"});
        } else {
            try body.print(self.allocator, "  %tag = extractvalue {s} %r, 0\n  %failed = icmp eq i8 %tag, {d}\n", .{ try self.llvmType(ret), shape.error_tag });
        }
        try body.appendSlice(self.allocator, "  br i1 %failed, label %failed.main, label %ok.main\nok.main:\n");
        if (ok_type == .void) {
            try body.print(self.allocator, "{s}  %s = call i32 @myl_core_exit(i64 0)\n  ret i32 %s\n", .{release_args});
        } else {
            try helper.unionPayload(&body, .{ .result = "%ok", .union_type = ret, .value = "%r", .case = shape.ok_tag });
            try body.print(self.allocator, "  %code = {s} {s} %ok to i64\n{s}  %s = call i32 @myl_core_exit(i64 %code)\n  ret i32 %s\n", .{ widening(ok_type), try self.llvmType(ok_type), release_args });
        }
        try body.appendSlice(self.allocator, "failed.main:\n");
        try helper.unionPayload(&body, .{ .result = "%error", .union_type = ret, .value = "%r", .case = shape.error_tag });
        if (error_type == .str) {
            const destroy = if (self.module.zero_rc) "myl_core_drop_owned" else "myl_core_release";
            try body.print(self.allocator, "  call void @myl_core_main_error_str(ptr %error)\n  call void @{s}(ptr %error)\n{s}  %e = call i32 @myl_core_exit(i64 1)\n", .{ destroy, release_args });
        } else if (error_type == .bool) {
            try body.print(self.allocator, "  call void @myl_core_main_error_bool(i1 zeroext %error)\n{s}  %e = call i32 @myl_core_exit(i64 1)\n", .{release_args});
        } else {
            const info = error_type.integer().?;
            const report = "  %status = {s} {s} %error to i64\n  call void @myl_core_main_error_{s}(i64 %status)\n{s}  %e = call i32 @myl_core_exit(i64 %status)\n";
            try body.print(self.allocator, report, .{ widening(error_type), try self.llvmType(error_type), if (info.signed) "i64" else "u64", release_args });
        }
        try body.appendSlice(self.allocator, "  ret i32 %e\n}\n");
        try out.appendSlice(self.allocator, self.allocas.items);
        try out.appendSlice(self.allocator, body.items);
    }
};

/// `sext` or `zext` an integer of `ty` to `i64` (`add` for `i64` itself is not a cast,
/// so a 64-bit value uses the no-op `sext i64 … to i64`'s spelling `bitcast`).
fn widening(ty: ir.Type) []const u8 {
    const info = ty.integer().?;
    if (info.bits == 64) return "bitcast";
    return if (info.signed) "sext" else "zext";
}

// ---- element layouts (lane O: the runtime's free and copy read them) ----------------

/// The `@myl.layout.N` constants of a module: per managed element type, where its
/// blocks are (`runtime/core_rt.c`, "element layouts").
const Layouts = struct {
    types: std.ArrayList(ir.Type) = .empty,
    text: Out = .empty,
};

/// One element's block references and the union-tag guards they depend on.
const LayoutParts = struct {
    refs: std.ArrayList([2]u32) = .empty,
    guards: std.ArrayList([3]u32) = .empty,
};

/// Collect the block pointers in a value of `ty` stored at `base`, each counted only under `guard`.
fn layoutParts(allocator: std.mem.Allocator, module: *const ir.Module, ty: ir.Type, base: u32, guard: u32, parts: *LayoutParts) std.mem.Allocator.Error!void {
    if (!module.managed(ty)) return;
    if (module.isBlock(ty)) return parts.refs.append(allocator, .{ base, guard });
    switch (module.compound(ty)) {
        .record => |fields| for (fields, 0..) |field, i| try layoutParts(allocator, module, field, base + module.fieldOffset(ty, i), guard, parts),
        .@"union" => |cases| {
            const layout = module.unionLayout(ty);
            // A niche pointer may be null, which the runtime skips.
            if (layout.form == .niche) return parts.refs.append(allocator, .{ base, guard });
            for (cases, 0..) |case, k| {
                if (!module.managed(case)) continue;
                try parts.guards.append(allocator, .{ base, @intCast(k), guard });
                try layoutParts(allocator, module, case, base + 8, @intCast(parts.guards.items.len), parts);
            }
        },
        .array => |array| for (0..array.n) |i| try layoutParts(allocator, module, array.elem, base + @as(u32, @intCast(i)) * module.size(array.elem), guard, parts),
        .list, .box, .dict, .@"fn" => unreachable,
    }
}

fn escaped(allocator: std.mem.Allocator, out: *Out, text: []const u8) !void {
    for (text) |byte| {
        if (byte < 0x20 or byte >= 0x7f or byte == '"' or byte == '\\') try out.print(allocator, "\\{X:0>2}", .{byte}) else try out.append(allocator, byte);
    }
}

/// The LLVM symbol of a mylang function.
fn symbol(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "@\"my.{s}\"", .{name});
}

/// The vectorized loops of one function, and the header phi values their vector parts resume with.
const VectorState = struct {
    plans: []const vector.Plan = &.{},
    /// Header phi → the value it takes on the edge from the vector part.
    resume_values: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,
    /// The IR block whose body is being rendered.
    block: u32 = 0,
};

/// What the emitter knows about the values that live in memory (records and unions over four
/// words, docs/design/new-core-s1.md §3): which constructions are stored straight into their
/// consumer, which home each value lives in (`emit_homes.zig`), how each call passes its in-out
/// arguments, and how edges were split to fill phis.
const MemoryState = struct {
    /// Per instruction: a `record_make` or `union_make` that is never materialized, because its
    /// only use stores it into its destination field by field.
    fused: []bool = &.{},
    /// Verify-only length snapshots, taken before ordinary ownership can release a bound's block.
    bound_lengths: []bool = &.{},
    /// Per block: the phis whose type lives in memory.
    phis: []const []const ir.Ref = &.{},
    /// The label of the block that fills a memory phi on an edge `pred << 32 | block`, where the edge was split.
    edges: std.AutoHashMapUnmanaged(u64, []const u8) = .empty,
    /// The home of every value in memory, and the views read where they lie.
    homes: emit_homes.Plan = .{ .class = &.{}, .view = &.{}, .homes = &.{}, .view_offset = &.{} },
    /// Per instruction: the in-out calls (CE-A P7).
    in_out: InOutCalls = .{},
    /// Per instruction: the uses of its value (a read nothing uses emits only its check, CE-B).
    uses: []u32 = &.{},
    /// Per instruction: a list element over four words lent to calls where it lies (CE2-B).
    borrowed: []bool = &.{},
    /// The lists and buffers whose length a loop keeps in slots while it appends (`emit_state.zig`).
    states: emit_state.Plan = .{},
    /// Per instruction: the index the program wrote, when it is a Python index normalization
    /// phi (`facts.normalizedRaw`), else `.none` (NEW-CORE-F2-WRAP-1).
    from_end: []ir.Ref = &.{},
    /// A normalized index's checked value (`checkedIndex`), by the written index's key and its
    /// list's length key: the LLVM value and the IR block it was made in, for the later
    /// accesses that block dominates.
    checked: std.AutoHashMapUnmanaged(NormalizedKey, CheckedIndex) = .empty,
    /// Dominators of the IR blocks (`facts.shape`), for `checked`.
    shape: ?facts.Shape = null,
    /// Value and length identities (`index_keys`), for `checked`.
    keys: ?index_keys.Keys = null,
};

/// A written index normalized against a list's length: equal keys, equal normalized values.
const NormalizedKey = struct { index: index_keys.IndexKey, length: index_keys.Key };

/// One normalized index a checked access made (NEW-CORE-F2-WRAP-1).
const CheckedIndex = struct { name: []const u8, block: u32 };

/// Per instruction, what an in-out call (CE-A P7) needs: its in-out arguments, and whether its
/// result record must also hold the final values.
const InOutCalls = struct {
    /// A call's in-out arguments, empty for every other instruction.
    args: []const []const emit_homes.InOut = &.{},
    /// An in-out call whose result record must also hold the final values (something reads it
    /// other than one `record_get` per final value).
    complete: []bool = &.{},
};

/// How a signature passes its `mut` parameters over four words (CE-A P7): by a pointer to the
/// caller's memory, which the callee updates in place to the parameter's final value. The IR
/// result still names that value (a `mut` parameter returns its final value, build.zig
/// `returnType`), but no copy of it crosses the call: the caller reads it where it passed it.
const InOutAbi = struct {
    /// Bit `i`: parameter `i` is in-out.
    params: u64 = 0,
    /// The result is the one in-out parameter's final value: the function returns nothing.
    whole: bool = false,
    /// The result record's field that holds the first `mut` parameter's final value (0, or 1
    /// after the declared result); the others follow in parameter order.
    first: u32 = 0,

    /// Whether parameter `param` is in-out (a signature of 64 or more parameters has none).
    fn inOut(self: InOutAbi, param: usize) bool {
        return param < 64 and self.params & (@as(u64, 1) << @intCast(param)) != 0;
    }

    /// The result record's field holding parameter `param`'s final value.
    fn field(self: InOutAbi, signature: ir.Signature, param: usize) u32 {
        const below = signature.owned & ((@as(u64, 1) << @intCast(param)) - 1);
        return self.first + @popCount(below);
    }
};

/// The in-out ABI of an internal signature whose result follows the `mut` convention (the
/// final value of each `mut` parameter, after the declared result unless that is `unit`);
/// every other signature passes nothing in-out.
fn inOutAbi(m: *const ir.Module, signature: ir.Signature) InOutAbi {
    if (!emit_homes.steps.in_out or signature.linkage != .internal or signature.owned == 0) return .{};
    if (signature.params.len > 63 or signature.owned >> @intCast(signature.params.len) != 0) return .{};
    const muts: u32 = @popCount(signature.owned);
    var abi: InOutAbi = .{};
    if (muts == 1) {
        const only: usize = @ctz(signature.owned);
        if (signature.ret == signature.params[only]) {
            if (!m.passedInMemory(signature.ret)) return .{};
            return .{ .params = signature.owned, .whole = true };
        }
    }
    if (m.kind(signature.ret) != .record) return .{};
    const fields = m.compound(signature.ret).record;
    if (fields.len != muts and fields.len != muts + 1) return .{};
    if (fields.len == muts and muts < 2) return .{};
    abi.first = @intCast(fields.len - muts);
    for (signature.params, 0..) |param, i| {
        if (signature.owned & (@as(u64, 1) << @intCast(i)) == 0) continue;
        if (fields[abi.field(signature, i)] != param) return .{};
        if (m.passedInMemory(param)) abi.params |= @as(u64, 1) << @intCast(i);
    }
    return abi;
}

/// Whether a value of `ty` travels through `sret` under `abi`.
fn returnsThroughSret(m: *const ir.Module, signature: ir.Signature, abi: InOutAbi) bool {
    return m.passedInMemory(signature.ret) and !abi.whole;
}

/// The read-only memory parameter of an internal function's result type that its callers may pass
/// in their `sret` destination, if its plan allows it (`emit_homes.Planner.shareable`): the first
/// one, of a function with no in-out parameter; `none` otherwise.
fn shareCandidate(m: *const ir.Module, signature: ir.Signature, abi: InOutAbi) u32 {
    if (!emit_homes.steps.share_sret) return emit_homes.none;
    if (signature.linkage != .internal or abi.params != 0 or !returnsThroughSret(m, signature, abi)) return emit_homes.none;
    for (signature.params, 0..) |param, i| {
        if (i >= 64) break;
        if (param == signature.ret and (signature.owned | signature.consumes) & (@as(u64, 1) << @intCast(i)) == 0) return @intCast(i);
    }
    return emit_homes.none;
}

/// Bit `k`: field `k` of the result record holds an in-out final value, which a `ret` moves to
/// its caller's memory instead of storing it in `%ret` (`FunctionEmitter.returnFinals`).
fn finalFields(signature: ir.Signature, abi: InOutAbi) u64 {
    if (abi.params == 0 or abi.whole) return 0;
    var bits: u64 = 0;
    for (0..signature.params.len) |i| {
        if (abi.inOut(i)) bits |= @as(u64, 1) << @intCast(abi.field(signature, i));
    }
    return bits;
}

/// Which count update `counted` emits.
const Counting = enum { retain, release };

/// One managed part of a value a store replaces, read before the store and released after
/// it; `guard` is the union-case condition under which it is live, or null.
const Held = struct { ty: ir.Type, text: []const u8, guard: ?[]const u8 = null };

/// One `union_payload` read: the name it defines, the union's type and value, and the case.
const PayloadRead = struct { result: []const u8, union_type: ir.Type, value: []const u8, case: u32 };

/// The operands of one floor division or remainder.
const FloorOperands = struct { result: []const u8, type_name: []const u8, left: []const u8, right: []const u8, safe: []const u8, is_rem: bool };

const FunctionEmitter = struct {
    state: *ModuleState,
    function: *const ir.Function,
    index: u32,
    /// The label each IR block's code ends in (its phis' predecessor name).
    exit_labels: std.ArrayList([]const u8) = .empty,
    /// Unique suffix for split blocks and temporaries.
    counter: u32 = 0,
    /// The label the body being rendered currently ends in.
    label: []const u8 = "",
    vectors: VectorState = .{},
    memory: MemoryState = .{},
    /// The function's `DISubprogram` node (`dwarf_lines`), or 0.
    scope: SourceScope = .{},
    /// Emitting a release of a value that may be `undef` (`own.empty_release`): every
    /// block pointer is tested for null first.
    may_be_empty: bool = false,
    /// A counting build's record of this function (`emit_count.Table.function`), or null.
    count_fn: ?u32 = null,
    /// The instruction being emitted: counter sites take its span and operation.
    current: ir.Ref = .none,
    /// A counter site detail that names a step of the operation (`list_set.old`), or null.
    count_detail: ?[]const u8 = null,
    /// Scalar loads and stores are list element data: tag them by scalar type
    /// (`element_tags`) instead of the generic `myl.data`.
    element_tags: bool = false,

    const SourceScope = struct {
        definition: u32 = 0,
        origin: ?u32 = null,
        inline_locations: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    };

    fn sourceFunction(self: *FunctionEmitter) *const ir.Function {
        const table = self.state.options.analysis.provenance orelse return self.function;
        const origin = self.scope.origin orelse return self.function;
        return &self.state.module.functions.items[table.frames.items[origin].function];
    }

    fn selectBlock(self: *FunctionEmitter, b: u32) void {
        self.scope.origin = if (self.state.options.analysis.provenance) |table| table.block(self.index, b) else null;
    }

    fn selectInstruction(self: *FunctionEmitter, b: u32, ref: ir.Ref) void {
        self.scope.origin = if (self.state.options.analysis.provenance) |table| table.instruction(self.index, b, ref) else null;
    }

    /// Whether operation sub-emitters must assert runtime invariants.
    pub fn verifyMode(self: *FunctionEmitter) bool {
        return self.state.options.verify;
    }

    /// The frozen module shapes available to operation sub-emitters.
    pub fn module(self: *FunctionEmitter) *const ir.Module {
        return self.state.module;
    }

    /// Emit a dictionary descriptor and inline probe once per dictionary type.
    pub fn dictDescriptor(self: *FunctionEmitter, dict_type: ir.Type) Error![]const u8 {
        const dictionaries = &self.state.local.dictionaries;
        const local = std.mem.indexOfScalar(ir.Type, dictionaries.items, dict_type) orelse dictionaries.items.len;
        if (local == dictionaries.items.len) try dictionaries.append(self.a(), dict_type);
        const name = try std.fmt.allocPrint(self.a(), "@myl.dict.{d}", .{local});
        for (self.state.declared.items) |known| if (std.mem.eql(u8, known, name)) return name;
        try self.state.declared.append(self.a(), name);
        const shape = self.state.module.compound(dict_type).dict;
        const value_offset = std.mem.alignForward(u32, self.state.module.size(shape.key), self.state.module.alignment(shape.value));
        const stride = @max(1, std.mem.alignForward(u32, value_offset + self.state.module.size(shape.value), @max(self.state.module.alignment(shape.key), self.state.module.alignment(shape.value))));
        var parts: LayoutParts = .{};
        try layoutParts(self.a(), self.state.module, shape.key, 0, 0, &parts);
        try layoutParts(self.a(), self.state.module, shape.value, value_offset, 0, &parts);
        const layout_name = try std.fmt.allocPrint(self.a(), "{s}.layout", .{name});
        try emit_release.emit(self.a(), &self.state.layouts.text, layout_name, stride, .{ .refs = parts.refs.items, .guards = parts.guards.items, .split = value_offset, .zero_rc = self.module().zero_rc });
        const structural = shape.key.integer() == null and shape.key != .bool and shape.key != .str and shape.key != .bytes;
        const hash = if (structural) try std.fmt.allocPrint(self.a(), "{s}.key.hash", .{name}) else "null";
        const same = if (structural) try std.fmt.allocPrint(self.a(), "{s}.key.same", .{name}) else "null";
        try self.state.layouts.text.print(self.a(), "{s} = private constant {{ i32, i32, i32, i32, ptr, ptr, ptr }} {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, ptr {s}.layout, ptr {s}, ptr {s} }}, align 8\n", .{
            name,
            stride,
            value_offset,
            @as(u32, if (structural) 3 else if (shape.key == .str or shape.key == .bytes) 2 else 0),
            self.state.module.size(shape.key),
            name,
            hash,
            same,
        });
        if (structural) try emit_dict.keyDefinitions(@TypeOf(self), self, &self.state.layouts.text, shape.key, try std.fmt.allocPrint(self.a(), "{s}.key", .{name}));
        try emit_dict.probeDefinition(@TypeOf(self), self, &self.state.layouts.text, dict_type, name);
        return name;
    }

    /// The allocation context used by operation sub-emitters.
    pub fn a(self: *FunctionEmitter) std.mem.Allocator {
        return self.state.allocator;
    }

    /// A unique LLVM temporary or label for an operation sub-emitter.
    pub fn fresh(self: *FunctionEmitter, prefix: []const u8) Error![]const u8 {
        self.counter += 1;
        return std.fmt.allocPrint(self.a(), "{s}.{d}", .{ freshBase(prefix), self.counter });
    }

    /// The LLVM spelling of a Core type for an operation sub-emitter.
    pub fn ty(self: *FunctionEmitter, t: ir.Type) Error![]const u8 {
        return self.state.llvmType(t);
    }

    /// The LLVM operand text for a value.
    /// The LLVM operand spelling for operation sub-emitters.
    pub fn value(self: *FunctionEmitter, raw: ir.Ref) Error![]const u8 {
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        return switch (inst.op) {
            .iconst => if (inst.ty == .bool) (if (inst.data != 0) "true" else "false") else std.fmt.allocPrint(self.a(), "{d}", .{@as(i64, @bitCast(inst.data))}),
            .fconst => std.fmt.allocPrint(self.a(), "0x{X:0>16}", .{inst.data}),
            .param => std.fmt.allocPrint(self.a(), "%p{d}", .{inst.data}),
            .undef => self.undefValue(inst.ty),
            .str_const => self.state.literal(@intCast(inst.data), inst.ty == .bytes),
            .func_ref => self.functionPointer(@intCast(inst.data)),
            else => std.fmt.allocPrint(self.a(), "%v{d}", .{ref.index()}),
        };
    }

    /// LLVM type and value pair for a scalar operation sub-emitter.
    pub fn typedValue(self: *FunctionEmitter, raw: ir.Ref) Error![]const u8 {
        const ref = self.function.resolve(raw);
        return std.fmt.allocPrint(self.a(), "{s} {s}", .{ try self.ty(self.function.inst(ref).ty), try self.value(ref) });
    }

    /// FLOAT-NAN-OBSERVED-3: `argument` with any NaN replaced by the canonical quiet NaN,
    /// selected on the double's bits with straight-line mask arithmetic, so no
    /// floating-point rule lets LLVM keep another NaN's sign or payload.
    fn canonicalNan(self: *FunctionEmitter, out: *Out, argument: ir.Ref) Error![]const u8 {
        const bits = try self.fresh("%nan.bits");
        const magnitude = try self.fresh("%nan.magnitude");
        const is_nan = try self.fresh("%nan.is");
        const word = try self.fresh("%nan.word");
        const canonical = try self.fresh("%nan");
        try out.print(self.a(), "  {s} = bitcast double {s} to i64\n  {s} = and i64 {s}, {s}\n", .{ bits, try self.value(argument), magnitude, bits, c_abi.magnitude_mask });
        try out.print(self.a(), "  {s} = icmp ugt i64 {s}, {s}\n", .{ is_nan, magnitude, c_abi.infinity_bits });
        try out.print(self.a(), "  {s} = select i1 {s}, i64 {s}, i64 {s}\n  {s} = bitcast i64 {s} to double\n", .{ word, is_nan, c_abi.canonical_nan_bits, bits, canonical, word });
        return canonical;
    }

    fn constantOf(self: *FunctionEmitter, raw: ir.Ref) ?i64 {
        const inst = self.function.inst(self.function.resolve(raw));
        return if (inst.op == .iconst) @bitCast(inst.data) else null;
    }

    fn emitFunction(self: *FunctionEmitter, out: *Out) !void {
        const f = self.function;
        const m = self.state.module;
        self.state.allocas = .empty;
        // Records and unions over four words cross calls in memory: by a read-only
        // pointer in, through `sret` out (docs/design/new-core-s1.md §3); a `mut` one by a
        // pointer the callee updates in place (`InOutAbi`).
        const abi = inOutAbi(m, f.signature);
        try self.analyzeMemory();
        self.memory.states = try emit_state.plan(self.a(), m, f);
        try emit_state.allocas(&self.memory.states, &self.state.allocas, self.a());
        try self.defineLine(out, abi);
        try self.collectBoundLengths();
        if (self.state.options.counters) self.count_fn = try self.state.count.function(self.a(), f.name);
        // `uwtable`: a trap walks the stack through `.eh_frame`, which needs every frame's CFI.
        try out.print(self.a(), ") nounwind uwtable{s} {{\n", .{try self.functionScope()});
        const bodies = try self.a().alloc(Out, f.blocks.items.len);
        try self.exit_labels.resize(self.a(), f.blocks.items.len);
        for (f.blocks.items, 0..) |block, b| {
            bodies[b] = .empty;
            self.exit_labels.items[b] = try std.fmt.allocPrint(self.a(), "b{d}", .{b});
            if (b != 0 and block.preds.items.len == 0) continue;
            self.label = self.exit_labels.items[b];
            self.vectors.block = @intCast(b);
            self.selectBlock(@intCast(b));
            try self.assertReachable(&bodies[b], @intCast(b));
            if (b == 0) try self.assertEntryFacts(&bodies[b]);
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .phi) {
                    self.selectInstruction(@intCast(b), ref);
                    try self.currentHeader(&bodies[b], ref);
                    try self.captureBoundLength(&bodies[b], ref);
                    try self.assertFacts(&bodies[b], ref, inst);
                }
            }
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .phi or inst.op == .copy) continue;
                self.selectInstruction(@intCast(b), ref);
                self.current = ref;
                try self.instruction(&bodies[b], ref, inst);
                if (!inst.op.terminates()) try self.currentHeader(&bodies[b], ref);
                if (inst.op != .param and inst.op != .str_const) try self.captureBoundLength(&bodies[b], ref);
                // A construction stored straight into its consumer never exists as a value to assert about.
                if (!inst.op.terminates() and !self.memory.fused[ref.index()]) try self.assertFacts(&bodies[b], ref, inst);
            }
            self.exit_labels.items[b] = self.label;
        }
        try out.appendSlice(self.a(), "entry:\n  %slot = alloca i64, align 8\n");
        try out.appendSlice(self.a(), self.state.allocas.items);
        if (self.count_fn) |record| try emit_count.prologue(self.a(), out, record);
        try out.appendSlice(self.a(), "  br label %b0\n");
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            try out.print(self.a(), "b{d}:\n", .{b});
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .phi) continue;
                // A phi of a value in memory lives in its home, filled on each incoming edge whose value lives elsewhere.
                if (m.passedInMemory(inst.ty)) continue;
                try out.print(self.a(), "  %v{d} = phi {s} ", .{ ref.index(), try self.ty(inst.ty) });
                for (f.operands(inst.data), block.preds.items, 0..) |operand, pred, i| {
                    const resumed = if (self.vectorPreheader(pred, @intCast(b))) self.vectors.resume_values.get(@intCast(ref.index())) else null;
                    const edge = self.memory.edges.get(edgeKey(pred.index(), b));
                    try out.print(self.a(), "{s}[ {s}, %{s} ]", .{ if (i == 0) "" else ", ", resumed orelse try self.value(operand), edge orelse self.exit_labels.items[pred.index()] });
                }
                try out.appendSlice(self.a(), "\n");
            }
            try out.appendSlice(self.a(), bodies[b].items);
        }
        try out.appendSlice(self.a(), "}\n");
    }

    /// Verify builds read a list's header to check its facts: a list whose length is kept in
    /// slots (`emit_state.zig`) has it stored back first.
    fn currentHeader(self: *FunctionEmitter, out: *Out, ref: ir.Ref) !void {
        if (self.knownFacts() == null) return;
        const slots = self.memory.states.of(ref) orelse return;
        try emit_state.store(*FunctionEmitter, self, out, try self.value(ref), slots);
    }

    /// The `define` line up to its parameters: a value over four words is used where the caller keeps
    /// it (the parameter is its pointer), and a parameter a caller may pass in `%ret` itself (CE2-B)
    /// aliases it, so neither is `noalias`.
    fn defineLine(self: *FunctionEmitter, out: *Out, abi: InOutAbi) !void {
        const f = self.function;
        const m = self.state.module;
        const sret = returnsThroughSret(m, f.signature, abi);
        const shared = if (self.memory.homes.shared) shareCandidate(m, f.signature, abi) else emit_homes.none;
        try out.print(self.a(), "define {s} fastcc {s} {s}(", .{ self.state.linkage(self.index), try self.state.returnType(f.signature, abi), try self.state.originalSymbol(self.index) });
        if (sret) try out.print(self.a(), "ptr {s}sret({s}) align 8 %ret", .{ if (shared == emit_homes.none) "noalias " else "", try self.state.memoryType(f.signature.ret) });
        for (f.signature.params, 0..) |param, i| {
            const separator = if (i == 0 and !sret) "" else ", ";
            if (abi.inOut(i)) {
                try out.print(self.a(), "{s}ptr noalias align 8 %p{d}", .{ separator, i });
            } else if (m.passedInMemory(param)) {
                try out.print(self.a(), "{s}ptr {s}readonly align 8 %p{d}", .{ separator, if (shared == i) "" else "noalias ", i });
            } else try out.print(self.a(), "{s}{s} %p{d}", .{ separator, try self.ty(param), i });
        }
    }

    /// Count uses, decide which constructions are stored straight into their consumer, find each
    /// call's in-out arguments, and give every value in memory its home (`emit_homes.zig`): an
    /// entry-block slot, a parameter's memory or `%ret`, named in the entry block as `%vN`.
    fn analyzeMemory(self: *FunctionEmitter) !void {
        try self.prepareMemory();
        self.memory.homes = try self.planMemory(true);
        try self.nameHomes();
    }

    /// Count uses, find the constructions stored straight into their consumer, each call's in-out
    /// arguments and the list elements lent to calls: what a home plan needs.
    fn prepareMemory(self: *FunctionEmitter) Error!void {
        const f = self.function;
        const m = self.state.module;
        const count = f.insts.items.len;
        const mem = &self.memory;
        const use_count = try self.a().alloc(u32, count);
        mem.uses = use_count;
        const users = try self.a().alloc(ir.Ref, count);
        mem.fused = try self.a().alloc(bool, count);
        @memset(use_count, 0);
        @memset(users, .none);
        @memset(mem.fused, false);
        const block_of = try self.a().alloc(u32, count);
        @memset(block_of, std.math.maxInt(u32));
        const phis = try self.a().alloc([]const ir.Ref, f.blocks.items.len);
        for (f.blocks.items, 0..) |block, b| {
            var mine: std.ArrayList(ir.Ref) = .empty;
            for (block.insts.items) |ref| {
                block_of[ref.index()] = @intCast(b);
                const inst = f.inst(ref);
                if (inst.op == .phi and m.passedInMemory(inst.ty)) try mine.append(self.a(), ref);
                if (inst.op == .copy) continue;
                const operands = f.valueOperands(inst);
                for (0..operands.len()) |i| {
                    const used = f.resolve(operands.get(i));
                    use_count[used.index()] += 1;
                    users[used.index()] = ref;
                }
            }
            phis[b] = mine.items;
        }
        mem.phis = phis;
        mem.checked = .empty;
        mem.shape = try facts.shape(self.a(), f);
        mem.keys = try index_keys.compute(self.a(), f, mem.shape.?.rpo);
        mem.from_end = try self.a().alloc(ir.Ref, count);
        @memset(mem.from_end, .none);
        for (f.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
            if (f.inst(ref).op != .phi) continue;
            mem.from_end[ref.index()] = facts.normalizedRaw(f, @fromBackingInt(@intCast(b)), ref) orelse .none;
        };
        const abi = inOutAbi(m, f.signature);
        // A construction whose only use stores it (a push, a write, a return through `sret`, a box,
        // or a field of a construction that is itself stored so or lives in memory) is never built
        // on its own.
        for (f.blocks.items, 0..) |block, b| {
            var at = block.insts.items.len;
            while (at > 0) {
                at -= 1;
                const ref = block.insts.items[at];
                const inst = f.inst(ref);
                if (inst.op != .record_make and inst.op != .union_make) continue;
                if (use_count[ref.index()] != 1) continue;
                if (inst.op == .union_make and m.unionLayout(inst.ty).form == .niche) continue;
                const user = users[ref.index()];
                const consumer = f.inst(user);
                // A whole-element store in a later block (past the index's negative-index branch
                // or the list's uniqueness test) builds the construction in the element too: its
                // operands are read there, and its homes keep them until then (CE2-A).
                if (block_of[user.index()] != b and consumer.op != .list_set) continue;
                mem.fused[ref.index()] = switch (consumer.op) {
                    .list_push => f.resolve(consumer.b) == ref,
                    .list_set => f.resolve(f.operands(consumer.data)[0]) == ref,
                    .ret => f.resolve(consumer.a) == ref and returnsThroughSret(m, f.signature, abi),
                    .box_make => f.resolve(consumer.a) == ref,
                    // A field of a construction built in memory is stored straight into it too.
                    .record_make, .union_make => mem.fused[user.index()] or (emit_homes.steps.views and m.passedInMemory(consumer.ty)),
                    else => false,
                };
            }
        }
        try self.inOutCalls();
        mem.borrowed = try self.lentElements();
    }

    /// The home plan of the function (`emit_homes.zig`). With `share_calls`, a call to a callee whose
    /// parameter may lie in its `%ret` (`sharedArgument`) treats that argument like an in-out one, so
    /// a result and an argument that dies at the call may share one home and be passed as one
    /// memory; a function that may itself share never does (its plan is the one callers checked).
    fn planMemory(self: *FunctionEmitter, share_calls: bool) Error!emit_homes.Plan {
        const f = self.function;
        const m = self.state.module;
        const mem = &self.memory;
        const abi = inOutAbi(m, f.signature);
        var input: emit_homes.Input = .{
            .module = m,
            .function = f,
            .fused = mem.fused,
            .in_out = abi.params,
            .calls = mem.in_out.args,
            .effects = self.state.options.analysis.effects,
            .results = .{
                .sret = returnsThroughSret(m, f.signature, abi),
                .finals = finalFields(f.signature, abi),
                .borrowed = mem.borrowed,
                .share = shareCandidate(m, f.signature, abi),
                .home = emit_homes.steps.in_out and abi.params == 0 and returnsThroughSret(m, f.signature, abi),
            },
        };
        const own = try emit_homes.plan(self.a(), input);
        if (!share_calls or own.shared) return own;
        input.calls = try self.sharedCalls() orelse return own;
        input.results.share = emit_homes.none;
        return emit_homes.plan(self.a(), input);
    }

    /// The in-out arguments of every call, plus, for a direct call to a callee in this unit whose
    /// parameter may lie in its `%ret`, that argument with the call's result as its final value; null
    /// when no call has such an argument.
    fn sharedCalls(self: *FunctionEmitter) Error!?[]const []const emit_homes.InOut {
        const f = self.function;
        var calls: ?[][]const emit_homes.InOut = null;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .call) continue;
                const param = try self.sharedArgument(inst);
                if (param == emit_homes.none) continue;
                if (calls == null) calls = try self.a().dupe([]const emit_homes.InOut, self.memory.in_out.args);
                calls.?[ref.index()] = try self.a().dupe(emit_homes.InOut, &.{.{ .argument = param, .final = ref }});
            }
        }
        return calls;
    }

    /// The parameter of a direct call's callee that may lie in the callee's `%ret` (its plan says
    /// `shared`), or `none`: only for a callee emitted in this unit, so the callee's own code is the
    /// code that was checked.
    fn sharedArgument(self: *FunctionEmitter, inst: ir.Inst) Error!u32 {
        const m = self.state.module;
        const callee: u32 = @intCast(inst.a.index());
        const target = &m.functions.items[callee];
        if (target.signature.linkage != .internal or !self.state.contains(callee)) return emit_homes.none;
        if (shareCandidate(m, target.signature, inOutAbi(m, target.signature)) == emit_homes.none) return emit_homes.none;
        if (self.state.shares.get(callee)) |known| return known;
        var scratch: FunctionEmitter = .{ .state = self.state, .function = target, .index = callee };
        try scratch.prepareMemory();
        const plan = try scratch.planMemory(false);
        const param = if (plan.shared) shareCandidate(m, target.signature, inOutAbi(m, target.signature)) else emit_homes.none;
        try self.state.shares.put(self.a(), callee, param);
        return param;
    }

    /// Name every home in the entry block (`analyzeMemory`).
    fn nameHomes(self: *FunctionEmitter) !void {
        const f = self.function;
        const plan = &self.memory.homes;
        const names = try self.a().alloc([]const u8, plan.homes.len);
        for (plan.homes, names) |home, *name| name.* = switch (home) {
            .slot => |size| try self.stackSlot(size),
            .param => |index| try std.fmt.allocPrint(self.a(), "%p{d}", .{index}),
            .ret => "%ret",
            .ret_at => |offset| try self.retPlace(offset),
            .field => "",
        };
        // A home inside another's field, once that other is named.
        for (plan.homes, names) |home, *name| {
            if (home != .field) continue;
            name.* = try self.fresh("%home");
            try self.state.allocas.print(self.a(), header_pointer_line, .{ name.*, names[home.field.class], home.field.offset });
        }
        for (plan.class, 0..) |class, index| {
            if (class == emit_homes.none or f.insts.items[index].op == .param) continue;
            try self.state.allocas.print(self.a(), "  %v{d} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ index, names[class] });
        }
    }

    /// The list elements over four words read where they lie (CE2-B): a `list_get` or `list_get_field`
    /// whose every use, in its own block, is a by-value argument of an internal call that takes no
    /// `mut` argument able to reach a list, or a load of a part in registers, with nothing in between
    /// that can write, free or move a list (`lendable`). The callee never writes such a parameter (it
    /// is a read-only pointer), so passing the element's own address passes its value.
    fn lentElements(self: *FunctionEmitter) ![]bool {
        const f = self.function;
        const m = self.state.module;
        const marks = try self.a().alloc(bool, f.insts.items.len);
        @memset(marks, false);
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items, 0..) |ref, i| {
                const inst = f.inst(ref);
                if (inst.op != .list_get and inst.op != .list_get_field) continue;
                if (!m.passedInMemory(inst.ty) or self.memory.uses[ref.index()] == 0) continue;
                marks[ref.index()] = self.lendable(block.insts.items, i);
            }
        }
        return marks;
    }

    /// Whether the element read at position `at` of `insts` may be lent: its uses all follow it in
    /// the block, each one `lendsTo`, and every instruction up to the last is `keepsLists`.
    fn lendable(self: *FunctionEmitter, insts: []const ir.Ref, at: usize) bool {
        const f = self.function;
        const ref = insts[at];
        var remaining = self.memory.uses[ref.index()];
        for (insts[at + 1 ..]) |next| {
            if (remaining == 0) return true;
            const user = f.inst(next);
            if (user.op == .copy or user.op == .phi) continue;
            const operands = f.valueOperands(user);
            var reads: u32 = 0;
            for (0..operands.len()) |k| {
                if (f.resolve(operands.get(k)) == ref) reads += 1;
            }
            if (reads == 0) {
                if (!self.keepsLists(user)) return false;
                continue;
            }
            if (!self.lendsTo(user, ref)) return false;
            remaining -= @min(remaining, reads);
        }
        return remaining == 0;
    }

    /// Whether `user` reads the lent element `ref` only where it lies: as by-value memory arguments of
    /// a call that `keepsLists`, as a load of a part in registers, or to count its parts.
    fn lendsTo(self: *FunctionEmitter, user: ir.Inst, ref: ir.Ref) bool {
        const f = self.function;
        const m = self.state.module;
        switch (user.op) {
            .record_get, .union_payload, .union_tag => return !m.passedInMemory(user.ty),
            .retain => return true,
            .call, .call_indirect => {
                if (!self.keepsLists(user)) return false;
                if (user.op == .call_indirect and f.resolve(user.a) == ref) return false;
                const signature = self.signatureOf(user);
                const abi = inOutAbi(m, signature);
                for (f.operands(user.data), signature.params, 0..) |argument, param, k| {
                    if (f.resolve(argument) != ref) continue;
                    if (!m.passedInMemory(param) or abi.inOut(k)) return false;
                }
                return true;
            },
            else => return false,
        }
    }

    /// Whether `inst` can neither write, free nor move a list block the caller holds: an inert
    /// instruction, a count increment, or an internal call with no consuming block parameter.
    fn keepsLists(self: *FunctionEmitter, inst: ir.Inst) bool {
        const m = self.state.module;
        switch (inst.op) {
            .retain, .is_unique, .err_trace => return true,
            .call, .call_indirect => {
                const signature = self.signatureOf(inst);
                if (signature.linkage != .internal) return false;
                for (signature.params, 0..) |param, k| {
                    if (k >= 64 or (signature.owned | signature.consumes) & (@as(u64, 1) << @intCast(k)) == 0) continue;
                    if (m.managed(param)) return false;
                }
                return true;
            },
            else => return fuse.inert(inst, false),
        }
    }

    /// The entry-block name of `%ret` at `offset`: the home of values built where a `ret` stores them (CE2-B).
    fn retPlace(self: *FunctionEmitter, offset: u32) ![]const u8 {
        const name = try self.fresh("%home");
        try self.state.allocas.print(self.a(), header_pointer_line, .{ name, "%ret", offset });
        return name;
    }

    /// Each call's in-out arguments and the values that hold their final values: the call itself
    /// when the result is that one value, else the one `record_get` of its field of the result
    /// (`.none` when there is not exactly one, and then the result record is completed after the call).
    fn inOutCalls(self: *FunctionEmitter) !void {
        const f = self.function;
        const m = self.state.module;
        const count = f.insts.items.len;
        const calls = try self.a().alloc([]const emit_homes.InOut, count);
        @memset(calls, &.{});
        self.memory.in_out.complete = try self.a().alloc(bool, count);
        @memset(self.memory.in_out.complete, false);
        self.memory.in_out.args = calls;
        var any = false;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .call and inst.op != .call_indirect) continue;
                const signature = self.signatureOf(inst);
                const abi = inOutAbi(m, signature);
                if (abi.params == 0) continue;
                var list: std.ArrayList(emit_homes.InOut) = .empty;
                for (0..signature.params.len) |i| {
                    if (!abi.inOut(i)) continue;
                    try list.append(self.a(), .{ .argument = @intCast(i), .final = if (abi.whole) ref else .none });
                }
                calls[ref.index()] = list.items;
                any = true;
            }
        }
        if (!any) return;
        self.markWholeReaders();
        for (calls, 0..) |in_outs, at| {
            if (in_outs.len == 0 or in_outs[0].final != .none) continue;
            calls[at] = try self.finalReads(@intCast(at), in_outs);
        }
    }

    /// Mark each in-out call whose result record something other than a `record_get` reads.
    fn markWholeReaders(self: *FunctionEmitter) void {
        const f = self.function;
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .copy or inst.op == .record_get) continue;
                const operands = f.valueOperands(inst);
                for (0..operands.len()) |i| {
                    const used = f.resolve(operands.get(i));
                    const in_outs = self.memory.in_out.args[used.index()];
                    if (in_outs.len != 0 and in_outs[0].final != used) self.memory.in_out.complete[used.index()] = true;
                }
            }
        }
    }

    /// The in-out arguments of call `at` with their final values: the one `record_get` of each
    /// one's field of the result, or `.none` (and the result completed) when there is not exactly one.
    fn finalReads(self: *FunctionEmitter, at: u32, in_outs: []const emit_homes.InOut) ![]const emit_homes.InOut {
        const f = self.function;
        const signature = self.signatureOf(f.insts.items[at]);
        const abi = inOutAbi(self.state.module, signature);
        const finals = try self.a().dupe(emit_homes.InOut, in_outs);
        for (finals) |*in_out| {
            const field = abi.field(signature, in_out.argument);
            var found: ir.Ref = .none;
            var readers: u32 = 0;
            for (f.blocks.items, 0..) |block, b| {
                if (b != 0 and block.preds.items.len == 0) continue;
                for (block.insts.items) |ref| {
                    const inst = f.inst(ref);
                    if (inst.op != .record_get or inst.data != field or f.resolve(inst.a).index() != at) continue;
                    readers += 1;
                    found = ref;
                }
            }
            if (readers == 1) in_out.final = found else self.memory.in_out.complete[at] = true;
        }
        return finals;
    }

    /// The signature a direct or indirect call is made with.
    fn signatureOf(self: *FunctionEmitter, inst: ir.Inst) ir.Signature {
        const m = self.state.module;
        if (inst.op == .call_indirect) return m.compound(self.typeOf(inst.a)).@"fn";
        return m.functions.items[inst.a.index()].signature;
    }

    /// Whether `name` is the `%vN` of a value with a home: its bytes go there.
    fn homedName(self: *FunctionEmitter, name: []const u8) bool {
        if (name.len < 3 or !std.mem.startsWith(u8, name, "%v")) return false;
        const index = std.fmt.parseInt(u32, name[2..], 10) catch return false;
        const class = self.memory.homes.class;
        return index < class.len and class[index] != emit_homes.none and self.function.insts.items[index].op != .param;
    }

    fn edgeKey(pred: usize, block: usize) u64 {
        return (@as(u64, pred) << 32) | block;
    }

    /// One copy a set of simultaneous writes makes (phi fills on an edge, a return's final values).
    const Move = struct { dst: []const u8, src: []const u8, size: u32, dst_class: u32, src_class: u32 };

    /// The copies that fill the memory phis of `target` on the edge from `pred`: none for a phi
    /// whose incoming value already lives in its home.
    fn edgeMoves(self: *FunctionEmitter, pred: usize, target: usize) ![]const Move {
        const phis = self.memory.phis[target];
        if (phis.len == 0) return &.{};
        const f = self.function;
        const m = self.state.module;
        const plan = &self.memory.homes;
        const position = for (f.blocks.items[target].preds.items, 0..) |candidate, i| {
            if (candidate.index() == pred) break i;
        } else return &.{};
        var moves: std.ArrayList(Move) = .empty;
        for (phis) |phi| {
            const incoming = f.resolve(f.operands(f.inst(phi).data)[position]);
            // Managed undef must initialize null block pointers before an empty release.
            // An unmanaged undef remains unspecified; copying its poison address is invalid.
            if (f.inst(incoming).op == .undef and !m.managed(f.inst(phi).ty)) continue;
            if (plan.holds(phi, 0, incoming)) continue;
            const dst_class = plan.storage(plan.class[phi.index()]);
            try moves.append(self.a(), .{ .dst = try self.value(phi), .src = try self.value(incoming), .size = m.size(f.inst(phi).ty), .dst_class = dst_class, .src_class = plan.storage(plan.rootClass(incoming)) });
        }
        return moves.items;
    }

    /// Make simultaneous copies (a parallel copy): a copy that reads a home another one writes
    /// goes first, and only a cycle of them goes through a temporary. A copy whose source lies in
    /// its own destination's home (a part of it moved to the whole) may overlap it.
    fn moveAll(self: *FunctionEmitter, out: *Out, all: []const Move) !void {
        var pending: std.ArrayList(Move) = .empty;
        for (all) |move| if (move.size != 0) try pending.append(self.a(), move);
        while (pending.items.len != 0) {
            const ready = for (pending.items, 0..) |move, i| {
                const read = for (pending.items, 0..) |other, j| {
                    if (i != j and other.src_class != emit_homes.none and other.src_class == move.dst_class) break true;
                } else false;
                if (!read) break i;
            } else null;
            if (ready) |i| {
                const move = pending.orderedRemove(i);
                try self.copyBytes(out, move.dst, move.src, move.size, move.src_class == move.dst_class);
                continue;
            }
            const first = &pending.items[0];
            const temporary = try self.stackSlot(first.size);
            try self.copyBytes(out, temporary, first.src, first.size, false);
            first.src = temporary;
            first.src_class = emit_homes.none;
        }
    }

    /// On the edge from block `pred` into `target`, copy the incoming value of each phi that lives
    /// in memory into the phi's home, unless it already lives there.
    fn fillMemoryPhis(self: *FunctionEmitter, out: *Out, pred: usize, target: usize) !void {
        try self.moveAll(out, try self.edgeMoves(pred, target));
    }

    /// `branch`: a successor whose memory phis need a copy on this edge gets a block of its own there, which fills them.
    fn branchTo(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const targets = ir.unpackTargets(inst.data);
        const pred: usize = self.vectors.block;
        const sides = [2]usize{ targets.then.index(), targets.otherwise.index() };
        var labels: [2][]const u8 = undefined;
        var moves: [2][]const Move = undefined;
        // An edge that leaves a region whose appends keep the length in slots stores it back
        // there (`emit_state.zig`), in a block of its own.
        var leaving: [2][]const emit_state.Exit = .{ &.{}, &.{} };
        for (sides, &labels, &moves, &leaving) |target, *label, *side, *exits| {
            side.* = try self.edgeMoves(pred, target);
            exits.* = self.memory.states.exit(@intCast(pred), @intCast(target));
            label.* = if (side.len != 0 or exits.len != 0) try self.fresh("edge") else try std.fmt.allocPrint(self.a(), "b{d}", .{target});
        }
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}\n", .{ try self.value(inst.a), labels[0], labels[1] });
        for (sides, labels, moves, leaving) |target, label, side, exits| {
            if (side.len == 0 and exits.len == 0) continue;
            try out.print(self.a(), "{s}:\n", .{label});
            for (exits) |stored| try emit_state.store(*FunctionEmitter, self, out, try self.value(stored.value), stored.slots);
            try self.moveAll(out, side);
            try out.print(self.a(), "  br label %b{d}\n", .{target});
            try self.memory.edges.put(self.a(), edgeKey(pred, target), label);
        }
    }

    /// `retain` or `release` the blocks a record or union in memory references: each managed field,
    /// or the payload of each managed case under its tag, loaded out of memory and counted as a value
    /// (a field or payload that is itself in memory is counted where it lies).
    fn countedMemory(self: *FunctionEmitter, out: *Out, mode: Counting, value_type: ir.Type, ptr: []const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                if (!m.managed(field)) continue;
                try self.countedAt(out, mode, field, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)));
            },
            .@"union" => |cases| {
                const word = try self.fresh("%cw");
                const tag = try self.fresh("%ct");
                try out.print(self.a(), word_load_line ++ "  {s} = trunc i64 {s} to i8\n", .{ word, ptr, tag, word });
                for (cases, 0..) |case, k| {
                    if (!m.managed(case)) continue;
                    const here = try self.fresh("%cc");
                    try out.print(self.a(), "  {s} = icmp eq i8 {s}, {d}\n", .{ here, tag, k });
                    const join = try self.enterIf(out, here);
                    try self.countedAt(out, mode, case, try self.offsetPointer(out, ptr, 8));
                    try self.leaveIf(out, join);
                }
            },
            .array => |array| for (0..array.n) |i| {
                try self.countedAt(out, mode, array.elem, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)));
            },
            .list, .box, .dict, .@"fn" => unreachable,
        }
    }

    /// Count the part of type `part_type` stored at `ptr` where it is: a part over four words
    /// field by field through `countedMemory` (never copied out first, NEW-CORE-CE-LISTS-4,
    /// while `emit_homes.steps.views` is on, the default), anything else loaded as a value.
    fn countedAt(self: *FunctionEmitter, out: *Out, mode: Counting, part_type: ir.Type, ptr: []const u8) Error!void {
        if (emit_homes.steps.views and self.state.module.passedInMemory(part_type)) return self.countedMemory(out, mode, part_type, ptr);
        const loaded = try self.fresh("%cm");
        try self.loadValue(out, part_type, ptr, loaded);
        try self.countedValue(out, mode, part_type, loaded);
    }

    /// Count a value held in a register or, over four words, a pointer to its slot.
    fn countedValue(self: *FunctionEmitter, out: *Out, mode: Counting, value_type: ir.Type, text: []const u8) Error!void {
        if (self.state.module.passedInMemory(value_type)) return self.countedMemory(out, mode, value_type, text);
        return self.counted(out, mode, value_type, text);
    }

    /// The check an instruction gets emitted with: verify mode emits proven checks as exact ones.
    pub fn checkOf(self: *FunctionEmitter, inst: ir.Inst) ir.Check {
        return if (inst.check == .proven and self.state.options.verify) .exact else inst.check;
    }

    /// Whether `pred` → `header` is the edge a vectorized loop is entered by.
    fn vectorPreheader(self: *FunctionEmitter, pred: ir.BlockId, header: u32) bool {
        for (self.vectors.plans) |plan| {
            if (plan.loop.header.index() == header and plan.preheader == pred) return true;
        }
        return false;
    }

    fn scalarName(context: *anyopaque, ref: ir.Ref) vector.Error![]const u8 {
        const self: *FunctionEmitter = @ptrCast(@alignCast(context));
        return self.value(ref) catch return error.OutOfMemory;
    }

    /// In front of the jump into a vectorized loop's header, run its vector part.
    fn vectorPrologue(self: *FunctionEmitter, out: *Out, target: u32) !void {
        for (self.vectors.plans) |plan| {
            if (plan.loop.header.index() != target or plan.preheader.index() != self.vectors.block) continue;
            self.state.meta.vector_count += 1;
            const resumed = try vector.emit(self.a(), out, self.function, .{
                .plan = plan,
                .id = self.state.meta.vector_count,
                .known = self.state.options.analysis.facts[self.index].?,
                .scalars = .{ .context = self, .name = scalarName },
                .from = self.label,
                .target = self.state.options.target,
            });
            try self.vectors.resume_values.put(self.a(), @intCast(plan.carried.counter.index()), resumed.counter);
            try self.vectors.resume_values.put(self.a(), @intCast(plan.carried.acc.index()), resumed.acc);
            self.label = resumed.label;
        }
    }

    fn knownFacts(self: *FunctionEmitter) ?facts.Facts {
        if (!self.state.options.verify or self.index >= self.state.options.analysis.facts.len) return null;
        return self.state.options.analysis.facts[self.index];
    }

    /// Verify mode: a block the facts call unreachable traps if it ever runs.
    fn assertReachable(self: *FunctionEmitter, out: *Out, block: u32) !void {
        const known = self.knownFacts() orelse return;
        if (known.reachable[block]) return;
        const at: ir.Inst = .{ .op = .@"unreachable", .ty = .void, .span = self.sourceFunction().span };
        const location = self.state.options.locator.locate(self.state.options.locator.context, at.span);
        const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "unreachable block", .function = self.sourceFunction().name });
        try self.trapIf(out, "true", index, "0", "0");
    }

    /// Verify mode: the value's interval and its list-length bound hold.
    fn assertFacts(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        try self.assertRange(out, ref, inst);
        try self.assertBound(out, ref, inst);
        try self.assertAggregate(out, ref, inst);
    }

    /// Entry values precede block instructions; caller-derived ranges remain asserted here.
    fn assertEntryFacts(self: *FunctionEmitter, out: *Out) !void {
        for (self.function.insts.items, 0..) |inst, index| {
            if (inst.op == .param or inst.op == .str_const)
                try self.captureBoundLength(out, @fromBackingInt(@as(u32, @intCast(index))));
        }
        for (self.function.insts.items, 0..) |inst, index| {
            if (inst.op == .param) try self.assertRange(out, @fromBackingInt(@as(u32, @intCast(index))), inst);
        }
    }

    /// Collect hidden length dependencies once; they must not extend ordinary RC liveness.
    fn collectBoundLengths(self: *FunctionEmitter) !void {
        const known = self.knownFacts() orelse return;
        self.memory.bound_lengths = try self.a().alloc(bool, self.function.insts.items.len);
        @memset(self.memory.bound_lengths, false);
        for (known.bounds) |maybe| {
            const bound = maybe orelse continue;
            if (bound.list == .none) continue;
            const source = self.function.resolve(bound.list);
            self.memory.bound_lengths[source.index()] = true;
        }
    }

    /// Snapshot the SSA block's byte/list length while the block still exists.
    fn captureBoundLength(self: *FunctionEmitter, out: *Out, ref: ir.Ref) !void {
        if (self.memory.bound_lengths.len == 0 or !self.memory.bound_lengths[ref.index()]) return;
        const at = try self.fresh("%bound.header");
        const len = try std.fmt.allocPrint(self.a(), "%bound.len.{d}", .{ref.index()});
        try out.print(self.a(), header_load_line, .{ at, try self.value(ref), len_offset, len, at });
    }

    /// Verify mode: a list's length lies in the interval the facts gave it, and every field of
    /// a record with a field interval lies in it.
    fn assertAggregate(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const m = self.state.module;
        const kind = m.kind(inst.ty) orelse return;
        if (kind == .list) {
            if (inst.op == .list_get) try self.assertChildLength(out, ref, inst);
            const len = known.aggregates.lists[ref.index()].len orelse return;
            const at = try self.fresh("%al");
            const length = try self.fresh("%an");
            const outside = try self.fresh("%ax");
            const below = try self.fresh("%ab");
            const above = try self.fresh("%aa");
            try out.print(self.a(), header_load_line, .{ at, try self.value(ref), len_offset, length, at });
            try out.print(self.a(), "  {s} = icmp ult i64 {s}, {d}\n  {s} = icmp ugt i64 {s}, {d}\n  {s} = or i1 {s}, {s}\n", .{ below, length, len.lo, above, length, len.hi, outside, below, above });
            const operation = try std.fmt.allocPrint(self.a(), "list length [{d}, {d}]", .{ len.lo, len.hi });
            const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = 64, .operation = operation, .function = self.sourceFunction().name });
            return self.trapIf(out, outside, index, length, "0");
        }
        if (kind != .record) return;
        const table = known.aggregates.fields[ref.index()] orelse return;
        const fields = m.compound(inst.ty).record;
        for (table, fields, 0..) |range_or_none, field, k| {
            const range = range_or_none orelse continue;
            const info: struct { bits: u16, signed: bool } = if (field.integer()) |found| .{ .bits = found.bits, .signed = found.signed } else if (field == .bool) .{ .bits = 1, .signed = false } else continue;
            const full = facts.typeRange(field) orelse continue;
            if (range.lo > range.hi or (range.lo <= full.lo and range.hi >= full.hi)) continue;
            const loaded = try self.fresh("%af");
            if (m.passedInMemory(inst.ty)) {
                try self.loadValue(out, field, try self.offsetPointer(out, try self.value(ref), m.fieldOffset(inst.ty, k)), loaded);
            } else try out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ loaded, try self.typedValue(ref), k });
            const tyname = try self.ty(field);
            const below = try self.fresh("%ab");
            const above = try self.fresh("%aa");
            const outside = try self.fresh("%ax");
            const signed = info.signed;
            try out.print(self.a(), bound_line, .{ below, if (signed) "slt" else "ult", tyname, loaded, range.lo });
            try out.print(self.a(), bound_line, .{ above, if (signed) "sgt" else "ugt", tyname, loaded, range.hi });
            try out.print(self.a(), or_line, .{ outside, below, above });
            const wide_value = if (info.bits == 64) loaded else blk: {
                const wide = try self.fresh("%aw");
                try out.print(self.a(), "  {s} = {s} {s} {s} to i64\n", .{ wide, if (signed) "sext" else "zext", tyname, loaded });
                break :blk wide;
            };
            const operation = try std.fmt.allocPrint(self.a(), "record field {d} range [{d}, {d}]", .{ k, range.lo, range.hi });
            const index = try self.state.site(.{
                .kind = .fact,
                .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span),
                .width = info.bits,
                .operation = operation,
                .function = self.sourceFunction().name,
            });
            try self.trapIf(out, outside, index, wide_value, "0");
        }
    }

    /// Uniform child lengths are symbolic facts. Assert the loaded child while
    /// it is live, without extending its RC lifetime or reading its parent.
    fn assertChildLength(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const bound = known.aggregates.lists[ref.index()].length;
        if (bound == .none) return;
        const producer = self.function.inst(bound);
        if (producer.op != .param and producer.op != .iconst) return;
        var expected = try self.value(bound);
        if (producer.ty == .i64) {
            const negative = try self.fresh("%child.negative");
            const positive = try self.fresh("%child.length");
            try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n", .{ negative, expected, positive, negative, expected });
            expected = positive;
        }
        const at = try self.fresh("%child.header");
        const length = try self.fresh("%child.actual");
        const outside = try self.fresh("%child.outside");
        try out.print(self.a(), header_load_line, .{ at, try self.value(ref), len_offset, length, at });
        try out.print(self.a(), "  {s} = icmp ne i64 {s}, {s}\n", .{ outside, length, expected });
        const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
        const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "uniform child list length", .function = self.sourceFunction().name });
        try self.trapIf(out, outside, index, length, expected);
    }

    /// Verify mode: the value is at most (below, when strict) the length of the list
    /// parameter the facts bound it by.
    fn assertBound(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const info = inst.ty.integer() orelse return;
        if (inst.op == .iconst or known.bounds.len == 0) return;
        const bound = known.bounds[ref.index()] orelse return;
        if (bound.list == .none) return;
        const source = self.function.resolve(bound.list);
        const len = try std.fmt.allocPrint(self.a(), "%bound.len.{d}", .{source.index()});
        const failed = try self.fresh("%bf");
        const name = try self.widened(out, ref);
        const predicate = if (bound.strict) (if (info.signed) "sge" else "uge") else (if (info.signed) "sgt" else "ugt");
        try out.print(self.a(), "  {s} = icmp {s} i64 {s}, {s}\n", .{ failed, predicate, name, len });
        const operation: []const u8 = if (bound.strict) "below the list length" else "at most the list length";
        const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = info.bits, .operation = operation, .function = self.sourceFunction().name });
        try self.trapIf(out, failed, index, name, len);
    }

    /// Verify mode: the value lies in the interval the facts gave it.
    fn assertRange(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const info = inst.ty.integer() orelse return;
        const range = known.ranges[ref.index()] orelse return;
        const full = facts.typeRange(inst.ty).?;
        if (inst.op == .iconst or range.lo > range.hi) return;
        const tyname = try self.ty(inst.ty);
        const name = try self.value(ref);
        var failed: ?[]const u8 = null;
        if (range.lo > full.lo) {
            const below = try self.fresh("%rl");
            try out.print(self.a(), bound_line, .{ below, if (info.signed) "slt" else "ult", tyname, name, range.lo });
            failed = below;
        }
        if (range.hi < full.hi) {
            const above = try self.fresh("%rh");
            try out.print(self.a(), bound_line, .{ above, if (info.signed) "sgt" else "ugt", tyname, name, range.hi });
            if (failed) |other| {
                const either = try self.fresh("%rx");
                try out.print(self.a(), or_line, .{ either, other, above });
                failed = either;
            } else failed = above;
        }
        const condition = failed orelse return;
        const operation = try std.fmt.allocPrint(self.a(), "range [{d}, {d}]", .{ range.lo, range.hi });
        const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = info.bits, .operation = operation, .function = self.sourceFunction().name });
        try self.trapIf(out, condition, index, try self.widened(out, ref), "0");
    }

    /// Register a trap site for operation sub-emitters.
    pub fn site(self: *FunctionEmitter, kind: TrapKind, inst: ir.Inst, operation: []const u8) Error!u32 {
        const bits: u16 = if (inst.ty.integer()) |info| info.bits else 64;
        // In verify mode a check the facts proved is still emitted, and its failure is the fact's.
        const effective: TrapKind = if (inst.check == .proven) .fact else kind;
        // An unsigned operation's operands are reported unsigned (TRAP-UNSIGNED-1): a cast's
        // operand is its source, any other's its result type.
        const operand = if (kind == .cast) self.typeOf(inst.a) else inst.ty;
        const reports_operands = effective == .overflow or effective == .division_by_zero or effective == .cast;
        const unsigned = reports_operands and if (operand.integer()) |info| !info.signed else false;
        const width = if (unsigned) bits | unsigned_site else bits;
        return self.state.site(.{ .kind = effective, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = width, .operation = operation, .function = self.sourceFunction().name });
    }

    /// Branch to a cold trap when `failed` (an `i1` operand) holds, and continue in a new label.
    /// Emit a conditional trap and continue in a fresh LLVM block.
    pub fn trapIf(self: *FunctionEmitter, out: *Out, failed: []const u8, site_index: u32, left: []const u8, right: []const u8) Error!void {
        const branch = try self.trapBegin(out, failed, site_index);
        try self.trapEnd(out, branch, .{ .left = left, .right = right });
    }

    /// A split conditional trap permits diagnostic work only on its cold path.
    pub const TrapBranch = struct { next: []const u8, site: u32, location: []const u8 };

    /// Start the cold trap block; complete it with trapEnd before emitting valid-path work.
    pub fn trapBegin(self: *FunctionEmitter, out: *Out, failed: []const u8, site_index: u32) Error!TrapBranch {
        // A counting build counts each execution of the check (an unconditional trap is no check).
        if (self.count_fn != null and !std.mem.eql(u8, failed, "true")) _ = try self.countSite(out, checkKind(self.state.sites.items[site_index].kind), "");
        const trap = try self.fresh("trap");
        const next = try self.fresh(self.label);
        const at = try self.trapLocation(site_index);
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}, !prof !0\n{s}:\n", .{ failed, trap, next, trap });
        return .{ .next = next, .site = site_index, .location = at };
    }

    /// Emit the located trap and resume in the valid-path block.
    pub fn trapEnd(self: *FunctionEmitter, out: *Out, branch: TrapBranch, detail: struct { left: []const u8, right: []const u8 }) Error!void {
        try out.print(self.a(), "  call void @myl_core_trap(ptr @myl.site.{d}, i64 {s}, i64 {s}) #2{s}\n  unreachable\n{s}:\n", .{ branch.site, detail.left, detail.right, branch.location, branch.next });
        self.label = branch.next;
    }

    /// Count Unicode scalars for a cold diagnostic, declaring the existing helper on demand.
    pub fn textScalars(self: *FunctionEmitter, out: *Out, receiver: ir.Ref) Error![]const u8 {
        const helper: ir.Function = .{ .name = flags.str_chars_symbol, .signature = .{ .params = &.{.str}, .ret = .u64, .linkage = .runtime_c } };
        try self.state.external(&helper, helper.name);
        const result = try self.fresh("%textscalars");
        try out.print(self.a(), "  {s} = call i64 @{s}(ptr {s})\n", .{ result, flags.str_chars_symbol, try self.value(receiver) });
        return result;
    }

    /// Sign- or zero-extend an integer operand to `i64` for a trap report.
    /// Widen an integer operand to an i64 LLVM value.
    pub fn widened(self: *FunctionEmitter, out: *Out, raw: ir.Ref) Error![]const u8 {
        const inst = self.function.inst(self.function.resolve(raw));
        const info = inst.ty.integer() orelse return "0";
        if (info.bits == 64) return self.value(raw);
        const name = try self.fresh("%w");
        try out.print(self.a(), "  {s} = {s} {s} to i64\n", .{ name, if (info.signed) "sext" else "zext", try self.typedValue(raw) });
        return name;
    }

    fn instruction(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        if (zero_rc.shallowManagedCopy(self.state.module, inst)) return error.UnsupportedInstruction;
        const name = try std.fmt.allocPrint(self.a(), "%v{d}", .{ref.index()});
        if (self.count_fn != null) try self.countBefore(out, inst);
        switch (inst.op) {
            .param, .iconst, .fconst, .undef, .str_const, .func_ref, .copy, .phi => {},
            .dict_new, .dict_len, .dict_find, .dict_entry_key, .dict_entry_value, .dict_set_value => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .dict_insert, .dict_remove, .dict_entries, .dict_entry_live, .dict_copy, .dict_clear => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .str_char, .str_width, .str_code, .str_append, .str_append_char, .str_slice, .str_view_of, .str_slice_view, .str_from_view => try emit_text.instruction(self, out, name, inst),
            .list_sort, .array_get, .array_set, .call_indirect => try emit_fn.instruction(self, out, name, inst),
            .buffer_new, .buffer_copy, .buffer_set, .buffer_push, .buffer_pop, .buffer_append => try emit_bytes.instruction(self, out, name, inst),
            .shift_left, .shift_right, .saturating_add, .float_unary => try emit_number.instruction(self, out, name, inst),
            .add, .sub, .mul => try self.arithmetic(out, name, inst),
            .div, .rem, .floor_div, .floor_rem => try self.division(out, name, inst),
            .neg => {
                const info = inst.ty.integer().?;
                if (self.checkOf(inst) == .exact) {
                    const pair = try self.fresh("%n");
                    const tyname = try self.ty(inst.ty);
                    try out.print(self.a(), "  {s} = call {{ {s}, i1 }} @llvm.{s}sub.with.overflow.{s}({s} 0, {s})\n", .{ pair, tyname, if (info.signed) "s" else "u", tyname, tyname, try self.typedValue(inst.a) });
                    try out.print(self.a(), "  {s} = extractvalue {{ {s}, i1 }} {s}, 0\n", .{ name, tyname, pair });
                    const failed = try self.fresh("%o");
                    try out.print(self.a(), "  {s} = extractvalue {{ {s}, i1 }} {s}, 1\n", .{ failed, tyname, pair });
                    try self.trapIf(out, failed, try self.site(.overflow, inst, "neg"), try self.widened(out, inst.a), "0");
                } else {
                    try out.print(self.a(), "  {s} = sub {s} 0, {s}\n", .{ name, try self.ty(inst.ty), try self.value(inst.a) });
                }
            },
            .bit_and, .bit_or, .bit_xor => {
                const op = switch (inst.op) {
                    .bit_and => "and",
                    .bit_or => "or",
                    else => "xor",
                };
                try out.print(self.a(), "  {s} = {s} {s}, {s}\n", .{ name, op, try self.typedValue(inst.a), try self.value(inst.b) });
            },
            .not => try out.print(self.a(), "  {s} = xor i1 {s}, true\n", .{ name, try self.value(inst.a) }),
            .cmp => {
                const operand_type = self.function.inst(self.function.resolve(inst.a)).ty;
                // Two operands the facts prove non-negative compare the same either way;
                // unsigned predicates let LLVM relate the comparison to unsigned bounds checks.
                const unsigned_safe = self.nonNegative(inst.a) and self.nonNegative(inst.b);
                const signed = if (operand_type.integer()) |info| info.signed and !unsigned_safe else false;
                const predicate: ir.Predicate = @fromBackingInt(@intCast(inst.data));
                const spelled = switch (predicate) {
                    .eq => "eq",
                    .ne => "ne",
                    .lt => if (signed) "slt" else "ult",
                    .le => if (signed) "sle" else "ule",
                    .gt => if (signed) "sgt" else "ugt",
                    .ge => if (signed) "sge" else "uge",
                };
                try out.print(self.a(), "  {s} = icmp {s} {s}, {s}\n", .{ name, spelled, try self.typedValue(inst.a), try self.value(inst.b) });
            },
            .fadd, .fsub, .fmul, .fdiv => {
                const op = switch (inst.op) {
                    .fadd => "fadd",
                    .fsub => "fsub",
                    .fmul => "fmul",
                    else => "fdiv",
                };
                try out.print(self.a(), "  {s} = {s} double {s}, {s}\n", .{ name, op, try self.value(inst.a), try self.value(inst.b) });
            },
            .fneg => try out.print(self.a(), "  {s} = fneg double {s}\n", .{ name, try self.value(inst.a) }),
            .fcmp => {
                const predicate: ir.Predicate = @fromBackingInt(@intCast(inst.data));
                const spelled = switch (predicate) {
                    .eq => "oeq",
                    .ne => "une",
                    .lt => "olt",
                    .le => "ole",
                    .gt => "ogt",
                    .ge => "oge",
                };
                try out.print(self.a(), "  {s} = fcmp {s} double {s}, {s}\n", .{ name, spelled, try self.value(inst.a), try self.value(inst.b) });
            },
            .int_to_float => {
                const source = self.function.inst(self.function.resolve(inst.a)).ty;
                const signed = (source.integer() orelse return error.UnsupportedInstruction).signed;
                if (source == .i64 and self.fitsI32(inst.a)) {
                    // Narrow first: AVX2 converts i32 lanes to doubles in one instruction, i64 lanes not at all.
                    const narrow = try self.fresh("%n32");
                    try out.print(self.a(), "  {s} = trunc i64 {s} to i32\n  {s} = sitofp i32 {s} to double\n", .{ narrow, try self.value(inst.a), name, narrow });
                } else {
                    try out.print(self.a(), "  {s} = {s} {s} to double\n", .{ name, if (signed) "sitofp" else "uitofp", try self.typedValue(inst.a) });
                }
            },
            .float_to_int => try self.floatToInt(out, name, inst),
            .convert => try self.convert(out, name, inst),
            .list_new => {
                const element = self.state.module.compound(inst.ty).list;
                if (inst.data != 0 and inst.data != flags.fill_capacity) return self.stackList(out, name, inst.data - 1, element);
                const capacity = if (inst.data == flags.fill_capacity) try self.fillCapacity(out, inst.a) else try self.value(inst.a);
                try out.print(self.a(), "  {s} = call ptr @myl_core_list_new(i64 {s}, i64 {d})\n", .{ name, capacity, self.state.stride(element) });
                try self.attachLayout(out, name, element);
            },
            .list_len, .str_len => try self.collectionLength(out, name, inst),
            .list_get => try self.listGet(out, name, inst),
            .list_push => try self.listPush(out, name, inst),
            .list_copy => {
                const element = self.state.module.compound(inst.ty).list;
                try out.print(self.a(), "  {s} = call ptr @myl_core_list_copy(ptr {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
            },
            .str_parse_int => {
                const ok = try self.fresh("%ok");
                const parsed = try self.fresh("%int");
                const tag = try self.fresh("%tag");
                const partial = try self.fresh("%opt");
                if (self.typeOf(inst.a) == .str_view) {
                    const data = try self.fresh("%parsedata");
                    const len = try self.fresh("%parselen");
                    try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n" ++
                        "  {s} = call fastcc i1 @myl_core_parse_span_inline(ptr {s}, i64 {s}, ptr %slot)\n", .{ data, try self.value(inst.a), len, try self.value(inst.a), ok, data, len });
                } else try out.print(self.a(), "  {s} = call fastcc i1 @myl_core_parse_int_inline(ptr {s}, ptr %slot)\n", .{ ok, try self.value(inst.a) });
                try out.print(self.a(), "  {s} = load i64, ptr %slot, align 8\n  {s} = zext i1 {s} to i8\n", .{ parsed, tag, ok });
                try out.print(self.a(), "  {s} = insertvalue {{ i8, i64 }} poison, i8 {s}, 0\n  {s} = insertvalue {{ i8, i64 }} {s}, i64 {s}, 1\n", .{ partial, tag, name, partial, parsed });
            },
            .union_make => if (!self.memory.fused[ref.index()]) try self.unionMake(out, name, inst),
            .union_tag => try self.unionTag(out, name, inst.a),
            .union_payload => if (!try self.viewOf(out, name, ref, 8)) try self.unionPayload(out, .{ .result = name, .union_type = self.typeOf(inst.a), .value = try self.value(inst.a), .case = @intCast(inst.data) }),
            .union_take => try self.unionTake(out, name, inst),
            .record_make => if (!self.memory.fused[ref.index()]) try self.recordMake(out, name, inst),
            .record_get => try self.recordGet(out, name, ref, inst),
            .record_set => try self.recordSet(out, name, ref, inst),
            .list_set => try self.listSet(out, name, inst),
            .list_pop => try self.listPop(out, name, inst),
            .list_get_field => try self.listGetField(out, name, inst),
            .list_set_field => try self.listSetField(out, name, inst),
            .box_make => {
                const inner = self.state.module.compound(inst.ty).box;
                try out.print(self.a(), "  {s} = call ptr @myl_core_box_new(i64 {d})\n", .{ name, self.state.module.size(inner) });
                try self.attachLayout(out, name, inner);
                try self.storeOperand(out, inner, inst.a, try self.offsetPointer(out, name, data_offset));
            },
            .box_get => try self.loadValue(out, inst.ty, try self.offsetPointer(out, try self.value(inst.a), data_offset), name),
            .box_take => try self.boxTake(out, name, inst.ty, try self.value(inst.a)),
            .retain, .release => {
                const mode: Counting = if (inst.op == .retain) .retain else .release;
                self.may_be_empty = inst.op == .release and inst.data == empty_release;
                defer self.may_be_empty = false;
                if (inst.op == .release and inst.data == unique_release) {
                    try self.freeUnique(out, inst);
                } else if (self.state.module.passedInMemory(self.typeOf(inst.a))) {
                    try self.countedMemory(out, mode, self.typeOf(inst.a), try self.value(inst.a));
                } else try self.counted(out, mode, self.typeOf(inst.a), try self.value(inst.a));
            },
            .is_unique => try self.isUnique(out, name, inst),
            .err_trace => try self.errTrace(out, inst),
            .call => try self.call(out, name, inst),
            .print => try self.print(out, inst),
            .jump => {
                try emit_state.jump(*FunctionEmitter, self, out, self.vectors.block, @intCast(inst.data));
                try self.vectorPrologue(out, @intCast(inst.data));
                try self.fillMemoryPhis(out, self.vectors.block, @intCast(inst.data));
                try out.print(self.a(), "  br label %b{d}\n", .{inst.data});
            },
            .branch => try self.branchTo(out, inst),
            .ret => try self.returnFrom(out, inst),
            .@"unreachable" => try self.trapTerminator(out, inst),
        }
    }

    /// `is_unique`: the block's count is 1. A counting build counts the test and its unique outcomes.
    fn isUnique(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const count = try self.fresh("%rc");
        try out.print(self.a(), count_load_line ++ "  {s} = icmp eq i32 {s}, 1\n", .{ count, try self.value(inst.a), name, count });
        const record = try self.countSite(out, .unique_test, "") orelse return;
        const unique = try self.fresh("%cnt");
        try out.print(self.a(), "  {s} = zext i1 {s} to i64\n", .{ unique, name });
        const step: emit_count.Increment = .{ .record = record, .offset = emit_count.site_extra, .amount = unique, .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") };
        try emit_count.increment(self.a(), out, step);
    }

    /// `ret`: a value over four words through `sret` (where it may already have been built), and
    /// each in-out parameter's final value into its caller's memory; a counting build first makes
    /// the caller's record current again.
    fn returnFrom(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const m = self.state.module;
        const signature = self.function.signature;
        const abi = inOutAbi(m, signature);
        const sret = inst.a != .none and returnsThroughSret(m, signature, abi);
        if (inst.a != .none and abi.whole) {
            try self.moveAll(out, &.{try self.finalMove(out, @ctz(abi.params), inst.a)});
        } else if (sret and abi.params != 0) {
            try self.returnFinals(out, inst.a, abi);
        } else if (sret and self.memory.homes.staged(self.current)) {
            // A value it reads lies in `%ret` where an earlier store would overwrite it: built
            // whole in a temporary first.
            const temporary = try self.stackSlot(m.size(signature.ret));
            try self.storeOperand(out, signature.ret, inst.a, temporary);
            try self.copyBytes(out, "%ret", temporary, m.size(signature.ret), false);
        } else if (sret) try self.storeAtRet(out, signature.ret, inst.a, 0);
        if (self.count_fn != null) try out.appendSlice(self.a(), emit_count.epilogue);
        if (inst.a == .none or sret or abi.whole) return out.appendSlice(self.a(), "  ret void\n");
        try out.print(self.a(), "  ret {s}\n", .{try self.typedValue(inst.a)});
    }

    /// Store `raw` at `offset` in `%ret` the way `storeOperand` would, except that a value already
    /// at that place (built there, `emit_homes.Planner.buildInRet`) is not stored again. The
    /// stores happen in the order `emit_homes.retStores` lists them.
    fn storeAtRet(self: *FunctionEmitter, out: *Out, value_type: ir.Type, raw: ir.Ref, offset: u32) Error!void {
        const m = self.state.module;
        const f = self.function;
        const ref = f.resolve(raw);
        if (!self.memory.fused[ref.index()]) {
            if (self.memory.homes.retOffset(ref) == offset) return;
            return self.storeValue(out, value_type, try self.value(ref), try self.offsetPointer(out, "%ret", offset));
        }
        const inst = f.inst(ref);
        if (m.kind(inst.ty) == .array) {
            const elem = m.compound(inst.ty).array.elem;
            for (f.operands(inst.data), 0..) |operand, i| try self.storeAtRet(out, elem, operand, offset + @as(u32, @intCast(i)) * m.size(elem));
            return;
        }
        switch (inst.op) {
            .record_make => for (f.operands(inst.data), m.compound(inst.ty).record, 0..) |operand, field, i| {
                try self.storeAtRet(out, field, operand, offset + m.fieldOffset(inst.ty, i));
            },
            .union_make => {
                try out.print(self.a(), "  store i64 {d}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ inst.data, try self.offsetPointer(out, "%ret", offset) });
                if (inst.a == .none) return;
                try self.storeAtRet(out, m.compound(inst.ty).@"union"[@intCast(inst.data)], inst.a, offset + 8);
            },
            else => unreachable,
        }
    }

    /// The copy of `raw`, in-out parameter `param`'s final value, into its caller's memory (empty
    /// when it already lives there).
    fn finalMove(self: *FunctionEmitter, out: *Out, param: usize, raw: ir.Ref) !Move {
        const f = self.function;
        const m = self.state.module;
        const plan = &self.memory.homes;
        const size = m.size(f.signature.params[param]);
        const dst = try std.fmt.allocPrint(self.a(), "%p{d}", .{param});
        const holder = for (f.insts.items, 0..) |inst, index| {
            if (inst.op == .param and inst.data == param) break @as(ir.Ref, @fromBackingInt(@as(u32, @intCast(index))));
        } else ir.Ref.none;
        const value_ref = f.resolve(raw);
        const empty: Move = .{ .dst = dst, .src = dst, .size = 0, .dst_class = emit_homes.none, .src_class = emit_homes.none };
        if (holder != .none and plan.holds(holder, 0, value_ref)) return empty;
        if (f.inst(value_ref).op == .undef and !m.managed(f.inst(value_ref).ty)) return empty;
        var src = try self.value(value_ref);
        if (self.memory.fused[value_ref.index()]) {
            // A construction stored straight here: built in a slot of its own first, since its
            // fields may read memory another final value is moved into.
            src = try self.stackSlot(size);
            try self.storeMake(out, f.inst(value_ref), src);
        }
        return .{ .dst = dst, .src = src, .size = size, .dst_class = if (holder == .none) emit_homes.none else plan.storage(plan.class[holder.index()]), .src_class = plan.storage(plan.rootClass(value_ref)) };
    }

    /// `ret` of a result record holding in-out final values: its other fields go to `%ret` first,
    /// while every final value is still where it is, then each final value to its caller's memory.
    fn returnFinals(self: *FunctionEmitter, out: *Out, raw: ir.Ref, abi: InOutAbi) !void {
        const f = self.function;
        const m = self.state.module;
        const signature = f.signature;
        const composite = f.resolve(raw);
        var moves: std.ArrayList(Move) = .empty;
        std.debug.assert(!self.memory.homes.staged(self.current));
        if (!self.memory.fused[composite.index()]) {
            // A whole record: copied to `%ret`, and each final value from there.
            try self.storeAtRet(out, signature.ret, raw, 0);
            for (signature.params, 0..) |param, i| {
                if (!abi.inOut(i)) continue;
                const at = try self.offsetPointer(out, "%ret", m.fieldOffset(signature.ret, abi.field(signature, i)));
                try self.copyBytes(out, try std.fmt.allocPrint(self.a(), "%p{d}", .{i}), at, m.size(param), false);
            }
            return;
        }
        const operands = f.operands(f.inst(composite).data);
        for (m.compound(signature.ret).record, operands, 0..) |field_type, operand, k| {
            const final = for (0..signature.params.len) |i| {
                if (abi.inOut(i) and abi.field(signature, i) == k) break true;
            } else false;
            if (!final) try self.storeAtRet(out, field_type, operand, m.fieldOffset(signature.ret, k));
        }
        for (0..signature.params.len) |i| {
            if (!abi.inOut(i)) continue;
            try moves.append(self.a(), try self.finalMove(out, i, operands[abi.field(signature, i)]));
        }
        try self.moveAll(out, moves.items);
    }

    fn trapTerminator(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        if (inst.data & flags.text_trap != 0) {
            const kind: TrapKind = @fromBackingInt(@intCast(@as(u8, @truncate(inst.data))));
            const index = try self.site(kind, inst, "text");
            try out.print(self.a(), zero_trap_line, .{ index, try self.trapLocation(index) });
        } else if (inst.data == capacity_assert) {
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "a stack list's length below its capacity", .function = self.sourceFunction().name });
            try out.print(self.a(), zero_trap_line, .{ index, try self.trapLocation(index) });
        } else if (inst.data == unique_assert) {
            // `own.zig`'s assert of a statically unique update (verify builds only).
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 32, .operation = "count == 1 before an in-place update", .function = self.sourceFunction().name });
            try out.print(self.a(), "  call void @myl_core_trap(ptr @myl.site.{d}, i64 0, i64 1) #2{s}\n  unreachable\n", .{ index, try self.trapLocation(index) });
        } else if (inst.data == flags.dict_missing_trap) {
            const index = try self.site(.missing_key, inst, "key");
            try out.print(self.a(), zero_trap_line, .{ index, try self.trapLocation(index) });
        } else if (inst.data == flags.iteration_trap) {
            const index = try self.site(.iteration_mutation, inst, "iteration");
            try out.print(self.a(), zero_trap_line, .{ index, try self.trapLocation(index) });
        } else if (inst.data & flags.assertion_trap != 0) {
            // A failed `assert` or contract clause: the message is in the module's string table.
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const kind: u16 = @truncate(inst.data >> 32);
            const message = self.state.module.strings.items[@as(u32, @truncate(inst.data))];
            const index = try self.state.site(.{ .kind = .assertion, .location = location, .width = kind, .operation = message, .function = self.sourceFunction().name });
            try out.print(self.a(), "  call void @myl_core_assert_fail(ptr @myl.site.{d}) #2{s}\n  unreachable\n", .{ index, try self.trapLocation(index) });
        } else try out.appendSlice(self.a(), "  unreachable\n");
    }

    fn arithmetic(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const info = inst.ty.integer() orelse return error.UnsupportedInstruction;
        const op = switch (inst.op) {
            .add => "add",
            .sub => "sub",
            else => "mul",
        };
        const tyname = try self.ty(inst.ty);
        switch (self.checkOf(inst)) {
            .exact => {
                const pair = try self.fresh("%p");
                try out.print(self.a(), "  {s} = call {{ {s}, i1 }} @llvm.{s}{s}.with.overflow.{s}({s}, {s})\n", .{ pair, tyname, if (info.signed) "s" else "u", op, tyname, try self.typedValue(inst.a), try self.typedValue(inst.b) });
                try out.print(self.a(), "  {s} = extractvalue {{ {s}, i1 }} {s}, 0\n", .{ name, tyname, pair });
                const failed = try self.fresh("%o");
                try out.print(self.a(), "  {s} = extractvalue {{ {s}, i1 }} {s}, 1\n", .{ failed, tyname, pair });
                try self.trapIf(out, failed, try self.site(.overflow, inst, op), try self.widened(out, inst.a), try self.widened(out, inst.b));
            },
            .proven => {
                // A proven signed operation on non-negative operands with a non-negative result wraps in neither sense.
                const both = info.signed and self.nonNegative(inst.a) and self.nonNegative(inst.b) and self.nonNegative(self.refOf(name));
                try out.print(self.a(), binary_line, .{ name, op, if (both) "nuw nsw" else if (info.signed) "nsw" else "nuw", try self.typedValue(inst.a), try self.value(inst.b) });
            },
            .none => try out.print(self.a(), "  {s} = {s} {s}, {s}\n", .{ name, op, try self.typedValue(inst.a), try self.value(inst.b) }),
        }
    }

    /// Truncating and floor division and remainder. Checks a zero divisor and
    /// the one signed overflow (`MIN / -1`) unless the divisor is a constant
    /// that rules them out; `proven` means both operands are non-negative.
    fn division(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const info = inst.ty.integer() orelse return error.UnsupportedInstruction;
        const tyname = try self.ty(inst.ty);
        const left = try self.value(inst.a);
        const right = try self.value(inst.b);
        const is_rem = inst.op == .rem or inst.op == .floor_rem;
        const operation = @tagName(inst.op);
        if (inst.check == .proven and self.state.options.verify) {
            // The fact behind `proven`: both operands non-negative, the divisor positive. An unsigned
            // operand is never negative (its high values are not), so only the divisor's zero is tested.
            const nonpositive = try self.fresh("%vz");
            var either = nonpositive;
            if (info.signed) {
                const negative = try self.fresh("%vn");
                either = try self.fresh("%ve");
                try out.print(self.a(), "  {s} = icmp slt {s} {s}, 0\n  {s} = icmp sle {s} {s}, 0\n", .{ negative, tyname, left, nonpositive, tyname, right });
                try out.print(self.a(), or_line, .{ either, negative, nonpositive });
            } else try out.print(self.a(), zero_test_line, .{ nonpositive, tyname, right });
            try self.trapIf(out, either, try self.site(.division_by_zero, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
        }
        if (!info.signed or inst.check == .proven) {
            const divisor = self.constantOf(inst.b);
            if (inst.check != .proven and (divisor == null or divisor.? == 0)) {
                const zero = try self.fresh("%z");
                try out.print(self.a(), zero_test_line, .{ zero, tyname, right });
                try self.trapIf(out, zero, try self.site(.division_by_zero, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
            }
            if (info.bits == 64 and self.fitsU32(inst.a) and self.fitsU32(inst.b)) return self.narrowDivision(out, name, is_rem, .{ left, right });
            try out.print(self.a(), binary_line, .{ name, if (is_rem) "urem" else "udiv", tyname, left, right });
            return;
        }
        const divisor = self.constantOf(inst.b);
        if (divisor == null or divisor.? == 0) {
            const zero = try self.fresh("%z");
            try out.print(self.a(), zero_test_line, .{ zero, tyname, right });
            try self.trapIf(out, zero, try self.site(.division_by_zero, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
        }
        // `MIN / -1` overflows; `MIN % -1` is 0, which LLVM's `srem` leaves undefined.
        var safe = right;
        // With a divisor of -1 the division runs by 1 instead (no `srem` UB), and the
        // quotient is then replaced by `-left` (MIN // -1 trapped above); the remainder is 0 either way.
        var minus_one_flag: ?[]const u8 = null;
        if (divisor == null or divisor.? == -1) {
            const minus_one = try self.fresh("%m");
            minus_one_flag = minus_one;
            try out.print(self.a(), "  {s} = icmp eq {s} {s}, -1\n", .{ minus_one, tyname, right });
            if (!is_rem) {
                const minimum = try self.fresh("%mn");
                const both = try self.fresh("%ov");
                try out.print(self.a(), "  {s} = icmp eq {s} {s}, {d}\n  {s} = and i1 {s}, {s}\n", .{ minimum, tyname, left, -(@as(i128, 1) << @intCast(info.bits - 1)), both, minimum, minus_one });
                try self.trapIf(out, both, try self.site(.overflow, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
            }
            safe = try self.fresh("%d");
            try out.print(self.a(), "  {s} = select i1 {s}, {s} 1, {s} {s}\n", .{ safe, minus_one, tyname, tyname, right });
        }
        // The quotient as computed with `safe`; `name` is bound last.
        const computed = if (!is_rem and minus_one_flag != null) try self.fresh("%qd") else name;
        if (inst.op == .div or inst.op == .rem) {
            try out.print(self.a(), binary_line, .{ computed, if (is_rem) "srem" else "sdiv", tyname, left, safe });
        } else {
            try self.floorAdjust(out, .{ .result = computed, .type_name = tyname, .left = left, .right = right, .safe = safe, .is_rem = is_rem });
        }
        if (computed.ptr != name.ptr) {
            const negated = try self.fresh("%qn");
            try out.print(self.a(), "  {s} = sub {s} 0, {s}\n  {s} = select i1 {s}, {s} {s}, {s} {s}\n", .{ negated, tyname, left, name, minus_one_flag.?, tyname, negated, tyname, computed });
        }
    }

    /// Python floor semantics: adjust when the remainder is nonzero and its sign differs from the divisor's.
    fn floorAdjust(self: *FunctionEmitter, out: *Out, d: FloorOperands) !void {
        const tyname = d.type_name;
        const left = d.left;
        const right = d.right;
        const safe = d.safe;
        const q = try self.fresh("%q");
        const r = try self.fresh("%r");
        const nonzero = try self.fresh("%rnz");
        const mixed = try self.fresh("%x");
        const negative = try self.fresh("%neg");
        const fix = try self.fresh("%fix");
        try out.print(self.a(), "  {s} = sdiv {s} {s}, {s}\n  {s} = srem {s} {s}, {s}\n", .{ q, tyname, left, safe, r, tyname, left, safe });
        try out.print(self.a(), "  {s} = icmp ne {s} {s}, 0\n  {s} = xor {s} {s}, {s}\n", .{ nonzero, tyname, r, mixed, tyname, r, right });
        try out.print(self.a(), "  {s} = icmp slt {s} {s}, 0\n  {s} = and i1 {s}, {s}\n", .{ negative, tyname, mixed, fix, nonzero, negative });
        if (d.is_rem) {
            const add = try self.fresh("%ra");
            try out.print(self.a(), "  {s} = select i1 {s}, {s} {s}, {s} 0\n  {s} = add {s} {s}, {s}\n", .{ add, fix, tyname, right, tyname, d.result, tyname, r, add });
        } else {
            const sub = try self.fresh("%qs");
            try out.print(self.a(), "  {s} = zext i1 {s} to {s}\n  {s} = sub {s} {s}, {s}\n", .{ sub, fix, tyname, d.result, tyname, q, sub });
        }
    }

    fn convert(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const source_type = self.function.inst(self.function.resolve(inst.a)).ty;
        const from = source_type.integer() orelse return error.UnsupportedInstruction;
        const to = inst.ty.integer() orelse return error.UnsupportedInstruction;
        const from_name = try self.ty(source_type);
        const operand = try self.value(inst.a);
        if (self.checkOf(inst) == .exact) {
            const lo_from: i128 = if (from.signed) -(@as(i128, 1) << @intCast(from.bits - 1)) else 0;
            const hi_from: i128 = if (from.signed) (@as(i128, 1) << @intCast(from.bits - 1)) - 1 else (@as(i128, 1) << @intCast(from.bits)) - 1;
            const lo_to: i128 = if (to.signed) -(@as(i128, 1) << @intCast(to.bits - 1)) else 0;
            const hi_to: i128 = if (to.signed) (@as(i128, 1) << @intCast(to.bits - 1)) - 1 else (@as(i128, 1) << @intCast(to.bits)) - 1;
            var failed: ?[]const u8 = null;
            if (lo_to > lo_from) {
                const below = try self.fresh("%lo");
                try out.print(self.a(), bound_line, .{ below, if (from.signed) "slt" else "ult", from_name, operand, lo_to });
                failed = below;
            }
            if (hi_to < hi_from) {
                const above = try self.fresh("%hi");
                // `hi_to` fits the source type here, so print it in that type's two's complement.
                try out.print(self.a(), bound_line, .{ above, if (from.signed) "sgt" else "ugt", from_name, operand, hi_to });
                if (failed) |other| {
                    const either = try self.fresh("%cv");
                    try out.print(self.a(), or_line, .{ either, other, above });
                    failed = either;
                } else failed = above;
            }
            if (failed) |condition| try self.trapIf(out, condition, try self.site(.cast, inst, "cast"), try self.widened(out, inst.a), "0");
        }
        if (to.bits == from.bits) {
            // Same width: the bits are the value; an `add 0` names it for later uses.
            try out.print(self.a(), "  {s} = add {s} {s}, 0\n", .{ name, from_name, operand });
        } else if (to.bits > from.bits) {
            try out.print(self.a(), "  {s} = {s} {s} {s} to {s}\n", .{ name, if (from.signed) "sext" else "zext", from_name, operand, try self.ty(inst.ty) });
        } else {
            try out.print(self.a(), "  {s} = trunc {s} {s} to {s}\n", .{ name, from_name, operand, try self.ty(inst.ty) });
        }
    }

    fn floatToInt(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const to = inst.ty.integer() orelse return error.UnsupportedInstruction;
        const lo: f64 = if (to.signed) -std.math.pow(f64, 2, @floatFromInt(to.bits - 1)) else -1.0;
        const hi: f64 = if (to.signed) std.math.pow(f64, 2, @floatFromInt(to.bits - 1)) else std.math.pow(f64, 2, @floatFromInt(to.bits));
        const operand = try self.value(inst.a);
        if (self.checkOf(inst) == .exact) {
            const above_lo = try self.fresh("%fl");
            const below_hi = try self.fresh("%fh");
            const ok = try self.fresh("%fok");
            const failed = try self.fresh("%fbad");
            // The value is truncated toward zero first, then checked: every target accepts the
            // values that truncate into its range, which are those above `lo - 1` (signed: `lo`
            // itself when `lo - 1` is not a double) and below `hi`; unsigned ones accept (-1, 2^N).
            const above = if (to.signed and lo - 1.0 != lo) lo - 1.0 else lo;
            const inclusive = to.signed and lo - 1.0 == lo;
            try out.print(self.a(), "  {s} = fcmp {s} double {s}, 0x{X:0>16}\n", .{ above_lo, if (inclusive) "oge" else "ogt", operand, @as(u64, @bitCast(above)) });
            try out.print(self.a(), "  {s} = fcmp olt double {s}, 0x{X:0>16}\n  {s} = and i1 {s}, {s}\n  {s} = xor i1 {s}, true\n", .{ below_hi, operand, @as(u64, @bitCast(hi)), ok, above_lo, below_hi, failed, ok });
            const bits = try self.fresh("%fb");
            try out.print(self.a(), "  {s} = bitcast double {s} to i64\n", .{ bits, operand });
            try self.trapIf(out, failed, try self.site(.float_conversion, inst, "convert"), bits, "0");
        }
        if (inst.ty == .i64 and inst.check == .proven and self.fitsI32(self.refOf(name))) {
            const narrow = try self.fresh("%f32");
            try out.print(self.a(), "  {s} = fptosi double {s} to i32\n  {s} = sext i32 {s} to i64\n", .{ narrow, operand, name, narrow });
            return;
        }
        try out.print(self.a(), "  {s} = {s} double {s} to {s}\n", .{ name, if (to.signed) "fptosi" else "fptoui", operand, try self.ty(inst.ty) });
    }

    fn collectionLength(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        if (self.typeOf(inst.a) == .str_view) return out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ name, try self.value(inst.a) });
        const at = try self.fresh("%h");
        try out.print(self.a(), header_tagged_line, .{ at, try self.value(inst.a), len_offset, name, at });
    }

    fn listGet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const list = try self.value(inst.a);
        const index = try self.checkedIndex(out, inst, list, try self.value(inst.b));
        // A read nothing uses is only its bounds check: the element is never loaded (a verify
        // build still loads it, for the fact assertions that name it).
        if (self.memory.uses[self.current.index()] == 0 and inst.data == 0 and self.knownFacts() == null) return;
        const slot = try self.elementSlot(out, list, index, inst.ty);
        // A lent element (`lentElements`) is its slot: no copy.
        if (self.lent(self.current)) return out.print(self.a(), identity_line, .{ name, slot });
        const saved = self.tagElements(true);
        defer _ = self.tagElements(saved);
        if (inst.ty == .bool or inst.ty.isCompound()) return self.loadValue(out, inst.ty, slot, name);
        const stored = storageType(inst.ty);
        try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}{s}, {s}\n", .{ name, stored, slot, elementSize(inst.ty), try self.loadRange(name, inst.ty), self.dataTag(stored) });
    }

    /// `boundsCheck`, answering the index the element's address takes. An index the builder
    /// normalized from the end (`facts.normalizedRaw`) is first tested as the program wrote it:
    /// a written index below the length, compared unsigned, is non-negative and so its own
    /// normalization, and only the others take the normalized value and its check, off the hot
    /// path (NEW-CORE-F2-WRAP-1). The check is counted once either way.
    fn checkedIndex(self: *FunctionEmitter, out: *Out, inst: ir.Inst, list: []const u8, index: []const u8) Error![]const u8 {
        const raw_ref = self.fromEndRaw(inst.b);
        const plain = inst.op == .list_get and (inst.data == flags.pop_read or inst.data == flags.pop_index_read);
        if (self.checkOf(inst) != .exact and raw_ref != .none and !plain) {
            // A proven access whose index a dominating checked access normalized reuses its value.
            const made = self.memory.checked.get(self.normalizedKey(inst, raw_ref) orelse return index) orelse return index;
            return if (self.blockDominates(made.block, self.vectors.block)) made.name else index;
        }
        if (self.checkOf(inst) != .exact or raw_ref == .none or plain) {
            try self.boundsCheck(out, inst, list, index);
            return index;
        }
        const raw = try self.value(raw_ref);
        const at = try self.fresh("%lh");
        const len = try self.fresh("%len");
        const written = try self.fresh("%rawout");
        try out.print(self.a(), header_tagged_line, .{ at, list, len_offset, len, at });
        const site_index = try self.site(.list_bounds, inst, "index");
        if (self.count_fn != null) _ = try self.countSite(out, checkKind(self.state.sites.items[site_index].kind), "");
        const entry = self.label;
        const slow = try self.fresh("wrapped");
        const join = try self.fresh(self.label);
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}, !prof !9\n{s}:\n", .{ written, raw, len, written, slow, join, slow });
        const outside = try self.fresh("%oob");
        const trap = try self.fresh("trap");
        const next = try self.fresh(slow);
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}, !prof !0\n{s}:\n", .{ outside, index, len, outside, trap, next, trap });
        try self.trapEnd(out, .{ .next = next, .site = site_index, .location = try self.trapLocation(site_index) }, .{ .left = raw, .right = len });
        const chosen = try self.fresh("%index");
        try out.print(self.a(), "  br label %{s}\n{s}:\n  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ join, join, chosen, raw, entry, index, next });
        self.label = join;
        if (self.normalizedKey(inst, raw_ref)) |key| try self.memory.checked.put(self.a(), key, .{ .name = chosen, .block = self.vectors.block });
        return chosen;
    }

    /// The key of an access's written index normalized against its list's length.
    fn normalizedKey(self: *FunctionEmitter, inst: ir.Inst, raw: ir.Ref) ?NormalizedKey {
        const keys = self.memory.keys orelse return null;
        return .{ .index = keys.index(raw), .length = keys.length(inst.a) };
    }

    /// Whether IR block `dominator` dominates IR block `block` (each dominates itself).
    fn blockDominates(self: *FunctionEmitter, dominator: u32, block: u32) bool {
        const shape = self.memory.shape orelse return false;
        var current: u32 = block;
        var steps: usize = 0;
        while (steps <= shape.idom.len) : (steps += 1) {
            if (current == dominator) return true;
            if (current == 0) return false;
            const up = shape.idom[current] orelse return false;
            current = @intCast(up.index());
        }
        return false;
    }

    /// The index the program wrote, when `index` is its Python normalization; else `.none`.
    fn fromEndRaw(self: *FunctionEmitter, index: ir.Ref) ir.Ref {
        const ref = self.function.resolve(index);
        if (ref.index() >= self.memory.from_end.len) return .none;
        return self.memory.from_end[ref.index()];
    }

    /// Trap unless `0 <= index < len(list)` (the index is unsigned here), for an exact check.
    pub fn boundsCheck(self: *FunctionEmitter, out: *Out, inst: ir.Inst, list: []const u8, index: []const u8) Error!void {
        if (self.checkOf(inst) != .exact) return;
        const at = try self.fresh("%lh");
        const len = try self.fresh("%len");
        const outside = try self.fresh("%oob");
        try out.print(self.a(), header_tagged_line, .{ at, list, len_offset, len, at });
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n", .{ outside, index, len });
        // The read a `pop` starts with fails exactly when the list is empty, which is the pop trap.
        if (inst.op == .list_get and inst.data == flags.pop_read) return self.trapIf(out, outside, try self.site(.list_empty, inst, "pop"), "0", len);
        if (inst.op == .list_get and inst.data == flags.pop_index_read) {
            // Only a too-negative original index can remain negative after normalization.
            const negative = try self.fresh("%popnegative");
            const before = try self.fresh("%popbefore");
            const original = try self.fresh("%popindex");
            try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = sub i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ negative, index, before, index, len, original, negative, before, index });
            return self.trapIf(out, outside, try self.site(.list_pop_index, inst, "pop"), original, len);
        }
        const source_index = emit_bytes.sourceIndex(@TypeOf(self), self, inst.b);
        if (source_index) |raw| return self.trapIf(out, outside, try self.site(.list_bounds, inst, "index"), try self.value(raw), len);
        try self.trapBounds(out, outside, try self.site(.list_bounds, inst, "index"), .{ .index = index, .len = len, .from_end = self.countsFromEnd(inst.b) });
    }

    /// An index bounds check's operands: the normalized index, the length, and whether the
    /// index was normalized from the end.
    pub const TrapBounds = struct { index: []const u8, len: []const u8, from_end: bool };

    /// Trap when `failed`, reporting the index the program wrote: an index normalized from
    /// the end is recovered on the trap's cold path, so the in-bounds path is unchanged.
    pub fn trapBounds(self: *FunctionEmitter, out: *Out, failed: []const u8, site_index: u32, bounds: TrapBounds) Error!void {
        if (!bounds.from_end) return self.trapIf(out, failed, site_index, bounds.index, bounds.len);
        const branch = try self.trapBegin(out, failed, site_index);
        const original = try self.originalIndex(out, bounds.index, bounds.len);
        try self.trapEnd(out, branch, .{ .left = original, .right = bounds.len });
    }

    /// Whether `index` is the join of a Python index normalization: a phi of the
    /// original index and the length plus it, as `xs[i]` builds it for a signed `i`.
    pub fn countsFromEnd(self: *FunctionEmitter, index: ir.Ref) bool {
        const f = self.function;
        const join = f.inst(f.resolve(index));
        if (join.op != .phi) return false;
        const incoming = f.operands(join.data);
        if (incoming.len != 2) return false;
        for ([_][2]ir.Ref{ .{ incoming[0], incoming[1] }, .{ incoming[1], incoming[0] } }) |pair| {
            const original = f.resolve(pair[0]);
            const sum = f.inst(f.resolve(pair[1]));
            if (sum.op == .add and (f.resolve(sum.a) == original or f.resolve(sum.b) == original)) return true;
        }
        return false;
    }

    /// The index the program wrote, recovered from its normalization (NEW-CORE-S5-UNITS-1):
    /// only a too-negative original stays negative, and it was the length less.
    pub fn originalIndex(self: *FunctionEmitter, out: *Out, index: []const u8, len: []const u8) Error![]const u8 {
        const negative = try self.fresh("%fromend");
        const before = try self.fresh("%frombefore");
        const original = try self.fresh("%fromindex");
        try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = sub i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ negative, index, before, index, len, original, negative, before, index });
        return original;
    }

    /// The address of element `index` of `list`: a typed `getelementptr` for scalars and
    /// pointers, a byte stride for records and unions stored inline.
    fn elementSlot(self: *FunctionEmitter, out: *Out, list: []const u8, index: []const u8, element: ir.Type) ![]const u8 {
        const data = try self.fresh("%data");
        const slot = try self.fresh("%elt");
        const inline_value = element.isCompound() and !self.state.module.isBlock(element);
        const stepped = if (inline_value) try std.fmt.allocPrint(self.a(), "[{d} x i8]", .{self.state.stride(element)}) else storageType(element);
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = getelementptr inbounds {s}, ptr {s}, i64 {s}\n", .{ data, list, data_offset, slot, stepped, data, index });
        return slot;
    }

    /// The type of the value `raw` stands for.
    /// The resolved Core type of an operand.
    pub fn typeOf(self: *FunctionEmitter, raw: ir.Ref) ir.Type {
        return self.function.inst(self.function.resolve(raw)).ty;
    }

    /// `ptr + offset`, or `ptr` itself at offset 0.
    fn offsetPointer(self: *FunctionEmitter, out: *Out, ptr: []const u8, offset: u32) ![]const u8 {
        if (offset == 0) return ptr;
        const at = try self.fresh("%fp");
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n", .{ at, ptr, offset });
        return at;
    }

    /// An entry-block stack slot of `bytes` bytes, 8-byte aligned.
    /// An entry-block stack slot for operation sub-emitters.
    pub fn stackSlot(self: *FunctionEmitter, bytes: u32) Error![]const u8 {
        const slot = try self.fresh("%stack");
        try self.state.allocas.print(self.a(), "  {s} = alloca [{d} x i8], align 8\n", .{ slot, @max(bytes, 1) });
        return slot;
    }

    /// The TBAA tag of a scalar load or store of LLVM type `storage`: its element tag
    /// inside a list operation (`element_tags`), else the generic data tag.
    fn dataTag(self: *const FunctionEmitter, storage: []const u8) []const u8 {
        return if (self.element_tags) elementTag(storage) else tbaa_data;
    }

    /// Enter (or, given the saved state, leave) a list operation's element accesses.
    fn tagElements(self: *FunctionEmitter, on: bool) bool {
        const saved = self.element_tags;
        self.element_tags = on;
        return saved;
    }

    /// Load the memory image of a `ty` value at `ptr` into register value `result`: field
    /// by field for records and unions, so no aggregate load is emitted (§3).
    /// Load a typed value field by field from an operation sub-emitter slot.
    pub fn loadValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, ptr: []const u8, result: []const u8) Error!void {
        const m = self.state.module;
        if (value_type == .void) return error.UnsupportedInstruction;
        if (m.passedInMemory(value_type)) {
            // A value over four words is copied into its home, or into a stack slot of its own: its SSA value is that slot.
            if (self.homedName(result)) return self.copyBytes(out, result, ptr, m.size(value_type), false);
            const slot = try self.stackSlot(m.size(value_type));
            try self.copyBytes(out, slot, ptr, m.size(value_type), false);
            try out.print(self.a(), identity_line, .{ result, slot });
            return;
        }
        if (value_type == .bool) {
            const byte = try self.fresh("%lb");
            try out.print(self.a(), "  {s} = load i8, ptr {s}, align 1, {s}\n  {s} = trunc i8 {s} to i1\n", .{ byte, ptr, self.dataTag("i8"), result, byte });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            const llvm_type = try self.ty(value_type);
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}, {s}\n", .{ result, llvm_type, ptr, m.size(value_type), self.dataTag(llvm_type) });
            return;
        }
        const tyname = try self.ty(value_type);
        switch (m.compound(value_type)) {
            .record => |fields| {
                if (fields.len == 0) {
                    try out.print(self.a(), "  {s} = select i1 true, {s} zeroinitializer, {s} zeroinitializer\n", .{ result, tyname, tyname });
                    return;
                }
                var partial: []const u8 = "poison";
                for (fields, 0..) |field, i| {
                    const field_value = try self.fresh("%lf");
                    try self.loadValue(out, field, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)), field_value);
                    const next = if (i + 1 == fields.len) result else try self.fresh("%lr");
                    try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s} {s}, {d}\n", .{ next, tyname, partial, try self.ty(field), field_value, i });
                    partial = next;
                }
            },
            .@"union" => {
                // A union's tag and payload words keep the generic tag: the cases share them.
                const saved = self.tagElements(false);
                defer _ = self.tagElements(saved);
                const layout = m.unionLayout(value_type);
                if (layout.form == .niche) {
                    try out.print(self.a(), "  {s} = load ptr, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ result, ptr });
                    return;
                }
                const word = try self.fresh("%lt");
                const tag = try self.fresh("%lt");
                try out.print(self.a(), tag_load_line, .{ word, ptr, tag, word });
                const last_words = layout.form == .words and layout.payload_words == 0;
                const tagged = if (last_words) result else try self.fresh("%lu");
                try out.print(self.a(), "  {s} = insertvalue {s} poison, i8 {s}, 0\n", .{ tagged, tyname, tag });
                const payload_at = try self.offsetPointer(out, ptr, 8);
                if (layout.form == .scalar) {
                    const payload = try self.fresh("%lp");
                    try self.loadValue(out, layout.payload, payload_at, payload);
                    try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s} {s}, 1\n", .{ result, tyname, tagged, try self.ty(layout.payload), payload });
                    return;
                }
                var partial = tagged;
                for (0..layout.payload_words) |k| {
                    const loaded = try self.fresh("%lw");
                    try out.print(self.a(), word_load_line, .{ loaded, try self.offsetPointer(out, payload_at, @intCast(8 * k)) });
                    const next = if (k + 1 == layout.payload_words) result else try self.fresh("%lu");
                    try out.print(self.a(), "  {s} = insertvalue {s} {s}, i64 {s}, 1, {d}\n", .{ next, tyname, partial, loaded, k });
                    partial = next;
                }
            },
            .array => |array| {
                var partial: []const u8 = "poison";
                for (0..array.n) |i| {
                    const loaded = try self.fresh("%la");
                    try self.loadValue(out, array.elem, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)), loaded);
                    const next = if (i + 1 == array.n) result else try self.fresh("%la");
                    try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s} {s}, {d}\n", .{ next, tyname, partial, try self.ty(array.elem), loaded, i });
                    partial = next;
                }
                if (array.n == 0) try out.print(self.a(), "  {s} = freeze {s} zeroinitializer\n", .{ result, tyname });
            },
            .list, .box, .dict, .@"fn" => unreachable,
        }
    }

    /// Store register value `value` of type `ty` as its memory image at `ptr`, field by field.
    /// Store a typed value field by field into an operation sub-emitter slot.
    pub fn storeValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, text: []const u8, ptr: []const u8) Error!void {
        const m = self.state.module;
        if (value_type == .void) return error.UnsupportedInstruction;
        if (m.passedInMemory(value_type)) return self.copyBytes(out, ptr, text, m.size(value_type), false);
        if (value_type == .bool) {
            const byte = try self.fresh("%sb");
            try out.print(self.a(), "  {s} = zext i1 {s} to i8\n  store i8 {s}, ptr {s}, align 1, {s}\n", .{ byte, text, byte, ptr, self.dataTag("i8") });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            const llvm_type = try self.ty(value_type);
            try out.print(self.a(), "  store {s} {s}, ptr {s}, align {d}, {s}\n", .{ llvm_type, text, ptr, m.size(value_type), self.dataTag(llvm_type) });
            return;
        }
        const tyname = try self.ty(value_type);
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                const field_value = try self.fresh("%sf");
                try out.print(self.a(), extract_value_line, .{ field_value, tyname, text, i });
                try self.storeValue(out, field, field_value, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)));
            },
            .@"union" => {
                const saved = self.tagElements(false);
                defer _ = self.tagElements(saved);
                const layout = m.unionLayout(value_type);
                if (layout.form == .niche) {
                    try out.print(self.a(), "  store ptr {s}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ text, ptr });
                    return;
                }
                const tag = try self.fresh("%st");
                const word = try self.fresh("%st");
                // The whole tag word is written, so a later load of it is defined.
                try out.print(self.a(), "  {s} = extractvalue {s} {s}, 0\n  {s} = zext i8 {s} to i64\n  store i64 {s}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ tag, tyname, text, word, tag, word, ptr });
                const payload_at = try self.offsetPointer(out, ptr, 8);
                if (layout.form == .scalar) {
                    const payload = try self.fresh("%sp");
                    try out.print(self.a(), "  {s} = extractvalue {s} {s}, 1\n", .{ payload, tyname, text });
                    return self.storeValue(out, layout.payload, payload, payload_at);
                }
                for (0..layout.payload_words) |k| {
                    const stored = try self.fresh("%sw");
                    try out.print(self.a(), "  {s} = extractvalue {s} {s}, 1, {d}\n", .{ stored, tyname, text, k });
                    try out.print(self.a(), "  store i64 {s}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ stored, try self.offsetPointer(out, payload_at, @intCast(8 * k)) });
                }
            },
            .array => |array| for (0..array.n) |i| {
                const element = try self.fresh("%sa");
                try out.print(self.a(), extract_value_line, .{ element, tyname, text, i });
                try self.storeValue(out, array.elem, element, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)));
            },
            .list, .box, .dict, .@"fn" => unreachable,
        }
    }

    /// Copy `size` bytes from `src` to `dst`; `overlap` when they may be the same slot.
    fn copyBytes(self: *FunctionEmitter, out: *Out, dst: []const u8, src: []const u8, size: u32, overlap: bool) !void {
        if (self.count_fn != null) _ = try self.countSite(out, .record_copy, try std.fmt.allocPrint(self.a(), "{d}", .{size}));
        try out.print(self.a(), "  call void @llvm.mem{s}.p0.p0.i64(ptr {s}, ptr {s}, i64 {d}, i1 false)\n", .{ if (overlap) "move" else "cpy", dst, src, size });
    }

    /// Store operand `raw` of type `value_type` at `dst`: a construction fused into this store
    /// writes its fields there, any other value is stored as its memory image.
    pub fn storeOperand(self: *FunctionEmitter, out: *Out, value_type: ir.Type, raw: ir.Ref, dst: []const u8) Error!void {
        const ref = self.function.resolve(raw);
        if (self.memory.fused[ref.index()]) return self.storeMake(out, self.function.inst(ref), dst);
        return self.storeValue(out, value_type, try self.value(ref), dst);
    }

    /// The fields of a `record_make`, or the tag word and payload of a `union_make`, stored at `dst`
    /// with no temporary: nothing is built in registers or copied.
    fn storeMake(self: *FunctionEmitter, out: *Out, inst: ir.Inst, dst: []const u8) Error!void {
        const m = self.state.module;
        if (m.kind(inst.ty) == .array) {
            const array = m.compound(inst.ty).array;
            for (self.function.operands(inst.data), 0..) |operand, i| try self.storeOperand(out, array.elem, operand, try self.offsetPointer(out, dst, @as(u32, @intCast(i)) * m.size(array.elem)));
            return;
        }
        switch (inst.op) {
            .record_make => for (self.function.operands(inst.data), m.compound(inst.ty).record, 0..) |operand, field, i| {
                try self.storeOperand(out, field, operand, try self.offsetPointer(out, dst, m.fieldOffset(inst.ty, i)));
            },
            .union_make => {
                const saved = self.tagElements(false);
                defer _ = self.tagElements(saved);
                try out.print(self.a(), "  store i64 {d}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ inst.data, dst });
                if (inst.a == .none) return;
                try self.storeOperand(out, m.compound(inst.ty).@"union"[@intCast(inst.data)], inst.a, try self.offsetPointer(out, dst, 8));
            },
            else => unreachable,
        }
    }

    /// Where a value over four words named `name` is built: its home, or a fresh stack slot
    /// (`fresh`, which the caller then names `name`).
    fn destination(self: *FunctionEmitter, name: []const u8, size: u32) !struct { ptr: []const u8, fresh: bool } {
        if (self.homedName(name)) return .{ .ptr = name, .fresh = false };
        return .{ .ptr = try self.stackSlot(size), .fresh = true };
    }

    /// A record or union over four words, built in its home (or a stack slot of its own).
    fn makeInMemory(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const into = try self.destination(name, self.state.module.size(inst.ty));
        try self.storeMake(out, inst, into.ptr);
        if (into.fresh) try out.print(self.a(), identity_line, .{ name, into.ptr });
    }

    /// A view (`emit_homes.zig`): the field or payload at `offset` inside its operand, named
    /// where it lies with no copy. Returns false when `ref` is not a view.
    fn viewOf(self: *FunctionEmitter, out: *Out, name: []const u8, ref: ir.Ref, offset: u32) !bool {
        const plan = &self.memory.homes;
        if (ref.index() >= plan.view.len or plan.view[ref.index()] == .none) return false;
        try out.print(self.a(), header_pointer_line, .{ name, try self.value(plan.view[ref.index()]), offset });
        return true;
    }

    /// Whether `ref` is the final value of an in-out argument read out of its call's result:
    /// the call already wrote it into `ref`'s home.
    fn writtenByCall(self: *FunctionEmitter, ref: ir.Ref, inst: ir.Inst) bool {
        if (inst.op != .record_get) return false;
        const maker = self.function.resolve(inst.a).index();
        if (maker >= self.memory.in_out.args.len) return false;
        const in_outs = self.memory.in_out.args[maker];
        for (in_outs) |in_out| if (in_out.final == ref) return true;
        return false;
    }

    /// `record_get`: `extractvalue` from a record in registers, one load from a record in memory;
    /// a field over four words is a view of it, or was written by an in-out call.
    fn recordGet(self: *FunctionEmitter, out: *Out, name: []const u8, ref: ir.Ref, inst: ir.Inst) !void {
        const m = self.state.module;
        const record_type = self.typeOf(inst.a);
        if (!m.passedInMemory(record_type)) return out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(inst.a), inst.data });
        if (self.writtenByCall(ref, inst)) return;
        const offset = m.fieldOffset(record_type, @intCast(inst.data));
        if (try self.viewOf(out, name, ref, offset)) return;
        const at = try self.offsetPointer(out, try self.value(inst.a), offset);
        try self.loadValue(out, inst.ty, at, name);
    }

    /// The backing storage of a memory-sized fixed array access. Reads address the existing
    /// array; writes reuse a proven dead input's home, copying only a still-live snapshot.
    pub fn arrayStorage(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error![]const u8 {
        const old = self.function.resolve(inst.a);
        if (inst.op == .array_get) return self.value(old);
        const size = self.state.module.size(inst.ty);
        const into = try self.destination(name, size);
        if (!self.memory.homes.holds(self.current, 0, old)) try self.copyBytes(out, into.ptr, try self.value(old), size, false);
        if (into.fresh) try out.print(self.a(), identity_line, .{ name, into.ptr });
        return into.ptr;
    }

    /// `record_set`: `insertvalue` for a record in registers. A record in memory is copied into
    /// the new value's home and the field stored there; when the old value shares that home
    /// (it has no later reader, `emit_homes.zig`) the field is written where it is.
    fn recordSet(self: *FunctionEmitter, out: *Out, name: []const u8, ref: ir.Ref, inst: ir.Inst) !void {
        const m = self.state.module;
        if (!m.passedInMemory(inst.ty)) return out.print(self.a(), "  {s} = insertvalue {s}, {s}, {d}\n", .{ name, try self.typedValue(inst.a), try self.typedValue(inst.b), inst.data });
        const old = self.function.resolve(inst.a);
        const into = try self.destination(name, m.size(inst.ty));
        const plan = &self.memory.homes;
        if (!plan.holds(ref, 0, old)) try self.copyBytes(out, into.ptr, try self.value(old), m.size(inst.ty), false);
        const field = m.compound(inst.ty).record[@intCast(inst.data)];
        const offset = m.fieldOffset(inst.ty, @intCast(inst.data));
        // A write-back of a value built in the field itself stores nothing.
        if (!plan.holds(ref, offset, self.function.resolve(inst.b))) try self.storeOperand(out, field, inst.b, try self.offsetPointer(out, into.ptr, offset));
        if (into.fresh) try out.print(self.a(), identity_line, .{ name, into.ptr });
    }

    fn recordMake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        if (self.state.module.passedInMemory(inst.ty)) return self.makeInMemory(out, name, inst);
        const tyname = try self.ty(inst.ty);
        const fields = self.function.operands(inst.data);
        if (fields.len == 0) {
            try out.print(self.a(), "  {s} = select i1 true, {s} zeroinitializer, {s} zeroinitializer\n", .{ name, tyname, tyname });
            return;
        }
        var partial: []const u8 = "poison";
        for (fields, 0..) |field, i| {
            const next = if (i + 1 == fields.len) name else try self.fresh("%rm");
            try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s}, {d}\n", .{ next, tyname, partial, try self.typedValue(field), i });
            partial = next;
        }
    }

    fn unionMake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        if (m.passedInMemory(inst.ty)) return self.makeInMemory(out, name, inst);
        const layout = m.unionLayout(inst.ty);
        const tyname = try self.ty(inst.ty);
        const payload_type = m.compound(inst.ty).@"union"[@intCast(inst.data)];
        switch (layout.form) {
            .niche => {
                const pointer = if (inst.a == .none) "null" else try self.value(inst.a);
                try out.print(self.a(), "  {s} = getelementptr i8, ptr {s}, i64 0\n", .{ name, pointer });
            },
            .scalar => {
                const partial = try self.fresh("%u");
                const payload = if (inst.a == .none) "zeroinitializer" else try self.value(inst.a);
                try out.print(self.a(), "  {s} = insertvalue {s} poison, i8 {d}, 0\n  {s} = insertvalue {s} {s}, {s} {s}, 1\n", .{ partial, tyname, inst.data, name, tyname, partial, try self.ty(layout.payload), payload });
            },
            .words => {
                // The payload's memory image, through a stack slot SROA removes.
                const words = layout.payload_words;
                const tagged = if (words == 0) name else try self.fresh("%u");
                try out.print(self.a(), "  {s} = insertvalue {s} poison, i8 {d}, 0\n", .{ tagged, tyname, inst.data });
                if (words == 0) return;
                const slot = try self.stackSlot(8 * words);
                try out.print(self.a(), "  store [{d} x i64] zeroinitializer, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ words, slot });
                if (payload_type != .void) try self.storeValue(out, payload_type, try self.value(inst.a), slot);
                var partial = tagged;
                for (0..words) |k| {
                    const loaded = try self.fresh("%uw");
                    try out.print(self.a(), word_load_line, .{ loaded, try self.offsetPointer(out, slot, @intCast(8 * k)) });
                    const next = if (k + 1 == words) name else try self.fresh("%u");
                    try out.print(self.a(), "  {s} = insertvalue {s} {s}, i64 {s}, 1, {d}\n", .{ next, tyname, partial, loaded, k });
                    partial = next;
                }
            },
        }
    }

    /// `union_tag`: the case index of a union value, as `i32`.
    fn unionTag(self: *FunctionEmitter, out: *Out, name: []const u8, raw: ir.Ref) !void {
        const union_type = self.typeOf(raw);
        const layout = self.state.module.unionLayout(union_type);
        const tag = try self.fresh("%t");
        if (self.state.module.passedInMemory(union_type)) {
            try out.print(self.a(), word_load_line ++ "  {s} = trunc i64 {s} to i32\n", .{ tag, try self.value(raw), name, tag });
            return;
        }
        if (layout.form == .niche) {
            // The payload case is the non-null pointer.
            try out.print(self.a(), "  {s} = icmp {s} ptr {s}, null\n  {s} = zext i1 {s} to i32\n", .{ tag, if (layout.empty_case == 0) "ne" else "eq", try self.value(raw), name, tag });
            return;
        }
        try out.print(self.a(), "  {s} = extractvalue {s}, 0\n  {s} = zext i8 {s} to i32\n", .{ tag, try self.typedValue(raw), name, tag });
    }

    /// `union_payload`: the payload of `case`, defined in `result`.
    fn unionPayload(self: *FunctionEmitter, out: *Out, read: PayloadRead) Error!void {
        const m = self.state.module;
        const layout = m.unionLayout(read.union_type);
        if (m.passedInMemory(read.union_type)) {
            // The payload sits after the tag word.
            return self.loadValue(out, m.compound(read.union_type).@"union"[read.case], try self.offsetPointer(out, read.value, 8), read.result);
        }
        const tyname = try self.ty(read.union_type);
        switch (layout.form) {
            .niche => try out.print(self.a(), "  {s} = getelementptr i8, ptr {s}, i64 0\n", .{ read.result, read.value }),
            .scalar => try out.print(self.a(), "  {s} = extractvalue {s} {s}, 1\n", .{ read.result, tyname, read.value }),
            .words => {
                const payload_type = m.compound(read.union_type).@"union"[read.case];
                const slot = try self.stackSlot(8 * layout.payload_words);
                for (0..layout.payload_words) |k| {
                    const word = try self.fresh("%pw");
                    try out.print(self.a(), "  {s} = extractvalue {s} {s}, 1, {d}\n", .{ word, tyname, read.value, k });
                    try out.print(self.a(), "  store i64 {s}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ word, try self.offsetPointer(out, slot, @intCast(8 * k)) });
                }
                try self.loadValue(out, payload_type, slot, read.result);
            },
        }
    }

    /// Transfer the active payload before reclaiming a recursive box's shell.
    /// Large payloads get their own home: none may keep pointing into that box.
    fn unionTake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const m = self.state.module;
        if (!m.zero_rc) return error.UnsupportedInstruction;
        const union_type = self.typeOf(inst.a);
        const stored = m.compound(union_type).@"union"[@intCast(inst.data)];
        const boxed = m.kind(stored) == .box;
        const payload = if (boxed) try self.fresh("%takenbox") else name;
        try self.unionPayload(out, .{ .result = payload, .union_type = union_type, .value = try self.value(inst.a), .case = @intCast(inst.data) });
        if (!boxed) return;
        try self.boxTake(out, name, inst.ty, payload);
    }

    /// Load into independent storage before returning only the empty box shell.
    fn boxTake(self: *FunctionEmitter, out: *Out, name: []const u8, inner: ir.Type, box: []const u8) Error!void {
        if (!self.state.module.zero_rc) return error.UnsupportedInstruction;
        try self.loadValue(out, inner, try self.offsetPointer(out, box, data_offset), name);
        _ = try self.countSite(out, .release_unique, "");
        try out.print(self.a(), "  call void @myl_core_box_drop_shell(ptr {s})\n", .{box});
    }

    /// Replace element `b` of list `a` in place with `extra[0]`; the element it
    /// replaces is released when the element type is managed.
    fn fillCapacity(self: *FunctionEmitter, out: *Out, bound: ir.Ref) ![]const u8 {
        const raw = try self.value(bound);
        const positive = if (self.typeOf(bound) == .i64) blk: {
            const negative = try self.fresh("%fillnegative");
            const clamped = try self.fresh("%fillpositive");
            try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n", .{ negative, raw, clamped, negative, raw });
            break :blk clamped;
        } else raw;
        const large = try self.fresh("%filllarge");
        const capacity = try self.fresh("%fillcapacity");
        try out.print(self.a(), "  {s} = icmp ugt i64 {s}, {d}\n  {s} = select i1 {s}, i64 {d}, i64 {s}\n", .{ large, positive, flags.fill_capacity_limit, capacity, large, flags.fill_capacity_limit, positive });
        return capacity;
    }

    fn listSet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const element = m.compound(inst.ty).list;
        const index = try self.checkedIndex(out, inst, list, try self.value(inst.b));
        const slot = try self.elementSlot(out, list, index, element);
        if (elements.storeBack(m, self.function, inst)) |back| return self.storeBackPointer(out, name, inst, back, slot);
        const managed = m.managed(element) and !flags.transferredSlot(self.function, inst);
        var held: std.ArrayList(Held) = .empty;
        const saved = self.tagElements(true);
        defer _ = self.tagElements(saved);
        // A counting build names a copy of the old element made to release it.
        self.count_detail = if (self.count_fn != null) "list_set.old" else null;
        if (managed) try self.holdManaged(out, element, slot, &held, null);
        self.count_detail = null;
        try self.storeOperand(out, element, self.function.operands(inst.data)[0], slot);
        // The releases read their own blocks, not this element: generic tags again.
        _ = self.tagElements(false);
        try self.releaseHeld(out, held.items);
        try out.print(self.a(), identity_line, .{ name, list });
    }

    /// `list_set_field`: store the value at the path's offset inside the element, in place
    /// (the list is unique by now), releasing the part it replaces; the rest of the element
    /// is never read.
    fn listSetField(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const element = m.compound(inst.ty).list;
        const index = try self.checkedIndex(out, inst, list, try self.value(inst.b));
        const slot = try self.elementSlot(out, list, index, element);
        const path = elements.setPath(self.function, inst) orelse return error.UnsupportedInstruction;
        const target = m.pathTarget(element, path) orelse return error.UnsupportedInstruction;
        const at = try self.offsetPointer(out, slot, target.offset);
        if (elements.storeBack(m, self.function, inst)) |back| return self.storeBackPointer(out, name, inst, back, at);
        const saved = self.tagElements(!m.pathCrossesUnion(element, path));
        defer _ = self.tagElements(saved);
        var held: std.ArrayList(Held) = .empty;
        self.count_detail = if (self.count_fn != null) "list_set_field.old" else null;
        // A field a transferred read took over (`xs[i].items.append(v)`, CE2-B) is not released.
        if (!flags.transferredSlot(self.function, inst)) try self.holdManaged(out, target.ty, at, &held, null);
        self.count_detail = null;
        try self.storeOperand(out, target.ty, self.function.operands(inst.data)[0], at);
        // The releases read their own blocks, not this element: generic tags again.
        _ = self.tagElements(false);
        try self.releaseHeld(out, held.items);
        try out.print(self.a(), identity_line, .{ name, list });
    }

    /// A store-back of a block pointer into the slot its transferred read took it from
    /// (`elements.storeBack`, NEW-CORE-F1-STOREBACK-1): nothing when the pointer is the
    /// read's on every path, else a store only when it differs. The old pointer's owner
    /// went with the read, so nothing is released either way.
    fn storeBackPointer(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst, back: elements.StoreBack, slot: []const u8) !void {
        if (!back.same) {
            const stored = try self.value(self.function.operands(inst.data)[0]);
            const changed = try self.fresh("%moved");
            try out.print(self.a(), "  {s} = icmp ne ptr {s}, {s}\n", .{ changed, stored, try self.value(back.read) });
            const join = try self.enterIf(out, changed);
            try out.print(self.a(), "  store ptr {s}, ptr {s}, align 8, {s}\n", .{ stored, slot, elementTag("ptr") });
            try self.leaveIf(out, join);
        }
        try out.print(self.a(), identity_line, .{ name, try self.value(inst.a) });
    }

    /// Read the managed parts of the `value_type` value at `ptr` that a store is about to
    /// replace, for `releaseHeld` after it: a value of at most four words into registers,
    /// and a record, array or union over four words part by part — only its managed parts
    /// are read, never the whole value; a union's are read for every managed case and
    /// released only under the case its tag names. `guard` is the condition (`i1`) under
    /// which the value is live, or null.
    fn holdManaged(self: *FunctionEmitter, out: *Out, value_type: ir.Type, ptr: []const u8, held: *std.ArrayList(Held), guard: ?[]const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        if (m.passedInMemory(value_type)) switch (m.compound(value_type)) {
            .record => |fields| {
                for (fields, 0..) |field, i| try self.holdManaged(out, field, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)), held, guard);
                return;
            },
            .array => |array| {
                for (0..array.n) |i| try self.holdManaged(out, array.elem, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)), held, guard);
                return;
            },
            .@"union" => |cases| {
                const saved = self.tagElements(false);
                defer _ = self.tagElements(saved);
                const word = try self.fresh("%oldw");
                const tag = try self.fresh("%oldt");
                try out.print(self.a(), tag_load_line, .{ word, ptr, tag, word });
                for (cases, 0..) |case, k| {
                    if (!m.managed(case)) continue;
                    const here = try self.fresh("%oldc");
                    try out.print(self.a(), case_test_line, .{ here, tag, k });
                    const live = if (guard) |outer| blk: {
                        const both = try self.fresh("%oldc");
                        try out.print(self.a(), "  {s} = and i1 {s}, {s}\n", .{ both, outer, here });
                        break :blk both;
                    } else here;
                    try self.holdManaged(out, case, try self.offsetPointer(out, ptr, 8), held, live);
                }
                return;
            },
            else => {},
        };
        const loaded = try self.fresh("%old");
        try self.loadValue(out, value_type, ptr, loaded);
        try held.append(self.a(), .{ .ty = value_type, .text = loaded, .guard = guard });
    }

    /// Release the parts `holdManaged` read, once the store that replaced them is done, each
    /// under the case condition it was read for.
    fn releaseHeld(self: *FunctionEmitter, out: *Out, held: []const Held) Error!void {
        for (held) |part| {
            const join = if (part.guard) |live| try self.enterIf(out, live) else null;
            try self.countedValue(out, .release, part.ty, part.text);
            if (join) |label| try self.leaveIf(out, label);
        }
    }

    /// Drop the last element of list `a` in place (its value was read before, and is
    /// not released); an empty list traps `R_LIST_BOUNDS` like the old core's pop.
    fn listPop(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const list = try self.value(inst.a);
        const at = try self.fresh("%ph");
        const len = try self.fresh("%plen");
        const next = try self.fresh("%pn");
        try out.print(self.a(), header_tagged_line, .{ at, list, len_offset, len, at });
        if (self.checkOf(inst) == .exact) {
            const empty = try self.fresh("%pe");
            try out.print(self.a(), "  {s} = icmp eq i64 {s}, 0\n", .{ empty, len });
            try self.trapIf(out, empty, try self.site(.list_empty, inst, "pop"), "0", len);
        }
        try out.print(self.a(), "  {s} = sub nuw i64 {s}, 1\n  store i64 {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ next, len, next, at });
        try out.print(self.a(), identity_line, .{ name, list });
    }

    /// Read one field (or a union's tag or payload) of an inline element, at its
    /// offset from the element's slot, without loading the rest of the element.
    /// Whether the element read `ref` is lent where it lies (`lentElements`).
    fn lent(self: *FunctionEmitter, ref: ir.Ref) bool {
        return ref.index() < self.memory.borrowed.len and self.memory.borrowed[ref.index()];
    }

    fn listGetField(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const element = m.compound(self.typeOf(inst.a)).list;
        const index = try self.checkedIndex(out, inst, list, try self.value(inst.b));
        const slot = try self.elementSlot(out, list, index, element);
        const target = m.pathTarget(element, ir.FieldPath.unpack(inst.data)) orelse return error.UnsupportedInstruction;
        const at = try self.offsetPointer(out, slot, target.offset);
        if (target.tag_of == .void and self.lent(self.current)) return out.print(self.a(), identity_line, .{ name, at });
        const saved = self.tagElements(!m.pathCrossesUnion(element, ir.FieldPath.unpack(inst.data)));
        defer _ = self.tagElements(saved);
        if (target.tag_of == .void) return self.loadValue(out, target.ty, at, name);
        const layout = m.unionLayout(target.tag_of);
        const loaded = try self.fresh("%gt");
        if (layout.form == .niche) {
            const present = try self.fresh("%gt");
            const predicate = if (layout.empty_case == 0) "ne" else "eq";
            try out.print(self.a(), "  {s} = load ptr, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ loaded, at });
            try out.print(self.a(), "  {s} = icmp {s} ptr {s}, null\n  {s} = zext i1 {s} to i32\n", .{ present, predicate, loaded, name, present });
            return;
        }
        try out.print(self.a(), word_load_line ++ "  {s} = trunc i64 {s} to i32\n", .{ loaded, at, name, loaded });
    }

    /// `retain` or `release` every block a value of `ty` references: a block pointer
    /// directly, a niche union when not null, a union's payload under its tag, and a
    /// record's managed fields.
    fn counted(self: *FunctionEmitter, out: *Out, mode: Counting, value_type: ir.Type, text: []const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        if (m.isBlock(value_type)) return self.countBlock(out, mode, text, value_type);
        const tyname = try self.ty(value_type);
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                if (!m.managed(field)) continue;
                const field_value = try self.fresh("%cf");
                try out.print(self.a(), extract_value_line, .{ field_value, tyname, text, i });
                try self.counted(out, mode, field, field_value);
            },
            .@"union" => |cases| {
                const layout = m.unionLayout(value_type);
                if (layout.form == .niche) {
                    const present = try self.fresh("%cn");
                    try out.print(self.a(), "  {s} = icmp ne ptr {s}, null\n", .{ present, text });
                    const join = try self.enterIf(out, present);
                    try self.countBlock(out, mode, text, layout.payload);
                    return self.leaveIf(out, join);
                }
                const tag = try self.fresh("%ct");
                try out.print(self.a(), "  {s} = extractvalue {s} {s}, 0\n", .{ tag, tyname, text });
                for (cases, 0..) |case, k| {
                    if (!m.managed(case)) continue;
                    const here = try self.fresh("%cc");
                    try out.print(self.a(), case_test_line, .{ here, tag, k });
                    const join = try self.enterIf(out, here);
                    const payload = try self.fresh("%cp");
                    try self.unionPayload(out, .{ .result = payload, .union_type = value_type, .value = text, .case = @intCast(k) });
                    try self.counted(out, mode, case, payload);
                    try self.leaveIf(out, join);
                }
            },
            .array => |array| for (0..array.n) |i| {
                const element = try self.fresh("%ca");
                try out.print(self.a(), extract_value_line, .{ element, tyname, text, i });
                try self.counted(out, mode, array.elem, element);
            },
            .list, .box, .dict, .@"fn" => unreachable,
        }
    }

    /// One error-trace record (ERROR-TRACE-1/2). `data` is the trace mode, numbered as
    /// docs/design/new-core-s1.md §6.2 fixes for the IR: 0 `origin` (`Err(...)`
    /// built), 1 `append` (a `?` passing the error on), 2 `runtime` (a runtime call
    /// answered `Err`), 3 `converted` (a `?` wrapping it into a case of the caller's
    /// error union; `a` is a string constant naming `Union.case`), 4 `returned` (a
    /// `return` of an `Err` the statement did not build). Origins (0, 2) restart the
    /// trace; the rest append. The site's operation is the action text the trace prints.
    fn errTrace(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
        const action: []const u8 = switch (inst.data) {
            0 => "Err(...) created",
            2 => "Err produced by the runtime",
            3 => try std.fmt.allocPrint(self.a(), "try converted to {s}", .{self.caseName(inst.a)}),
            4 => "returned",
            else => "try propagated",
        };
        const action_symbol: []const u8 = if (inst.data == 0 or inst.data == 2) "origin" else "append";
        const index = try self.state.site(.{ .kind = .trace, .location = location, .width = 0, .operation = action, .function = self.sourceFunction().name });
        // ERROR-TRACE-5/6: zero inline cost and the compiler-owned preserving ABI.
        try out.print(self.a(), "  call preserve_mostcc void @myl_core_err_trace_{s}_preserve_most(ptr @myl.site.{d}) #1\n", .{ action_symbol, index });
    }

    /// The text of string constant `raw` (a converting `?`'s `Union.case`), or "?".
    fn caseName(self: *FunctionEmitter, raw: ir.Ref) []const u8 {
        if (raw == .none) return "?";
        const inst = self.function.inst(self.function.resolve(raw));
        if (inst.op != .str_const) return "?";
        return self.state.module.strings.items[@intCast(inst.data)];
    }

    // ---- trap frames (lane O; docs/design/new-core-s1.md §13 R-1) -------------------

    /// ` !dbg !N` naming this function's `DISubprogram` (`dwarf_lines` only).
    fn functionScope(self: *FunctionEmitter) ![]const u8 {
        if (self.state.options.target.traps != .dwarf_lines) return "";
        const location = self.state.options.locator.locate(self.state.options.locator.context, self.function.span);
        self.scope.definition = try self.state.debug.function(self.a(), self.index, self.function, location);
        return std.fmt.allocPrint(self.a(), function_scope, .{self.scope.definition});
    }

    /// `, !dbg !N` for a call at `span` (`dwarf_lines` only): LLVM keeps it through
    /// inlining as an inline record, so a return address maps to every frame it stands for.
    pub fn callLocation(self: *FunctionEmitter, span: u32) Error![]const u8 {
        if (self.scope.definition == 0) return "";
        const location = self.state.options.locator.locate(self.state.options.locator.context, span);
        const node = try self.sourceLocation(location, self.scope.origin);
        return std.fmt.allocPrint(self.a(), instruction_location, .{node});
    }

    fn trapLocation(self: *FunctionEmitter, site_index: u32) ![]const u8 {
        if (self.scope.definition == 0) return "";
        const location = self.state.sites.items[site_index].location;
        const node = try self.sourceLocation(location, self.scope.origin);
        return std.fmt.allocPrint(self.a(), instruction_location, .{node});
    }

    /// A source location in its exact callee scope and original inline call chain.
    fn sourceLocation(self: *FunctionEmitter, location: Location, origin: ?u32) Error!u32 {
        const id = origin orelse return self.state.debug.location(self.a(), location, self.scope.definition);
        const table = self.state.options.analysis.provenance.?;
        const frame = table.frames.items[id];
        const callee = &self.state.module.functions.items[frame.function];
        const declaration = self.state.options.locator.locate(self.state.options.locator.context, callee.span);
        const scope = try self.state.debug.function(self.a(), frame.function, callee, declaration);
        const at = try self.inlineLocation(id);
        return self.state.debug.inlinedLocation(self.a(), location, scope, at);
    }

    fn inlineLocation(self: *FunctionEmitter, id: u32) Error!u32 {
        if (self.scope.inline_locations.get(id)) |node| return node;
        const frame = self.state.options.analysis.provenance.?.frames.items[id];
        const at = self.state.options.locator.locate(self.state.options.locator.context, frame.call_span);
        const node = try self.sourceLocation(at, frame.parent);
        try self.scope.inline_locations.put(self.a(), id, node);
        return node;
    }

    /// A list `promote.zig` put on the stack: an entry-block `alloca` with the block
    /// header (count 1, the stack class, room for `capacity` elements), set up where
    /// the `list_new` runs; nothing counts, frees or grows it.
    fn stackList(self: *FunctionEmitter, out: *Out, name: []const u8, capacity: u64, element: ir.Type) !void {
        const bytes = data_offset + capacity * self.state.stride(element);
        const frame = try self.fresh("%stacklist");
        try self.state.allocas.print(self.a(), "  {s} = alloca [{d} x i8], align 32\n", .{ frame, bytes });
        try out.print(self.a(), identity_line, .{ name, frame });
        if (!self.state.module.zero_rc) try out.print(self.a(), "  store i32 1, ptr {s}, align 8, " ++ tbaa_count ++ "\n", .{name});
        const fields = [_]struct { offset: u32, ty: []const u8, value: []const u8 }{
            .{ .offset = self.state.module.kindOffset(), .ty = "i32", .value = stack_kind },
            .{ .offset = len_offset, .ty = "i64", .value = "0" },
            .{ .offset = cap_offset, .ty = "i64", .value = try std.fmt.allocPrint(self.a(), "{d}", .{capacity}) },
            .{ .offset = 24, .ty = "i64", .value = "0" },
        };
        for (fields) |field| {
            const at = try self.fresh("%sh");
            try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  store {s} {s}, ptr {s}, align 4, " ++ tbaa_header ++ "\n", .{ at, name, field.offset, field.ty, field.value, at });
        }
    }

    /// `undef` of `ty`: poison when it holds no block; otherwise a value whose every block
    /// pointer is null (a null pointer, a zero struct, or for a record or union kept in
    /// memory a pointer to zeroed memory), which a release of a possibly-`undef` value
    /// (`empty_release`) tests and skips.
    fn undefValue(self: *FunctionEmitter, value_type: ir.Type) ![]const u8 {
        const m = self.state.module;
        if (!m.managed(value_type)) return "poison";
        if (m.passedInMemory(value_type)) {
            self.state.local.zeros = @max(self.state.local.zeros, m.size(value_type));
            return "@myl.zeros";
        }
        if (m.isBlock(value_type) or (m.kind(value_type) == .@"union" and m.unionLayout(value_type).form == .niche)) return "null";
        return "zeroinitializer";
    }

    /// The release of a block `own.zig` proved unique: free it without the count test
    /// (verify builds first assert the count is 1 and trap `R_CORE_FACT`).
    fn freeUnique(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const block = try self.value(inst.a);
        return self.freeUniqueBlock(out, block, self.typeOf(inst.a), inst.span);
    }

    fn freeUniqueBlock(self: *FunctionEmitter, out: *Out, block: []const u8, block_type: ir.Type, span: u32) !void {
        _ = try self.countSite(out, .release_unique, "");
        if (self.state.module.zero_rc) return out.print(self.a(), "  call void @myl_core_drop_owned(ptr {s})\n", .{block});
        if (self.state.options.verify) {
            const count = try self.fresh("%uc");
            const shared = try self.fresh("%us");
            try out.print(self.a(), count_load_line ++ "  {s} = icmp ne i32 {s}, 1\n", .{ count, block, shared, count });
            const location = self.state.options.locator.locate(self.state.options.locator.context, span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 32, .operation = "count == 1 before freeing a unique block", .function = self.sourceFunction().name });
            try self.trapIf(out, shared, index, "0", "1");
        }
        const m = self.state.module;
        if (m.single_owner and m.kind(block_type) == .list) {
            const element = m.compound(block_type).list;
            if (@import("single_owner.zig").containsList(m, element)) try self.freeUniqueElements(out, block, element);
        }
        try out.print(self.a(), "  call void @myl_core_free(ptr {s})\n", .{block});
    }

    /// Emit child cleanup from record/array element types. Exclusive list families
    /// free directly; snapshot families and immutable leaves use normal releases.
    /// Recursive owning types are refused by the checker.
    fn freeUniqueElements(self: *FunctionEmitter, out: *Out, block: []const u8, element: ir.Type) Error!void {
        const length = try self.fresh("%drop.len");
        const at = try self.fresh("%drop.len.at");
        try out.print(self.a(), header_tagged_line, .{ at, block, len_offset, length, at });
        const loop = try self.fresh("drop.loop");
        const body = try self.fresh("drop.body");
        const step = try self.fresh("drop.step");
        const done = try self.fresh("drop.done");
        const index = try self.fresh("%drop.index");
        const next = try self.fresh("%drop.next");
        const more = try self.fresh("%drop.more");
        try out.print(self.a(), "  br label %{s}\n{s}:\n  {s} = phi i64 [ 0, %{s} ], [ {s}, %{s} ]\n", .{ loop, loop, index, self.label, next, step });
        try out.print(self.a(), "  {s} = icmp ult i64 {s}, {s}\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ more, index, length, more, body, done, body });
        self.label = body;
        const saved_tags = self.tagElements(false);
        defer _ = self.tagElements(saved_tags);
        const saved_empty = self.may_be_empty;
        self.may_be_empty = true;
        defer self.may_be_empty = saved_empty;
        try self.countedAt(out, .release, element, try self.elementSlot(out, block, index, element));
        try out.print(self.a(), "  br label %{s}\n{s}:\n  {s} = add nuw i64 {s}, 1\n  br label %{s}\n{s}:\n", .{ step, step, next, index, loop, done });
        self.label = done;
        // Children are already destroyed. Detach the descriptor so the ordinary
        // allocator free cannot visit them again (including its pointer-list fast path).
        const layout = try self.offsetPointer(out, block, 24);
        try out.print(self.a(), "  store ptr null, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{layout});
    }

    /// Record in a fresh list's or box's header (`reserved`, offset 24) where the blocks
    /// in its elements are, when `element` holds any: the runtime's free releases them
    /// and its copy retains them.
    fn attachLayout(self: *FunctionEmitter, out: *Out, block: []const u8, element: ir.Type) !void {
        if (!self.state.module.managed(element)) return;
        const at = try self.fresh("%lay");
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 24\n  store ptr {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ at, block, try self.state.layoutSymbol(element), at });
    }

    /// Branch on `condition` into a fresh block; returns the join label `leaveIf` ends it with.
    fn enterIf(self: *FunctionEmitter, out: *Out, condition: []const u8) ![]const u8 {
        const then = try self.fresh("rc.then");
        const join = try self.fresh(self.label);
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ condition, then, join, then });
        self.label = then;
        return join;
    }

    fn leaveIf(self: *FunctionEmitter, out: *Out, join: []const u8) !void {
        try out.print(self.a(), "  br label %{s}\n{s}:\n", .{ join, join });
        self.label = join;
    }

    /// Plain counts update inline after one threshold test. Shared counts and plain
    /// saturation use one cold preserve-most call; immortal constants stay read-only.
    fn countBlock(self: *FunctionEmitter, out: *Out, mode: Counting, block: []const u8, block_type: ir.Type) !void {
        if (self.may_be_empty) {
            // An `undef` value is all null pointers (`undefValue`): nothing to count.
            const present = try self.fresh("%re");
            try out.print(self.a(), "  {s} = icmp ne ptr {s}, null\n", .{ present, block });
            const join = try self.enterIf(out, present);
            self.may_be_empty = false;
            defer self.may_be_empty = true;
            try self.countBlock(out, mode, block, block_type);
            return self.leaveIf(out, join);
        }
        if (self.state.module.zero_rc and mode == .retain) return error.UnsupportedInstruction;
        if (mode == .release and (self.state.module.zero_rc or self.state.module.exclusiveList(block_type))) {
            return self.freeUniqueBlock(out, block, block_type, if (self.current == .none) self.function.span else self.function.inst(self.current).span);
        }
        if (self.count_fn != null) {
            const bytes = if (mode == .retain) try self.blockBytes(out, block, block_type) else "";
            _ = try self.countSite(out, if (mode == .retain) .retain else .release, bytes);
        }
        const count = try self.fresh("%rc");
        const plain = try self.fresh("%rp");
        const update = try self.fresh(if (mode == .retain) "rc.inc" else "rc.dec");
        const slow = try self.fresh("rc.slow");
        const done = try self.fresh(self.label);
        const next = try self.fresh("%rn");
        try out.print(self.a(), count_load_line, .{ count, block });
        try out.print(self.a(), "  {s} = icmp ult i32 {s}, {d}\n  br i1 {s}, label %{s}, label %{s}, !prof !23\n{s}:\n", .{ plain, count, @as(u32, if (mode == .retain) 0x7ffffffe else 0x80000000), plain, update, slow, update });
        if (mode == .retain) {
            try out.print(self.a(), "  {s} = add nuw i32 {s}, 1\n  store i32 {s}, ptr {s}, align 8, " ++ tbaa_count ++ "\n  br label %{s}\n", .{ next, count, next, block, done });
        } else {
            const last = try self.fresh("%rz");
            const keep = try self.fresh("rc.keep");
            const free = try self.fresh("rc.free");
            try out.print(self.a(), "  {s} = sub nuw i32 {s}, 1\n  {s} = icmp eq i32 {s}, 0\n  br i1 {s}, label %{s}, label %{s}\n", .{ next, count, last, next, last, free, keep });
            try out.print(self.a(), "{s}:\n  store i32 {s}, ptr {s}, align 8, " ++ tbaa_count ++ "\n  br label %{s}\n", .{ keep, next, block, done });
            try out.print(self.a(), "{s}:\n  call void @myl_core_free(ptr {s})\n  br label %{s}\n", .{ free, block, done });
        }
        try out.print(self.a(), "{s}:\n", .{slow});
        try out.print(self.a(), "  call preserve_mostcc void @myl_core_{s}_slow(ptr {s})\n  br label %{s}\n{s}:\n", .{ @tagName(mode), block, done, done });
        self.label = done;
    }

    /// In a counting build, a new counter site of `kind` at the instruction being
    /// emitted: `c0` counts its executions and, unless `bytes` is empty, `c1` adds
    /// `bytes` each time. Returns the site's symbol, or null outside a counting build.
    fn countSite(self: *FunctionEmitter, out: *Out, kind: emit_count.Kind, bytes: []const u8) Error!?[]const u8 {
        const record = try self.newCountSite(kind) orelse return null;
        try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_count, .amount = "1", .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") });
        if (bytes.len != 0) try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_bytes, .amount = bytes, .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") });
        return record;
    }

    fn newCountSite(self: *FunctionEmitter, kind: emit_count.Kind) Error!?[]const u8 {
        const record = self.count_fn orelse return null;
        const inst: ?ir.Inst = if (self.current == .none) null else self.function.inst(self.current);
        // Releases at a function's end carry no span of their own: they belong to the function.
        const span = if (inst != null and inst.?.span != 0) inst.?.span else self.function.span;
        const location = self.state.options.locator.locate(self.state.options.locator.context, span);
        const index = try self.state.count.add(self.a(), .{
            .function = record,
            .origin = self.sourceFunction().name,
            .path = if (location.path.len != 0) location.path else self.state.options.source_path,
            .line = location.line,
            .column = location.column,
            .kind = kind,
            .detail = self.count_detail orelse if (inst) |known| @tagName(known.op) else "function",
        });
        const name = try std.fmt.allocPrint(self.a(), "@myl.cs.{d}", .{index});
        return name;
    }

    /// The counter sites an instruction gets before its own code in a counting build:
    /// the site a runtime copy credits (`myl_count_copy_site`), a push's element bytes,
    /// and a whole small aggregate read from or written into a list.
    fn countBefore(self: *FunctionEmitter, out: *Out, inst: ir.Inst) Error!void {
        const m = self.state.module;
        const copied: ?emit_count.Kind = switch (inst.op) {
            .list_copy => .list_copy,
            .dict_copy => .dict_copy,
            .buffer_copy => .buffer_copy,
            .str_from_view => .text_copy,
            else => null,
        };
        if (copied) |kind| {
            const record = (try self.newCountSite(kind)).?;
            try out.print(self.a(), "  store ptr {s}, ptr @myl_count_copy_site, align 8\n", .{record});
            return;
        }
        const element: ir.Type = switch (inst.op) {
            .list_push, .list_set => m.compound(inst.ty).list,
            .list_get => inst.ty,
            else => return,
        };
        const bytes = try std.fmt.allocPrint(self.a(), "{d}", .{self.state.stride(element)});
        if (inst.op == .list_push) {
            const record = (try self.countSite(out, .list_push, bytes)).?;
            // A growth this push causes credits its moved bytes to this site (`extra`).
            if (inst.data != stack_push) try out.print(self.a(), "  store ptr {s}, ptr @myl_count_push_site, align 8\n", .{record});
            return;
        }
        const aggregate = element.isCompound() and !m.isBlock(element) and !m.passedInMemory(element) and m.kind(element) != .@"fn";
        if (aggregate) _ = try self.countSite(out, if (inst.op == .list_get) .element_load else .element_store, bytes);
    }

    /// A counting build's measure of what a retain shares: the data bytes of `block`
    /// (elements times their stride, text and byte lengths, entries times key and value
    /// sizes, a box's value), the bytes a copy would move instead.
    fn blockBytes(self: *FunctionEmitter, out: *Out, block: []const u8, block_type: ir.Type) Error![]const u8 {
        const m = self.state.module;
        const textual = block_type == .str or block_type == .bytes or block_type == .byte_buffer;
        const kind = if (textual) null else m.kind(block_type);
        const per: u32 = if (textual) 1 else if (kind == null) return "0" else switch (kind.?) {
            .list => self.state.stride(m.compound(block_type).list),
            .dict => m.size(m.compound(block_type).dict.key) + m.size(m.compound(block_type).dict.value),
            .box => return std.fmt.allocPrint(self.a(), "{d}", .{m.size(m.compound(block_type).box)}),
            else => return "0",
        };
        const at = try self.fresh("%cnt");
        const len = try self.fresh("%cnt");
        const bytes = try self.fresh("%cnt");
        try out.print(self.a(), header_load_line ++ "  {s} = mul i64 {s}, {d}\n", .{ at, block, len_offset, len, at, bytes, len, per });
        return bytes;
    }

    /// The value an `%vN` name stands for, or null for any other name.
    fn refOfName(name: []const u8) ?ir.Ref {
        if (name.len < 3 or !std.mem.startsWith(u8, name, "%v")) return null;
        return @fromBackingInt(std.fmt.parseInt(u32, name[2..], 10) catch return null);
    }

    /// The value an `%vN` name stands for.
    fn refOf(self: *FunctionEmitter, name: []const u8) ir.Ref {
        _ = self;
        return @fromBackingInt(std.fmt.parseInt(u32, name[2..], 10) catch 0);
    }

    /// Whether trusted facts prove an integer value non-negative (never in verify builds).
    fn nonNegative(self: *FunctionEmitter, raw: ir.Ref) bool {
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        const info = inst.ty.integer() orelse return false;
        if (!info.signed) return true;
        if (inst.op == .iconst) return @as(i64, @bitCast(inst.data)) >= 0;
        if (self.state.options.verify or self.index >= self.state.options.analysis.facts.len) return false;
        const known = self.state.options.analysis.facts[self.index] orelse return false;
        const range = known.ranges[ref.index()] orelse return false;
        return range.lo >= 0;
    }

    /// An unsigned 64-bit division or remainder whose operands the trusted facts put in
    /// `u32` (NEW-CORE-F1-OVERFLOW-4): each operand masked to its low 32 bits (the same
    /// value) before the 64-bit operation, so LLVM knows their high bits are zero and a
    /// constant divisor's multiply-by-reciprocal needs no 65-bit correction steps.
    fn narrowDivision(self: *FunctionEmitter, out: *Out, name: []const u8, is_rem: bool, operands: [2][]const u8) !void {
        const left = try self.fresh("%nl");
        const right = try self.fresh("%nr");
        try out.print(self.a(), "  {s} = and i64 {s}, 4294967295\n  {s} = and i64 {s}, 4294967295\n", .{ left, operands[0], right, operands[1] });
        try out.print(self.a(), binary_line, .{ name, if (is_rem) "urem" else "udiv", "i64", left, right });
    }

    /// Whether trusted facts put an integer value inside `u32` (never in verify builds).
    fn fitsU32(self: *FunctionEmitter, raw: ir.Ref) bool {
        if (self.state.options.verify or self.index >= self.state.options.analysis.facts.len) return false;
        const known = self.state.options.analysis.facts[self.index] orelse return false;
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        if (inst.op == .iconst) return inst.data <= std.math.maxInt(u32);
        const range = known.ranges[ref.index()] orelse return false;
        return range.lo >= 0 and range.hi <= std.math.maxInt(u32);
    }

    /// Whether trusted facts put an integer value inside `i32` (never in verify builds).
    fn fitsI32(self: *FunctionEmitter, raw: ir.Ref) bool {
        if (self.state.options.verify or self.index >= self.state.options.analysis.facts.len) return false;
        const known = self.state.options.analysis.facts[self.index] orelse return false;
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        const range = if (inst.op == .iconst) facts.Interval.point(@as(i64, @bitCast(inst.data))) else known.ranges[ref.index()] orelse return false;
        return range.lo >= std.math.minInt(i32) and range.hi <= std.math.maxInt(i32);
    }

    /// `, !range !N` when the facts bound the loaded value more tightly than its type.
    fn loadRange(self: *FunctionEmitter, name: []const u8, loaded: ir.Type) ![]const u8 {
        const info = loaded.integer() orelse return "";
        if (self.state.options.verify or self.index >= self.state.options.analysis.facts.len) return "";
        const known = self.state.options.analysis.facts[self.index] orelse return "";
        const index = std.fmt.parseInt(usize, name[2..], 10) catch return "";
        const range = known.ranges[index] orelse return "";
        const full = facts.typeRange(loaded).?;
        if (range.lo > range.hi or (range.lo == full.lo and range.hi == full.hi)) return "";
        // A half-open `!range` cannot spell an upper bound one past the type's maximum.
        if (range.hi == full.hi) return "";
        return self.state.rangeNode(info.bits, range);
    }

    /// Append in place: `myl_core_list_reserve` returns a block with room for one more element.
    fn listPush(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        // A push that is one of a web's updates (`emit_state.zig`), not merely of a web value.
        if (self.memory.states.of(self.current)) |slots| return self.slotPush(out, name, inst, slots);
        const element = self.state.module.compound(inst.ty).list;
        const len_at = try self.fresh("%pl");
        const counter = if (inst.data == flags.fill_push) self.fillCounter(inst.a) else null;
        const len = if (counter) |ref| try self.value(ref) else try self.fresh("%plen");
        const next = try self.fresh("%pn");
        if (inst.data == stack_push) {
            // A promoted list's room is proven (`promote.zig`): no growth call.
            try out.print(self.a(), same_pointer, .{ name, try self.value(inst.a) });
        } else if (counter != null) {
            try out.print(self.a(), "  {s} = call ptr @myl_core_list_fill_reserve(ptr {s}, i64 {d}, i64 {s})\n", .{ name, try self.value(inst.a), self.state.stride(element), len });
        } else try out.print(self.a(), "  {s} = call ptr @myl_core_list_reserve(ptr {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
        if (self.count_fn != null and inst.data != stack_push) try out.appendSlice(self.a(), "  store ptr null, ptr @myl_count_push_site, align 8\n");
        if (counter != null) {
            try out.print(self.a(), header_pointer_line, .{ len_at, name, len_offset });
            if (self.state.options.verify) try self.assertFillRoom(out, name, len_at, len, inst);
        } else try out.print(self.a(), header_tagged_line, .{ len_at, name, len_offset, len, len_at });
        const slot = try self.elementSlot(out, name, len, element);
        const saved = self.tagElements(true);
        defer _ = self.tagElements(saved);
        if (element == .bool or element.isCompound()) {
            try self.storeOperand(out, element, inst.b, slot);
        } else {
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, {s}\n", .{ try self.typedValue(inst.b), slot, elementSize(element), self.dataTag(storageType(element)) });
        }
        try out.print(self.a(), "  {s} = add nuw nsw i64 {s}, 1\n  store i64 {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ next, len, next, len_at });
    }

    /// A push into a list whose length and capacity a loop keeps in slots (NEW-CORE-U1-STATE-2):
    /// room is the slots' test; growth stores the length back, grows the block and loads the
    /// grown capacity; the element goes at the slots' length, which then advances.
    fn slotPush(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst, slots: emit_state.Slots) !void {
        const element = self.state.module.compound(inst.ty).list;
        const list = try self.value(inst.a);
        const len = try self.fresh("%spl");
        const cap = try self.fresh("%spc");
        const room = try self.fresh("%spr");
        const fits = try self.fresh("push.fits");
        const grow = try self.fresh("push.grow");
        const join = try self.fresh(self.label);
        const grown = try self.fresh("%spg");
        try out.print(self.a(), "  {s} = load i64, ptr {s}, align 8\n  {s} = load i64, ptr {s}, align 8\n  {s} = icmp ult i64 {s}, {s}\n", .{ len, slots.len, cap, slots.cap, room, len, cap });
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}, !prof !10\n{s}:\n", .{ room, fits, grow, grow });
        try emit_state.store(*FunctionEmitter, self, out, list, slots);
        try out.print(self.a(), "  {s} = call ptr @myl_core_list_grow(ptr {s}, i64 {d})\n", .{ grown, list, self.state.stride(element) });
        const cap_at = try self.fresh("%spc");
        const grown_cap = try self.fresh("%spc");
        try out.print(self.a(), header_tagged_line, .{ cap_at, grown, cap_offset, grown_cap, cap_at });
        try out.print(self.a(), "  store i64 {s}, ptr {s}, align 8\n  br label %{s}\n{s}:\n  br label %{s}\n{s}:\n", .{ grown_cap, slots.cap, join, fits, join, join });
        try out.print(self.a(), "  {s} = phi ptr [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ name, list, fits, grown, grow });
        self.label = join;
        if (self.count_fn != null) try out.appendSlice(self.a(), "  store ptr null, ptr @myl_count_push_site, align 8\n");
        const slot = try self.elementSlot(out, name, len, element);
        const saved = self.tagElements(true);
        defer _ = self.tagElements(saved);
        if (element == .bool or element.isCompound()) {
            try self.storeOperand(out, element, inst.b, slot);
        } else {
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, {s}\n", .{ try self.typedValue(inst.b), slot, elementSize(element), self.dataTag(storageType(element)) });
        }
        const next = try self.fresh("%spn");
        try out.print(self.a(), "  {s} = add nuw nsw i64 {s}, 1\n  store i64 {s}, ptr {s}, align 8\n", .{ next, len, next, slots.len });
    }

    fn fillCounter(self: *FunctionEmitter, list: ir.Ref) ?ir.Ref {
        if (self.index >= self.state.options.analysis.facts.len) return null;
        const known = self.state.options.analysis.facts[self.index] orelse return null;
        const ref = self.function.resolve(list);
        for (known.counted) |fill| for (self.function.blocks.items[fill.loop.header.index()].insts.items) |phi| {
            if (phi == ref and known.aggregates.lists[ref.index()].pattern) return fill.counter;
        };
        return null;
    }

    fn assertFillRoom(self: *FunctionEmitter, out: *Out, list: []const u8, len_at: []const u8, index: []const u8, inst: ir.Inst) !void {
        const actual = try self.fresh("%fill.actual");
        const cap_at = try self.fresh("%fill.cap_at");
        const cap = try self.fresh("%fill.cap");
        const mismatch = try self.fresh("%fill.mismatch");
        const full = try self.fresh("%fill.full");
        const failed = try self.fresh("%fill.failed");
        try out.print(self.a(), "  {s} = load i64, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ actual, len_at });
        try out.print(self.a(), header_load_line, .{ cap_at, list, cap_offset, cap, cap_at });
        try out.print(self.a(), "  {s} = icmp ne i64 {s}, {s}\n  {s} = icmp uge i64 {s}, {s}\n  {s} = or i1 {s}, {s}\n", .{ mismatch, actual, index, full, index, cap, failed, mismatch, full });
        try self.trapIf(out, failed, try self.site(.fact, inst, "counted fill capacity and index"), index, cap);
    }

    /// Resolve a function value to its owner's symbol, declaring it when another unit owns it.
    pub fn functionPointer(self: *FunctionEmitter, index: u32) Error![]const u8 {
        try self.state.dependency(index);
        return self.state.originalSymbol(index);
    }

    /// Emit a placeholder that traps precisely before its result can be observed.
    pub fn unsupported(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        try out.print(self.a(), "  call void @myl_core_s2_unsupported(i32 {d})\n", .{@backingInt(inst.op)});
        if (inst.ty != .void) try out.print(self.a(), "  {s} = freeze {s} poison\n", .{ name, try self.ty(inst.ty) });
    }

    fn specialRuntimeCall(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!bool {
        if (try @import("aggregate_provider.zig").call(self.state.module, inst)) return true;
        if (try @import("emit_render.zig").runtimeCall(@TypeOf(self), @TypeOf(out), self, out, name, inst)) return true;
        if (try emit_bytes.runtimeCall(@TypeOf(self), @TypeOf(out), self, out, name, inst)) return true;
        if (try emit_text.runtimeCall(@TypeOf(self), @TypeOf(out), self, out, name, inst)) return true;
        return emit_text_split.runtimeCall(@TypeOf(self), @TypeOf(out), self, out, name, inst);
    }

    fn borrowedSelection(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!bool {
        const selection = (try @import("borrow_selection.zig").call(self.state.module, self.function, inst)) orelse return false;
        if (self.state.module.isBlock(inst.ty)) {
            try out.print(self.a(), same_pointer, .{ name, try self.value(selection.value) });
        } else {
            const slot = try self.stackSlot(self.state.module.size(inst.ty));
            try self.storeOperand(out, inst.ty, selection.value, slot);
            try self.loadValue(out, inst.ty, slot, name);
        }
        return true;
    }

    /// Emit a direct or indirect call under the internal aggregate ABI.
    pub fn call(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        if (try self.borrowedSelection(out, name, inst)) return;
        const m = self.state.module;
        const signature = if (inst.op == .call_indirect) m.compound(self.typeOf(inst.a)).@"fn" else m.functions.items[inst.a.index()].signature;
        const external = signature.linkage != .internal;
        const program = !external or (inst.op == .call and emit_values.generated(&m.functions.items[inst.a.index()]));
        if (inst.op == .call) {
            try self.state.dependency(@intCast(inst.a.index()));
            try emit_cap.beforeCall(@TypeOf(self), self, out, inst);
        }
        if (try self.specialRuntimeCall(out, name, inst)) return;
        const borrowed_bytes = external and signature.ret == .bytes and signature.owned == 0;
        const text_parameter = signature.params.len == 1 and signature.params[0] == .str;
        // Zero-RC encode returns fresh owned bytes; only the RC ABI aliases text.
        const encode_alias = borrowed_bytes and text_parameter and !m.zero_rc;
        if (inst.op == .call and encode_alias and
            std.mem.eql(u8, m.functions.items[inst.a.index()].name, flags.text_encode_symbol))
        {
            const source = self.function.operands(inst.data)[0];
            return out.print(self.a(), same_pointer, .{ name, try self.value(source) });
        }
        const ret = signature.ret;
        const abi: InOutAbi = if (external) .{} else inOutAbi(m, signature);
        const sret = !external and returnsThroughSret(m, signature, abi);
        var arguments: Out = .empty;
        var first = true;
        const result = if (sret) try self.destination(name, m.size(ret)) else null;
        const result_slot = if (result) |into| into.ptr else "";
        const places = try self.inOutPlaces(out, name, inst);
        if (sret) {
            try arguments.print(self.a(), "ptr sret({s}) align 8 {s}", .{ try self.state.memoryType(ret), result_slot });
            first = false;
        }
        const c_function = inst.op == .call and signature.linkage == .extern_c;
        for (self.function.operands(inst.data), signature.params, 0..) |argument, param, i| {
            if (signature.linkage == .extern_c and !c_abi.passes(param)) continue;
            const separator = if (first) "" else ", ";
            first = false;
            if (external and i < 64 and signature.views & (@as(u64, 1) << @intCast(i)) != 0) {
                try arguments.print(self.a(), "{s}{s}", .{ separator, try self.spanArgument(out, argument) });
                continue;
            }
            if (!external and m.passedInMemory(param)) {
                const in_out = abi.inOut(i);
                try arguments.print(self.a(), "{s}ptr {s}", .{ separator, if (in_out) places[i] else try self.value(argument) });
                continue;
            }
            try arguments.print(self.a(), "{s}{s}", .{ separator, try self.scalarArgument(out, argument, param, c_function) });
        }
        const target = if (inst.op == .call_indirect)
            try self.value(inst.a)
        else
            try self.state.originalSymbol(@intCast(inst.a.index()));
        // A trap's DWARF caller chain must survive a call in return position.
        const tail = if (program and self.state.options.target.traps == .dwarf_lines) "notail " else "";
        if (ret == .void or sret or abi.whole) {
            try out.print(self.a(), "  {s}call {s}void {s}({s}){s}\n", .{ tail, if (program) "fastcc " else "", target, arguments.items, try self.callLocation(inst.span) });
            if (result != null and result.?.fresh) try out.print(self.a(), identity_line, .{ name, result_slot });
            // The one in-out parameter's final value is the result: it is where it was passed.
            if (abi.whole and !self.homedName(name)) try out.print(self.a(), identity_line, .{ name, places[@ctz(abi.params)] });
        } else {
            try out.print(self.a(), "  {s} = {s}call {s}{s} {s}({s}){s}\n", .{ name, tail, if (program) "fastcc " else "", try self.ty(ret), target, arguments.items, try self.callLocation(inst.span) });
        }
        if (sret) try self.completeResult(out, name, signature, .{ .result = result_slot, .places = places });
    }

    /// A register argument: widened or sign-marked for a C function, its NaN made canonical.
    fn scalarArgument(self: *FunctionEmitter, out: *Out, argument: ir.Ref, param: ir.Type, c_function: bool) ![]const u8 {
        const extension = if (c_function) c_abi.argumentExtension(param) else "";
        if (extension.len != 0) return std.fmt.allocPrint(self.a(), "{s} {s} {s}", .{ try self.ty(self.typeOf(argument)), extension, try self.value(argument) });
        if (c_function and c_abi.canonicalizesNan(param)) return std.fmt.allocPrint(self.a(), "double {s}", .{try self.canonicalNan(out, argument)});
        return self.typedValue(argument);
    }

    /// A borrowed `(data, byte_length)` span argument of an extern-C `str` parameter.
    pub fn spanArgument(self: *FunctionEmitter, out: *Out, argument: ir.Ref) Error![]const u8 {
        const data = try self.fresh("%span");
        const len = try self.fresh("%span");
        const text = try self.value(argument);
        if (self.typeOf(argument) == .str_view) {
            try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, text, len, text });
        } else {
            const at = try self.fresh("%span");
            try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ data, text, at, text, len, at });
        }
        return std.fmt.allocPrint(self.a(), "ptr {s}, i64 {s}", .{ data, len });
    }

    /// Where an in-out call's result record and its in-out arguments are.
    const CallPlaces = struct { result: []const u8, places: []const []const u8 };

    /// A result record something reads whole gets its in-out final values too, after the call.
    fn completeResult(self: *FunctionEmitter, out: *Out, name: []const u8, signature: ir.Signature, at: CallPlaces) !void {
        const ref = refOfName(name) orelse return;
        if (ref.index() >= self.memory.in_out.complete.len) return;
        if (!self.memory.in_out.complete[ref.index()]) return;
        const m = self.state.module;
        const abi = inOutAbi(m, signature);
        for (self.memory.in_out.args[ref.index()]) |in_out| {
            const field = abi.field(signature, in_out.argument);
            const into = try self.offsetPointer(out, at.result, m.fieldOffset(signature.ret, field));
            try self.copyBytes(out, into, at.places[in_out.argument], m.size(signature.params[in_out.argument]), false);
        }
    }

    /// Per parameter of the call `name`, the memory its in-out argument is passed in: the home
    /// of the parameter's final value, holding the argument (copied there unless it already lives
    /// there), or a fresh slot holding a copy when nothing names the final value.
    fn inOutPlaces(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) ![]const []const u8 {
        const ref = refOfName(name) orelse return &.{};
        if (ref.index() >= self.memory.in_out.args.len or self.memory.in_out.args[ref.index()].len == 0) return &.{};
        const m = self.state.module;
        const f = self.function;
        const operands = f.operands(inst.data);
        const places = try self.a().alloc([]const u8, operands.len);
        for (self.memory.in_out.args[ref.index()]) |in_out| {
            const argument = f.resolve(operands[in_out.argument]);
            const final = in_out.final;
            const size = m.size(self.typeOf(argument));
            const homed = final != .none and self.homedName(try self.value(final));
            places[in_out.argument] = if (homed) try self.value(final) else try self.stackSlot(size);
            if (homed and self.memory.homes.holds(final, 0, argument)) continue;
            if (f.inst(argument).op == .undef and !m.managed(f.inst(argument).ty)) continue;
            try self.copyBytes(out, places[in_out.argument], try self.value(argument), size, false);
        }
        return places;
    }

    /// The entry adapter's report of the `Err` `main` returned: the runtime writes `error: VALUE`
    /// and the error return trace.
    fn reportError(self: *FunctionEmitter, out: *Out, argument: ir.Ref) !void {
        const argument_type = self.typeOf(argument);
        if (argument_type == .bool) return out.print(self.a(), "  call void @myl_core_main_error_bool(i1 zeroext {s})\n", .{try self.value(argument)});
        if (argument_type == .str) return out.print(self.a(), "  call void @myl_core_main_error_str(ptr {s})\n", .{try self.value(argument)});
        const info = argument_type.integer() orelse return error.UnsupportedInstruction;
        try out.print(self.a(), "  call void @myl_core_main_error_{s}(i64 {s})\n", .{ if (info.signed) "i64" else "u64", try self.widened(out, argument) });
    }

    fn print(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const operands = self.function.operands(inst.data);
        const stream = try self.value(operands[0]);
        if (self.constantOf(operands[0]) == flags.error_stream) return self.reportError(out, operands[1]);
        for (operands[1..], 0..) |argument, i| {
            if (i != 0) try out.print(self.a(), "  call void @myl_core_print_sep(i64 {s})\n", .{stream});
            const argument_type = self.function.inst(self.function.resolve(argument)).ty;
            if (argument_type == .bool) {
                try out.print(self.a(), "  call void @myl_core_print_bool(i64 {s}, i1 zeroext {s})\n", .{ stream, try self.value(argument) });
            } else if (argument_type == .str_view) {
                try out.print(self.a(), "  call void @myl_core_print_view(i64 {s}, {s})\n", .{ stream, try self.spanArgument(out, argument) });
            } else if (argument_type == .str) {
                try out.print(self.a(), "  call void @myl_core_print_str(i64 {s}, ptr {s})\n", .{ stream, try self.value(argument) });
            } else {
                const info = argument_type.integer() orelse return error.UnsupportedInstruction;
                try out.print(self.a(), "  call void @myl_core_print_{s}(i64 {s}, i64 {s})\n", .{ if (info.signed) "i64" else "u64", stream, try self.widened(out, argument) });
            }
        }
        try out.print(self.a(), "  call void @myl_core_print_end(i64 {s})\n", .{stream});
    }
};

/// Bytes one list element occupies.
fn elementSize(ty: ir.Type) u32 {
    return switch (ty) {
        .bool, .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32 => 4,
        else => 8,
    };
}

/// The in-memory type of one list element.
fn storageType(ty: ir.Type) []const u8 {
    return switch (ty) {
        .bool, .i8, .u8 => "i8",
        .i16, .u16 => "i16",
        .i32, .u32 => "i32",
        .f64 => "double",
        .str, .bytes, .byte_buffer, .capability, .resource => "ptr",
        else => if (ty.isCompound()) "ptr" else "i64",
    };
}

/// ` !dbg !N` on a function definition and `, !dbg !N` on an instruction.
const function_scope = " !dbg !{d}";
const instruction_location = ", !dbg !{d}";

/// The DWARF metadata of a `dwarf_lines` module: one compile unit and file, one
/// `DISubprogram` per function, one `DILocation` per call and trap. Numbered from
/// `first_node`, clear of the TBAA and `!range` nodes.
const Debug = struct {
    text: Out = .empty,
    next: u32 = first_node,
    unit: u32 = 0,
    files: std.ArrayList(File) = .empty,
    fallback: []const u8 = "",
    scopes: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    const File = struct { path: []const u8, id: u32 };

    const first_node = 1_000_000;

    fn node(self: *Debug, allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !u32 {
        const id = self.next;
        self.next += 1;
        try self.text.print(allocator, "!{d} = ", .{id});
        try self.text.print(allocator, format ++ "\n", args);
        return id;
    }

    /// Start the compile unit (file, unit and subroutine type) on first use.
    fn file(self: *Debug, allocator: std.mem.Allocator, input: []const u8) !u32 {
        const path = if (input.len == 0) self.fallback else input;
        for (self.files.items) |known| if (std.mem.eql(u8, known.path, path)) return known.id;
        var quoted: Out = .empty;
        try escaped(allocator, &quoted, path);
        const id = try self.node(allocator, "!DIFile(filename: \"{s}\", directory: \"\")", .{quoted.items});
        try self.files.append(allocator, .{ .path = path, .id = id });
        return id;
    }

    fn begin(self: *Debug, allocator: std.mem.Allocator, path: []const u8) !void {
        if (self.unit != 0) return;
        _ = try self.file(allocator, path);
        self.unit = try self.node(allocator, "distinct !DICompileUnit(language: DW_LANG_C99, file: !{d}, producer: \"mylang-core\", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)", .{first_node});
        _ = try self.node(allocator, "!DISubroutineType(types: !{{}})", .{});
    }

    fn subprogram(self: *Debug, allocator: std.mem.Allocator, name: []const u8, at: Location) !u32 {
        try self.begin(allocator, at.path);
        const source = try self.file(allocator, at.path);
        const format = "distinct !DISubprogram(name: \"{s}\", scope: !{d}, file: !{d}, line: {d}, type: !{d}, scopeLine: {d}, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !{d})";
        return self.node(allocator, format, .{ name, source, source, at.line, first_node + 2, at.line, self.unit });
    }

    fn function(self: *Debug, allocator: std.mem.Allocator, index: u32, f: *const ir.Function, at: Location) !u32 {
        if (self.scopes.get(index)) |known| return known;
        const created = try self.subprogram(allocator, f.name, at);
        try self.scopes.put(allocator, index, created);
        return created;
    }

    fn location(self: *Debug, allocator: std.mem.Allocator, at: Location, scope: u32) !u32 {
        const source = try self.file(allocator, at.path);
        const local = try self.node(allocator, "!DILexicalBlockFile(scope: !{d}, file: !{d}, discriminator: 0)", .{ scope, source });
        return self.node(allocator, "!DILocation(line: {d}, column: {d}, scope: !{d})", .{ at.line, at.column, local });
    }

    fn inlinedLocation(self: *Debug, allocator: std.mem.Allocator, at: Location, scope: u32, inlined_at: u32) !u32 {
        const source = try self.file(allocator, at.path);
        const local = try self.node(allocator, "!DILexicalBlockFile(scope: !{d}, file: !{d}, discriminator: 0)", .{ scope, source });
        return self.node(allocator, "!DILocation(line: {d}, column: {d}, scope: !{d}, inlinedAt: !{d})", .{ at.line, at.column, local, inlined_at });
    }

    /// The nodes and the module flags that make LLVM emit them (DWARF 4: the runtime's reader).
    fn finish(self: *Debug, allocator: std.mem.Allocator, out: *Out) !void {
        if (self.unit == 0) return;
        try out.appendSlice(allocator, self.text.items);
        try out.print(allocator, "!llvm.dbg.cu = !{{!{d}}}\n!llvm.module.flags = !{{!{d}, !{d}}}\n", .{ self.unit, self.next, self.next + 1 });
        try out.print(allocator, "!{d} = !{{i32 2, !\"Debug Info Version\", i32 3}}\n!{d} = !{{i32 7, !\"Dwarf Version\", i32 4}}\n", .{ self.next, self.next + 1 });
    }
};

// R4: weak_odr survives LLVM dead stripping when its only caller is the
// separately compiled C runtime, while the linker merges one copy per unit.
const task_bridge =
    \\define weak_odr hidden ptr @myl_core_task_call(ptr %run, ptr %env) nounwind {
    \\  %result = call fastcc ptr %run(ptr %env)
    \\  ret ptr %result
    \\}
    \\
;

/// The allocator's common cases, inlined into every caller (`runtime/core_rt.c`,
/// "allocation"): a small list taken from its size class's free list, a push into a
/// list with room, and the free of a small block that holds no blocks. Everything
/// else calls the runtime. Free-list accesses carry no TBAA tag; nothing is counted
/// here (the leak check counts free-list entries at exit). The inline free starts with
/// a compiler barrier (an empty `asm` that clobbers memory, NEW-CORE-F1-TBAA-2): a block
/// it frees may come back from the inline `myl_core_list_new` as a list of another
/// element type, whose element tag says it cannot alias the old one's, so no access
/// may move across the free.
const runtime_fast_paths =
    \\@myl_core_free_lists = external thread_local(localexec) global [33 x ptr]
    \\declare preserve_mostcc void @myl_core_retain_slow(ptr) nounwind cold
    \\declare preserve_mostcc void @myl_core_release_slow(ptr) nounwind cold
    \\declare ptr @myl_core_list_new_slow(i64, i64) nounwind
    \\declare ptr @myl_core_list_grow(ptr, i64) nounwind
    \\declare void @myl_core_free_block(ptr) nounwind cold
    \\define internal ptr @myl_core_list_new(i64 %cap, i64 %size) alwaysinline nounwind {
    \\entry:
    \\  %many = icmp ugt i64 %cap, 1024
    \\  %data = mul i64 %cap, %size
    \\  %bytes = add i64 %data, 63
    \\  %class = lshr i64 %bytes, 5
    \\  %large = icmp ugt i64 %class, 32
    \\  %slow = or i1 %many, %large
    \\  br i1 %slow, label %call, label %small, !prof !9
    \\small:
    \\  %slot = getelementptr inbounds [33 x ptr], ptr @myl_core_free_lists, i64 0, i64 %class
    \\  %head = load ptr, ptr %slot, align 8
    \\  %empty = icmp eq ptr %head, null
    \\  br i1 %empty, label %call, label %pop, !prof !9
    \\pop:
    \\  %next = load ptr, ptr %head, align 8
    \\  store ptr %next, ptr %slot, align 8
    \\  store i32 1, ptr %head, align 8, !tbaa !3
    \\  %class32 = trunc i64 %class to i32
    \\  %kind = shl i32 %class32, 24
    \\  %kind_at = getelementptr inbounds i8, ptr %head, i64 4
    \\  store i32 %kind, ptr %kind_at, align 4, !tbaa !5
    \\  %len_at = getelementptr inbounds i8, ptr %head, i64 8
    \\  store i64 0, ptr %len_at, align 8, !tbaa !5
    \\  %room_total = shl i64 %class, 5
    \\  %room = sub i64 %room_total, 32
    \\  %fits = udiv i64 %room, %size
    \\  %cap_at = getelementptr inbounds i8, ptr %head, i64 16
    \\  store i64 %fits, ptr %cap_at, align 8, !tbaa !5
    \\  %reserved_at = getelementptr inbounds i8, ptr %head, i64 24
    \\  store i64 0, ptr %reserved_at, align 8, !tbaa !5
    \\  ret ptr %head
    \\call:
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
    \\  %prefix = icmp ult i64 %index, 4096
    \\  br i1 %prefix, label %fits, label %check, !prof !10
    \\fits:
    \\  ret ptr %list
    \\check:
    \\  %room = call ptr @myl_core_list_reserve(ptr %list, i64 %size)
    \\  ret ptr %room
    \\}
    \\define internal void @myl_core_free(ptr %block) alwaysinline nounwind {
    \\entry:
    \\  %kind_at = getelementptr inbounds i8, ptr %block, i64 4
    \\  %kind = load i32, ptr %kind_at, align 4, !tbaa !5
    \\  %class32 = lshr i32 %kind, 24
    \\  %reserved_at = getelementptr inbounds i8, ptr %block, i64 24
    \\  %reserved = load i64, ptr %reserved_at, align 8, !tbaa !5
    \\  %small = icmp ne i32 %class32, 0
    \\  %plain = icmp eq i64 %reserved, 0
    \\  %fast = and i1 %small, %plain
    \\  br i1 %fast, label %push, label %call, !prof !10
    \\push:
    \\  call void asm sideeffect "", "~{memory}"()
    \\  %class = zext i32 %class32 to i64
    \\  %slot = getelementptr inbounds [33 x ptr], ptr @myl_core_free_lists, i64 0, i64 %class
    \\  %head = load ptr, ptr %slot, align 8
    \\  store ptr %head, ptr %block, align 8
    \\  store ptr %block, ptr %slot, align 8
    \\  ret void
    \\call:
    \\  call void @myl_core_free_block(ptr %block)
    \\  ret void
    \\}
    \\
;

fn fastPaths(a: std.mem.Allocator, out: *Out, prelude: []const u8, body: []const u8, layouts: []const u8) !void {
    const first = std.mem.indexOf(u8, prelude, "define internal") orelse return error.UnsupportedInstruction;
    try out.appendSlice(a, prelude[0..first]);
    var definitions: std.ArrayList([]const u8) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var start = first;
    while (start < prelude.len) {
        const close = std.mem.indexOfPos(u8, prelude, start, "\n}\n") orelse break;
        const definition = prelude[start .. close + 3];
        var refs: emit_constants.Symbols = .{ .text = definition };
        const name = refs.next() orelse return error.UnsupportedInstruction;
        try definitions.append(a, definition);
        try names.append(a, name);
        start = close + 3;
    }
    var reached: std.ArrayList(u32) = .empty;
    for (names.items, 0..) |name, index| if (uses(body, name) or uses(layouts, name)) try reached.append(a, @intCast(index));
    var index: usize = 0;
    while (index < reached.items.len) : (index += 1) {
        const definition = definitions.items[reached.items[index]];
        try out.appendSlice(a, definition);
        for (names.items, 0..) |name, dependency| {
            if (!uses(definition, name) or std.mem.indexOfScalar(u32, reached.items, @intCast(dependency)) != null) continue;
            try reached.append(a, @intCast(dependency));
        }
    }
}

fn uses(text: []const u8, name: []const u8) bool {
    var refs: emit_constants.Symbols = .{ .text = text };
    while (refs.next()) |ref| if (std.mem.eql(u8, ref, name)) return true;
    return false;
}

/// Trace calls cost nothing to inline around (ERROR-TRACE-5). Trapping calls must
/// not merge across source scopes: a merged PC loses an inline caller frame.
const call_attributes = "attributes #1 = { \"call-inline-cost\"=\"0\" }\nattributes #2 = { nomerge }\n";

/// The branch-weight metadata every trap branch names (`!0`: the trap is cold).
pub const metadata = "!0 = !{!\"branch_weights\", i32 1, i32 1048575}\n";
