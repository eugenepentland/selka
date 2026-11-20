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
const memory_type_format = "[{d} x i8]";
const std = @import("std");
const product = @import("selka").product;
const equality = @import("build_equality.zig");
const zero_rc = @import("zero_rc.zig");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const loop_hoist = @import("loop_hoist.zig");
const emit_block_frame = @import("emit_block_frame.zig");
const vector = @import("vector.zig");
const c_abi = @import("c_abi.zig");
const transfers = @import("transfers.zig");
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
const type_ids = @import("type_ids.zig");
const emit_constants = @import("emit_constants.zig");
const emit_count = @import("emit_count.zig");
const freestanding_emitted = @import("freestanding_emitted.zig");
const emit_survey = @import("emit_survey.zig");
const fast_paths = @import("emit_fast_paths.zig");
const origins = @import("inline_origins.zig");
const emit_homes = @import("emit_homes.zig");
const emit_state = @import("emit_state.zig");
const effects = @import("effects.zig");
const fuse = @import("fuse.zig");

/// A source line and column for a span start.
pub const Location = @import("source_location.zig").Location;

/// Resolves span starts to lines and columns without tying the emitter to the front end.
pub const Locator = @import("source_location.zig").Locator;

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
    target: @import("target.zig").Target = @import("target.zig").host,
    /// A counting build (`--counters`, `emit_count.zig`): every function and counted
    /// site gets a record, and the program writes the counts at exit. Off, nothing
    /// in the emitted text changes.
    counters: bool = false,
    /// `alwaysinline` on the runtime fast paths and the emitter's helpers. Release and
    /// `--unoptimized` builds keep it. An optimized debug build clears it, so LLVM's cost
    /// model decides where a helper inlines: forced expansion at every call site was
    /// about a quarter of that build's LLVM work (the critical-path unit alone has 7,528 `drop` calls).
    forced_inline: bool = true,
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
    /// Whether the entry reads its runtime options from `SELKA_OPTIONS` before calling
    /// `main` (`myl_core_start`, NATIVE-ARGV-1): a program's entry does, a test executable's does not.
    runtime_options: bool = false,
    /// The device hooks bound to Selka functions (`device_hooks`), by name, in the order of the roots after `main` (MCU-NOC4A):
    /// the entry unit writes each one's C-ABI function beside `main`.
    hooks: []const []const u8 = &.{},
};

/// The capability family of an `Input` parameter (`Type.capabilityIndex`); it is granted unconditionally.
const input_family: u8 = 8;

/// Set in `MainOptions.capabilities` on the family of an entry parameter written `T?` (CAP-OPT): the entry passes
/// `Some` of the capability when the command line grants it and `None` when it does not.
pub const optional_family: u8 = 0x80;

/// The case tags of `main`'s `Result` return type.
pub const MainResult = struct { ok_tag: u32, error_tag: u32 };

/// What a call reaches, for how its register arguments cross: a selka function, a runtime helper compiled from C, or
/// a source `extern def` (which also sees every NaN as the canonical one).
const Callee = enum { selka, runtime, foreign };

/// Whether `function` is compiled C, a source `extern def` or a runtime helper, and not an adapter this compiler
/// defines in LLVM: a C callee reads a `bool` or narrow integer argument from the register its caller widened (FX4,
/// `c_abi.argumentExtension`), which an unoptimised LLVM caller does only when the argument carries the attribute.
fn compiledC(function: *const ir.Function) bool {
    return switch (function.signature.linkage) {
        .extern_c, .extern_address => true,
        .runtime_c => !emit_values.generated(function),
        .internal => false,
    };
}

/// What a call instruction reaches; an indirect call reaches a selka function.
fn calleeOf(m: *const ir.Module, inst: ir.Inst) Callee {
    if (inst.op != .call) return .selka;
    const function = &m.functions.items[inst.a.index()];
    if (function.signature.linkage.externC()) return .foreign;
    return if (compiledC(function)) .runtime else .selka;
}

/// Trap kinds, in the order the runtime's code table lists them. `list_empty` is a
/// pop of an empty list (`R_LIST_BOUNDS`, operation `pop`); `trace` marks an
/// error-trace site, which never traps; `assertion` is a failed `assert` or contract clause (its
/// `width` is the `typed.AssertionKind`, its `operation` the message).
/// Runtime helpers whose first parameter is the trap site the compiler emits for
/// the call: the boundary-checked text slices (B3, DECISIONS F17).
fn siteTaking(name: []const u8) bool {
    return std.mem.eql(u8, name, "myl_core_ir_str_slice_bytes") or
        std.mem.eql(u8, name, "myl_core_ir_str_slice_bytes_span") or
        std.mem.eql(u8, name, "myl_core_view_slice_text") or
        std.mem.eql(u8, name, "myl_core_text_search_bytes") or
        std.mem.eql(u8, name, "myl_core_span_text_search_bytes");
}

/// The `myl_core_site.kind` a trap call reports: the numeric tag the runtime's
/// diagnostic renderer switches on (`core_rt.c`).
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
    text_boundary = 20,
    typed_hole = 21,
    /// A `-> bytes` extern's length is negative, or its pointer null with a positive length (D-FFI-3).
    foreign_result = 22,
    /// An `@address` extern was called through a null handle or the address 0 (`R_FOREIGN_TARGET`).
    foreign_target = 23,
    /// A foreign call in freestanding code whose `Host` token is not the live one (`R_CAPABILITY`): a fault only, which
    /// `myl_core_trap` never sees (`freestanding_emitted.capability_kind`).
    capability = freestanding_emitted.capability_kind,
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

/// One trap site. A `fault` site is a failed check of a `@freestanding` function: only its path is emitted, which the
/// fault names by address (`freestanding_emitted.zig`); it has no record and no operation or function text.
const Site = struct { kind: TrapKind, location: Location, width: u16, operation: []const u8, function: []const u8, fault: bool = false };

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
/// operands the runtime prints unsigned (`SELKA_CORE_SITE_UNSIGNED` in `runtime/core_rt.c`).
const unsigned_site: u16 = 0x100;

/// `  %x = getelementptr inbounds i8, ptr p, i64 0`: a new name for the same block.
const zero_trap_line = "  call void @myl_core_trap(ptr @myl.site.{d}, i64 0, i64 0) #2{s}\n  unreachable\n";

const same_pointer = "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n";

/// A destruction operation whose owner may be absent on one control-flow path.
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

/// Header and value data use distinct alias tags; scalar element tags refine data.
const tbaa_header = "!tbaa !5";
const tbaa_data = "!tbaa !7";
/// The first `!range` node number free for fact intervals.
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
    \\!4 = !{!"myl.header", !1, i64 0}
    \\!5 = !{!4, !4, i64 0}
    \\!6 = !{!"myl.data", !1, i64 0}
    \\!7 = !{!6, !6, i64 0}
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
    \\
;
/// `  %x = load i64, ptr %at` of one data word (a union's tag word or payload word).
const word_load_line = "  {s} = load i64, ptr {s}, align 8, " ++ tbaa_data ++ "\n";
/// A union's tag word loaded from memory, then its tag byte.
const tag_load_line = word_load_line ++ "  {s} = trunc i64 {s} to i8\n";
/// Whether a union's tag byte names case `k`.
const case_test_line = "  {s} = icmp eq i8 {s}, {d}\n";
/// Non-tearing count reads after task publication; unordered preserves loop hoisting.
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
    /// What every unit of the program reads of the whole module, read once (`survey`); null makes the render read it.
    survey: ?*const emit_survey.Survey = null,
};

/// Survey `module` for the units a partition renders with `options`: the whole-module facts and the fast-path preludes
/// `ModuleState.emitPrelude` would otherwise compute for each unit.
pub fn survey(allocator: std.mem.Allocator, module: *const ir.Module, options: Options) Error!emit_survey.Survey {
    var number: Out = .empty;
    try emit_number.prelude(allocator, &number);
    const counted = options.counters or @import("testcount_runtime.zig").needed(module);
    const preludes = [_][]const u8{ if (counted) emit_count.fast_paths else runtime_fast_paths, runtime_owned_drop, number.items };
    return emit_survey.Survey.of(allocator, module, &preludes);
}

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
    try emit_survey.validateEquality(allocator, if (selection) |chosen| chosen.survey else null, module);
    var options = given;
    if (options.analysis.effects == null) {
        const summaries = try allocator.create(effects.Summaries);
        summaries.* = try effects.analyze(allocator, module);
        options.analysis.effects = summaries;
    }
    const ids = if (selection) |chosen| chosen.constants.ids else type_ids.Table.build(allocator, module) catch return error.UnsupportedInstruction;
    var state: ModuleState = .{ .allocator = allocator, .module = module, .options = options, .local = .{ .selection = selection, .ids = ids }, .debug = .{ .fallback = if (selection) |chosen| chosen.source_path else options.source_path } };
    var body: Out = .empty;
    if (selection) |chosen| {
        for (chosen.functions) |index| try renderFunction(&state, &body, index);
    } else for (module.functions.items, 0..) |_, index| try renderFunction(&state, &body, @intCast(index));
    if (selection == null or selection.?.entry) {
        try state.emitEntry(&body);
        try state.emitHooks(&body);
    }
    try state.faultHandler(&body);
    var out: Out = .empty;
    try out.appendSlice(allocator, "; generated by selka-core\n");
    try out.appendSlice(allocator, "; selka-zero-rc-v2\n");
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
    if (selection == null) try emit_values.descriptorsWith(allocator, module, state.local.ids, &out);
    try out.appendSlice(allocator, call_attributes);
    if (state.local.zeros != 0) try out.print(allocator, "@myl.zeros = private constant [{d} x i8] zeroinitializer, align 8\n", .{state.local.zeros});
    try state.debug.finish(allocator, &out);
    if (!zero_rc.emittedClean(out.items)) return error.UnsupportedInstruction;
    if (!options.forced_inline) out = try withoutForcedInline(allocator, out.items);
    if (selection) |chosen| return chosen.constants.finish(allocator, out.items);
    return out.toOwnedSlice(allocator);
}

/// The unit's text with `alwaysinline` taken off each definition. Only `define` lines
/// carry the attribute, so every other line is copied unchanged.
pub fn withoutForcedInline(allocator: std.mem.Allocator, text: []const u8) Error!Out {
    var out: Out = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try out.append(allocator, '\n');
        first = false;
        if (std.mem.startsWith(u8, line, "define ")) {
            if (std.mem.indexOf(u8, line, " alwaysinline")) |at| {
                try out.appendSlice(allocator, line[0..at]);
                try out.appendSlice(allocator, line[at + " alwaysinline".len ..]);
                continue;
            }
        }
        try out.appendSlice(allocator, line);
    }
    return out;
}

fn renderFunction(state: *ModuleState, body: *Out, index: u32) Error!void {
    const function = &state.module.functions.items[index];
    if (function.signature.linkage != .internal) {
        if (state.local.selection != null) {
            _ = try emit_values.adapterNamed(state.allocator, body, state.local.ids, function, .{ .symbol = state.functionName(index), .linkage = state.linkage(index) });
        } else try state.declareExtern(index);
        return;
    }
    try @import("marker_validation.zig").validate(state.allocator, state.module, function);
    var emitter: FunctionEmitter = .{ .state = state, .function = function, .index = index };
    // A target without vector plans (`Vector.plans`) keeps every loop scalar.
    if (index < state.options.analysis.vectors.len and state.options.target.vector.plans) emitter.vectors.plans = state.options.analysis.vectors[index];
    const start = body.items.len;
    try emitter.emitFunction(body);
    if (state.module.isFreestanding(function)) try checkFreestanding(state, function, body.items[start..]);
}

/// A `@freestanding` function's emitted text names only what it may call (`freestanding_emitted.check`): the other
/// freestanding functions, `extern func`s and the `registers` reads and writes. A broken promise is an internal error that
/// names the function and the symbol.
fn checkFreestanding(state: *ModuleState, function: *const ir.Function, text: []const u8) Error!void {
    var allowed: std.ArrayList([]const u8) = .empty;
    for (state.module.functions.items, 0..) |*candidate, index| {
        const permitted = candidate.signature.linkage.externC() or state.module.isFreestanding(candidate) or freestanding_emitted.registersAccess(state.module, index);
        if (permitted) try allowed.append(state.allocator, try state.originalSymbol(@intCast(index)));
    }
    const violation = freestanding_emitted.check(function.name, text, allowed.items, state.options.target) orelse return;
    freestanding_emitted.report(violation);
    return error.UnsupportedInstruction;
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
    /// The ids of the module's type descriptors: the build's catalog's, or one built for this render.
    ids: type_ids.Table = .{},
    strings: std.ArrayList(Literal) = .empty,
    dictionaries: std.ArrayList(ir.Type) = .empty,
    /// The element types whose empty list this LLVM module declares, in order of first use: an empty list is named by its place here.
    empty_lists: std.ArrayList(ir.Type) = .empty,
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
        if (sret) try self.externs.print(self.allocator, "ptr noalias sret({s}) align 8", .{try std.fmt.allocPrint(self.allocator, memory_type_format, .{abi.size(self.module, function.signature)})});
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
        // An `@address` extern is called through a value: it has no symbol to declare.
        if (self.module.functions.items[index].signature.linkage == .extern_address) return;
        if (try equality.declaration(self.module, &self.module.functions.items[index])) return;
        if (try @import("borrow_selection.zig").declaration(self.module, &self.module.functions.items[index])) return;
        if (try @import("borrowed_provider.zig").declaration(self.module, &self.module.functions.items[index])) return;
        const function = &self.module.functions.items[index];
        if (@import("emit_registers.zig").declaration(self.options.target, function)) return;
        return self.external(function, self.functionName(index));
    }

    fn external(self: *ModuleState, function: *const ir.Function, name: []const u8) !void {
        if (try equality.declaration(self.module, function)) return;
        if (try @import("aggregate_provider.zig").marker(self.module, function)) return;
        if (self.local.selection == null and try emit_values.adapter(self.allocator, &self.externs, self.local.ids, function)) return;
        // Several signatures of one runtime function (`myl_core_list_sort` over lists of different
        // elements) are one declaration.
        const symbol_name = c_abi.symbol(name);
        if (std.mem.eql(u8, symbol_name, flags.str_eq_symbol)) return;
        // The prelude declares the printing and text primitives every module may
        // use, so a lowered call reuses that declaration: LLVM rejects a second
        // declaration of the same function.
        if (predeclared(symbol_name)) return;
        for (self.declared.items) |known| if (std.mem.eql(u8, known, symbol_name)) return;
        try self.declared.append(self.allocator, symbol_name);
        if (c_abi.foreign(function)) return self.foreignDeclaration(function, symbol_name);
        const returns = try self.llvmType(function.signature.ret);
        // A structure result the target's C convention returns through memory is a hidden first argument (`sret`).
        const in_memory = compiledC(function) and c_abi.returnsInMemory(self.options.target.machine.c_abi, returns);
        const convention = if (emit_values.generated(function)) "hidden fastcc " else "";
        const result_extension = if (function.signature.ret == .bool) "zeroext " else "";
        try self.externs.print(self.allocator, "declare {s}{s}{s} @{s}(", .{ convention, result_extension, if (in_memory) "void" else returns, symbol_name });
        var first = true;
        if (in_memory) {
            try self.externs.print(self.allocator, "ptr sret({s}) align 8", .{returns});
            first = false;
        }
        // A site-taking helper receives the trap site the compiler emits for each
        // call, ahead of its IR parameters (B3, DECISIONS F17).
        if (siteTaking(symbol_name)) {
            try self.externs.appendSlice(self.allocator, "ptr");
            first = false;
        }
        const c_function = compiledC(function);
        for (function.signature.params, 0..) |param, i| {
            if (function.signature.linkage.externC() and !c_abi.passes(param)) continue;
            const span = function.signature.passing.viewAt(i);
            const extension = if (c_function) c_abi.argumentExtension(param) else "";
            const spelling = if (!span) try self.llvmType(param) else if (zero_rc.ownerSpan(symbol_name)) "ptr, ptr, i64" else "ptr, i64";
            try self.externs.print(self.allocator, "{s}{s}{s}{s}", .{ if (first) "" else ", ", spelling, if (extension.len == 0) "" else " ", extension });
            first = false;
        }
        // The runtime's string helpers only read their arguments, so LLVM may merge and hoist calls.
        try self.externs.appendSlice(self.allocator, if (flags.readsOnly(c_abi.symbol(function.name))) ") nounwind willreturn memory(argmem: read)\n" else ") nounwind\n");
    }

    /// The C prototype of a source extern with a copied `bytes` result or `mut` out-parameters (D-FFI-3, D-FFI-5): each
    /// `mut` position is a `ptr` to its temporary, a `bytes` result returns `ptr` and takes a trailing `int64_t *` length.
    fn foreignDeclaration(self: *ModuleState, function: *const ir.Function, symbol_name: []const u8) !void {
        const signature = function.signature;
        const result = c_abi.foreignResult(self.module, signature);
        const returns = if (result == .bytes) "ptr" else try self.llvmType(result);
        try self.externs.print(self.allocator, "declare {s}{s} @{s}(", .{ if (result == .bool) "zeroext " else "", returns, symbol_name });
        var first = true;
        for (signature.params, 0..) |param, i| {
            if (!c_abi.passes(param)) continue;
            const extension = c_abi.argumentExtension(param);
            const spelling = if (signature.passing.ownedAt(i)) "ptr" else if (signature.passing.viewAt(i)) "ptr, i64" else try self.llvmType(param);
            const marked = !signature.passing.ownedAt(i) and extension.len != 0;
            try self.externs.print(self.allocator, "{s}{s}{s}{s}", .{ if (first) "" else ", ", spelling, if (marked) " " else "", if (marked) extension else "" });
            first = false;
        }
        if (result == .bytes) try self.externs.print(self.allocator, "{s}ptr", .{if (first) "" else ", "});
        try self.externs.appendSlice(self.allocator, ") nounwind\n");
        if (result != .bytes) return;
        for (self.declared.items) |known| if (std.mem.eql(u8, known, c_abi.bytes_copy)) return;
        try self.declared.append(self.allocator, c_abi.bytes_copy);
        try self.externs.print(self.allocator, "declare ptr @{s}(ptr, ptr, i64) nounwind\n", .{c_abi.bytes_copy});
    }

    /// A `!range` node for `[lo, hi]` in a `bits`-wide integer.
    fn rangeNode(self: *ModuleState, bits: u16, range: facts.Interval) ![]const u8 {
        self.meta.range_count += 1;
        try self.meta.ranges.print(self.allocator, "!{d} = !{{i{d} {d}, i{d} {d}}}\n", .{ self.meta.range_count, bits, range.lo, bits, range.hi + 1 });
        return std.fmt.allocPrint(self.allocator, ", !range !{d}", .{self.meta.range_count});
    }

    /// The `@myl.layout.N` constant for elements of `ty` (a managed type), emitted once.
    pub fn layoutSymbol(self: *ModuleState, ty: ir.Type) Error![]const u8 {
        for (self.layouts.types.items, 0..) |known, i| {
            if (known == ty) return std.fmt.allocPrint(self.allocator, "@myl.layout.{d}", .{i});
        }
        var parts: LayoutParts = .{};
        try layoutParts(self.allocator, self.module, ty, 0, 0, &parts);
        const index = self.layouts.types.items.len;
        try self.layouts.types.append(self.allocator, ty);
        const name = try std.fmt.allocPrint(self.allocator, "@myl.layout.{d}", .{index});
        try emit_release.emit(self.allocator, &self.layouts.text, name, @max(1, self.module.size(ty)), .{ .refs = parts.refs.items, .guards = parts.guards.items });
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
            .f32 => "float",
            .str, .bytes, .byte_buffer, .capability, .resource, .task_group, .task_handle => "ptr",
            .str_view, .bytes_view => "{ ptr, i64 }",
            _ => switch (self.module.compound(ty)) {
                .list, .box, .dict, .@"fn" => "ptr",
                .list_view => "{ ptr, i64 }",
                .borrowed => |inner| self.llvmType(inner),
                .array => |array| if (array.vector)
                    std.fmt.allocPrint(self.allocator, "<{d} x {s}>", .{ array.n, try self.llvmType(array.elem) })
                else if (self.module.passedInMemory(ty))
                    "ptr"
                else
                    std.fmt.allocPrint(self.allocator, "[{d} x {s}]", .{ array.n, try self.llvmType(array.elem) }),
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
        return std.fmt.allocPrint(self.allocator, memory_type_format, .{self.module.size(ty)});
    }

    /// Bytes between consecutive list elements of type `ty`.
    pub fn stride(self: *ModuleState, ty: ir.Type) u32 {
        return @max(1, self.module.size(ty));
    }

    fn emitPrelude(self: *ModuleState, out: *Out, body: []const u8) !void {
        const target = self.options.target;
        try out.appendSlice(self.allocator, try forTarget(self.allocator, target, prelude_declarations));
        if (self.options.counters) try out.appendSlice(self.allocator, try forTarget(self.allocator, target, emit_count.declarations));
        try out.appendSlice(self.allocator, task_bridge);
        try out.appendSlice(self.allocator, "declare void @myl_core_drop_owned(ptr) nounwind\ndeclare void @myl_core_box_drop_shell(ptr) nounwind\n");
        // A testing measurement counts every allocation, including reuse from
        // a free list. The inline allocator bypasses the runtime's count event.
        const counted_allocations = self.options.counters or emit_survey.testCounts(self.surveyed(), self.module);
        const paths = try forTarget(self.allocator, target, if (counted_allocations) emit_count.fast_paths else runtime_fast_paths);
        // The unit's text is read once for the symbols it names; each prelude then appends the helpers they reach.
        const named = try fast_paths.Named.of(self.allocator, &.{ body, self.layouts.text.items });
        try self.fastPaths(out, paths, &named);
        if (!self.options.counters) try self.fastPaths(out, runtime_owned_drop, &named);
        try out.appendSlice(self.allocator, self.externs.items);
        var number: Out = .empty;
        try emit_number.prelude(self.allocator, &number);
        try self.fastPaths(out, number.items, &named);
        try emit_bytes.prelude(self.allocator, out);
    }

    /// The survey of this render's program when it describes this module (`emit_survey.fitting`).
    fn surveyed(self: *const ModuleState) ?*const emit_survey.Survey {
        const selected = self.local.selection orelse return null;
        return emit_survey.fitting(selected.survey, self.module);
    }

    /// Append the helpers of `text` (a fast-path prelude) that `named` reaches, parsing it unless the survey has.
    fn fastPaths(self: *ModuleState, out: *Out, text: []const u8, named: *const fast_paths.Named) !void {
        var parsed: fast_paths.Prelude = undefined;
        const prelude = if (self.surveyed()) |known| known.prelude(text) else null;
        const chosen = prelude orelse chosen: {
            parsed = try fast_paths.Prelude.parse(self.allocator, text);
            break :chosen &parsed;
        };
        try fast_paths.append(self.allocator, out, chosen, named);
    }

    /// The Linux handler of a unit that holds a freestanding fault (`freestanding_emitted.linuxHandler`), with the
    /// declarations the unit does not have yet. A unit with no fault gets nothing, so its text is what it was.
    fn faultHandler(self: *ModuleState, body: *Out) !void {
        if (!freestanding_emitted.linuxTarget(self.options.target)) return;
        for (self.sites.items) |s| {
            if (s.fault) break;
        } else return;
        for (freestanding_emitted.handler_externs) |known| {
            if (predeclared(known.name)) continue;
            for (self.declared.items) |name| {
                if (std.mem.eql(u8, name, known.name)) break;
            } else {
                try self.declared.append(self.allocator, known.name);
                try self.externs.appendSlice(self.allocator, known.declaration);
            }
        }
        try freestanding_emitted.linuxHandler(self.allocator, body);
    }

    fn emitSites(self: *ModuleState, out: *Out) !void {
        for (self.sites.items, 0..) |s, i| {
            const path = if (s.location.path.len != 0) s.location.path else self.options.source_path;
            try out.print(self.allocator, "@myl.path.{d} = private constant [{d} x i8] c\"", .{ i, path.len + 1 });
            try escaped(self.allocator, out, path);
            try out.appendSlice(self.allocator, nul_terminator);
            if (s.fault) continue;
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

    /// String constants carry the static-storage bit, so destruction leaves them intact.
    fn emitStrings(self: *ModuleState, out: *Out) !void {
        for (self.local.strings.items, 0..) |literal_info, i| {
            const bytes = self.module.strings.items[literal_info.original];
            const block_type = try std.fmt.allocPrint(self.allocator, "{{ i32, i32, i64, i64, i64, [{d} x i8] }}", .{bytes.len + 1});
            try out.print(self.allocator, "@myl.str.{d} = private unnamed_addr constant {s} ", .{ i, block_type });
            const cached = text_builder.metadata(bytes);
            const kind = (if (literal_info.raw) (cached.kind & ~@as(u32, 255)) | 3 else cached.kind) | @as(u32, 1 << 23);
            const first: i64 = kind;
            const second: u32 = 0;
            try out.print(self.allocator, "{{ i32 {d}, i32 {d}, i64 {d}, i64 {d}, i64 {d}, [{d} x i8] c\"", .{ first, second, bytes.len, bytes.len, cached.meta, bytes.len + 1 });
            try escaped(self.allocator, out, bytes);
            try out.appendSlice(self.allocator, "\\00\" }, align 32\n");
        }
    }

    /// The entry's first call, the runtime's start (NATIVE-ARGV-1): `myl_core_start`, which also installs the byte ceiling
    /// the environment names, or, when `main` installs a run's budget, the start that leaves the ceiling to that budget
    /// (`run_budget.installs`, BIN-CEILING). The second is declared here, so a program built without a budget emits as before.
    fn emitStart(self: *ModuleState, out: *Out) !void {
        const run_budget = @import("run_budget.zig");
        if (!run_budget.installs(self.module)) return out.appendSlice(self.allocator, "  call void @myl_core_start()\n");
        const name = run_budget.budgeted_start;
        const declared = for (self.declared.items) |known| {
            if (std.mem.eql(u8, known, name)) break true;
        } else false;
        if (!declared) {
            try self.declared.append(self.allocator, name);
            try self.externs.print(self.allocator, "declare void @{s}() nounwind\n", .{name});
        }
        try out.print(self.allocator, "  call void @{s}()\n", .{name});
    }

    /// `int main(argc, argv)`: build the arguments `main` asks for, call it, release
    /// the arguments `main` borrows and exit with its status. An argument `main` takes
    /// (`own fs`, `own args`) is dropped by `main` itself, so the entry leaves it alone
    /// (F-G2b-34: releasing it here as well freed the grant twice). A `main` returning
    /// a `Result` reports an `Err` with its trace first (RESULT-MAIN-1/2, ERROR-TRACE-2).
    fn emitEntry(self: *ModuleState, out: *Out) !void {
        const entry = &self.module.functions.items[self.module.entry];
        try self.dependency(self.module.entry);
        // `dwarf_lines`: the C entry has a subprogram too (named `myl.entry`, which trap
        // frames never print), or inlining `main` into it would drop every location.
        var at: []const u8 = "";
        var scope: []const u8 = "";
        if (self.options.target.system.lines) {
            const node = try self.debug.subprogram(self.allocator, "myl.entry", .{ .line = 1, .column = 1, .path = self.options.source_path });
            scope = try std.fmt.allocPrint(self.allocator, function_scope, .{node});
            at = try std.fmt.allocPrint(self.allocator, instruction_location, .{try self.debug.location(self.allocator, .{ .line = 1, .column = 1 }, node)});
        }
        try out.print(self.allocator, "define i32 @main(i32 %argc, ptr %argv){s}{s} {{\nentry:\n", .{ unwindTable(self.options.target), scope });
        if (self.options.main.runtime_options) try self.emitStart(out);
        var arguments: Out = .empty;
        var owns_args = false;
        var cleanup: Out = .empty;
        for (entry.signature.params, 0..) |param, i| {
            if (i != 0) try arguments.appendSlice(self.allocator, ", ");
            const taken = entry.signature.passing.takes(i);
            if (param == .cap) {
                if (try emit_cap.entry(self, out, i)) |handle| {
                    try arguments.appendSlice(self.allocator, handle);
                    continue;
                }
                if (try emit_cap.token(self, out, i)) |token| {
                    try arguments.appendSlice(self.allocator, token);
                    continue;
                }
                // An `Input` is the process's standard input, descriptor 0; a `Stream` is stdout or, named `err`, stderr.
                if (i < self.options.main.capabilities.len and self.options.main.capabilities[i] == input_family) {
                    try arguments.appendSlice(self.allocator, "i64 0");
                    continue;
                }
                const name = if (i < self.options.main.parameters.len) self.options.main.parameters[i] else "";
                try arguments.print(self.allocator, "i64 {d}", .{@as(u8, if (std.mem.eql(u8, name, "err")) 2 else 1)});
            } else if (try emit_cap.offered(@TypeOf(self), self, out, i, param)) |option| {
                try arguments.appendSlice(self.allocator, option);
            } else if (param.isCompound() and self.module.compound(param) == .list and self.module.compound(param).list == .str) {
                try out.appendSlice(self.allocator, "  %args = call ptr @myl_core_args(i32 %argc, ptr %argv)\n");
                try arguments.appendSlice(self.allocator, "ptr %args");
                owns_args = !taken;
            } else return error.UnsupportedEntry;
        }
        if (owns_args) try cleanup.appendSlice(self.allocator, "  call void @myl_core_drop_owned(ptr %args)\n");
        const release_args = cleanup.items;
        const ret = entry.signature.ret;
        const callee = try symbol(self.allocator, entry.name);
        const tail = if (self.options.target.system.traps == .dwarf_lines) "notail " else "";
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

    /// The C-ABI function of each device hook (`options.main.hooks`), named as the runtime's hook symbol (strong, so it replaces the
    /// runtime's weak default): it widens the C arguments to the Selka function's types and calls it with the `Registers` token,
    /// `i64 0`, as `main` gets it, and, for a hook that takes `host` after `reg` (MCU-NOC4C), the `Host` token the runtime's grant
    /// answers, as `main(host: Host)` gets it. Hook `n` is function `n + 1`: the roots after `main` (`build.Input.hooks`).
    fn emitHooks(self: *ModuleState, out: *Out) !void {
        const device_hooks = @import("selka").device_hooks;
        for (self.options.main.hooks, 0..) |name, position| {
            const hook = device_hooks.named(name) orelse continue;
            const index: u32 = @intCast(position + 1);
            const function = &self.module.functions.items[index];
            try self.dependency(index);
            const callee = try symbol(self.allocator, function.name);
            var parameters: Out = .empty;
            var extended: Out = .empty;
            var arguments: Out = .empty;
            try arguments.appendSlice(self.allocator, "i64 0");
            const leading: usize = if (device_hooks.takesHost(hook, function.signature.params.len)) 2 else 1;
            if (leading == 2) {
                try emit_cap.hostGrant(self, &extended, "%host");
                try arguments.appendSlice(self.allocator, ", i64 %host");
            }
            for (hook.params, 0..) |param, at| {
                try parameters.print(self.allocator, "{s}i32 %a{d}", .{ if (at == 0) "" else ", ", at });
                if (std.mem.eql(u8, try self.llvmType(function.signature.params[at + leading]), "i64")) {
                    try extended.print(self.allocator, "  %w{d} = {s} i32 %a{d} to i64\n", .{ at, if (param == .int) "sext" else "zext", at });
                    try arguments.print(self.allocator, ", i64 %w{d}", .{at});
                } else try arguments.print(self.allocator, ", i32 %a{d}", .{at});
            }
            const result = hook.result;
            const c_result: []const u8 = if (result == null) "void" else if (result.? == .bool) "zeroext i1" else "i32";
            try out.print(self.allocator, "define {s} @{s}({s}) {{\nentry:\n{s}", .{ c_result, hook.symbol, parameters.items, extended.items });
            if (result == null) {
                try out.print(self.allocator, "  call fastcc void {s}({s})\n", .{ callee, arguments.items });
                try out.appendSlice(self.allocator, if (hook.noreturn) "  br label %halt\nhalt:\n  call void asm sideeffect \"wfi\", \"\"()\n  br label %halt\n}\n" else "  ret void\n}\n");
            } else if (result.? == .bool) {
                try out.print(self.allocator, "  %r = call fastcc i1 {s}({s})\n  ret i1 %r\n}}\n", .{ callee, arguments.items });
            } else if (std.mem.eql(u8, try self.llvmType(function.signature.ret), "i64")) {
                try out.print(self.allocator, "  %r = call fastcc i64 {s}({s})\n  %t = trunc i64 %r to i32\n  ret i32 %t\n}}\n", .{ callee, arguments.items });
            } else try out.print(self.allocator, "  %r = call fastcc i32 {s}({s})\n  ret i32 %r\n}}\n", .{ callee, arguments.items });
        }
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
            const destroy = "myl_core_drop_owned";
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

/// Collect the block pointers in a value of `ty` stored at `base`, each visited only under `guard`.
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
        .list, .box, .dict, .@"fn", .list_view, .borrowed => unreachable,
    }
}

fn escaped(allocator: std.mem.Allocator, out: *Out, text: []const u8) !void {
    for (text) |byte| {
        if (byte < 0x20 or byte >= 0x7f or byte == '"' or byte == '\\') try out.print(allocator, "\\{X:0>2}", .{byte}) else try out.append(allocator, byte);
    }
}

/// The LLVM symbol of a selka function.
fn symbol(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "@\"" ++ product.guest_symbol_prefix ++ "{s}\"", .{name});
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
    /// Per instruction: an old slot transferred by a dominating earlier read.
    transferred: []bool = &.{},
    /// The lists and buffers whose length a loop keeps in slots while it appends (`emit_state.zig`).
    states: emit_state.Plan = .{},
};

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

    /// Logical tuple fields updated through their parameter pointer do not cross sret.
    fn omitted(self: InOutAbi, signature: ir.Signature, field_index: usize) bool {
        for (0..signature.params.len) |param| {
            if (self.inOut(param) and self.field(signature, param) == field_index) return true;
        }
        return false;
    }

    /// Wide transported fields retain their logical layout so CE2 can construct them
    /// directly in the caller's destination, including nested union payloads and call results.
    fn compact(self: InOutAbi, m: *const ir.Module, signature: ir.Signature) bool {
        if (self.params == 0 or self.whole) return false;
        for (m.compound(signature.ret).record, 0..) |field_type, i| {
            if (!self.omitted(signature, i) and m.passedInMemory(field_type)) return false;
        }
        return true;
    }

    fn offset(self: InOutAbi, m: *const ir.Module, signature: ir.Signature, field_index: usize) u32 {
        if (!self.compact(m, signature)) return m.fieldOffset(signature.ret, field_index);
        var bytes: u32 = 0;
        for (m.compound(signature.ret).record[0..field_index], 0..) |field_type, i| {
            if (!self.omitted(signature, i)) bytes = std.mem.alignForward(u32, bytes, m.alignment(field_type)) + m.size(field_type);
        }
        return std.mem.alignForward(u32, bytes, m.alignment(m.compound(signature.ret).record[field_index]));
    }

    fn size(self: InOutAbi, m: *const ir.Module, signature: ir.Signature) u32 {
        if (!self.compact(m, signature)) return m.size(signature.ret);
        var bytes: u32 = 0;
        var alignment: u32 = 1;
        for (m.compound(signature.ret).record, 0..) |field_type, i| {
            if (self.omitted(signature, i)) continue;
            const field_alignment = m.alignment(field_type);
            bytes = std.mem.alignForward(u32, bytes, field_alignment) + m.size(field_type);
            alignment = @max(alignment, field_alignment);
        }
        return @max(std.mem.alignForward(u32, bytes, alignment), 1);
    }

    /// Whether parameter `param` is in-out (a signature of 64 or more parameters has none).
    fn inOut(self: InOutAbi, param: usize) bool {
        return param < 64 and self.params & (@as(u64, 1) << @intCast(param)) != 0;
    }

    /// The result record's field holding parameter `param`'s final value.
    fn field(self: InOutAbi, signature: ir.Signature, param: usize) u32 {
        const below = signature.passing.owned & ((@as(u64, 1) << @intCast(param)) - 1);
        return self.first + @popCount(below);
    }
};

/// The in-out ABI of an internal signature whose result follows the `mut` convention (the
/// final value of each `mut` parameter, after the declared result unless that is `unit`);
/// every other signature passes nothing in-out.
fn inOutAbi(m: *const ir.Module, signature: ir.Signature) InOutAbi {
    if (!emit_homes.steps.in_out or signature.linkage != .internal) return .{};
    if (!signature.passing.hasOwned() or signature.passing.hasExtras()) return .{};
    if (signature.params.len > 63 or signature.passing.owned >> @intCast(signature.params.len) != 0) return .{};
    const muts: u32 = @popCount(signature.passing.owned);
    var abi: InOutAbi = .{};
    if (muts == 1) {
        const only: usize = @ctz(signature.passing.owned);
        if (signature.ret == signature.params[only]) {
            if (!m.passedInMemory(signature.ret)) return .{};
            return .{ .params = signature.passing.owned, .whole = true };
        }
    }
    if (m.kind(signature.ret) != .record) return .{};
    const fields = m.compound(signature.ret).record;
    if (fields.len != muts and fields.len != muts + 1) return .{};
    if (fields.len == muts and muts < 2) return .{};
    abi.first = @intCast(fields.len - muts);
    for (signature.params, 0..) |param, i| {
        if (signature.passing.owned & (@as(u64, 1) << @intCast(i)) == 0) continue;
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
    if (!emit_homes.steps.share_sret or signature.passing.hasExtras()) return emit_homes.none;
    if (signature.linkage != .internal or abi.params != 0 or !returnsThroughSret(m, signature, abi)) return emit_homes.none;
    for (signature.params, 0..) |param, i| {
        if (i >= 64) break;
        if (param == signature.ret and !signature.passing.takes(i)) return @intCast(i);
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
    /// A counting build's record of this function (`emit_count.Table.function`), or null.
    count_fn: ?u32 = null,
    /// The instruction being emitted: counter sites take its span and operation.
    current: ir.Ref = .none,
    /// A counter site detail that names a step of the operation (`list_set.old`), or null.
    count_detail: ?[]const u8 = null,
    /// Scalar loads and stores are list element data: tag them by scalar type
    /// (`element_tags`) instead of the generic `myl.data`.
    element_tags: bool = false,
    /// The loops' cached values (`loop_hoist.zig`): loaded in each preheader, used in the body.
    hoist: loop_hoist.Plan = .{},
    /// The frame block slot of each parameter view a `block_frame` copies (RB1, `emit_block_frame.zig`), by its value.
    block_frames: std.AutoHashMapUnmanaged(u32, []const u8) = .empty,

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
        try emit_release.emit(self.a(), &self.state.layouts.text, layout_name, stride, .{ .refs = parts.refs.items, .guards = parts.guards.items, .split = value_offset });
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
        // A record field a loop caches is the value loaded in its preheader (`loop_hoist.zig`).
        if (ref != .none and self.hoist.fields.len != 0) if (self.hoist.fields[ref.index()]) |cached| return cached;
        const inst = self.function.inst(ref);
        return switch (inst.op) {
            .iconst => if (inst.ty == .bool) (if (inst.data != 0) "true" else "false") else std.fmt.allocPrint(self.a(), "{d}", .{@as(i64, @bitCast(inst.data))}),
            .fconst => std.fmt.allocPrint(self.a(), "0x{X:0>16}", .{if (inst.ty == .f32) binary64Pattern(inst.data) else inst.data}),
            .param => std.fmt.allocPrint(self.a(), "%p{d}", .{inst.data}),
            .undef => self.undefValue(inst.ty),
            .str_const => self.state.literal(@intCast(inst.data), inst.ty == .bytes),
            .text_sentinel => if (inst.ty == .str) "@myl_core_text_no_cache" else "@myl_core_list_no_cache",
            .func_ref => self.functionPointer(@intCast(inst.data)),
            .borrow => self.value(inst.a),
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
        try emit_block_frame.plan(*FunctionEmitter, self);
        try self.defineLine(out, abi);
        try self.collectBoundLengths();
        // A freestanding function counts nothing: a counter is a runtime call (`freestanding_emitted.zig`).
        if (self.state.options.counters and !m.isFreestanding(f)) self.count_fn = try self.state.count.function(self.a(), f.name);
        // `uwtable`: a trap walks the stack through `.eh_frame`, which needs every frame's CFI.
        try out.print(self.a(), ") nounwind{s}{s}{s} {{\n", .{ unwindTable(self.state.options.target), freestanding_emitted.placement(self.state.options.target, self.placement()), try self.functionScope() });
        // A verify or counting build keeps every load of every check, so it caches nothing.
        self.hoist = if (self.state.options.verify or self.count_fn != null) .{} else try loop_hoist.plan(self.a(), m, f, try self.vectorHeaders());
        const bodies = try self.a().alloc(Out, f.blocks.items.len);
        // A counting build counts each executed basic block: one site per emitted block,
        // charged at the block's entry to the function and to that site.
        const block_sites = try self.a().alloc(?u32, f.blocks.items.len);
        @memset(block_sites, null);
        try self.exit_labels.resize(self.a(), f.blocks.items.len);
        for (f.blocks.items, 0..) |block, b| {
            bodies[b] = .empty;
            self.exit_labels.items[b] = try std.fmt.allocPrint(self.a(), "b{d}", .{b});
            if (b != 0 and block.preds.items.len == 0) continue;
            self.label = self.exit_labels.items[b];
            self.vectors.block = @intCast(b);
            self.selectBlock(@intCast(b));
            if (self.count_fn != null) block_sites[b] = try self.blockSite(@intCast(b));
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
                // The cached values of a loop preheader load before its terminator (`loop_hoist.zig`).
                if (inst.op.terminates()) try self.emitHoisted(&bodies[b], @intCast(b));
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
            // The block counts itself on entry, after its phis (which LLVM requires first).
            if (block_sites[b]) |index| try self.countBlock(out, index);
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
        if (sret) try out.print(self.a(), "ptr {s}sret({s}) align 8 %ret", .{ if (shared == emit_homes.none) "noalias " else "", try std.fmt.allocPrint(self.a(), memory_type_format, .{abi.size(m, f.signature)}) });
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
        mem.transferred = try transfers.slots(self.a(), f);
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
                .sret = returnsThroughSret(m, f.signature, abi) and !abi.compact(m, f.signature),
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
            .err_trace => return true,
            .call, .call_indirect => {
                const signature = self.signatureOf(inst);
                if (signature.linkage != .internal) return false;
                for (signature.params, 0..) |param, k| {
                    if (!signature.passing.takes(k)) continue;
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
        const header = if (self.vectorizedHeader(pred)) try self.vectorizedHeaderMarker(inst.span) else "";
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}{s}\n", .{ try self.value(inst.a), labels[0], labels[1], header });
        for (sides, labels, moves, leaving) |target, label, side, exits| {
            if (side.len == 0 and exits.len == 0) continue;
            try out.print(self.a(), "{s}:\n", .{label});
            for (exits) |stored| try emit_state.store(*FunctionEmitter, self, out, try self.value(stored.value), stored.slots);
            try self.moveAll(out, side);
            try out.print(self.a(), "  br label %b{d}\n", .{target});
            try self.memory.edges.put(self.a(), edgeKey(pred, target), label);
        }
    }

    /// Destroy the owned managed fields of a record, union or array in memory.
    fn dropMemory(self: *FunctionEmitter, out: *Out, value_type: ir.Type, ptr: []const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                if (!m.managed(field)) continue;
                try self.dropAt(out, field, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)));
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
                    try self.dropAt(out, case, try self.offsetPointer(out, ptr, 8));
                    try self.leaveIf(out, join);
                }
            },
            .array => |array| for (0..array.n) |i| {
                try self.dropAt(out, array.elem, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)));
            },
            .list, .box, .dict, .@"fn", .list_view, .borrowed => unreachable,
        }
    }

    /// Count the part of type `part_type` stored at `ptr` where it is: a part over four words
    /// field by field through `dropMemory` (never copied out first, NEW-CORE-CE-LISTS-4,
    /// while `emit_homes.steps.views` is on, the default), anything else loaded as a value.
    fn dropAt(self: *FunctionEmitter, out: *Out, part_type: ir.Type, ptr: []const u8) Error!void {
        if (emit_homes.steps.views and self.state.module.passedInMemory(part_type)) return self.dropMemory(out, part_type, ptr);
        const loaded = try self.fresh("%cm");
        try self.loadValue(out, part_type, ptr, loaded);
        try self.dropValue(out, part_type, loaded);
    }

    /// Count a value held in a register or, over four words, a pointer to its slot.
    fn dropValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, text: []const u8) Error!void {
        if (self.state.module.passedInMemory(value_type)) return self.dropMemory(out, value_type, text);
        return self.dropAggregate(out, value_type, text);
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
                .module = self.state.module,
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

    /// Load the element count of list `ref` into `name`: a block's header, or a list view's own count (C9 lists).
    fn listLength(self: *FunctionEmitter, out: *Out, name: []const u8, ref: ir.Ref) !void {
        if (self.state.module.kind(self.typeOf(ref)) == .list_view) return out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ name, try self.value(ref) });
        const at = try self.fresh("%list.header");
        try out.print(self.a(), header_load_line, .{ at, try self.value(ref), len_offset, name, at });
    }

    /// Snapshot the SSA block's byte/list length while the block still exists.
    fn captureBoundLength(self: *FunctionEmitter, out: *Out, ref: ir.Ref) !void {
        if (self.memory.bound_lengths.len == 0 or !self.memory.bound_lengths[ref.index()]) return;
        const len = try std.fmt.allocPrint(self.a(), "%bound.len.{d}", .{ref.index()});
        // A span (text or bytes view) carries its octet length in the pair; it has no block header to read (C9 bytes).
        // A list view carries its element count the same way (C9 lists).
        if (self.typeOf(ref).isSpan() or self.state.module.kind(self.typeOf(ref)) == .list_view) return out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ len, try self.value(ref) });
        const at = try self.fresh("%bound.header");
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
            const length = try self.fresh("%an");
            const outside = try self.fresh("%ax");
            const below = try self.fresh("%ab");
            const above = try self.fresh("%aa");
            try self.listLength(out, length, ref);
            try out.print(self.a(), "  {s} = icmp ult i64 {s}, {d}\n  {s} = icmp ugt i64 {s}, {d}\n  {s} = or i1 {s}, {s}\n", .{ below, length, len.lo, above, length, len.hi, outside, below, above });
            const operation = try std.fmt.allocPrint(self.a(), "list length [{d}, {d}]", .{ len.lo, len.hi });
            const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = 64, .operation = operation, .function = self.sourceFunction().name });
            return self.trapIf(out, outside, index, length, "0");
        }
        if (kind != .record) return;
        const table = known.aggregates.fields[ref.index()] orelse return;
        const fields = m.compound(m.storageType(inst.ty)).record;
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
        const length = try self.fresh("%child.actual");
        const outside = try self.fresh("%child.outside");
        try self.listLength(out, length, ref);
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
        if (self.freestandingCode()) {
            try self.fault(out, branch.site, branch.location);
            try out.print(self.a(), "{s}:\n", .{branch.next});
            self.label = branch.next;
            return;
        }
        try out.print(self.a(), "  call void @myl_core_trap(ptr @myl.site.{d}, i64 {s}, i64 {s}) #2{s}\n  unreachable\n{s}:\n", .{ branch.site, detail.left, detail.right, branch.location, branch.next });
        self.label = branch.next;
    }

    /// Count Unicode scalars for a cold diagnostic, declaring the existing helper on demand.
    pub fn textScalars(self: *FunctionEmitter, out: *Out, receiver: ir.Ref) Error![]const u8 {
        // A view receiver counts its span in place; a block receiver counts through its helper.
        if (self.function.inst(self.function.resolve(receiver)).ty == .str_view) {
            const pair = try self.value(receiver);
            const data = try self.fresh("%textdata");
            const length = try self.fresh("%textlen");
            const result = try self.fresh("%textscalars");
            try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n" ++
                "  {s} = call i64 @myl_core_span_utf8_count(ptr {s}, i64 {s})\n", .{ data, pair, length, pair, result, data, length });
            return result;
        }
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
            .param, .iconst, .fconst, .undef, .str_const, .text_sentinel, .func_ref, .copy, .borrow, .phi => {},
            .dict_new, .dict_len, .dict_find, .dict_entry_key, .dict_entry_value, .dict_set_value => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .dict_insert, .dict_remove, .dict_entries, .dict_entry_live, .dict_copy, .dict_clear => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .str_char, .str_width, .str_code, .str_append, .str_append_char, .str_slice, .str_view_of, .str_slice_view, .str_slice_bytes_view, .str_from_view, .text_frame => try emit_text.instruction(self, out, name, inst),
            .list_sort, .array_get, .array_set, .call_indirect => try emit_fn.instruction(self, out, name, inst),
            .list_view_of, .list_slice_view => try self.listView(out, name, inst),
            .buffer_new, .buffer_copy, .buffer_set, .buffer_push, .buffer_pop, .buffer_append => try emit_bytes.instruction(self, out, name, inst),
            .shift_left, .shift_right, .saturating_add, .float_unary => try emit_number.instruction(self, out, name, inst),
            .add, .sub, .mul => try self.arithmetic(out, name, inst),
            .div, .rem, .floor_div, .floor_rem => try self.division(out, name, inst),
            .neg => {
                const info = self.laneType(inst.ty).integer().?;
                const zero = if (self.isVector(inst.ty)) "zeroinitializer" else "0";
                if (self.checkOf(inst) == .exact) {
                    const pair = try self.fresh("%n");
                    const tyname = try self.ty(inst.ty);
                    const flag = try self.overflowFlag(inst.ty);
                    const sign = if (info.signed) "s" else "u";
                    const suffix = try self.intrinsicSuffix(inst.ty);
                    try out.print(self.a(), "  {s} = call {{ {s}, {s} }} @llvm.{s}sub.with.overflow.{s}({s} {s}, {s})\n", .{ pair, tyname, flag, sign, suffix, tyname, zero, try self.typedValue(inst.a) });
                    try out.print(self.a(), "  {s} = extractvalue {{ {s}, {s} }} {s}, 0\n", .{ name, tyname, flag, pair });
                    const failed = try self.fresh("%o");
                    try out.print(self.a(), "  {s} = extractvalue {{ {s}, {s} }} {s}, 1\n", .{ failed, tyname, flag, pair });
                    try self.trapIf(out, try self.anyLane(out, failed, inst.ty), try self.site(.overflow, inst, "neg"), try self.widened(out, inst.a), "0");
                } else {
                    try out.print(self.a(), "  {s} = sub {s} {s}, {s}\n", .{ name, try self.ty(inst.ty), zero, try self.value(inst.a) });
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
            .not => try self.negation(out, name, inst),
            .cmp => {
                const operand_type = self.function.inst(self.function.resolve(inst.a)).ty;
                // Two operands the facts prove non-negative compare the same either way;
                // unsigned predicates let LLVM relate the comparison to unsigned bounds checks.
                const unsigned_safe = self.nonNegative(inst.a) and self.nonNegative(inst.b);
                const signed = if (self.laneType(operand_type).integer()) |info| info.signed and !unsigned_safe else false;
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
                try out.print(self.a(), "  {s} = {s} {s} {s}, {s}\n", .{ name, op, try self.ty(inst.ty), try self.value(inst.a), try self.value(inst.b) });
            },
            .fneg => try out.print(self.a(), "  {s} = fneg {s} {s}\n", .{ name, try self.ty(inst.ty), try self.value(inst.a) }),
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
                try out.print(self.a(), "  {s} = fcmp {s} {s} {s}, {s}\n", .{ name, spelled, try self.ty(self.function.inst(self.function.resolve(inst.a)).ty), try self.value(inst.a), try self.value(inst.b) });
            },
            .int_to_float => {
                const source = self.function.inst(self.function.resolve(inst.a)).ty;
                const signed = (source.integer() orelse return error.UnsupportedInstruction).signed;
                const floating = try self.ty(inst.ty);
                if (source == .i64 and self.fitsI32(inst.a)) {
                    // Narrow first: AVX2 converts i32 lanes to doubles in one instruction, i64 lanes not at all.
                    const narrow = try self.fresh("%n32");
                    try out.print(self.a(), "  {s} = trunc i64 {s} to i32\n  {s} = sitofp i32 {s} to {s}\n", .{ narrow, try self.value(inst.a), name, narrow, floating });
                } else {
                    try out.print(self.a(), "  {s} = {s} {s} to {s}\n", .{ name, if (signed) "sitofp" else "uitofp", try self.typedValue(inst.a), floating });
                }
            },
            .float_convert => {
                const widen = self.laneType(inst.ty) == .f64;
                try out.print(self.a(), "  {s} = {s} {s} to {s}\n", .{ name, if (widen) "fpext" else "fptrunc", try self.typedValue(inst.a), try self.ty(inst.ty) });
            },
            .bitcast => try out.print(self.a(), "  {s} = bitcast {s} to {s}\n", .{ name, try self.typedValue(inst.a), try self.ty(inst.ty) }),
            .float_fma, .vector_select => try self.fusedOrSelect(out, name, inst),
            .byte_load => try self.byteLoad(out, name, inst),
            .float_to_int => try self.floatToInt(out, name, inst),
            .convert => try self.convert(out, name, inst),
            .list_new => try self.listNew(out, name, inst),
            .list_len, .str_len => try self.collectionLength(out, name, inst),
            .list_get => try self.listGet(out, name, inst),
            .list_push => try self.listPush(out, name, inst),
            .list_copy => {
                const element = self.state.module.compound(inst.ty).list;
                // A list view copies its elements from its own data and count (C9 lists): no block header is read.
                if (self.state.module.isView(self.typeOf(inst.a))) {
                    const source = try self.value(inst.a);
                    const data = try self.viewData(out, source);
                    const count = try self.viewLength(out, source);
                    try out.print(self.a(), "  {s} = call ptr @myl_core_list_copy_view(ptr {s}, i64 {s}, i64 {d})\n", .{ name, data, count, self.state.stride(element) });
                } else try out.print(self.a(), "  {s} = call ptr @myl_core_list_copy(ptr {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
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
            .union_take => if (!try self.viewOf(out, name, ref, 8)) try self.unionTake(out, name, inst),
            .record_make => if (!self.memory.fused[ref.index()]) try self.recordMake(out, name, inst),
            .array_from_bytes => try self.arrayFromBytes(out, name, inst),
            .record_get => try self.recordGet(out, name, ref, inst),
            .record_take => try self.recordTake(out, name, inst),
            .record_set => try self.recordSet(out, name, ref, inst),
            .list_set => try self.listSet(out, name, inst),
            .list_pop => try self.listPop(out, name, inst),
            .list_get_field => try self.listGetField(out, name, inst),
            .list_set_field => try self.listSetField(out, name, inst),
            .box_make => {
                const inner = self.state.module.compound(inst.ty).box;
                try out.print(self.a(), "  {s} = call ptr @myl_core_box_new(i64 {d})\n", .{ name, self.state.module.size(inner) });
                try self.attachBoxLayout(out, name, inner, inst.data);
                try self.storeOperand(out, inner, inst.a, try self.offsetPointer(out, name, data_offset));
            },
            .box_get => try self.loadValue(out, inst.ty, try self.offsetPointer(out, try self.value(inst.a), data_offset), name),
            .box_frame => try self.boxFrame(out, name, inst),
            .block_frame => try emit_block_frame.instruction(*FunctionEmitter, self, out, name, inst),
            .box_take => try self.boxTake(out, name, inst.ty, try self.value(inst.a)),
            .drop => {
                try self.dropValue(out, self.typeOf(inst.a), try self.value(inst.a));
            },
            .err_trace => try self.errTrace(out, inst),
            .call => try self.call(out, name, inst),
            .print => try self.print(out, inst),
            .jump => try self.jumpTo(out, inst),
            .branch => try self.branchTo(out, inst),
            .ret => try self.returnFrom(out, inst),
            .@"unreachable" => try self.trapTerminator(out, inst),
        }
        if (self.count_fn != null) try self.clearCountHook(out, inst);
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
        // Every frame block copy this call made dies with it (RB1).
        try emit_block_frame.release(*FunctionEmitter, self, out);
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
            .record_make => for (f.operands(inst.data), m.compound(m.storageType(inst.ty)).record, 0..) |operand, field, i| {
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
            if (!abi.compact(m, signature)) {
                // Nominal transport retains CE2's existing whole-result destination.
                try self.storeAtRet(out, signature.ret, raw, 0);
                for (signature.params, 0..) |param, i| {
                    if (!abi.inOut(i)) continue;
                    const at = try self.offsetPointer(out, "%ret", m.fieldOffset(signature.ret, abi.field(signature, i)));
                    try self.copyBytes(out, try std.fmt.allocPrint(self.a(), "%p{d}", .{i}), at, m.size(param), false);
                }
                return;
            }
            // Preserve logical tuple bytes before updating potentially overlapping finals.
            const snapshot = try self.stackSlot(m.size(signature.ret));
            try self.storeOperand(out, signature.ret, raw, snapshot);
            for (m.compound(signature.ret).record, 0..) |field_type, k| {
                if (abi.omitted(signature, k)) continue;
                const src = try self.offsetPointer(out, snapshot, m.fieldOffset(signature.ret, k));
                const dst = try self.offsetPointer(out, "%ret", abi.offset(m, signature, k));
                try self.copyBytes(out, dst, src, m.size(field_type), false);
            }
            for (signature.params, 0..) |param, i| {
                if (!abi.inOut(i)) continue;
                const at = try self.offsetPointer(out, snapshot, m.fieldOffset(signature.ret, abi.field(signature, i)));
                try self.copyBytes(out, try std.fmt.allocPrint(self.a(), "%p{d}", .{i}), at, m.size(param), false);
            }
            return;
        }
        const operands = f.operands(f.inst(composite).data);
        for (m.compound(signature.ret).record, operands, 0..) |field_type, operand, k| {
            const final = for (0..signature.params.len) |i| {
                if (abi.inOut(i) and abi.field(signature, i) == k) break true;
            } else false;
            if (!final) try self.storeAtRet(out, field_type, operand, abi.offset(m, signature, k));
        }
        for (0..signature.params.len) |i| {
            if (!abi.inOut(i)) continue;
            try moves.append(self.a(), try self.finalMove(out, i, operands[abi.field(signature, i)]));
        }
        try self.moveAll(out, moves.items);
    }

    fn trapTerminator(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        var left: []const u8 = "0";
        var right: []const u8 = "0";
        var assertion = false;
        const index = if (inst.data & flags.text_trap != 0) index: {
            const kind: TrapKind = @fromBackingInt(@intCast(@as(u8, @truncate(inst.data))));
            const index = try self.site(kind, inst, "text");
            if (inst.a != .none or inst.b != .none) {
                if (inst.a != .none) left = try self.widened(out, inst.a);
                if (inst.b != .none) right = try self.widened(out, inst.b);
            }
            break :index index;
        } else if (inst.data == capacity_assert) index: {
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            break :index try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "a stack list's length below its capacity", .function = self.sourceFunction().name });
        } else if (inst.data == flags.case_trap) index: {
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            break :index try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "a nested `match mut` binding's union still in the binding's case", .function = self.sourceFunction().name });
        } else if (inst.data == flags.typed_hole_trap)
            try self.site(.typed_hole, inst, "typed hole")
        else if (inst.data == flags.dict_missing_trap)
            try self.site(.missing_key, inst, "key")
        else if (inst.data == flags.iteration_trap)
            try self.site(.iteration_mutation, inst, "iteration")
        else if (inst.data & flags.assertion_trap != 0) index: {
            // A failed `assert` or contract clause: the message is in the module's string table.
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const kind: u16 = @truncate(inst.data >> 32);
            const message = self.state.module.strings.items[@as(u32, @truncate(inst.data))];
            assertion = true;
            break :index try self.state.site(.{ .kind = .assertion, .location = location, .width = kind, .operation = message, .function = self.sourceFunction().name });
        } else return out.appendSlice(self.a(), "  unreachable\n");
        const location = try self.trapLocation(index);
        if (self.freestandingCode()) return self.fault(out, index, location);
        if (assertion) return out.print(self.a(), "  call void @myl_core_assert_fail(ptr @myl.site.{d}) #2{s}\n  unreachable\n", .{ index, location });
        try out.print(self.a(), "  call void @myl_core_trap(ptr @myl.site.{d}, i64 {s}, i64 {s}) #2{s}\n  unreachable\n", .{ index, left, right, location });
    }

    /// Where this function's code goes on a bare target (`freestanding_emitted.placement`).
    fn placement(self: *FunctionEmitter) freestanding_emitted.Placement {
        const m = self.state.module;
        if (m.ram.count() == 0) return .default;
        if (m.isRam(self.function)) return .ram;
        return if (freestanding_emitted.registersAccess(m, self.index)) .ram_helper else .default;
    }

    /// Whether the code being emitted is a `@freestanding` function's, its own or inlined into this one: a failed check
    /// there is a fault that calls nothing (`fault`).
    fn freestandingCode(self: *FunctionEmitter) bool {
        return self.state.module.freestanding.count() != 0 and self.state.module.isFreestanding(self.sourceFunction());
    }

    /// The failed check of site `index` in freestanding code: its code and place in the first three argument registers
    /// and the target's trap instruction, with no call and no text (`freestanding_emitted.fault`).
    fn fault(self: *FunctionEmitter, out: *Out, index: u32, location: []const u8) Error!void {
        const site_record = &self.state.sites.items[index];
        site_record.fault = true;
        const assertion_kind: u32 = if (site_record.kind == .assertion) site_record.width else 0;
        const fault_code = freestanding_emitted.faultCode(@backingInt(site_record.kind), assertion_kind);
        try freestanding_emitted.fault(self.a(), out, self.state.options.target, .{ .code = fault_code, .path = index, .line = site_record.location.line, .location = location });
    }

    /// The element type of a vector, or the type itself for a scalar: the domain an integer operation checks.
    fn laneType(self: *FunctionEmitter, t: ir.Type) ir.Type {
        if (self.state.module.kind(t) != .array) return t;
        const lanes = self.state.module.compound(t).array;
        return if (lanes.vector) lanes.elem else t;
    }

    /// Whether a value type is a `Simd` vector rather than a scalar.
    fn isVector(self: *FunctionEmitter, t: ir.Type) bool {
        return self.laneType(t) != t;
    }

    /// The overflow flag of a checked operation on `t`: one bit for a scalar, one bit per lane for a vector.
    fn overflowFlag(self: *FunctionEmitter, t: ir.Type) Error![]const u8 {
        if (!self.isVector(t)) return "i1";
        return std.fmt.allocPrint(self.a(), "<{d} x i1>", .{self.state.module.compound(t).array.n});
    }

    /// The overloaded suffix of an LLVM intrinsic on `t`: `i64` for a scalar, `v4i64` for a vector.
    fn intrinsicSuffix(self: *FunctionEmitter, t: ir.Type) Error![]const u8 {
        if (!self.isVector(t)) return self.ty(t);
        return std.fmt.allocPrint(self.a(), "v{d}{s}", .{ self.state.module.compound(t).array.n, try self.ty(self.laneType(t)) });
    }

    /// The one flag a checked operation traps on: the scalar flag, or the OR of the lanes' flags.
    fn anyLane(self: *FunctionEmitter, out: *Out, lane_flags: []const u8, t: ir.Type) Error![]const u8 {
        if (!self.isVector(t)) return lane_flags;
        const n = self.state.module.compound(t).array.n;
        const any = try self.fresh("%any");
        try out.print(self.a(), "  {s} = call i1 @llvm.vector.reduce.or.v{d}i1(<{d} x i1> {s})\n", .{ any, n, n, lane_flags });
        return any;
    }

    fn arithmetic(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const info = self.laneType(inst.ty).integer() orelse return error.UnsupportedInstruction;
        const op = switch (inst.op) {
            .add => "add",
            .sub => "sub",
            else => "mul",
        };
        const tyname = try self.ty(inst.ty);
        switch (self.checkOf(inst)) {
            .exact => {
                // A vector's `with.overflow` yields one flag per lane; any lane's overflow traps.
                const pair = try self.fresh("%p");
                const flag = try self.overflowFlag(inst.ty);
                const sign = if (info.signed) "s" else "u";
                const suffix = try self.intrinsicSuffix(inst.ty);
                try out.print(self.a(), "  {s} = call {{ {s}, {s} }} @llvm.{s}{s}.with.overflow.{s}({s}, {s})\n", .{ pair, tyname, flag, sign, op, suffix, try self.typedValue(inst.a), try self.typedValue(inst.b) });
                try out.print(self.a(), "  {s} = extractvalue {{ {s}, {s} }} {s}, 0\n", .{ name, tyname, flag, pair });
                const failed = try self.fresh("%o");
                try out.print(self.a(), "  {s} = extractvalue {{ {s}, {s} }} {s}, 1\n", .{ failed, tyname, flag, pair });
                try self.trapIf(out, try self.anyLane(out, failed, inst.ty), try self.site(.overflow, inst, op), try self.widened(out, inst.a), try self.widened(out, inst.b));
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
        if (self.state.module.isView(self.typeOf(inst.a))) return out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ name, try self.value(inst.a) });
        const at = try self.fresh("%h");
        try out.print(self.a(), header_tagged_line, .{ at, try self.value(inst.a), len_offset, name, at });
    }

    fn listGet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        if (self.typeOf(inst.a).isSpan()) return emit_text.byteRead(@TypeOf(self), @TypeOf(out), self, out, name, inst);
        const list = try self.value(inst.a);
        const index = if (self.state.module.isView(self.typeOf(inst.a)))
            try self.viewIndex(out, inst, list, try self.value(inst.b))
        else
            try self.checkedIndex(out, inst, list, try self.value(inst.b));
        // A read nothing uses is only its bounds check: the element is never loaded (a verify
        // build still loads it, for the fact assertions that name it).
        if (self.memory.uses[self.current.index()] == 0 and inst.data == 0 and self.knownFacts() == null) return;
        // A view is `{ptr, i64}`: its first word is the element data, with no block header.
        const slot = if (self.state.module.isView(self.typeOf(inst.a)))
            try self.elementSlotAt(out, try self.viewData(out, list), index, inst.ty)
        else
            try self.elementSlot(out, list, index, inst.ty);
        // A lent element (`lentElements`) is its slot: no copy.
        if (self.lent(self.current)) return out.print(self.a(), identity_line, .{ name, slot });
        const saved = self.tagElements(true);
        defer _ = self.tagElements(saved);
        if (inst.ty == .bool or inst.ty.isCompound()) return self.loadValue(out, inst.ty, slot, name);
        const stored = storageType(inst.ty);
        try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}{s}, {s}\n", .{ name, stored, slot, elementSize(self.state.module, inst.ty), try self.loadRange(name, inst.ty), self.dataTag(stored) });
    }

    /// A view of list `inst.a`'s elements: the whole list (`list_view_of`) or a
    /// range (`list_slice_view`). The range is clamped to the source's length, so
    /// the view always names storage the source owns.
    fn listView(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const m = self.state.module;
        const source = try self.value(inst.a);
        const element = m.compound(inst.ty).list_view;
        const view_source = m.isView(self.typeOf(inst.a));
        const data = if (view_source) try self.viewData(out, source) else blk: {
            const block_data = try self.fresh("%lvdata");
            try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n", .{ block_data, source, data_offset });
            break :blk block_data;
        };
        const length = if (view_source) try self.viewLength(out, source) else blk: {
            const at = try self.fresh("%lvlenat");
            const len = try self.fresh("%lvlen");
            try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8\n", .{ at, source, len_offset, len, at });
            break :blk len;
        };
        if (inst.op == .list_view_of) return self.insertView(out, name, data, length);
        const first = try self.value(inst.b);
        const last = try self.value(self.function.operands(inst.data)[0]);
        const start = try self.clampView(out, first, length);
        const stop = try self.clampView(out, last, length);
        const width = try self.fresh("%lvwidth");
        const empty = try self.fresh("%lvempty");
        const clamped = try self.fresh("%lvclamped");
        try out.print(self.a(), "  {s} = sub i64 {s}, {s}\n  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n", .{ width, stop, start, empty, width, clamped, empty, width });
        const offset = try self.fresh("%lvoff");
        const at = try self.fresh("%lvat");
        try out.print(self.a(), "  {s} = mul i64 {s}, {d}\n  {s} = getelementptr inbounds i8, ptr {s}, i64 {s}\n", .{ offset, start, self.state.stride(element), at, data, offset });
        return self.insertView(out, name, at, clamped);
    }

    /// Clamp one range endpoint into `[0, length]`.
    fn clampView(self: *FunctionEmitter, out: *Out, endpoint: []const u8, length: []const u8) Error![]const u8 {
        const below = try self.fresh("%lvbelow");
        const low = try self.fresh("%lvlow");
        const above = try self.fresh("%lvabove");
        const clamped = try self.fresh("%lvclamp");
        try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n", .{ below, endpoint, low, below, endpoint });
        try out.print(self.a(), "  {s} = icmp sgt i64 {s}, {s}\n  {s} = select i1 {s}, i64 {s}, i64 {s}\n", .{ above, low, length, clamped, above, length, low });
        return clamped;
    }

    /// Insert the `{ptr, i64}` view value `name`.
    fn insertView(self: *FunctionEmitter, out: *Out, name: []const u8, data_ptr: []const u8, length: []const u8) Error!void {
        const partial = try self.fresh("%lvp");
        try out.print(self.a(), "  {s} = insertvalue {{ ptr, i64 }} poison, ptr {s}, 0\n  {s} = insertvalue {{ ptr, i64 }} {s}, i64 {s}, 1\n", .{ partial, data_ptr, name, partial, length });
    }

    /// The address of element `index` of the list view `view`, bounds-checked
    /// against the view's own length. A view is `{ptr, i64}`: the data pointer and
    /// the element count, so no block header is read.
    fn viewElementSlot(self: *FunctionEmitter, out: *Out, inst: ir.Inst, view: []const u8, index: []const u8, element: ir.Type) ![]const u8 {
        const checked = try self.viewIndex(out, inst, view, index);
        return self.elementSlotAt(out, try self.viewData(out, view), checked, element);
    }

    /// Trap unless the index is inside the view and return it.
    fn viewIndex(self: *FunctionEmitter, out: *Out, inst: ir.Inst, view: []const u8, index: []const u8) ![]const u8 {
        if (self.checkOf(inst) != .exact) return index;
        const length = try self.viewLength(out, view);
        const outside = try self.fresh("%voob");
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n", .{ outside, index, length });
        const detail = if (emit_bytes.sourceIndex(@TypeOf(self), self, inst.b)) |source_index| try self.value(source_index) else index;
        try self.trapIf(out, outside, try self.site(.list_bounds, inst, "index"), detail, length);
        return index;
    }

    /// The element pointer of `view`.
    fn viewData(self: *FunctionEmitter, out: *Out, view: []const u8) ![]const u8 {
        const data = try self.fresh("%vdata");
        try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n", .{ data, view });
        return data;
    }

    /// The element count of `view`.
    fn viewLength(self: *FunctionEmitter, out: *Out, view: []const u8) ![]const u8 {
        const length = try self.fresh("%vlen");
        try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ length, view });
        return length;
    }

    /// The address of element `index` from a data pointer (no header).
    fn elementSlotAt(self: *FunctionEmitter, out: *Out, data: []const u8, index: []const u8, element: ir.Type) ![]const u8 {
        const slot = try self.fresh("%elt");
        const inline_value = element.isCompound() and !self.state.module.isBlock(element);
        const stepped = if (inline_value) try std.fmt.allocPrint(self.a(), memory_type_format, .{self.state.stride(element)}) else storageType(element);
        try out.print(self.a(), "  {s} = getelementptr inbounds {s}, ptr {s}, i64 {s}\n", .{ slot, stepped, data, index });
        return slot;
    }

    /// Check the written index with one unsigned comparison, including negative indexes.
    fn checkedIndex(self: *FunctionEmitter, out: *Out, inst: ir.Inst, list: []const u8, index: []const u8) Error![]const u8 {
        try self.boundsCheck(out, inst, list, index);
        return index;
    }

    /// Trap unless `0 <= index < len(list)` (the index is unsigned here), for an exact check.
    /// The count is the loop's cached one when the proof holds (`loop_hoist.zig`), else the header's.
    pub fn boundsCheck(self: *FunctionEmitter, out: *Out, inst: ir.Inst, list: []const u8, index: []const u8) Error!void {
        if (self.checkOf(inst) != .exact) return;
        const len = if (self.cachedLength()) |cached| cached else blk: {
            const at = try self.fresh("%lh");
            const count = try self.fresh("%len");
            try out.print(self.a(), header_tagged_line, .{ at, list, len_offset, count, at });
            break :blk count;
        };
        const outside = try self.fresh("%oob");
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n", .{ outside, index, len });
        // The read a `pop` starts with fails exactly when the list is empty, which is the pop trap.
        if (inst.op == .list_get and inst.data == flags.pop_read) return self.trapIf(out, outside, try self.site(.list_empty, inst, "pop"), "0", len);
        if (inst.op == .list_get and inst.data == flags.pop_index_read)
            return self.trapIf(out, outside, try self.site(.list_pop_index, inst, "pop"), index, len);
        const source_index = emit_bytes.sourceIndex(@TypeOf(self), self, inst.b);
        if (source_index) |raw| return self.trapIf(out, outside, try self.site(.list_bounds, inst, "index"), try self.value(raw), len);
        try self.trapIf(out, outside, try self.site(.list_bounds, inst, "index"), index, len);
    }

    /// The element count the current instruction's loop caches for it, or null.
    fn cachedLength(self: *FunctionEmitter) ?[]const u8 {
        if (self.hoist.lengths.len == 0 or self.current == .none) return null;
        return self.hoist.lengths[self.current.index()];
    }

    /// The header-tagged loop plans of the vectorized loops: their scalar loops keep every load.
    fn vectorHeaders(self: *FunctionEmitter) ![]const u32 {
        const headers = try self.a().alloc(u32, self.vectors.plans.len);
        for (self.vectors.plans, headers) |plan, *header| header.* = @intCast(plan.loop.header.index());
        return headers;
    }

    /// Load the values `block` caches for its loops, before its terminator (`loop_hoist.zig`).
    fn emitHoisted(self: *FunctionEmitter, out: *Out, block: u32) !void {
        for (self.hoist.entries) |entry| {
            if (entry.preheader != block) continue;
            switch (entry.what) {
                .field => |field| try self.hoistedField(out, field, entry.name),
                .length => |list| {
                    const at = try self.fresh("%hoist.at");
                    try out.print(self.a(), header_tagged_line, .{ at, try self.value(list), len_offset, entry.name, at });
                },
                .field_length => |field| {
                    const pointer = try self.fresh("%hoist.ptr");
                    try self.hoistedField(out, field, pointer);
                    const at = try self.fresh("%hoist.at");
                    try out.print(self.a(), header_tagged_line, .{ at, pointer, len_offset, entry.name, at });
                },
            }
        }
    }

    /// Field `field.index` of the record value `field.record`, loaded (or extracted) into `name`.
    fn hoistedField(self: *FunctionEmitter, out: *Out, field: loop_hoist.Field, name: []const u8) !void {
        const m = self.state.module;
        const record_type = m.storageType(self.typeOf(field.record));
        const field_type = m.compound(record_type).record[field.index];
        if (!m.passedInMemory(record_type)) return out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(field.record), field.index });
        const at = try self.offsetPointer(out, try self.value(field.record), m.fieldOffset(record_type, field.index));
        try self.loadValue(out, field_type, at, name);
    }

    /// The address of element `index` of `list`: a typed `getelementptr` for scalars and
    /// pointers, a byte stride for records and unions stored inline.
    fn elementSlot(self: *FunctionEmitter, out: *Out, list: []const u8, index: []const u8, element: ir.Type) ![]const u8 {
        const data = try self.fresh("%data");
        const slot = try self.fresh("%elt");
        const inline_value = element.isCompound() and !self.state.module.isBlock(element);
        const stepped = if (inline_value) try std.fmt.allocPrint(self.a(), memory_type_format, .{self.state.stride(element)}) else storageType(element);
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

    /// `value_call.name = call T value_call.callee(value_call.arguments)` for a result of type `ret`: through memory for a C function whose
    /// structure result the target's C convention returns so (`callResultInMemory`), in registers otherwise.
    fn valueCall(self: *FunctionEmitter, out: *Out, value_call: ValueCall, ret: ir.Type, location: []const u8) Error!void {
        const llvm_type = try self.ty(ret);
        if (!value_call.program and c_abi.returnsInMemory(self.state.options.target.machine.c_abi, llvm_type)) {
            return self.callResultInMemory(out, .{ .name = value_call.name, .ty = llvm_type, .bytes = self.state.module.size(ret) }, value_call.callee, value_call.arguments, location);
        }
        const convention = if (value_call.program) "fastcc " else "";
        try out.print(self.a(), "  {s} = {s}call {s}{s} {s}({s}){s}\n", .{ value_call.name, value_call.tail, convention, llvm_type, value_call.callee, value_call.arguments, location });
    }

    /// `result.name = call result.ty callee(arguments)` of a C function whose structure result the target's C convention returns
    /// through memory: an entry-block slot of `result.bytes` passed first (`sret`), loaded after the call.
    pub fn callResultInMemory(self: *FunctionEmitter, out: *Out, result: StructResult, callee: []const u8, arguments: []const u8, location: []const u8) Error!void {
        const slot = try self.stackSlot(result.bytes);
        const separator = if (arguments.len == 0) "" else ", ";
        try out.print(self.a(), "  call void {s}(ptr sret({s}) align 8 {s}{s}{s}){s}\n", .{ callee, result.ty, slot, separator, arguments, location });
        try out.print(self.a(), "  {s} = load {s}, ptr {s}, align 8\n", .{ result.name, result.ty, slot });
    }

    /// `result.name = call result.ty callee(arguments)` of a C runtime function with a structure result: in registers, or
    /// through memory where the target's C convention returns it so (`callResultInMemory`).
    pub fn cStructCall(self: *FunctionEmitter, out: *Out, result: StructResult, callee: []const u8, arguments: []const u8) Error!void {
        if (c_abi.returnsInMemory(self.state.options.target.machine.c_abi, result.ty)) return self.callResultInMemory(out, result, callee, arguments, "");
        try out.print(self.a(), "  {s} = call {s} {s}({s})\n", .{ result.name, result.ty, callee, arguments });
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
    pub fn loadValue(self: *FunctionEmitter, out: *Out, raw_type: ir.Type, ptr: []const u8, result: []const u8) Error!void {
        const m = self.state.module;
        const value_type = m.storageType(raw_type);
        if (value_type == .void) return error.UnsupportedInstruction;
        // A float vector loads as one `<N x T>` from its lanes in memory; a mask is rebuilt lane by lane.
        if (m.kind(value_type) == .array and m.compound(value_type).array.vector and m.compound(value_type).array.elem != .bool) {
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ result, try self.ty(value_type), ptr, accessAlign(m, value_type, m.alignment(value_type)) });
            return;
        }
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
        if (value_type.isSpan() or m.kind(value_type) == .list_view) return self.loadSpan(out, ptr, result);
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            const llvm_type = try self.ty(value_type);
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}, {s}\n", .{ result, llvm_type, ptr, accessAlign(m, value_type, m.alignment(value_type)), self.dataTag(llvm_type) });
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
            .list, .box, .dict, .@"fn", .list_view, .borrowed => unreachable,
        }
    }

    // Transient views share a two-word memory image with word-aligned payloads.
    fn loadSpan(self: *FunctionEmitter, out: *Out, ptr: []const u8, result: []const u8) Error!void {
        try out.print(self.a(), "  {s} = load {{ ptr, i64 }}, ptr {s}, align 8\n", .{ result, ptr });
    }

    fn storeSpan(self: *FunctionEmitter, out: *Out, text: []const u8, ptr: []const u8) Error!void {
        try out.print(self.a(), "  store {{ ptr, i64 }} {s}, ptr {s}, align 8\n", .{ text, ptr });
    }

    /// Store register value `value` of type `ty` as its memory image at `ptr`, field by field.
    /// Store a typed value field by field into an operation sub-emitter slot.
    pub fn storeValue(self: *FunctionEmitter, out: *Out, raw_type: ir.Type, text: []const u8, ptr: []const u8) Error!void {
        const m = self.state.module;
        const value_type = m.storageType(raw_type);
        if (value_type == .void) return error.UnsupportedInstruction;
        if (m.passedInMemory(value_type)) return self.copyBytes(out, ptr, text, m.size(value_type), false);
        // A float vector's memory image is its lanes in order, so the whole value is one store. A mask
        // (`<N x i1>`) is bit-packed by LLVM, so its lanes are spilled one by one, as a Boolean array is.
        if (m.kind(value_type) == .array and m.compound(value_type).array.vector and m.compound(value_type).array.elem != .bool) {
            try out.print(self.a(), "  store {s} {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ try self.ty(value_type), text, ptr, accessAlign(m, value_type, m.alignment(value_type)) });
            return;
        }
        if (value_type == .bool) {
            const byte = try self.fresh("%sb");
            try out.print(self.a(), "  {s} = zext i1 {s} to i8\n  store i8 {s}, ptr {s}, align 1, {s}\n", .{ byte, text, byte, ptr, self.dataTag("i8") });
            return;
        }
        if (value_type.isSpan() or m.kind(value_type) == .list_view) return self.storeSpan(out, text, ptr);
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            const llvm_type = try self.ty(value_type);
            try out.print(self.a(), "  store {s} {s}, ptr {s}, align {d}, {s}\n", .{ llvm_type, text, ptr, accessAlign(m, value_type, m.alignment(value_type)), self.dataTag(llvm_type) });
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
                if (array.vector) {
                    try out.print(self.a(), "  {s} = extractelement {s} {s}, i64 {d}\n", .{ element, tyname, text, i });
                } else try out.print(self.a(), extract_value_line, .{ element, tyname, text, i });
                try self.storeValue(out, array.elem, element, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)));
            },
            .list, .box, .dict, .@"fn", .list_view, .borrowed => unreachable,
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
            .record_make => for (self.function.operands(inst.data), m.compound(m.storageType(inst.ty)).record, 0..) |operand, field, i| {
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

    /// An inline `u8` array over four words copied from the data of byte list `a` in one
    /// `memcpy`, into its home (or a stack slot of its own): the code does not grow with the array.
    fn arrayFromBytes(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const size = self.state.module.size(inst.ty);
        const into = try self.destination(name, size);
        try self.copyBytes(out, into.ptr, try self.offsetPointer(out, try self.value(inst.a), data_offset), size, false);
        if (into.fresh) try out.print(self.a(), identity_line, .{ name, into.ptr });
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
        // A cached field is loaded in the preheader; the read itself emits nothing (`value`).
        if (self.hoist.fields.len != 0 and self.hoist.fields[ref.index()] != null) return;
        const record_type = self.typeOf(inst.a);
        if (!m.passedInMemory(record_type)) return out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(inst.a), inst.data });
        if (self.writtenByCall(ref, inst)) return;
        const offset = m.fieldOffset(record_type, @intCast(inst.data));
        if (try self.viewOf(out, name, ref, offset)) return;
        const at = try self.offsetPointer(out, try self.value(inst.a), offset);
        try self.loadValue(out, inst.ty, at, name);
    }

    /// Transfer one stored field before destroying the consumed record's
    /// siblings. Memory-sized fields receive their own home, never a loan.
    fn recordTake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const m = self.state.module;
        const record_type = self.typeOf(inst.a);
        const fields = m.compound(record_type).record;
        const source = try self.value(inst.a);
        const memory = m.passedInMemory(record_type);
        if (memory) {
            try self.loadValue(out, inst.ty, try self.offsetPointer(out, source, m.fieldOffset(record_type, @intCast(inst.data))), name);
        } else try out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(inst.a), inst.data });
        for (fields, 0..) |field, index| {
            if (index == inst.data or !m.managed(field)) continue;
            if (memory) {
                try self.dropAt(out, field, try self.offsetPointer(out, source, m.fieldOffset(record_type, index)));
            } else {
                const sibling = try self.fresh("%taken_sibling");
                try out.print(self.a(), extract_value_line, .{ sibling, try self.ty(record_type), source, index });
                try self.dropValue(out, field, sibling);
            }
        }
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
        const field = m.compound(m.storageType(inst.ty)).record[@intCast(inst.data)];
        const offset = m.fieldOffset(inst.ty, @intCast(inst.data));
        // A write-back of a value built in the field itself stores nothing.
        if (!plan.holds(ref, offset, self.function.resolve(inst.b))) try self.storeOperand(out, field, inst.b, try self.offsetPointer(out, into.ptr, offset));
        if (into.fresh) try out.print(self.a(), identity_line, .{ name, into.ptr });
    }

    /// `a * b + c` with one rounding (`llvm.fma`, a vector by its lane intrinsic), or a lane select on vectors.
    fn fusedOrSelect(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const third = self.function.operands(inst.data)[0];
        if (inst.op == .vector_select) return out.print(self.a(), "  {s} = select {s}, {s}, {s}\n", .{ name, try self.typedValue(inst.a), try self.typedValue(inst.b), try self.typedValue(third) });
        // A vector names its intrinsic by lane count and element, as `llvm.fma.v4f64`.
        const suffix = if (self.state.module.kind(inst.ty) == .array) try self.vectorSuffix(inst.ty) else if (inst.ty == .f32) "f32" else "f64";
        try out.print(self.a(), "  {s} = call {s} @llvm.fma.{s}({s}, {s}, {s})\n", .{ name, try self.ty(inst.ty), suffix, try self.typedValue(inst.a), try self.typedValue(inst.b), try self.typedValue(third) });
    }
    /// One fixed-width read of a view's octets: the data pointer, the address at the checked offset, one unaligned
    /// load of the result type, and a byte swap when the read is big-endian. The bounds check is already in the IR.
    fn byteLoad(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const view = try self.typedValue(inst.a);
        const offset = try self.value(inst.b);
        const llvm_type = try self.ty(inst.ty);
        const big = inst.data != 0;
        try out.print(self.a(), "  {s}.data = extractvalue {s}, 0\n", .{ name, view });
        try out.print(self.a(), "  {s}.at = getelementptr inbounds i8, ptr {s}.data, i64 {s}\n", .{ name, name, offset });
        if (!big) return out.print(self.a(), "  {s} = load {s}, ptr {s}.at, align 1\n", .{ name, llvm_type, name });
        try out.print(self.a(), "  {s}.raw = load {s}, ptr {s}.at, align 1\n", .{ name, llvm_type, name });
        try out.print(self.a(), "  {s} = call {s} @llvm.bswap.{s}({s} {s}.raw)\n", .{ name, llvm_type, llvm_type, llvm_type, name });
    }
    /// A Boolean complement: one `xor` with `true` on a scalar, or with the all-true vector on a mask.
    fn negation(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        if (self.isVector(inst.ty)) return self.maskNot(out, name, inst);
        try out.print(self.a(), "  {s} = xor i1 {s}, true\n", .{ name, try self.value(inst.a) });
    }
    /// The complement of a mask, lane by lane: one `xor` with the all-true vector.
    fn maskNot(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const lanes = self.state.module.compound(inst.ty).array.n;
        var ones: std.ArrayList(u8) = .empty;
        for (0..lanes) |lane| try ones.appendSlice(self.a(), if (lane == 0) "i1 true" else ", i1 true");
        try out.print(self.a(), "  {s} = xor {s}, <{s}>\n", .{ name, try self.typedValue(inst.a), ones.items });
    }
    /// The intrinsic suffix of a vector type: its lane count and element, as `v4f64` or `v2f32`.
    pub fn vectorSuffix(self: *FunctionEmitter, lane_type: ir.Type) Error![]const u8 {
        const lanes = self.state.module.compound(lane_type).array;
        return std.fmt.allocPrint(self.a(), "v{d}{s}", .{ lanes.n, if (lanes.elem == .f32) "f32" else "f64" });
    }

    fn recordMake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        if (self.state.module.passedInMemory(inst.ty)) return self.makeInMemory(out, name, inst);
        const tyname = try self.ty(inst.ty);
        const fields = self.function.operands(inst.data);
        if (fields.len == 0) {
            try out.print(self.a(), "  {s} = select i1 true, {s} zeroinitializer, {s} zeroinitializer\n", .{ name, tyname, tyname });
            return;
        }
        // A vector's lanes are set one by one with `insertelement`; an aggregate's fields with `insertvalue`.
        const lanes = self.state.module.kind(inst.ty) == .array and self.state.module.compound(inst.ty).array.vector;
        var partial: []const u8 = "poison";
        for (fields, 0..) |field, i| {
            const next = if (i + 1 == fields.len) name else try self.fresh("%rm");
            if (lanes) {
                try out.print(self.a(), "  {s} = insertelement {s} {s}, {s}, i64 {d}\n", .{ next, tyname, partial, try self.typedValue(field), i });
            } else {
                try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s}, {d}\n", .{ next, tyname, partial, try self.typedValue(field), i });
            }
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
            return self.loadValue(out, m.compound(m.storageType(read.union_type)).@"union"[read.case], try self.offsetPointer(out, read.value, 8), read.result);
        }
        const tyname = try self.ty(read.union_type);
        switch (layout.form) {
            .niche => try out.print(self.a(), "  {s} = getelementptr i8, ptr {s}, i64 0\n", .{ read.result, read.value }),
            .scalar => try out.print(self.a(), "  {s} = extractvalue {s} {s}, 1\n", .{ read.result, tyname, read.value }),
            .words => {
                const payload_type = m.compound(m.storageType(read.union_type)).@"union"[read.case];
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
        const union_type = m.storageType(self.typeOf(inst.a));
        const stored = m.compound(union_type).@"union"[@intCast(inst.data)];
        const boxed = m.kind(stored) == .box;
        const payload = if (boxed) try self.fresh("%takenbox") else name;
        try self.unionPayload(out, .{ .result = payload, .union_type = union_type, .value = try self.value(inst.a), .case = @intCast(inst.data) });
        if (!boxed) return;
        try self.boxTake(out, name, inst.ty, payload);
    }

    /// Load into independent storage before returning only the empty box shell.
    /// A frame box (O4): this call's stack slot with a box header (kind box, static storage, so no drop frees it; the
    /// payload's layout, so a deep copy of it destroys what it copies) and the read-only parameter `a` after it.
    fn boxFrame(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const inner = self.state.module.compound(inst.ty).box;
        const size = self.state.module.size(inner);
        const slot = try self.stackSlot(@intCast(data_offset + size));
        const kind: u32 = 2 | (1 << 23);
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n  store i32 {d}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ name, slot, kind, name });
        const len = try self.fresh("%frame");
        const cap = try self.fresh("%frame");
        const reserved = try self.fresh("%frame");
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  store i64 {d}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ len, name, size, len });
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 16\n  store i64 {d}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ cap, name, size, cap });
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 24\n  store i64 0, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ reserved, name, reserved });
        try self.attachLayout(out, name, inner);
        try self.storeOperand(out, inner, inst.a, try self.offsetPointer(out, name, data_offset));
    }

    fn boxTake(self: *FunctionEmitter, out: *Out, name: []const u8, inner: ir.Type, box: []const u8) Error!void {
        try self.loadValue(out, inner, try self.offsetPointer(out, box, data_offset), name);
        try out.print(self.a(), "  call void @myl_core_box_drop_shell(ptr {s})\n", .{box});
    }

    /// Replace element `b` of list `a` in place with `extra[0]`; the element it
    /// replaces is released when the element type is managed.
    /// The room a counted fill reserves: its whole count when `exact` and count times the
    /// stride fits (`flags.fill_exact`), else the speculative prefix; a larger exact count takes the prefix too.
    fn fillCapacity(self: *FunctionEmitter, out: *Out, bound: ir.Ref, exact: bool, stride: u32) ![]const u8 {
        const raw = try self.value(bound);
        const positive = if (self.typeOf(bound) == .i64) blk: {
            const negative = try self.fresh("%fillnegative");
            const clamped = try self.fresh("%fillpositive");
            try out.print(self.a(), "  {s} = icmp slt i64 {s}, 0\n  {s} = select i1 {s}, i64 0, i64 {s}\n", .{ negative, raw, clamped, negative, raw });
            break :blk clamped;
        } else raw;
        const large = try self.fresh("%filllarge");
        const capacity = try self.fresh("%fillcapacity");
        const limit: u64 = if (exact) (@as(u64, 1) << 62) / @max(@as(u64, stride), 1) else flags.fill_capacity_limit;
        try out.print(self.a(), "  {s} = icmp ugt i64 {s}, {d}\n  {s} = select i1 {s}, i64 {d}, i64 {s}\n", .{ large, positive, limit, capacity, large, flags.fill_capacity_limit, positive });
        return capacity;
    }

    /// Whether the current overwrite follows a read that took its slot owner.
    pub fn transferredSlot(self: *const FunctionEmitter) bool {
        return self.memory.transferred[self.current.index()];
    }

    fn listSet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const element = m.compound(inst.ty).list;
        const index = try self.checkedIndex(out, inst, list, try self.value(inst.b));
        const slot = try self.elementSlot(out, list, index, element);
        if (elements.storeBack(m, self.function, inst, self.transferredSlot())) |back| return self.storeBackPointer(out, name, inst, back, slot);
        const managed = m.managed(element) and !self.transferredSlot();
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
        try self.dropHeld(out, held.items);
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
        if (elements.storeBack(m, self.function, inst, self.transferredSlot())) |back| return self.storeBackPointer(out, name, inst, back, at);
        const saved = self.tagElements(!m.pathCrossesUnion(element, path));
        defer _ = self.tagElements(saved);
        var held: std.ArrayList(Held) = .empty;
        self.count_detail = if (self.count_fn != null) "list_set_field.old" else null;
        // A field a transferred read took over (`xs[i].items.append(v)`, CE2-B) is not released.
        if (!self.transferredSlot()) try self.holdManaged(out, target.ty, at, &held, null);
        self.count_detail = null;
        try self.storeOperand(out, target.ty, self.function.operands(inst.data)[0], at);
        // The releases read their own blocks, not this element: generic tags again.
        _ = self.tagElements(false);
        try self.dropHeld(out, held.items);
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
    /// replace, for `dropHeld` after it: a value of at most four words into registers,
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
    fn dropHeld(self: *FunctionEmitter, out: *Out, held: []const Held) Error!void {
        for (held) |part| {
            const join = if (part.guard) |live| try self.enterIf(out, live) else null;
            try self.dropValue(out, part.ty, part.text);
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
        const element = m.listElement(self.typeOf(inst.a)) orelse return error.UnsupportedInstruction;
        // A list view reads its element through its own count and data, with no block header (C9 lists).
        const viewed = m.isView(self.typeOf(inst.a));
        const index = if (viewed) try self.viewIndex(out, inst, list, try self.value(inst.b)) else try self.checkedIndex(out, inst, list, try self.value(inst.b));
        const slot = if (viewed) try self.elementSlotAt(out, try self.viewData(out, list), index, element) else try self.elementSlot(out, list, index, element);
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

    /// Destroy each owned block in a scalar or small aggregate value.
    fn dropAggregate(self: *FunctionEmitter, out: *Out, value_type: ir.Type, text: []const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        if (m.isBlock(value_type)) return self.dropBlock(out, text);
        const tyname = try self.ty(value_type);
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                if (!m.managed(field)) continue;
                const field_value = try self.fresh("%cf");
                try out.print(self.a(), extract_value_line, .{ field_value, tyname, text, i });
                try self.dropAggregate(out, field, field_value);
            },
            .@"union" => |cases| {
                const layout = m.unionLayout(value_type);
                if (layout.form == .niche) {
                    const present = try self.fresh("%cn");
                    try out.print(self.a(), "  {s} = icmp ne ptr {s}, null\n", .{ present, text });
                    const join = try self.enterIf(out, present);
                    try self.dropBlock(out, text);
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
                    try self.dropAggregate(out, case, payload);
                    try self.leaveIf(out, join);
                }
            },
            .array => |array| for (0..array.n) |i| {
                const element = try self.fresh("%ca");
                try out.print(self.a(), extract_value_line, .{ element, tyname, text, i });
                try self.dropAggregate(out, array.elem, element);
            },
            .list, .box, .dict, .@"fn", .list_view, .borrowed => unreachable,
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
        // A freestanding function records no error trace: the trace is the runtime's (`freestanding.zig`).
        if (self.freestandingCode()) return;
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

    /// ` !dbg !N` naming this function's `DISubprogram` (`System.lines` only: trap frames and debuggers read it).
    fn functionScope(self: *FunctionEmitter) ![]const u8 {
        if (!self.state.options.target.system.lines) return "";
        const location = self.state.options.locator.locate(self.state.options.locator.context, self.function.span);
        self.scope.definition = try self.state.debug.function(self.a(), self.index, self.function, location);
        return std.fmt.allocPrint(self.a(), function_scope, .{self.scope.definition});
    }

    /// An unconditional edge; a `@vectorize` loop's back edge carries the loop hint.
    fn jumpTo(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        try emit_state.jump(*FunctionEmitter, self, out, self.vectors.block, @intCast(inst.data));
        try self.vectorPrologue(out, @intCast(inst.data));
        try self.fillMemoryPhis(out, self.vectors.block, @intCast(inst.data));
        const hint = if (self.loopBackEdge(self.vectors.block, @intCast(inst.data))) try self.vectorizeHint() else "";
        try out.print(self.a(), "  br label %b{d}{s}\n", .{ inst.data, hint });
    }

    /// Whether `block` is the header of a loop written with `@vectorize`.
    fn vectorizedHeader(self: *FunctionEmitter, block: usize) bool {
        for (self.function.loops.items) |loop| if (loop.vectorize and loop.header.index() == block) return true;
        return false;
    }

    /// The header branch of a `@vectorize` loop: its `!dbg` (the remark names that line) and a comment
    /// with the loop's location, which the driver matches against the remarks of a release compile.
    fn vectorizedHeaderMarker(self: *FunctionEmitter, span: u32) Error![]const u8 {
        const at = self.state.options.locator.locate(self.state.options.locator.context, span);
        const marker = try std.fmt.allocPrint(self.a(), "\n  ; vectorize {s}:{d}:{d}", .{ at.path, at.line, at.column });
        return std.fmt.allocPrint(self.a(), "{s}{s}", .{ try self.callLocation(span), marker });
    }

    /// Whether the jump from `from` to `to` is the back edge of a `@vectorize` loop.
    fn loopBackEdge(self: *FunctionEmitter, from: usize, to: usize) bool {
        for (self.function.loops.items) |loop| {
            if (loop.vectorize and loop.latch.index() == from and loop.header.index() == to) return true;
        }
        return false;
    }

    /// `, !llvm.loop !N` for a back edge: the loop's node asks LLVM's loop vectorizer to vectorize it.
    fn vectorizeHint(self: *FunctionEmitter) Error![]const u8 {
        const node = try self.state.debug.vectorizeLoop(self.a());
        return std.fmt.allocPrint(self.a(), ", !llvm.loop !{d}", .{node});
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
    /// header (the stack class and room for `capacity` elements), set up where
    /// the `list_new` runs; nothing counts, frees or grows it.
    fn stackList(self: *FunctionEmitter, out: *Out, name: []const u8, capacity: u64, element: ir.Type) !void {
        const bytes = data_offset + capacity * self.state.stride(element);
        const frame = try self.fresh("%stacklist");
        try self.state.allocas.print(self.a(), "  {s} = alloca [{d} x i8], align 32\n", .{ frame, bytes });
        try out.print(self.a(), identity_line, .{ name, frame });
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
    /// memory a pointer to zeroed memory). Direct destruction safely skips nulls.
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

    fn listNew(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const element = self.state.module.compound(inst.ty).list;
        if (inst.data != 0 and !flags.isFillCapacity(inst.data)) return self.stackList(out, name, inst.data - 1, element);
        if (inst.data == 0 and inst.a != .none) {
            const bound = self.function.inst(self.function.resolve(inst.a));
            if (bound.op == .iconst and bound.data == 0) return self.emptyList(out, name, element);
        }
        const capacity = if (flags.isFillCapacity(inst.data)) try self.fillCapacity(out, inst.a, inst.data & flags.fill_exact != 0, self.state.stride(element)) else try self.value(inst.a);
        try out.print(self.a(), "  {s} = call ptr @myl_core_list_new(i64 {s}, i64 {d})\n", .{ name, capacity, self.state.stride(element) });
        try self.attachLayout(out, name, element);
    }

    /// Immutable empty lists carry their layout before publication. A first push
    /// grows into independent writable storage without touching this header.
    /// The constant is named by the element's place among the element types this module declares an empty list for, in order of
    /// first use, as its layouts and strings are; the element's type ordinal is the build's own numbering of its types, and a unit
    /// served from an emission receipt would carry the numbering of the build that rendered it (`stage_verify.zig`).
    fn emptyList(self: *FunctionEmitter, out: *Out, name: []const u8, element: ir.Type) !void {
        const lists = &self.state.local.empty_lists;
        const ordinal = std.mem.indexOfScalar(ir.Type, lists.items, element) orelse lists.items.len;
        const empty_symbol = try std.fmt.allocPrint(self.a(), "@myl.empty.list.{d}", .{ordinal});
        if (ordinal == lists.items.len) {
            try lists.append(self.a(), element);
            const layout = if (self.state.module.managed(element)) try self.state.layoutSymbol(element) else "null";
            try self.state.layouts.text.print(self.a(), "{s} = private constant {{ i32, i32, i64, i64, ptr }} {{ i32 8388608, i32 0, i64 0, i64 0, ptr {s} }}, align 32\n", .{ empty_symbol, layout });
        }
        try out.print(self.a(), same_pointer, .{ name, empty_symbol });
    }

    /// The layout of a fresh box of `element` (E1b): a lent box (`flags.lent_box`) holds borrowed contents and gets none, so its
    /// drop frees the shell and releases no child. Every other box gets the layout of its contents.
    fn attachBoxLayout(self: *FunctionEmitter, out: *Out, block: []const u8, element: ir.Type, data: u64) !void {
        if (data & flags.lent_box != 0) return;
        try self.attachLayout(out, block, element);
    }

    /// Describe the owned child blocks in each list or box element for destruction.
    fn attachLayout(self: *FunctionEmitter, out: *Out, block: []const u8, element: ir.Type) !void {
        if (!self.state.module.managed(element)) return;
        const at = try self.fresh("%lay");
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 24\n  store ptr {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ at, block, try self.state.layoutSymbol(element), at });
    }

    /// Branch on `condition` into a fresh block; returns the join label `leaveIf` ends it with.
    fn enterIf(self: *FunctionEmitter, out: *Out, condition: []const u8) ![]const u8 {
        const then = try self.fresh("drop.then");
        const join = try self.fresh(self.label);
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ condition, then, join, then });
        self.label = then;
        return join;
    }

    fn leaveIf(self: *FunctionEmitter, out: *Out, join: []const u8) !void {
        try out.print(self.a(), "  br label %{s}\n{s}:\n", .{ join, join });
        self.label = join;
    }

    /// Destroy one block; the runtime skips null and immutable static storage.
    fn dropBlock(self: *FunctionEmitter, out: *Out, block: []const u8) !void {
        const drop_symbol = if (self.state.options.counters) "drop_owned" else "drop_inline";
        try out.print(self.a(), "  call void @myl_core_{s}(ptr {s})\n", .{ drop_symbol, block });
    }

    /// In a counting build, a new counter site of `kind` at the instruction being
    /// emitted: `c0` counts its executions and, unless `bytes` is empty, `c1` adds
    /// `bytes` each time. Returns the site's symbol, or null outside a counting build.
    fn countSite(self: *FunctionEmitter, out: *Out, kind: emit_count.Kind, bytes: []const u8) Error!?[]const u8 {
        const record = try self.newCountSite(kind, null) orelse return null;
        try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_count, .amount = "1", .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") });
        if (bytes.len != 0) try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_bytes, .amount = bytes, .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") });
        return record;
    }

    fn newCountSite(self: *FunctionEmitter, kind: emit_count.Kind, detail: ?[]const u8) Error!?[]const u8 {
        const record = self.count_fn orelse return null;
        const inst: ?ir.Inst = if (self.current == .none) null else self.function.inst(self.current);
        // Releases at a function's end carry no span of their own: they belong to the function.
        const span = if (inst != null and inst.?.span != 0) inst.?.span else self.function.span;
        const index = try self.countSiteAt(record, span, kind, detail orelse self.count_detail orelse if (inst) |known| @tagName(known.op) else "function");
        const name = try std.fmt.allocPrint(self.a(), "@myl.cs.{d}", .{index});
        return name;
    }

    /// Register one site of `kind` with `detail` at `span`, charged to function record `record`.
    fn countSiteAt(self: *FunctionEmitter, record: u32, span: u32, kind: emit_count.Kind, detail: []const u8) Error!u32 {
        const location = self.state.options.locator.locate(self.state.options.locator.context, span);
        return self.state.count.add(self.a(), .{
            .function = record,
            .origin = self.sourceFunction().name,
            .path = if (location.path.len != 0) location.path else self.state.options.source_path,
            .line = location.line,
            .column = location.column,
            .kind = kind,
            .detail = detail,
        });
    }

    /// The counter site of the instruction being emitted, with `detail` as its operation.
    fn countSiteIndex(self: *FunctionEmitter, kind: emit_count.Kind, detail: []const u8) Error!u32 {
        const inst: ?ir.Inst = if (self.current == .none) null else self.function.inst(self.current);
        const span = if (inst != null and inst.?.span != 0) inst.?.span else self.function.span;
        return self.countSiteAt(self.count_fn.?, span, kind, detail);
    }

    /// The counter site of emitted block `b`: its first instruction's span, or the
    /// function's span for an empty block.
    fn blockSite(self: *FunctionEmitter, b: u32) Error!?u32 {
        const record = self.count_fn orelse return null;
        const block = &self.function.blocks.items[b];
        var span = self.function.span;
        if (block.insts.items.len != 0) {
            const first = self.function.inst(block.insts.items[0]).span;
            if (first != 0) span = first;
        }
        const index = try self.countSiteAt(record, span, .blocks, "block");
        return index;
    }

    /// Count one entry of the block whose site is `site`: the site's `c0` and the
    /// running function's `blocks` slot, one increment each.
    fn countBlock(self: *FunctionEmitter, out: *Out, index: u32) Error!void {
        const record = try std.fmt.allocPrint(self.a(), "@myl.cs.{d}", .{index});
        try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_count, .amount = "1", .loaded = try self.fresh("%blk"), .sum = try self.fresh("%blk") });
        try emit_count.increment(self.a(), out, .{ .record = "%myl.cnt.active", .offset = emit_count.function_blocks, .amount = "1", .loaded = try self.fresh("%blkfn"), .sum = try self.fresh("%blkfn") });
    }

    /// The C symbol a direct call names, or null when the instruction is not one.
    fn callSymbol(self: *FunctionEmitter, inst: ir.Inst) ?[]const u8 {
        if (inst.op != .call) return null;
        return c_abi.symbol(self.state.module.functions.items[inst.a.index()].name);
    }

    /// The site a runtime operation's own work credits (`emit_count.Hook`): the elements a
    /// native insert/remove/pop_at rotation shifts, or the comparisons of a stable sort,
    /// plain or keyed. The emitted code names it before the call and clears it after. A
    /// sort also names its `elements_sorted` site here, with the length it starts from.
    fn countHook(self: *FunctionEmitter, out: *Out, inst: ir.Inst) Error!bool {
        if (inst.op == .list_sort) {
            const index = try self.countSiteIndex(.sort_compares, emit_count.sort_detail);
            try out.print(self.a(), "  store ptr @myl.cs.{d}, ptr {s}, align 8\n", .{ index, emit_count.Hook.sort_compares.global() });
            try self.countElements(out, inst.a, emit_count.sort_detail);
            return true;
        }
        const callee = self.callSymbol(inst) orelse return false;
        const hook = emit_count.runtimeHook(callee);
        const kind = hook.siteKind() orelse return false;
        const detail = emit_count.hookDetail(hook, callee);
        const index = try self.countSiteIndex(kind, detail);
        try out.print(self.a(), "  store ptr @myl.cs.{d}, ptr {s}, align 8\n", .{ index, hook.global() });
        // A keyed sort is a runtime call whose first argument is the source list it
        // consumes; the elements it sorts are the ones that list holds now.
        if (hook == .sort_compares) {
            const arguments = self.function.operands(inst.data);
            if (arguments.len != 0) try self.countElements(out, arguments[0], detail);
        }
        return true;
    }

    /// Count the elements the sort of `list` processes at a new site of `detail` and in
    /// the running function's `elements_sorted` slot: the list's length when the sort
    /// starts, whichever path the runtime then takes (comparison, radix or keyed).
    fn countElements(self: *FunctionEmitter, out: *Out, list: ir.Ref, detail: []const u8) Error!void {
        const index = try self.countSiteIndex(.elements_sorted, detail);
        const record = try std.fmt.allocPrint(self.a(), "@myl.cs.{d}", .{index});
        const at = try self.fresh("%els");
        const length = try self.fresh("%els");
        try out.print(self.a(), "  {s}.at = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}.at, align 8\n", .{ at, try self.value(list), length, at });
        try emit_count.increment(self.a(), out, .{ .record = record, .offset = emit_count.site_count, .amount = length, .loaded = try self.fresh("%cnt"), .sum = try self.fresh("%cnt") });
        try emit_count.increment(self.a(), out, .{ .record = "%myl.cnt.active", .offset = emit_count.function_elements_sorted, .amount = length, .loaded = try self.fresh("%elsfn"), .sum = try self.fresh("%elsfn") });
    }

    /// After a site-carrying runtime call, its site is no longer credited.
    fn clearCountHook(self: *FunctionEmitter, out: *Out, inst: ir.Inst) Error!void {
        if (inst.op == .list_sort) return out.print(self.a(), "  store ptr null, ptr {s}, align 8\n", .{emit_count.Hook.sort_compares.global()});
        const callee = self.callSymbol(inst) orelse return;
        const hook = emit_count.runtimeHook(callee);
        if (hook == .none) return;
        try out.print(self.a(), "  store ptr null, ptr {s}, align 8\n", .{hook.global()});
    }

    /// The counter sites an instruction gets before its own code in a counting build:
    /// the site a runtime copy credits (`myl_count_copy_site`), a push's element bytes,
    /// a whole small aggregate read from or written into a list, and the site a
    /// rotation or a stable sort credits.
    fn countBefore(self: *FunctionEmitter, out: *Out, inst: ir.Inst) Error!void {
        const m = self.state.module;
        if (try self.countHook(out, inst)) return;
        const copied: ?emit_count.Kind = switch (inst.op) {
            .list_copy => .list_copy,
            .dict_copy => .dict_copy,
            .buffer_copy => .buffer_copy,
            .str_from_view => .text_copy,
            // The span copy of a list view's scalar elements is a list copy (C9 lists).
            else => null,
        };
        if (copied) |kind| {
            const record = (try self.newCountSite(kind, null)).?;
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
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, {s}\n", .{ try self.typedValue(inst.b), slot, elementSize(self.state.module, element), self.dataTag(storageType(element)) });
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
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, {s}\n", .{ try self.typedValue(inst.b), slot, elementSize(self.state.module, element), self.dataTag(storageType(element)) });
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
        if (inst.op == .call and c_abi.foreign(&self.state.module.functions.items[inst.a.index()])) {
            try self.foreignCall(out, name, inst);
            return true;
        }
        if (try equality.runtimeCall(@TypeOf(self), @TypeOf(out), self, out, name, inst)) return true;
        if (try @import("emit_registers.zig").runtimeCall(@TypeOf(self), self, out, name, inst)) return true;
        if (try @import("aggregate_provider.zig").call(self.state.module, self.function, inst)) return true;
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
        if (try @import("borrowed_provider.zig").call(self.state.module, self.function, inst)) |args| {
            var construction = inst;
            if (self.state.module.kind(inst.ty) == .@"union") {
                construction.op = .union_make;
                construction.a = args[0];
                construction.data = 1;
                try self.unionMake(out, name, construction);
            } else {
                construction.op = .record_make;
                construction.a = .none;
                try self.recordMake(out, name, construction);
            }
            return;
        }
        if (try self.borrowedSelection(out, name, inst)) return;
        const m = self.state.module;
        const signature = if (inst.op == .call_indirect) m.compound(self.typeOf(inst.a)).@"fn" else m.functions.items[inst.a.index()].signature;
        const external = signature.linkage != .internal;
        const program = !external or (inst.op == .call and emit_values.generated(&m.functions.items[inst.a.index()]));
        if (inst.op == .call) {
            if (try self.freestandingHostCheck(out, inst)) return;
            try self.state.dependency(@intCast(inst.a.index()));
            try emit_cap.beforeCall(@TypeOf(self), self, out, inst);
        }
        if (try self.specialRuntimeCall(out, name, inst)) return;
        const ret = signature.ret;
        const abi: InOutAbi = if (external) .{} else inOutAbi(m, signature);
        const sret = !external and returnsThroughSret(m, signature, abi);
        var arguments: Out = .empty;
        var first = true;
        const result = if (sret) try self.destination(name, m.size(ret)) else null;
        const logical_result = if (result) |into| into.ptr else "";
        const result_slot = try self.transportSlot(signature, abi, logical_result);
        const places = try self.inOutPlaces(out, name, inst);
        if (sret) {
            try arguments.print(self.a(), "ptr sret({s}) align 8 {s}", .{ try std.fmt.allocPrint(self.a(), memory_type_format, .{abi.size(m, signature)}), result_slot });
            first = false;
        }
        const callee = calleeOf(m, inst);
        first = try self.siteArgument(inst, signature, &arguments, first);
        const owners = inst.op == .call and zero_rc.ownerSpan(c_abi.symbol(m.functions.items[inst.a.index()].name));
        const address = try self.addressTarget(out, inst, signature);
        for (self.function.operands(inst.data), signature.params, 0..) |argument, param, i| {
            if (signature.linkage.externC() and !c_abi.passes(param)) continue;
            if (address != null and address.?.position == i) continue;
            const separator = if (first) "" else ", ";
            first = false;
            if (external and signature.passing.viewAt(i)) {
                const text = if (owners) try self.ownerSpanArgument(out, argument) else try self.spanArgument(out, argument);
                try arguments.print(self.a(), "{s}{s}", .{ separator, text });
                continue;
            }
            if (!external and m.passedInMemory(param)) {
                const in_out = abi.inOut(i);
                try arguments.print(self.a(), "{s}ptr {s}", .{ separator, if (in_out) places[i] else try self.value(argument) });
                continue;
            }
            try arguments.print(self.a(), "{s}{s}", .{ separator, try self.scalarArgument(out, argument, param, callee) });
        }
        const target = if (inst.op == .call_indirect)
            try self.value(inst.a)
        else if (address) |found|
            found.callee
        else
            try self.state.originalSymbol(@intCast(inst.a.index()));
        // A trap's DWARF caller chain must survive a call in return position.
        const tail = if (program and self.state.options.target.system.traps == .dwarf_lines) "notail " else "";
        if (ret == .void or sret or abi.whole) {
            try out.print(self.a(), "  {s}call {s}void {s}({s}){s}\n", .{ tail, if (program) "fastcc " else "", target, arguments.items, try self.callLocation(inst.span) });
            if (result != null and result.?.fresh) try out.print(self.a(), identity_line, .{ name, logical_result });
            // The one in-out parameter's final value is the result: it is where it was passed.
            if (abi.whole and !self.homedName(name)) try out.print(self.a(), identity_line, .{ name, places[@ctz(abi.params)] });
        } else {
            const value_call: ValueCall = .{ .name = name, .tail = tail, .program = program, .callee = target, .arguments = arguments.items };
            try self.valueCall(out, value_call, ret, try self.callLocation(inst.span));
        }
        if (sret) {
            try self.unpackTransport(out, signature, abi, result_slot, logical_result);
            try self.completeResult(out, name, signature, .{ .result = logical_result, .places = places });
        }
    }

    /// In freestanding code, the `Host` check before a foreign call (`myl_core_host_check`, `build.zig` `callTarget`): the
    /// token compared inline with its constant (`freestanding_emitted.host_token`), a mismatch the fault `R_CAPABILITY`.
    /// Nothing is called and no place recorded (`emit_cap.beforeCall`). Any other call, and every call outside
    /// freestanding code, is lowered as before.
    fn freestandingHostCheck(self: *FunctionEmitter, out: *Out, inst: ir.Inst) Error!bool {
        if (!self.freestandingCode()) return false;
        const callee = &self.state.module.functions.items[inst.a.index()];
        if (callee.signature.linkage != .runtime_c or !std.mem.eql(u8, callee.name, "myl_core_host_check")) return false;
        const token = self.function.operands(inst.data)[0];
        const wrong = try self.fresh("%host.wrong");
        try out.print(self.a(), "  {s} = icmp ne {s} {s}, {d}\n", .{ wrong, try self.ty(self.typeOf(token)), try self.value(token), freestanding_emitted.host_token });
        try self.trapIf(out, wrong, try self.site(.capability, inst, "host"), "0", "0");
        return true;
    }

    /// The callee of a call to an `@address` extern and the argument position it came from.
    const AddressTarget = struct { callee: []const u8, position: usize };

    /// The callee of a call to an `@address` extern (`ir.Linkage.extern_address`), null for any other call: its first
    /// passed argument (a handle or an address), which traps `R_FOREIGN_TARGET` when it is 0, before any jump, and is
    /// then used as given as the pointer the call goes through. On `thumbv6m-none` the caller passes a Thumb address
    /// with its low bit set, as the boot ROM's table holds them: `blx` reads that bit.
    fn addressTarget(self: *FunctionEmitter, out: *Out, inst: ir.Inst, signature: ir.Signature) Error!?AddressTarget {
        if (inst.op != .call or signature.linkage != .extern_address) return null;
        const operands = self.function.operands(inst.data);
        const position = for (signature.params, 0..) |param, i| {
            if (c_abi.passes(param)) break i;
        } else return error.UnsupportedInstruction;
        const width = try self.ty(signature.params[position]);
        const operand = try self.value(operands[position]);
        const null_target = try self.fresh("%address.null");
        try out.print(self.a(), "  {s} = icmp eq {s} {s}, 0\n", .{ null_target, width, operand });
        try self.trapIf(out, null_target, try self.site(.foreign_target, inst, "foreign target"), "0", "0");
        const callee = try self.fresh("%address");
        try out.print(self.a(), "  {s} = inttoptr {s} {s} to ptr\n", .{ callee, width, operand });
        return .{ .callee = callee, .position = position };
    }

    /// A source extern call with a copied `bytes` result or `mut` out-parameters (D-FFI-3, D-FFI-5, `foreignDeclaration`).
    /// Each `mut` argument is stored in a stack temporary whose address C receives and whose value is loaded after the
    /// call into the IR result record; a `bytes` result's pointer and stored length go to the runtime copy at once.
    fn foreignCall(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const m = self.state.module;
        const signature = m.functions.items[inst.a.index()].signature;
        const result = c_abi.foreignResult(m, signature);
        var arguments: Out = .empty;
        var slots: std.ArrayList([]const u8) = .empty;
        var slot_types: std.ArrayList(ir.Type) = .empty;
        var first = true;
        const address = try self.addressTarget(out, inst, signature);
        for (self.function.operands(inst.data), signature.params, 0..) |argument, param, i| {
            if (!c_abi.passes(param)) continue;
            if (address != null and address.?.position == i) continue;
            const separator = if (first) "" else ", ";
            first = false;
            if (signature.passing.ownedAt(i)) {
                const slot = try self.stackSlot(8);
                try out.print(self.a(), "  store {s}, ptr {s}, align 8\n", .{ try self.typedValue(argument), slot });
                try slots.append(self.a(), slot);
                try slot_types.append(self.a(), param);
                try arguments.print(self.a(), "{s}ptr {s}", .{ separator, slot });
            } else if (signature.passing.viewAt(i)) {
                try arguments.print(self.a(), "{s}{s}", .{ separator, try self.spanArgument(out, argument) });
            } else {
                try arguments.print(self.a(), "{s}{s}", .{ separator, try self.scalarArgument(out, argument, param, .foreign) });
            }
        }
        const length = if (result == .bytes) try self.stackSlot(8) else "";
        if (result == .bytes) try arguments.print(self.a(), "{s}ptr {s}", .{ if (first) "" else ", ", length });
        const target = if (address) |found| found.callee else try self.state.originalSymbol(@intCast(inst.a.index()));
        const location = try self.callLocation(inst.span);
        if (result == .bytes) {
            const raw = try self.fresh("%foreign");
            const count = try self.fresh("%foreign.length");
            try out.print(self.a(), "  {s} = call ptr {s}({s}){s}\n  {s} = load i64, ptr {s}, align 8\n", .{ raw, target, arguments.items, location, count, length });
            const site_index = try self.site(.foreign_result, inst, "foreign result");
            try out.print(self.a(), "  {s} = call ptr @{s}(ptr @myl.site.{d}, ptr {s}, i64 {s}){s}\n", .{ name, c_abi.bytes_copy, site_index, raw, count, location });
            return;
        }
        const returned = if (result == .void) "" else try self.fresh("%foreign");
        if (result == .void) {
            try out.print(self.a(), "  call void {s}({s}){s}\n", .{ target, arguments.items, location });
        } else {
            try out.print(self.a(), "  {s} = call {s} {s}({s}){s}\n", .{ returned, try self.ty(result), target, arguments.items, location });
        }
        // One out-parameter and no C result: the IR result is that parameter's final value.
        if (m.kind(signature.ret) != .record) {
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align 8\n", .{ name, try self.ty(slot_types.items[0]), slots.items[0] });
            return;
        }
        const record = try self.ty(signature.ret);
        var partial: []const u8 = "poison";
        var field: usize = 0;
        if (result != .void) {
            const next = if (slots.items.len == 0) name else try self.fresh("%foreign.record");
            try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s} {s}, 0\n", .{ next, record, partial, try self.ty(result), returned });
            partial = next;
            field = 1;
        }
        for (slots.items, slot_types.items, 0..) |slot, param, k| {
            const loaded = try self.fresh("%foreign.out");
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align 8\n", .{ loaded, try self.ty(param), slot });
            const next = if (k + 1 == slots.items.len) name else try self.fresh("%foreign.record");
            try out.print(self.a(), "  {s} = insertvalue {s} {s}, {s} {s}, {d}\n", .{ next, record, partial, try self.ty(param), loaded, field + k });
            partial = next;
        }
    }

    /// Pass a site-taking helper this call's located trap site, ahead of its IR
    /// parameters, so the trap prints the source line and function (B3).
    fn siteArgument(self: *FunctionEmitter, inst: ir.Inst, signature: ir.Signature, arguments: *Out, first: bool) !bool {
        if (inst.op != .call or signature.linkage == .internal) return first;
        const m = self.state.module;
        if (!siteTaking(c_abi.symbol(m.functions.items[inst.a.index()].name))) return first;
        const site_index = try self.site(.text_boundary, inst, "slice");
        try arguments.print(self.a(), "{s}ptr @myl.site.{d}", .{ if (first) "" else ", ", site_index });
        return false;
    }

    /// Compact transport is separate from the logical IR home, which whole readers still need.
    fn transportSlot(self: *FunctionEmitter, signature: ir.Signature, abi: InOutAbi, logical: []const u8) ![]const u8 {
        if (!abi.compact(self.state.module, signature)) return logical;
        return self.stackSlot(abi.size(self.state.module, signature));
    }

    /// Restore transported fields at their logical offsets; in-out fields stay in argument homes.
    fn unpackTransport(self: *FunctionEmitter, out: *Out, signature: ir.Signature, abi: InOutAbi, transport: []const u8, logical: []const u8) !void {
        const m = self.state.module;
        if (!abi.compact(m, signature)) return;
        for (m.compound(signature.ret).record, 0..) |field_type, k| {
            if (abi.omitted(signature, k)) continue;
            const src = try self.offsetPointer(out, transport, abi.offset(m, signature, k));
            const dst = try self.offsetPointer(out, logical, m.fieldOffset(signature.ret, k));
            if (m.passedInMemory(field_type)) {
                try self.copyBytes(out, dst, src, m.size(field_type), false);
            } else {
                const transported = try self.fresh("%transport");
                try self.loadValue(out, field_type, src, transported);
                try self.storeValue(out, field_type, transported, dst);
            }
        }
    }

    /// A register argument: widened or sign-marked for any C callee, and its NaN made canonical for a source extern.
    fn scalarArgument(self: *FunctionEmitter, out: *Out, argument: ir.Ref, param: ir.Type, callee: Callee) ![]const u8 {
        const extension = if (callee != .selka) c_abi.argumentExtension(param) else "";
        if (extension.len != 0) return std.fmt.allocPrint(self.a(), "{s} {s} {s}", .{ try self.ty(self.typeOf(argument)), extension, try self.value(argument) });
        if (callee == .foreign and c_abi.canonicalizesNan(param)) return std.fmt.allocPrint(self.a(), "double {s}", .{try self.canonicalNan(out, argument)});
        return self.typedValue(argument);
    }

    /// A borrowed `(data, byte_length)` span argument of an extern-C `str` parameter.
    /// A `str` argument of an owner-or-NULL helper (C9 3a): the owning block, which is NULL for a borrowed view,
    /// then its octets and its length. A view passes the static sentinel block `myl_core_text_no_cache`; an owned
    /// argument passes its own block (see `runtime/core_rt.c`).
    pub fn ownerSpanArgument(self: *FunctionEmitter, out: *Out, argument: ir.Ref) Error![]const u8 {
        // A borrowed text or bytes span passes the sentinel: it carries no cached facts (C9 bytes).
        if (self.typeOf(argument).isSpan()) return std.fmt.allocPrint(self.a(), "ptr @myl_core_text_no_cache, {s}", .{try self.spanArgument(out, argument)});
        return std.fmt.allocPrint(self.a(), "ptr {s}, {s}", .{ try self.value(argument), try self.spanArgument(out, argument) });
    }

    /// A borrowed `(data, length)` span of a `str` or `str_view` argument, declared into `out` when a block's
    /// octets and length are loaded from its header.
    pub fn spanArgument(self: *FunctionEmitter, out: *Out, argument: ir.Ref) Error![]const u8 {
        const parts = try self.spanParts(out, argument);
        return std.fmt.allocPrint(self.a(), "ptr {s}, i64 {s}", .{ parts.data, parts.len });
    }

    /// The names of a span's address and octet count, declared into `out`.
    pub const SpanParts = struct { data: []const u8, len: []const u8 };

    /// The `(data, length)` of a text, bytes or list-view operand: a span's own pair, or the octets and length a block's
    /// header holds. Emits the extraction or the header loads and answers their names.
    pub fn spanParts(self: *FunctionEmitter, out: *Out, argument: ir.Ref) Error!SpanParts {
        const data = try self.fresh("%span");
        const len = try self.fresh("%span");
        const text = try self.value(argument);
        // A list view is the same `{ptr, i64}` pair as a text span: its elements' address and their count (C9 lists).
        if (self.typeOf(argument).isSpan() or self.state.module.kind(self.typeOf(argument)) == .list_view) {
            try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, text, len, text });
        } else {
            const at = try self.fresh("%span");
            try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ data, text, at, text, len, at });
        }
        return .{ .data = data, .len = len };
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

/// The declarations every module's prelude carries: types, the printing
/// primitives, and the text and dictionary helpers the emitter calls directly.
/// A lowered call to one of these reuses the prelude's declaration, so
/// `predeclared` answers from this text and never repeats it.
const prelude_declarations =
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
    \\@myl_core_text_no_cache = external constant i8
    \\@myl_core_list_no_cache = external constant i8
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
    \\declare i16 @llvm.bswap.i16(i16) nounwind speculatable willreturn memory(none)
    \\declare i32 @llvm.bswap.i32(i32) nounwind speculatable willreturn memory(none)
    \\declare i64 @llvm.bswap.i64(i64) nounwind speculatable willreturn memory(none)
    \\declare zeroext i1 @myl_core_dict_live(ptr, i64) nounwind willreturn memory(argmem: read)
    \\declare ptr @myl_core_ir_str_char(ptr, i64) nounwind
    \\declare i64 @myl_core_ir_str_width(ptr, i64) nounwind
    \\declare i32 @myl_core_ir_str_code(ptr, i64) nounwind
    \\declare i32 @myl_core_span_str_code(ptr, i64, i64) nounwind
    \\declare i64 @myl_core_span_str_width(ptr, i64, i64) nounwind
    \\declare i64 @myl_core_span_utf8_count(ptr, i64) nounwind
    \\declare ptr @myl_core_ir_str_append(ptr, ptr) nounwind
    \\declare ptr @myl_core_ir_str_append_char(ptr, ptr, i64) nounwind
    \\declare ptr @myl_core_span_str_append_char(ptr, ptr, i64, i64) nounwind
    \\declare ptr @myl_core_ir_str_slice(ptr, i64, i64) nounwind
    \\declare ptr @myl_core_ir_str_from_view(ptr, i64) nounwind
    \\declare { i64, i64 } @myl_core_ir_str_slice_span(ptr, i64, i64) nounwind
    \\declare { i64, i64 } @myl_core_ir_str_slice_bytes_span(ptr, ptr, i64, i64) nounwind
    \\declare ptr @myl_core_ir_str_from_span(ptr, i64, i1 zeroext) nounwind
    \\declare ptr @myl_core_s2_sort_in_place(ptr, i64, i1 zeroext) nounwind
    \\declare ptr @myl_core_list_copy(ptr, i64) nounwind
    \\declare ptr @myl_core_list_copy_view(ptr, i64, i64) nounwind
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
    \\declare void @myl_core_main_error_i64(i64) nounwind cold
    \\declare void @myl_core_main_error_u64(i64) nounwind cold
    \\declare void @myl_core_main_error_bool(i1 zeroext) nounwind cold
    \\declare void @myl_core_main_error_str(ptr) nounwind cold
    \\
;

/// Whether the module prelude already declares `symbol`, whose declaration a
/// lowered call must therefore not repeat: LLVM rejects a redefinition.
fn predeclared(name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '(') == null) return preludeHas(name);
    // A name with `(` is not a set member by construction: the substring search answers for it.
    var needle: [192]u8 = undefined;
    const text = std.fmt.bufPrint(&needle, "@{s}(", .{name}) catch return false;
    return std.mem.indexOf(u8, prelude_declarations, text) != null;
}

/// `predeclared` for tests: whether the prelude declares `name`.
pub fn predeclaredForTest(name: []const u8) bool {
    return predeclared(name);
}

/// The names the prelude declares, each once: the text between each `@` and the `(` that follows it, in prelude
/// order. For a name without `(`, `@name(` occurs in the prelude exactly when `name` is one of them (the first `(`
/// after an `@` is the one a match must end at), so a set lookup answers as the substring search did.
const prelude_symbols = preludeSymbols();

/// `prelude_symbols`, built at compile time from `prelude_declarations`.
fn preludeSymbols() []const []const u8 {
    @setEvalBranchQuota(1_000_000);
    var names: []const []const u8 = &.{};
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, prelude_declarations, at, '@')) |start| {
        at = start + 1;
        const open = std.mem.indexOfScalarPos(u8, prelude_declarations, at, '(') orelse break;
        const name = prelude_declarations[at..open];
        var known = false;
        for (names) |existing| {
            if (std.mem.eql(u8, existing, name)) known = true;
        }
        if (!known) names = names ++ &[_][]const u8{name};
    }
    return names;
}

/// Whether `name` is one of `prelude_symbols`.
fn preludeHas(name: []const u8) bool {
    for (prelude_symbols) |known| {
        if (std.mem.eql(u8, known, name)) return true;
    }
    return false;
}

/// The binary64 pattern of an `f32` constant: LLVM spells every float constant in its double
/// encoding, and widening a binary32 value to binary64 is exact.
fn binary64Pattern(bits32: u64) u64 {
    const value: f32 = @bitCast(@as(u32, @truncate(bits32)));
    return @bitCast(@as(f64, value));
}

/// Bytes one list element occupies.
/// The alignment a memory access of a value of `ty` may assume: `default`, except for a `Simd` vector.
/// A vector sits wherever its container put it (a list buffer is 8-aligned), so its accesses assume
/// 8 bytes and LLVM moves the vector unaligned rather than with an aligned move that faults.
fn accessAlign(m: *const ir.Module, ty: ir.Type, default: u32) u32 {
    if (m.kind(ty) == .array and m.compound(ty).array.vector) return 8;
    return default;
}

/// The value a call of a C function with a structure result names: its SSA name, LLVM type and size in bytes.
pub const StructResult = struct { name: []const u8, ty: []const u8, bytes: u32 };

/// A call whose result is a value: its SSA name, `notail ` or nothing, whether it calls a selka function, the callee and
/// the argument text.
const ValueCall = struct { name: []const u8, tail: []const u8, program: bool, callee: []const u8, arguments: []const u8 };

/// The alignment a list element's load or store assumes: its width, and a pointer's (`storageType` "ptr") is the target's.
pub fn elementSize(m: *const ir.Module, ty: ir.Type) u32 {
    return switch (ty) {
        .bool, .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32, .f32 => 4,
        .str, .bytes, .byte_buffer, .capability, .resource, .task_group, .task_handle => m.lowering.pointer_bytes,
        else => if (ty.isCompound()) m.lowering.pointer_bytes else 8,
    };
}

/// The in-memory type of one list element.
pub fn storageType(ty: ir.Type) []const u8 {
    return switch (ty) {
        .bool, .i8, .u8 => "i8",
        .i16, .u16 => "i16",
        .i32, .u32 => "i32",
        .f64 => "double",
        .f32 => "float",
        // A task group or handle is a pointer, as its value (`ty`) and its layout (`ir.Module.size`) are.
        .str, .bytes, .byte_buffer, .capability, .resource, .task_group, .task_handle => "ptr",
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
        // The producer keeps its pre-rename name, like the runtime's symbols (decision GH-D16): the runtime's trap walker compares it (core_rt.c).
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

    /// A `@vectorize` loop's `llvm.loop` node: `distinct !{self, {"llvm.loop.vectorize.enable", true}}`.
    fn vectorizeLoop(self: *Debug, allocator: std.mem.Allocator) !u32 {
        const hint = try self.node(allocator, "!{{!\"llvm.loop.vectorize.enable\", i1 true}}", .{});
        return self.node(allocator, "distinct !{{!{d}, !{d}}}", .{ self.next, hint });
    }

    /// The nodes and the module flags that make LLVM emit them (DWARF 4: the runtime's reader).
    /// Loop nodes need no compile unit, so they are written in every trap mode.
    fn finish(self: *Debug, allocator: std.mem.Allocator, out: *Out) !void {
        if (self.unit == 0) return out.appendSlice(allocator, self.text.items);
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
const runtime_owned_drop =
    \\define internal void @myl_core_drop_inline(ptr %block) alwaysinline nounwind {
    \\entry:
    \\  %null = icmp eq ptr %block, null
    \\  br i1 %null, label %done, label %inspect
    \\inspect:
    \\  %kind = load i32, ptr %block, align 4, !tbaa !5
    \\  %static_mask = and i32 %kind, 8388608
    \\  %static = icmp ne i32 %static_mask, 0
    \\  br i1 %static, label %done, label %classify
    \\classify:
    \\  %class32 = lshr i32 %kind, 24
    \\  %small = icmp ne i32 %class32, 0
    \\  %base_kind = and i32 %kind, 255
    \\  %string = icmp eq i32 %base_kind, 1
    \\  %bytes = icmp eq i32 %base_kind, 3
    \\  %buffer = icmp eq i32 %base_kind, 5
    \\  %octets = or i1 %string, %bytes
    \\  %leaf = or i1 %octets, %buffer
    \\  %list = icmp eq i32 %base_kind, 0
    \\  %box = icmp eq i32 %base_kind, 2
    \\  %container = or i1 %list, %box
    \\  %layout_at = getelementptr inbounds i8, ptr %block, i64 24
    \\  %layout = load i64, ptr %layout_at, align 8, !tbaa !5
    \\  %plain = icmp eq i64 %layout, 0
    \\  %scalar_container = and i1 %container, %plain
    \\  %childless = or i1 %leaf, %scalar_container
    \\  %fast = and i1 %small, %childless
    \\  br i1 %fast, label %push, label %slow, !prof !10
    \\push:
    \\  call void asm sideeffect "", "~{memory}"()
    \\  %class = zext i32 %class32 to i64
    \\  %slot = getelementptr inbounds [33 x ptr], ptr @myl_core_free_lists, i64 0, i64 %class
    \\  %head = load ptr, ptr %slot, align 8
    \\  store ptr %head, ptr %block, align 8
    \\  store ptr %block, ptr %slot, align 8
    \\  br label %done
    \\slow:
    \\  call void @myl_core_drop_owned(ptr %block)
    \\  br label %done
    \\done:
    \\  ret void
    \\}
    \\
;

/// ` uwtable` when the target unwinds (`System.unwind_tables`), else nothing.
fn unwindTable(target: @import("target.zig").Target) []const u8 {
    return if (target.system.unwind_tables) " uwtable" else "";
}

/// A prelude's text for `target`: unchanged for the host; `memchr` takes the target's `size_t`, and with one thread
/// (`System.threads`) the runtime's globals are plain, not thread-local.
fn forTarget(allocator: std.mem.Allocator, target: @import("target.zig").Target, text: []const u8) ![]const u8 {
    var result = text;
    if (target.machine.size_bits != 64) {
        const memchr = try std.fmt.allocPrint(allocator, "declare ptr @memchr(ptr, i32, {s})", .{target.sizeType()});
        result = try std.mem.replaceOwned(u8, allocator, result, "declare ptr @memchr(ptr, i32, i64)", memchr);
    }
    if (!target.system.threads) result = try std.mem.replaceOwned(u8, allocator, result, " thread_local(localexec)", "");
    // A C function's structure result comes back through memory the caller passes where the C convention says so.
    if (!c_abi.structResultInMemory(target.machine.c_abi)) return result;
    var lines: Out = .empty;
    var rest = std.mem.splitScalar(u8, result, '\n');
    var first = true;
    while (rest.next()) |line| : (first = false) {
        if (!first) try lines.append(allocator, '\n');
        try sretDeclaration(allocator, &lines, line);
    }
    return lines.items;
}

/// `text`, a bare unit's LLVM, with the free lists of the two-core flavour of the bare runtime, which keeps one copy for
/// each core (MCU-CORE1, `runtime/bare/core_bare_cores.c`; the driver rewrites the units of a program that starts the
/// second core, `driver.bareCores`, and no other): the runtime's `myl_core_free_lists` is an emulated thread-local
/// variable, so the declaration becomes its control record and each access first asks `__emutls_get_address` for the
/// calling core's copy (`%NAME.lists` before the line that defines `%NAME`). The call is written here, not left to the
/// backend's emulated TLS, because the link-time code generation of a `--release` image lowers a `thread_local` to native
/// TLS, which a bare image has no segment for. The address is the same for the life of a core, so the call reads no memory.
pub fn perCoreFreeLists(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const declaration = "@myl_core_free_lists = external global [33 x ptr]";
    const use = "ptr @myl_core_free_lists";
    if (std.mem.indexOf(u8, text, "@myl_core_free_lists") == null) return text;
    var out: Out = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| : (first = false) {
        if (!first) try out.append(allocator, '\n');
        if (std.mem.eql(u8, line, declaration)) {
            try out.appendSlice(allocator, "@__emutls_v.myl_core_free_lists = external global { i32, i32, ptr, ptr }\n" ++
                "declare ptr @__emutls_get_address(ptr) nounwind willreturn memory(none)");
            continue;
        }
        const at = std.mem.indexOf(u8, line, use);
        const name_start = std.mem.indexOfScalar(u8, line, '%');
        const name_end = std.mem.indexOf(u8, line, " = ");
        if (at == null or name_start == null or name_end == null or name_start.? > name_end.?) {
            try out.appendSlice(allocator, line);
            continue;
        }
        const name = line[name_start.?..name_end.?];
        try out.print(allocator, "{s}{s}.lists = call ptr @__emutls_get_address(ptr @__emutls_v.myl_core_free_lists)\n", .{ line[0..name_start.?], name });
        try out.print(allocator, "{s}ptr {s}.lists{s}", .{ line[0..at.?], name, line[at.? + use.len ..] });
    }
    return out.items;
}

/// `line` as `declare` of a C function whose structure result `T` is returned through memory: `declare T @f(A)` becomes
/// `declare void @f(ptr sret(T) align 8, A)`; any other line is kept.
fn sretDeclaration(allocator: std.mem.Allocator, out: *Out, line: []const u8) !void {
    const head = "declare {";
    const close = std.mem.indexOf(u8, line, "} @") orelse return out.appendSlice(allocator, line);
    const open = std.mem.indexOfScalarPos(u8, line, close, '(') orelse return out.appendSlice(allocator, line);
    if (!std.mem.startsWith(u8, line, head) or std.mem.startsWith(u8, line[close + 2 ..], "@llvm.")) return out.appendSlice(allocator, line);
    const result = line["declare ".len .. close + 1];
    const empty = line.len > open + 1 and line[open + 1] == ')';
    try out.print(allocator, "declare void {s}(ptr sret({s}) align 8{s}{s}", .{ line[close + 2 .. open], result, if (empty) "" else ", ", line[open + 1 ..] });
}

const runtime_fast_paths =
    \\@myl_core_free_lists = external thread_local(localexec) global [33 x ptr]
    \\declare ptr @myl_core_list_new_slow(i64, i64) nounwind
    \\declare ptr @myl_core_list_grow(ptr, i64) nounwind
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
    \\  %class32 = trunc i64 %class to i32
    \\  %kind = shl i32 %class32, 24
    \\  %kind_at = getelementptr inbounds i8, ptr %head, i64 0
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

/// Trace calls cost nothing to inline around (ERROR-TRACE-5). Trapping calls must
/// not merge across source scopes: a merged PC loses an inline caller frame.
const call_attributes = "attributes #1 = { \"call-inline-cost\"=\"0\" }\nattributes #2 = { nomerge }\n";

/// The branch-weight metadata every trap branch names (`!0`: the trap is cold).
pub const metadata = "!0 = !{!\"branch_weights\", i32 1, i32 1048575}\n";
