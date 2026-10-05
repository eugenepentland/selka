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
//! their data at offset 32; traps call `myl_core_trap(site, a, b)` with an index
//! into the `@myl_core_sites` table this module defines.
const std = @import("std");
const ir = @import("ir.zig");
const facts = @import("facts.zig");
const vector = @import("vector.zig");
const c_abi = @import("c_abi.zig");
const flags = @import("flags.zig");
const emit_dict = @import("emit_dict.zig");
const emit_text = @import("emit_text.zig");
const emit_fn = @import("emit_fn.zig");

/// A source line and column for a span start.
pub const Location = struct { line: u32, column: u32 };

/// Resolves span starts to lines and columns without tying the emitter to the front end.
pub const Locator = struct {
    context: *const anyopaque,
    locate: *const fn (*const anyopaque, u32) Location,
};

/// What the emitted module needs from its caller.
pub const Options = struct {
    locator: Locator,
    /// The path traps report (the entry file's).
    source_path: []const u8,
    /// Parameter names of `main`, which select stdout or stderr for a `Stream`.
    /// What the C entry needs to know about `main`.
    main: Main,
    /// Per function, the facts a release build computed (empty in debug builds):
    /// element ranges become `!range` metadata on list loads.
    facts: []const ?facts.Facts = &.{},
    /// Verify mode: every proven check is emitted anyway, every fact interval and
    /// unreachable block is asserted, and a failure traps `R_CORE_FACT`. No `nsw`,
    /// `!range` or other fact-derived promise reaches LLVM, so it cannot fold the asserts away.
    verify: bool = false,
    /// Per function, the loops the vector lowering takes (empty in debug and verify builds).
    vectors: []const []const vector.Plan = &.{},
    /// The target description (`target.zig`): vector width and available intrinsics.
    target: @import("target.zig").Target = @import("target.zig").current,
};

/// `main` as the C entry calls it.
pub const Main = struct {
    /// Parameter names, which select stdout or stderr for a `Stream`.
    parameters: []const []const u8 = &.{},
    /// When `main` returns a `Result`, the tags of its `Ok` and `Err` cases (the
    /// checker's order): the entry reports an `Err` (RESULT-MAIN-1/2).
    result: ?MainResult = null,
};

/// The case tags of `main`'s `Result` return type.
pub const MainResult = struct { ok_tag: u32, error_tag: u32 };

/// Trap kinds, in the order the runtime's code table lists them. `list_empty` is a
/// pop of an empty list (`R_LIST_BOUNDS`, operation `pop`); `trace` marks an
/// error-trace site, which never traps; `assertion` is a failed `assert` or contract clause (its
/// `width` is the `typed.AssertionKind`, its `operation` the message).
pub const TrapKind = enum(u8) { overflow, division_by_zero, list_bounds, float_conversion, cast, fact, list_empty, trace, assertion, missing_key = 9, iteration_mutation = 10 };

const Site = struct { kind: TrapKind, location: Location, width: u16, operation: []const u8, function: []const u8 };

/// `  %x = getelementptr inbounds i8, ptr p, i64 0`: a new name for the same block.
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

const trap_zero = "  call void @myl_core_trap(i32 {d}, i64 0, i64 0){s}\n  unreachable\n";
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

/// TBAA access tags and the count's `!range` (docs/design/new-core-s1.md §6, R-2):
/// the reference count, the header's length and capacity, and element, field and
/// box data are three types no access of another aliases, so LLVM may move or fold
/// count updates across data accesses. Fixed node numbers, emitted with the module.
const tbaa_count = "!tbaa !3";
const tbaa_header = "!tbaa !5";
const tbaa_data = "!tbaa !7";
/// A count is never 0 while its block is reachable: `[1, 0)`, i.e. 1 through saturated.
const count_range = "!range !8";
/// The first `!range` node number free for fact intervals.
const first_range_node = 10;
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
    \\
;
/// `  %x = load i64, ptr %at` of one data word (a union's tag word or payload word).
const word_load_line = "  {s} = load i64, ptr {s}, align 8, " ++ tbaa_data ++ "\n";
/// The count load every `retain`, `release` and `is_unique` starts with.
const count_load_line = "  {s} = load i32, ptr {s}, align 8, " ++ tbaa_count ++ ", " ++ count_range ++ "\n";
/// The header field loads of a list or string, tagged as header data.
const header_tagged_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8, " ++ tbaa_header ++ "\n";

/// `  %x = getelementptr inbounds i8, ptr %p, i64 0`: a second name for the same pointer.
const identity_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n";

/// One instruction line of the shape `  %x = op type a, b`.
/// Extract one constant-index aggregate component from a register value.
const extract_value_line = "  {s} = extractvalue {s} {s}, {d}\n";

const binary_line = "  {s} = {s} {s} {s}, {s}\n";

/// Render `module` as one LLVM IR module, including the C `main` entry.
pub fn emitModule(allocator: std.mem.Allocator, module: *const ir.Module, options: Options) Error![]u8 {
    var state: ModuleState = .{ .allocator = allocator, .module = module, .options = options };
    var body: Out = .empty;
    for (module.functions.items, 0..) |*function, index| {
        if (function.signature.linkage == .extern_c) {
            try state.declareExtern(function);
            continue;
        }
        var emitter: FunctionEmitter = .{ .state = &state, .function = function, .index = @intCast(index) };
        if (index < options.vectors.len) emitter.vectors.plans = options.vectors[index];
        try emitter.emitFunction(&body);
    }
    try state.emitEntry(&body);
    var out: Out = .empty;
    try out.appendSlice(allocator, "; generated by mylang-core\n");
    try state.emitPrelude(&out);
    try out.appendSlice(allocator, body.items);
    try state.emitSites(&out);
    try state.emitStrings(&out);
    try out.appendSlice(allocator, metadata);
    try out.appendSlice(allocator, tbaa_metadata);
    try out.appendSlice(allocator, state.meta.ranges.items);
    try out.appendSlice(allocator, state.layouts.text.items);
    try out.appendSlice(allocator, trace_call_attributes);
    if (state.zeros != 0) try out.print(allocator, "@myl.zeros = private constant [{d} x i8] zeroinitializer, align 8\n", .{state.zeros});
    try state.debug.finish(allocator, &out);
    return out.toOwnedSlice(allocator);
}

/// Module-wide numbering: `!range` nodes (after the fixed TBAA nodes; `!0` is the
/// trap branch weight) and vector loops.
const Metadata = struct {
    ranges: Out = .empty,
    range_count: u32 = first_range_node,
    vector_count: u32 = 0,
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
    /// Bytes of the zeroed constant `@myl.zeros` (an `undef` record or union in memory), 0 for none.
    zeros: u32 = 0,

    fn declareExtern(self: *ModuleState, function: *const ir.Function) !void {
        // Several signatures of one runtime function (`myl_core_list_sort` over lists of different
        // elements) are one declaration.
        const symbol_name = c_abi.symbol(function.name);
        if (std.mem.eql(u8, symbol_name, flags.str_eq_symbol)) return;
        for (self.declared.items) |known| if (std.mem.eql(u8, known, symbol_name)) return;
        try self.declared.append(self.allocator, symbol_name);
        const returns = try self.llvmType(function.signature.ret);
        try self.externs.print(self.allocator, "declare {s}{s} @{s}(", .{ if (function.signature.ret == .bool) "zeroext " else "", returns, c_abi.symbol(function.name) });
        var first = true;
        for (function.signature.params, 0..) |param, i| {
            if (!c_abi.passes(param)) continue;
            const span = i < 64 and function.signature.views & (@as(u64, 1) << @intCast(i)) != 0;
            try self.externs.print(self.allocator, "{s}{s}", .{ if (first) "" else ", ", if (span) "ptr, i64" else try self.llvmType(param) });
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
        const words = 3 + 2 * parts.refs.items.len + 3 * parts.guards.items.len;
        try self.layouts.text.print(self.allocator, "@myl.layout.{d} = private constant [{d} x i32] [i32 {d}, i32 {d}, i32 {d}", .{ index, words, @max(1, self.module.size(ty)), parts.refs.items.len, parts.guards.items.len });
        for (parts.refs.items) |ref| try self.layouts.text.print(self.allocator, ", i32 {d}, i32 {d}", .{ ref[0], ref[1] });
        for (parts.guards.items) |g| try self.layouts.text.print(self.allocator, ", i32 {d}, i32 {d}, i32 {d}", .{ g[0], g[1], g[2] });
        try self.layouts.text.appendSlice(self.allocator, "], align 4\n");
        return std.fmt.allocPrint(self.allocator, "@myl.layout.{d}", .{index});
    }

    /// Register a trap site for an operation sub-emitter.
    fn site(self: *ModuleState, s: Site) !u32 {
        try self.sites.append(self.allocator, s);
        return @intCast(self.sites.items.len - 1);
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
            .str, .bytes => "ptr",
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

    fn emitPrelude(self: *ModuleState, out: *Out) !void {
        try out.appendSlice(self.allocator,
            \\%myl.site = type { i32, i32, i32, i32, ptr, ptr }
            \\declare void @myl_core_trap(i32, i64, i64) noreturn nounwind cold
            \\declare ptr @myl_core_args(i32, ptr) nounwind
            \\declare i32 @myl_core_exit(i64) nounwind
            \\declare void @myl_core_s2_unsupported(i32) noreturn nounwind cold
            \\declare ptr @myl_core_dict_new(i64, ptr) nounwind
            \\declare i32 @llvm.cttz.i32(i32, i1 immarg) nounwind readnone
            \\declare zeroext i1 @myl_core_str_eq(ptr, ptr) nounwind
            \\declare i32 @myl_core_str_hash(ptr) nounwind
            \\declare void @llvm.memset.p0.i64(ptr, i8, i64, i1) nounwind
            \\declare i64 @myl_core_dict_hash(ptr, ptr) nounwind
            \\declare i64 @myl_core_dict_find_span(ptr, ptr, i64) nounwind
            \\declare i64 @myl_core_dict_find(ptr, ptr, i64) nounwind willreturn memory(argmem: read)
            \\declare ptr @myl_core_dict_set(ptr, i64, ptr) nounwind
            \\declare ptr @myl_core_dict_insert(ptr, i64, ptr, ptr, i1 zeroext) nounwind
            \\declare ptr @myl_core_dict_remove(ptr, i64) nounwind
            \\declare ptr @myl_core_dict_copy(ptr) nounwind
            \\declare ptr @myl_core_dict_clear(ptr) nounwind
            \\declare i64 @myl_core_dict_entries(ptr) nounwind willreturn memory(argmem: read)
            \\declare zeroext i1 @myl_core_dict_live(ptr, i64) nounwind willreturn memory(argmem: read)
            \\declare ptr @myl_core_ir_str_char(ptr, i64) nounwind
            \\declare ptr @myl_core_ir_str_from_view(ptr, i64) nounwind
            \\declare ptr @myl_core_list_copy(ptr, i64) nounwind
            \\declare zeroext i1 @myl_core_str_parse_int(ptr, ptr) nounwind
            \\declare void @myl_core_print_i64(i64, i64) nounwind
            \\declare void @myl_core_print_u64(i64, i64) nounwind
            \\declare void @myl_core_print_bool(i64, i1 zeroext) nounwind
            \\declare void @myl_core_print_str(i64, ptr) nounwind
            \\declare void @myl_core_print_sep(i64) nounwind
            \\declare void @myl_core_print_end(i64) nounwind
            \\declare ptr @myl_core_box_new(i64) nounwind
            \\declare void @myl_core_err_trace(i32, i32) nounwind cold
            \\declare void @myl_core_assert_fail(i32) noreturn nounwind cold
            \\declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg)
            \\declare void @llvm.memmove.p0.p0.i64(ptr nocapture writeonly, ptr nocapture readonly, i64, i1 immarg)
            \\declare void @myl_core_release(ptr) nounwind
            \\declare void @myl_core_main_error_i64(i64) nounwind cold
            \\declare void @myl_core_main_error_u64(i64) nounwind cold
            \\declare void @myl_core_main_error_bool(i1 zeroext) nounwind cold
            \\declare void @myl_core_main_error_str(ptr) nounwind cold
            \\
        );
        try out.appendSlice(self.allocator, runtime_fast_paths);
        try out.appendSlice(self.allocator, self.externs.items);
    }

    fn emitSites(self: *ModuleState, out: *Out) !void {
        try out.print(self.allocator, "@myl_core_source_path = constant [{d} x i8] c\"", .{self.options.source_path.len + 1});
        try escaped(self.allocator, out, self.options.source_path);
        try out.appendSlice(self.allocator, nul_terminator);
        for (self.sites.items, 0..) |s, i| {
            try out.print(self.allocator, "@myl.op.{d} = private constant [{d} x i8] c\"", .{ i, s.operation.len + 1 });
            try escaped(self.allocator, out, s.operation);
            try out.appendSlice(self.allocator, nul_terminator);
            try out.print(self.allocator, "@myl.fn.{d} = private constant [{d} x i8] c\"", .{ i, s.function.len + 1 });
            try escaped(self.allocator, out, s.function);
            try out.appendSlice(self.allocator, nul_terminator);
        }
        try out.print(self.allocator, "@myl_core_site_count = constant i32 {d}\n", .{self.sites.items.len});
        try out.print(self.allocator, "@myl_core_sites = constant [{d} x %myl.site] [", .{self.sites.items.len});
        for (self.sites.items, 0..) |s, i| {
            try out.print(self.allocator, "{s}%myl.site {{ i32 {d}, i32 {d}, i32 {d}, i32 {d}, ptr @myl.op.{d}, ptr @myl.fn.{d} }}", .{ if (i == 0) "" else ", ", @backingInt(s.kind), s.location.line, s.location.column, s.width, i, i });
        }
        try out.appendSlice(self.allocator, "]\n");
    }

    /// String constants are immortal blocks: the count is saturated (D4), so no release frees them.
    fn emitStrings(self: *ModuleState, out: *Out) !void {
        for (self.module.strings.items, 0..) |bytes, i| {
            const block_type = try std.fmt.allocPrint(self.allocator, "{{ i32, i32, i64, i64, i64, [{d} x i8] }}", .{bytes.len + 1});
            try out.print(self.allocator, "@myl.str.{d} = private unnamed_addr constant {s} ", .{ i, block_type });
            try out.print(self.allocator, "{{ i32 -1, i32 1, i64 {d}, i64 {d}, i64 0, [{d} x i8] c\"", .{ bytes.len, bytes.len, bytes.len + 1 });
            try escaped(self.allocator, out, bytes);
            try out.appendSlice(self.allocator, "\\00\" }, align 32\n");
        }
    }

    /// `int main(argc, argv)`: build the arguments `main` asks for, call it, release
    /// the arguments (`main` borrows them) and exit with its status. A `main` returning
    /// a `Result` reports an `Err` with its trace first (RESULT-MAIN-1/2, ERROR-TRACE-2).
    fn emitEntry(self: *ModuleState, out: *Out) !void {
        const entry = &self.module.functions.items[self.module.entry];
        // `dwarf_lines`: the C entry has a subprogram too (named `myl.entry`, which trap
        // frames never print), or inlining `main` into it would drop every location.
        var at: []const u8 = "";
        var scope: []const u8 = "";
        if (self.options.target.traps == .dwarf_lines) {
            const node = try self.debug.subprogram(self.allocator, "myl.entry", 1);
            scope = try std.fmt.allocPrint(self.allocator, function_scope, .{node});
            at = try std.fmt.allocPrint(self.allocator, instruction_location, .{try self.debug.location(self.allocator, .{ .line = 1, .column = 1 }, node)});
        }
        try out.print(self.allocator, "define i32 @main(i32 %argc, ptr %argv) uwtable{s} {{\nentry:\n", .{scope});
        var arguments: Out = .empty;
        var owns_args = false;
        for (entry.signature.params, 0..) |param, i| {
            if (i != 0) try arguments.appendSlice(self.allocator, ", ");
            if (param == .cap) {
                const name = if (i < self.options.main.parameters.len) self.options.main.parameters[i] else "";
                try arguments.print(self.allocator, "i64 {d}", .{@as(u8, if (std.mem.eql(u8, name, "err")) 2 else 1)});
            } else if (param.isCompound() and self.module.compound(param) == .list and self.module.compound(param).list == .str) {
                try out.appendSlice(self.allocator, "  %args = call ptr @myl_core_args(i32 %argc, ptr %argv)\n");
                try arguments.appendSlice(self.allocator, "ptr %args");
                owns_args = true;
            } else return error.UnsupportedEntry;
        }
        const release_args = if (owns_args) "  call void @myl_core_release(ptr %args)\n" else "";
        const ret = entry.signature.ret;
        const callee = try symbol(self.allocator, entry.name);
        if (ret == .void) {
            try out.print(self.allocator, "  call void {s}({s}){s}\n{s}  %s = call i32 @myl_core_exit(i64 0)\n", .{ callee, arguments.items, at, release_args });
        } else if (ret == .i64) {
            try out.print(self.allocator, "  %r = call i64 {s}({s}){s}\n{s}  %s = call i32 @myl_core_exit(i64 %r)\n", .{ callee, arguments.items, at, release_args });
        } else if (self.options.main.result != null and self.module.kind(ret) == .@"union" and !self.module.passedInMemory(ret)) {
            try out.print(self.allocator, "  %r = call {s} {s}({s}){s}\n", .{ try self.llvmType(ret), callee, arguments.items, at });
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
            try body.print(self.allocator, "  call void @myl_core_main_error_str(ptr %error)\n  call void @myl_core_release(ptr %error)\n{s}  %e = call i32 @myl_core_exit(i64 1)\n", .{release_args});
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
/// words, docs/design/new-core-s1.md §3): who uses each value, which constructions are stored
/// straight into their consumer, which phis own a stack slot and how edges were split to fill them.
const MemoryState = struct {
    /// Uses of each instruction's value, and the last instruction that used it.
    uses: []u32 = &.{},
    users: []ir.Ref = &.{},
    /// Per instruction: a `record_make` or `union_make` that is never materialized, because its
    /// only use stores it into its destination field by field.
    fused: []bool = &.{},
    /// Per block: the phis whose type lives in memory.
    phis: []const []const ir.Ref = &.{},
    /// Every instruction that reads a value living in memory, by the value's instruction index.
    readers: std.AutoHashMapUnmanaged(u32, std.ArrayList(ir.Ref)) = .empty,
    /// The label of the block that fills a memory phi on an edge `pred << 32 | block`, where the edge was split.
    edges: std.AutoHashMapUnmanaged(u64, []const u8) = .empty,
};

/// Which count update `counted` emits.
const Counting = enum { retain, release };

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
    scope: u32 = 0,
    /// Emitting a release of a value that may be `undef` (`own.empty_release`): every
    /// block pointer is tested for null first.
    may_be_empty: bool = false,

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
        const name = try std.fmt.allocPrint(self.a(), "@myl.dict.{d}", .{@backingInt(dict_type)});
        for (self.state.declared.items) |known| if (std.mem.eql(u8, known, name)) return name;
        try self.state.declared.append(self.a(), name);
        const shape = self.state.module.compound(dict_type).dict;
        const value_offset = std.mem.alignForward(u32, self.state.module.size(shape.key), self.state.module.alignment(shape.value));
        const stride = @max(1, std.mem.alignForward(u32, value_offset + self.state.module.size(shape.value), @max(self.state.module.alignment(shape.key), self.state.module.alignment(shape.value))));
        var parts: LayoutParts = .{};
        try layoutParts(self.a(), self.state.module, shape.key, 0, 0, &parts);
        try layoutParts(self.a(), self.state.module, shape.value, value_offset, 0, &parts);
        const words = 3 + 2 * parts.refs.items.len + 3 * parts.guards.items.len;
        try self.state.layouts.text.print(self.a(), "{s}.layout = private constant [{d} x i32] [i32 {d}, i32 {d}, i32 {d}", .{ name, words, stride, parts.refs.items.len, parts.guards.items.len });
        for (parts.refs.items) |reference| try self.state.layouts.text.print(self.a(), ", i32 {d}, i32 {d}", .{ reference[0], reference[1] });
        for (parts.guards.items) |guard| try self.state.layouts.text.print(self.a(), ", i32 {d}, i32 {d}, i32 {d}", .{ guard[0], guard[1], guard[2] });
        try self.state.layouts.text.appendSlice(self.a(), "], align 4\n");
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
        return std.fmt.allocPrint(self.a(), "{s}.{d}", .{ prefix, self.counter });
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
            .str_const => std.fmt.allocPrint(self.a(), "@myl.str.{d}", .{inst.data}),
            .func_ref => self.functionPointer(@intCast(inst.data)),
            else => std.fmt.allocPrint(self.a(), "%v{d}", .{ref.index()}),
        };
    }

    fn typedValue(self: *FunctionEmitter, raw: ir.Ref) ![]const u8 {
        const ref = self.function.resolve(raw);
        return std.fmt.allocPrint(self.a(), "{s} {s}", .{ try self.ty(self.function.inst(ref).ty), try self.value(ref) });
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
        // pointer in, through `sret` out (docs/design/new-core-s1.md §3).
        const sret = m.passedInMemory(f.signature.ret);
        try out.print(self.a(), "define internal {s} {s}(", .{ if (sret) "void" else try self.ty(f.signature.ret), try symbol(self.a(), f.name) });
        if (sret) try out.print(self.a(), "ptr noalias sret({s}) align 8 %ret", .{try self.state.memoryType(f.signature.ret)});
        var entry: Out = .empty;
        // A value over four words is used where the caller keeps it: the parameter is its pointer.
        for (f.signature.params, 0..) |param, i| {
            const separator = if (i == 0 and !sret) "" else ", ";
            if (m.passedInMemory(param)) {
                try out.print(self.a(), "{s}ptr noalias readonly align 8 %p{d}", .{ separator, i });
            } else try out.print(self.a(), "{s}{s} %p{d}", .{ separator, try self.ty(param), i });
        }
        try self.analyzeMemory(&entry);
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
            try self.assertReachable(&bodies[b], @intCast(b));
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .phi) try self.assertFacts(&bodies[b], ref, inst);
            }
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op == .phi or inst.op == .copy) continue;
                try self.instruction(&bodies[b], ref, inst);
                // A construction stored straight into its consumer never exists as a value to assert about.
                if (!inst.op.terminates() and !self.memory.fused[ref.index()]) try self.assertFacts(&bodies[b], ref, inst);
            }
            self.exit_labels.items[b] = self.label;
        }
        try out.appendSlice(self.a(), "entry:\n  %slot = alloca i64, align 8\n");
        try out.appendSlice(self.a(), self.state.allocas.items);
        try out.appendSlice(self.a(), entry.items);
        try out.appendSlice(self.a(), "  br label %b0\n");
        for (f.blocks.items, 0..) |block, b| {
            if (b != 0 and block.preds.items.len == 0) continue;
            try out.print(self.a(), "b{d}:\n", .{b});
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (inst.op != .phi) continue;
                // A phi of a value in memory is its own stack slot, filled on each incoming edge.
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

    /// Count uses, decide which constructions are stored straight into their consumer, and give
    /// every phi of a value in memory its stack slot (defined in the entry block as `%vN`).
    fn analyzeMemory(self: *FunctionEmitter, entry: *Out) !void {
        _ = entry;
        const f = self.function;
        const m = self.state.module;
        const count = f.insts.items.len;
        const mem = &self.memory;
        mem.uses = try self.a().alloc(u32, count);
        mem.users = try self.a().alloc(ir.Ref, count);
        mem.fused = try self.a().alloc(bool, count);
        @memset(mem.uses, 0);
        @memset(mem.users, .none);
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
                    mem.uses[used.index()] += 1;
                    mem.users[used.index()] = ref;
                    if (m.passedInMemory(f.inst(used).ty)) {
                        const list = try mem.readers.getOrPut(self.a(), @intCast(used.index()));
                        if (!list.found_existing) list.value_ptr.* = .empty;
                        try list.value_ptr.append(self.a(), ref);
                    }
                }
            }
            phis[b] = mine.items;
        }
        mem.phis = phis;
        // A construction whose only use stores it (a push, a write, a return through `sret`, a box,
        // or a field of a construction that is itself stored so) is never built on its own.
        for (f.blocks.items, 0..) |block, b| {
            var at = block.insts.items.len;
            while (at > 0) {
                at -= 1;
                const ref = block.insts.items[at];
                const inst = f.inst(ref);
                if (inst.op != .record_make and inst.op != .union_make) continue;
                if (mem.uses[ref.index()] != 1 or block_of[mem.users[ref.index()].index()] != b) continue;
                if (inst.op == .union_make and m.unionLayout(inst.ty).form == .niche) continue;
                const user = mem.users[ref.index()];
                const consumer = f.inst(user);
                mem.fused[ref.index()] = switch (consumer.op) {
                    .list_push => f.resolve(consumer.b) == ref,
                    .list_set => f.resolve(f.operands(consumer.data)[0]) == ref,
                    .ret => f.resolve(consumer.a) == ref and m.passedInMemory(f.signature.ret),
                    .box_make => f.resolve(consumer.a) == ref,
                    .record_make, .union_make => mem.fused[user.index()],
                    else => false,
                };
            }
        }
        for (phis) |block_phis| for (block_phis) |phi| {
            const slot = try self.stackSlot(m.size(f.inst(phi).ty));
            try self.state.allocas.print(self.a(), "  %v{d} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ phi.index(), slot });
        };
    }

    fn edgeKey(pred: usize, block: usize) u64 {
        return (@as(u64, pred) << 32) | block;
    }

    /// On the edge from block `pred` into `target`, copy the incoming value of each phi that lives
    /// in memory into the phi's own slot. With several such phis, an incoming value may be another
    /// phi's slot, so all are copied out to temporaries first.
    fn fillMemoryPhis(self: *FunctionEmitter, out: *Out, pred: usize, target: usize) !void {
        const phis = self.memory.phis[target];
        if (phis.len == 0) return;
        const f = self.function;
        const m = self.state.module;
        const position = for (f.blocks.items[target].preds.items, 0..) |candidate, i| {
            if (candidate.index() == pred) break i;
        } else return;
        var staged = false;
        for (phis) |phi| {
            const incoming = f.resolve(f.operands(f.inst(phi).data)[position]);
            if (std.mem.indexOfScalar(ir.Ref, phis, incoming) != null) staged = true;
        }
        var copies: std.ArrayList(struct { phi: ir.Ref, from: []const u8 }) = .empty;
        for (phis) |phi| {
            const incoming = f.resolve(f.operands(f.inst(phi).data)[position]);
            if (f.inst(incoming).op == .undef) continue;
            const size = m.size(f.inst(phi).ty);
            if (!staged) {
                try self.copyBytes(out, try self.value(phi), try self.value(incoming), size, true);
                continue;
            }
            const temporary = try self.stackSlot(size);
            try self.copyBytes(out, temporary, try self.value(incoming), size, false);
            try copies.append(self.a(), .{ .phi = phi, .from = temporary });
        }
        for (copies.items) |copy| try self.copyBytes(out, try self.value(copy.phi), copy.from, m.size(f.inst(copy.phi).ty), false);
    }

    /// `branch`: a successor with phis in memory gets a block of its own on the edge, which fills them.
    fn branchTo(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const targets = ir.unpackTargets(inst.data);
        const pred: usize = self.vectors.block;
        const sides = [2]usize{ targets.then.index(), targets.otherwise.index() };
        var labels: [2][]const u8 = undefined;
        for (sides, &labels) |target, *label| {
            label.* = if (self.memory.phis[target].len != 0) try self.fresh("edge") else try std.fmt.allocPrint(self.a(), "b{d}", .{target});
        }
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}\n", .{ try self.value(inst.a), labels[0], labels[1] });
        for (sides, labels) |target, label| {
            if (self.memory.phis[target].len == 0) continue;
            try out.print(self.a(), "{s}:\n", .{label});
            try self.fillMemoryPhis(out, pred, target);
            try out.print(self.a(), "  br label %b{d}\n", .{target});
            try self.memory.edges.put(self.a(), edgeKey(pred, target), label);
        }
    }

    /// `retain` or `release` the blocks a record or union in memory references: each managed field,
    /// or the payload of each managed case under its tag, loaded out of memory and counted as a value.
    fn countedMemory(self: *FunctionEmitter, out: *Out, mode: Counting, value_type: ir.Type, ptr: []const u8) Error!void {
        const m = self.state.module;
        if (!m.managed(value_type)) return;
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                if (!m.managed(field)) continue;
                const loaded = try self.fresh("%cm");
                try self.loadValue(out, field, try self.offsetPointer(out, ptr, m.fieldOffset(value_type, i)), loaded);
                try self.countedValue(out, mode, field, loaded);
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
                    const loaded = try self.fresh("%cp");
                    try self.loadValue(out, case, try self.offsetPointer(out, ptr, 8), loaded);
                    try self.countedValue(out, mode, case, loaded);
                    try self.leaveIf(out, join);
                }
            },
            .array => |array| for (0..array.n) |i| {
                const loaded = try self.fresh("%cm");
                try self.loadValue(out, array.elem, try self.offsetPointer(out, ptr, @as(u32, @intCast(i)) * m.size(array.elem)), loaded);
                try self.countedValue(out, mode, array.elem, loaded);
            },
            .list, .box, .dict, .@"fn" => unreachable,
        }
    }

    /// Count a value held in a register or, over four words, a pointer to its slot.
    fn countedValue(self: *FunctionEmitter, out: *Out, mode: Counting, value_type: ir.Type, text: []const u8) Error!void {
        if (self.state.module.passedInMemory(value_type)) return self.countedMemory(out, mode, value_type, text);
        return self.counted(out, mode, value_type, text);
    }

    /// The check an instruction gets emitted with: verify mode emits proven checks as exact ones.
    fn checkOf(self: *FunctionEmitter, inst: ir.Inst) ir.Check {
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
                .known = self.state.options.facts[self.index].?,
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
        if (!self.state.options.verify or self.index >= self.state.options.facts.len) return null;
        return self.state.options.facts[self.index];
    }

    /// Verify mode: a block the facts call unreachable traps if it ever runs.
    fn assertReachable(self: *FunctionEmitter, out: *Out, block: u32) !void {
        const known = self.knownFacts() orelse return;
        if (known.reachable[block]) return;
        const at: ir.Inst = .{ .op = .@"unreachable", .ty = .void, .span = self.function.span };
        const location = self.state.options.locator.locate(self.state.options.locator.context, at.span);
        const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "unreachable block", .function = self.function.name });
        try self.trapIf(out, "true", index, "0", "0");
    }

    /// Verify mode: the value's interval and its list-length bound hold.
    fn assertFacts(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        try self.assertRange(out, ref, inst);
        try self.assertBound(out, ref, inst);
        try self.assertAggregate(out, ref, inst);
    }

    /// Verify mode: a list's length lies in the interval the facts gave it, and every field of
    /// a record with a field interval lies in it.
    fn assertAggregate(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const m = self.state.module;
        const kind = m.kind(inst.ty) orelse return;
        if (kind == .list) {
            const len = known.aggregates.lists[ref.index()].len orelse return;
            const at = try self.fresh("%al");
            const length = try self.fresh("%an");
            const outside = try self.fresh("%ax");
            const below = try self.fresh("%ab");
            const above = try self.fresh("%aa");
            try out.print(self.a(), header_load_line, .{ at, try self.value(ref), len_offset, length, at });
            try out.print(self.a(), "  {s} = icmp ult i64 {s}, {d}\n  {s} = icmp ugt i64 {s}, {d}\n  {s} = or i1 {s}, {s}\n", .{ below, length, len.lo, above, length, len.hi, outside, below, above });
            const operation = try std.fmt.allocPrint(self.a(), "list length [{d}, {d}]", .{ len.lo, len.hi });
            const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = 64, .operation = operation, .function = self.function.name });
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
            const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = info.bits, .operation = operation, .function = self.function.name });
            try self.trapIf(out, outside, index, wide_value, "0");
        }
    }

    /// Verify mode: the value is at most (below, when strict) the length of the list
    /// parameter the facts bound it by.
    fn assertBound(self: *FunctionEmitter, out: *Out, ref: ir.Ref, inst: ir.Inst) !void {
        const known = self.knownFacts() orelse return;
        const info = inst.ty.integer() orelse return;
        if (inst.op == .iconst or known.bounds.len == 0) return;
        const bound = known.bounds[ref.index()] orelse return;
        if (bound.list == .none) return;
        const at = try self.fresh("%bh");
        const len = try self.fresh("%bl");
        const failed = try self.fresh("%bf");
        const name = try self.widened(out, ref);
        const predicate = if (bound.strict) (if (info.signed) "sge" else "uge") else (if (info.signed) "sgt" else "ugt");
        try out.print(self.a(), header_load_line, .{ at, try self.value(bound.list), len_offset, len, at });
        try out.print(self.a(), "  {s} = icmp {s} i64 {s}, {s}\n", .{ failed, predicate, name, len });
        const operation: []const u8 = if (bound.strict) "below the list length" else "at most the list length";
        const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = info.bits, .operation = operation, .function = self.function.name });
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
        const index = try self.state.site(.{ .kind = .fact, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = info.bits, .operation = operation, .function = self.function.name });
        try self.trapIf(out, condition, index, try self.widened(out, ref), "0");
    }

    /// Register a trap site for operation sub-emitters.
    pub fn site(self: *FunctionEmitter, kind: TrapKind, inst: ir.Inst, operation: []const u8) Error!u32 {
        const width: u16 = if (inst.ty.integer()) |info| info.bits else 64;
        // In verify mode a check the facts proved is still emitted, and its failure is the fact's.
        const effective: TrapKind = if (inst.check == .proven) .fact else kind;
        return self.state.site(.{ .kind = effective, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = width, .operation = operation, .function = self.function.name });
    }

    /// Branch to a cold trap when `failed` (an `i1` operand) holds, and continue in a new label.
    /// Emit a conditional trap and continue in a fresh LLVM block.
    pub fn trapIf(self: *FunctionEmitter, out: *Out, failed: []const u8, site_index: u32, left: []const u8, right: []const u8) Error!void {
        const trap = try self.fresh("trap");
        const next = try self.fresh(self.label);
        const at = try self.trapLocation(site_index);
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}, !prof !0\n{s}:\n  call void @myl_core_trap(i32 {d}, i64 {s}, i64 {s}){s}\n  unreachable\n{s}:\n", .{ failed, trap, next, trap, site_index, left, right, at, next });
        self.label = next;
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
        const name = try std.fmt.allocPrint(self.a(), "%v{d}", .{ref.index()});
        switch (inst.op) {
            .param, .iconst, .fconst, .undef, .str_const, .func_ref, .copy, .phi => {},
            .dict_new, .dict_len, .dict_find, .dict_entry_key, .dict_entry_value, .dict_set_value => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .dict_insert, .dict_remove, .dict_entries, .dict_entry_live, .dict_copy, .dict_clear => try emit_dict.instruction(@TypeOf(self), self, out, name, inst),
            .str_char, .str_width, .str_code, .str_append, .str_append_char, .str_slice, .str_view_of, .str_from_view => try emit_text.instruction(self, out, name, inst),
            .list_sort, .array_get, .array_set, .call_indirect => try emit_fn.instruction(self, out, name, inst),
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
                if (inst.data != 0) return self.stackList(out, name, inst.data - 1, element);
                try out.print(self.a(), "  {s} = call ptr @myl_core_list_new(i64 {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
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
                try out.print(self.a(), "  {s} = call zeroext i1 @myl_core_str_parse_int(ptr {s}, ptr %slot)\n  {s} = load i64, ptr %slot, align 8\n  {s} = zext i1 {s} to i8\n", .{ ok, try self.value(inst.a), parsed, tag, ok });
                try out.print(self.a(), "  {s} = insertvalue {{ i8, i64 }} poison, i8 {s}, 0\n  {s} = insertvalue {{ i8, i64 }} {s}, i64 {s}, 1\n", .{ partial, tag, name, partial, parsed });
            },
            .union_make => if (!self.memory.fused[ref.index()]) try self.unionMake(out, name, inst),
            .union_tag => try self.unionTag(out, name, inst.a),
            .union_payload => try self.unionPayload(out, .{ .result = name, .union_type = self.typeOf(inst.a), .value = try self.value(inst.a), .case = @intCast(inst.data) }),
            .record_make => if (!self.memory.fused[ref.index()]) try self.recordMake(out, name, inst),
            .record_get => try self.recordGet(out, name, inst),
            .record_set => try self.recordSet(out, name, ref, inst),
            .list_set => try self.listSet(out, name, inst),
            .list_pop => try self.listPop(out, name, inst),
            .list_get_field => try self.listGetField(out, name, inst),
            .box_make => {
                const inner = self.state.module.compound(inst.ty).box;
                try out.print(self.a(), "  {s} = call ptr @myl_core_box_new(i64 {d})\n", .{ name, self.state.module.size(inner) });
                try self.attachLayout(out, name, inner);
                try self.storeOperand(out, inner, inst.a, try self.offsetPointer(out, name, data_offset));
            },
            .box_get => try self.loadValue(out, inst.ty, try self.offsetPointer(out, try self.value(inst.a), data_offset), name),
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
            .is_unique => {
                const count = try self.fresh("%rc");
                try out.print(self.a(), count_load_line ++ "  {s} = icmp eq i32 {s}, 1\n", .{ count, try self.value(inst.a), name, count });
            },
            .err_trace => try self.errTrace(out, inst),
            .call => try self.call(out, name, inst),
            .print => try self.print(out, inst),
            .jump => {
                try self.vectorPrologue(out, @intCast(inst.data));
                try self.fillMemoryPhis(out, self.vectors.block, @intCast(inst.data));
                try out.print(self.a(), "  br label %b{d}\n", .{inst.data});
            },
            .branch => try self.branchTo(out, inst),
            .ret => if (inst.a == .none) {
                try out.appendSlice(self.a(), "  ret void\n");
            } else if (self.state.module.passedInMemory(self.function.signature.ret)) {
                try self.storeOperand(out, self.function.signature.ret, inst.a, "%ret");
                try out.appendSlice(self.a(), "  ret void\n");
            } else try out.print(self.a(), "  ret {s}\n", .{try self.typedValue(inst.a)}),
            .@"unreachable" => try self.trapTerminator(out, inst),
        }
    }

    fn trapTerminator(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        if (inst.data == capacity_assert) {
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 64, .operation = "a stack list's length below its capacity", .function = self.function.name });
            try out.print(self.a(), trap_zero, .{ index, try self.trapLocation(index) });
        } else if (inst.data == unique_assert) {
            // `own.zig`'s assert of a statically unique update (verify builds only).
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 32, .operation = "count == 1 before an in-place update", .function = self.function.name });
            try out.print(self.a(), "  call void @myl_core_trap(i32 {d}, i64 0, i64 1){s}\n  unreachable\n", .{ index, try self.trapLocation(index) });
        } else if (inst.data == flags.dict_missing_trap) {
            const index = try self.site(.missing_key, inst, "key");
            try out.print(self.a(), trap_zero, .{ index, try self.trapLocation(index) });
        } else if (inst.data == flags.iteration_trap) {
            const index = try self.site(.iteration_mutation, inst, "iteration");
            try out.print(self.a(), trap_zero, .{ index, try self.trapLocation(index) });
        } else if (inst.data & flags.assertion_trap != 0) {
            // A failed `assert` or contract clause: the message is in the module's string table.
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const kind: u16 = @truncate(inst.data >> 32);
            const message = self.state.module.strings.items[@as(u32, @truncate(inst.data))];
            const index = try self.state.site(.{ .kind = .assertion, .location = location, .width = kind, .operation = message, .function = self.function.name });
            try out.print(self.a(), "  call void @myl_core_assert_fail(i32 {d}){s}\n  unreachable\n", .{ index, try self.trapLocation(index) });
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
        const index = try self.value(inst.b);
        try self.boundsCheck(out, inst, list, index);
        const slot = try self.elementSlot(out, list, index, inst.ty);
        if (inst.ty == .bool or inst.ty.isCompound()) return self.loadValue(out, inst.ty, slot, name);
        const stored = storageType(inst.ty);
        try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}{s}, " ++ tbaa_data ++ "\n", .{ name, stored, slot, elementSize(inst.ty), try self.loadRange(name, inst.ty) });
    }

    /// Trap unless `0 <= index < len(list)` (the index is unsigned here), for an exact check.
    fn boundsCheck(self: *FunctionEmitter, out: *Out, inst: ir.Inst, list: []const u8, index: []const u8) !void {
        if (self.checkOf(inst) != .exact) return;
        const at = try self.fresh("%lh");
        const len = try self.fresh("%len");
        const outside = try self.fresh("%oob");
        try out.print(self.a(), header_tagged_line, .{ at, list, len_offset, len, at });
        try out.print(self.a(), "  {s} = icmp uge i64 {s}, {s}\n", .{ outside, index, len });
        // The read a `pop` starts with fails exactly when the list is empty, which is the pop trap.
        if (inst.op == .list_get and inst.data == flags.pop_read) return self.trapIf(out, outside, try self.site(.list_empty, inst, "pop"), "0", len);
        try self.trapIf(out, outside, try self.site(.list_bounds, inst, "index"), index, len);
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

    /// Load the memory image of a `ty` value at `ptr` into register value `result`: field
    /// by field for records and unions, so no aggregate load is emitted (§3).
    /// Load a typed value field by field from an operation sub-emitter slot.
    pub fn loadValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, ptr: []const u8, result: []const u8) Error!void {
        const m = self.state.module;
        if (value_type == .void) return error.UnsupportedInstruction;
        if (m.passedInMemory(value_type)) {
            // A value over four words is copied into a stack slot of its own: its SSA value is that slot.
            const slot = try self.stackSlot(m.size(value_type));
            try self.copyBytes(out, slot, ptr, m.size(value_type), false);
            try out.print(self.a(), identity_line, .{ result, slot });
            return;
        }
        if (value_type == .bool) {
            const byte = try self.fresh("%lb");
            try out.print(self.a(), "  {s} = load i8, ptr {s}, align 1, " ++ tbaa_data ++ "\n  {s} = trunc i8 {s} to i1\n", .{ byte, ptr, result, byte });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            try out.print(self.a(), "  {s} = load {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ result, try self.ty(value_type), ptr, m.size(value_type) });
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
                const layout = m.unionLayout(value_type);
                if (layout.form == .niche) {
                    try out.print(self.a(), "  {s} = load ptr, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ result, ptr });
                    return;
                }
                const word = try self.fresh("%lt");
                const tag = try self.fresh("%lt");
                try out.print(self.a(), word_load_line ++ "  {s} = trunc i64 {s} to i8\n", .{ word, ptr, tag, word });
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
            try out.print(self.a(), "  {s} = zext i1 {s} to i8\n  store i8 {s}, ptr {s}, align 1, " ++ tbaa_data ++ "\n", .{ byte, text, byte, ptr });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type) or m.kind(value_type) == .@"fn") {
            try out.print(self.a(), "  store {s} {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ try self.ty(value_type), text, ptr, m.size(value_type) });
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
                try out.print(self.a(), "  store i64 {d}, ptr {s}, align 8, " ++ tbaa_data ++ "\n", .{ inst.data, dst });
                if (inst.a == .none) return;
                try self.storeOperand(out, m.compound(inst.ty).@"union"[@intCast(inst.data)], inst.a, try self.offsetPointer(out, dst, 8));
            },
            else => unreachable,
        }
    }

    /// A record or union over four words, built in a stack slot of its own.
    fn makeInMemory(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const slot = try self.stackSlot(self.state.module.size(inst.ty));
        try self.storeMake(out, inst, slot);
        try out.print(self.a(), identity_line, .{ name, slot });
    }

    /// `record_get`: `extractvalue` from a record in registers, one load from a record in memory.
    fn recordGet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const record_type = self.typeOf(inst.a);
        if (!m.passedInMemory(record_type)) return out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(inst.a), inst.data });
        const at = try self.offsetPointer(out, try self.value(inst.a), m.fieldOffset(record_type, @intCast(inst.data)));
        try self.loadValue(out, inst.ty, at, name);
    }

    /// `record_set`: `insertvalue` for a record in registers. A record in memory is copied into a
    /// slot of its own and the field stored, or, when the old value's only use is this write and it
    /// was made in this block, written where it is.
    fn recordSet(self: *FunctionEmitter, out: *Out, name: []const u8, ref: ir.Ref, inst: ir.Inst) !void {
        const m = self.state.module;
        if (!m.passedInMemory(inst.ty)) return out.print(self.a(), "  {s} = insertvalue {s}, {s}, {d}\n", .{ name, try self.typedValue(inst.a), try self.typedValue(inst.b), inst.data });
        const old = self.function.resolve(inst.a);
        var slot: []const u8 = try self.value(old);
        if (!self.writableInPlace(old, ref)) {
            slot = try self.stackSlot(m.size(inst.ty));
            try self.copyBytes(out, slot, try self.value(old), m.size(inst.ty), false);
        }
        const field = m.compound(inst.ty).record[@intCast(inst.data)];
        try self.storeOperand(out, field, inst.b, try self.offsetPointer(out, slot, m.fieldOffset(inst.ty, @intCast(inst.data))));
        try out.print(self.a(), identity_line, .{ name, slot });
    }

    /// Whether the memory value `old` may be updated where `writer` (a `record_set` of it) runs: it
    /// was made by an instruction of this block, so each run of the block makes it again (not a
    /// parameter, nor a slot filled on an edge), and every other reader is in this block, runs before
    /// the write and has finished with it by then (a load, a call, a copy into a container).
    fn writableInPlace(self: *FunctionEmitter, old: ir.Ref, writer: ir.Ref) bool {
        const f = self.function;
        const inst = f.inst(old);
        if (inst.op == .param or inst.op == .phi or inst.op.isConstant()) return false;
        const block = f.blocks.items[self.vectors.block].insts.items;
        const written = std.mem.indexOfScalar(ir.Ref, block, writer) orelse return false;
        if (std.mem.indexOfScalar(ir.Ref, block, old) == null) return false;
        const readers = self.memory.readers.get(@intCast(old.index())) orelse return false;
        for (readers.items) |reader| {
            if (reader == writer) continue;
            const at = std.mem.indexOfScalar(ir.Ref, block, reader) orelse return false;
            if (at >= written) return false;
            switch (f.inst(reader).op) {
                .record_get, .union_tag, .union_payload, .call, .list_push, .list_set, .box_make, .record_set => {},
                .record_make, .union_make => if (self.memory.fused[reader.index()]) return false,
                else => return false,
            }
            // A construction stored later would read the changed value.
            if (self.memory.fused[reader.index()]) return false;
        }
        return true;
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

    /// Replace element `b` of list `a` in place with `extra[0]`; the element it
    /// replaces is released when the element type is managed.
    fn listSet(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const index = try self.value(inst.b);
        const element = m.compound(inst.ty).list;
        try self.boundsCheck(out, inst, list, index);
        const slot = try self.elementSlot(out, list, index, element);
        const managed = m.managed(element);
        const old = if (managed) try self.fresh("%old") else "";
        if (managed) try self.loadValue(out, element, slot, old);
        try self.storeOperand(out, element, self.function.operands(inst.data)[0], slot);
        if (managed) try self.countedValue(out, .release, element, old);
        try out.print(self.a(), identity_line, .{ name, list });
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
    fn listGetField(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const list = try self.value(inst.a);
        const index = try self.value(inst.b);
        const element = m.compound(self.typeOf(inst.a)).list;
        try self.boundsCheck(out, inst, list, index);
        const slot = try self.elementSlot(out, list, index, element);
        const target = m.pathTarget(element, ir.FieldPath.unpack(inst.data)) orelse return error.UnsupportedInstruction;
        const at = try self.offsetPointer(out, slot, target.offset);
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
        if (m.isBlock(value_type)) return self.countBlock(out, mode, text);
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
                    try self.countBlock(out, mode, text);
                    return self.leaveIf(out, join);
                }
                const tag = try self.fresh("%ct");
                try out.print(self.a(), "  {s} = extractvalue {s} {s}, 0\n", .{ tag, tyname, text });
                for (cases, 0..) |case, k| {
                    if (!m.managed(case)) continue;
                    const here = try self.fresh("%cc");
                    try out.print(self.a(), "  {s} = icmp eq i8 {s}, {d}\n", .{ here, tag, k });
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
            3 => try std.fmt.allocPrint(self.a(), "? converted to {s}", .{self.caseName(inst.a)}),
            4 => "returned",
            else => "? propagated",
        };
        const restarts: u8 = if (inst.data == 0 or inst.data == 2) 0 else 1;
        const index = try self.state.site(.{ .kind = .trace, .location = location, .width = 0, .operation = action, .function = self.function.name });
        // ERROR-TRACE-5: the recorder never counts against inlining.
        try out.print(self.a(), "  call void @myl_core_err_trace(i32 {d}, i32 {d}) #1\n", .{ index, restarts });
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
        self.scope = try self.state.debug.subprogram(self.a(), self.function.name, location.line);
        return std.fmt.allocPrint(self.a(), function_scope, .{self.scope});
    }

    /// `, !dbg !N` for a call at `span` (`dwarf_lines` only): LLVM keeps it through
    /// inlining as an inline record, so a return address maps to every frame it stands for.
    fn callLocation(self: *FunctionEmitter, span: u32) ![]const u8 {
        if (self.scope == 0) return "";
        const location = self.state.options.locator.locate(self.state.options.locator.context, span);
        return std.fmt.allocPrint(self.a(), instruction_location, .{try self.state.debug.location(self.a(), location, self.scope)});
    }

    fn trapLocation(self: *FunctionEmitter, site_index: u32) ![]const u8 {
        if (self.scope == 0) return "";
        const location = self.state.sites.items[site_index].location;
        return std.fmt.allocPrint(self.a(), instruction_location, .{try self.state.debug.location(self.a(), location, self.scope)});
    }

    /// A list `promote.zig` put on the stack: an entry-block `alloca` with the block
    /// header (count 1, the stack class, room for `capacity` elements), set up where
    /// the `list_new` runs; nothing counts, frees or grows it.
    fn stackList(self: *FunctionEmitter, out: *Out, name: []const u8, capacity: u64, element: ir.Type) !void {
        const bytes = data_offset + capacity * self.state.stride(element);
        const frame = try self.fresh("%stacklist");
        try self.state.allocas.print(self.a(), "  {s} = alloca [{d} x i8], align 32\n", .{ frame, bytes });
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n  store i32 1, ptr {s}, align 8, " ++ tbaa_count ++ "\n", .{ name, frame, name });
        const fields = [_]struct { offset: u32, ty: []const u8, value: []const u8 }{
            .{ .offset = 4, .ty = "i32", .value = stack_kind },
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
            self.state.zeros = @max(self.state.zeros, m.size(value_type));
            return "@myl.zeros";
        }
        if (m.isBlock(value_type) or (m.kind(value_type) == .@"union" and m.unionLayout(value_type).form == .niche)) return "null";
        return "zeroinitializer";
    }

    /// The release of a block `own.zig` proved unique: free it without the count test
    /// (verify builds first assert the count is 1 and trap `R_CORE_FACT`).
    fn freeUnique(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const block = try self.value(inst.a);
        if (self.state.options.verify) {
            const count = try self.fresh("%uc");
            const shared = try self.fresh("%us");
            try out.print(self.a(), count_load_line ++ "  {s} = icmp ne i32 {s}, 1\n", .{ count, block, shared, count });
            const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
            const index = try self.state.site(.{ .kind = .fact, .location = location, .width = 32, .operation = "count == 1 before freeing a unique block", .function = self.function.name });
            try self.trapIf(out, shared, index, "0", "1");
        }
        try out.print(self.a(), "  call void @myl_core_free(ptr {s})\n", .{block});
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

    /// The inline count update of one block (§6, R-2): the count is a `u32` at offset
    /// 0, tagged `myl.count` and known non-zero; `0xFFFFFFFF` is saturated (D4) and
    /// never changes, so immortal string constants are never written; a release
    /// that drops the last owner calls the cold, out-of-line `myl_core_free`.
    fn countBlock(self: *FunctionEmitter, out: *Out, mode: Counting, block: []const u8) !void {
        if (self.may_be_empty) {
            // An `undef` value is all null pointers (`undefValue`): nothing to count.
            const present = try self.fresh("%re");
            try out.print(self.a(), "  {s} = icmp ne ptr {s}, null\n", .{ present, block });
            const join = try self.enterIf(out, present);
            self.may_be_empty = false;
            defer self.may_be_empty = true;
            try self.countBlock(out, mode, block);
            return self.leaveIf(out, join);
        }
        const count = try self.fresh("%rc");
        const saturated = try self.fresh("%rs");
        const update = try self.fresh(if (mode == .retain) "rc.inc" else "rc.dec");
        const done = try self.fresh(self.label);
        const next = try self.fresh("%rn");
        try out.print(self.a(), count_load_line, .{ count, block });
        try out.print(self.a(), "  {s} = icmp eq i32 {s}, -1\n  br i1 {s}, label %{s}, label %{s}\n{s}:\n", .{ saturated, count, saturated, done, update, update });
        if (mode == .retain) {
            try out.print(self.a(), "  {s} = add nuw i32 {s}, 1\n  store i32 {s}, ptr {s}, align 8, " ++ tbaa_count ++ "\n  br label %{s}\n{s}:\n", .{ next, count, next, block, done, done });
        } else {
            const last = try self.fresh("%rz");
            const keep = try self.fresh("rc.keep");
            const free = try self.fresh("rc.free");
            try out.print(self.a(), "  {s} = sub nuw i32 {s}, 1\n  {s} = icmp eq i32 {s}, 0\n  br i1 {s}, label %{s}, label %{s}\n", .{ next, count, last, next, last, free, keep });
            try out.print(self.a(), "{s}:\n  store i32 {s}, ptr {s}, align 8, " ++ tbaa_count ++ "\n  br label %{s}\n", .{ keep, next, block, done });
            try out.print(self.a(), "{s}:\n  call void @myl_core_free(ptr {s})\n  br label %{s}\n{s}:\n", .{ free, block, done, done });
        }
        self.label = done;
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
        if (self.state.options.verify or self.index >= self.state.options.facts.len) return false;
        const known = self.state.options.facts[self.index] orelse return false;
        const range = known.ranges[ref.index()] orelse return false;
        return range.lo >= 0;
    }

    /// Whether trusted facts put an integer value inside `i32` (never in verify builds).
    fn fitsI32(self: *FunctionEmitter, raw: ir.Ref) bool {
        if (self.state.options.verify or self.index >= self.state.options.facts.len) return false;
        const known = self.state.options.facts[self.index] orelse return false;
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        const range = if (inst.op == .iconst) facts.Interval.point(@as(i64, @bitCast(inst.data))) else known.ranges[ref.index()] orelse return false;
        return range.lo >= std.math.minInt(i32) and range.hi <= std.math.maxInt(i32);
    }

    /// `, !range !N` when the facts bound the loaded value more tightly than its type.
    fn loadRange(self: *FunctionEmitter, name: []const u8, loaded: ir.Type) ![]const u8 {
        const info = loaded.integer() orelse return "";
        if (self.state.options.verify or self.index >= self.state.options.facts.len) return "";
        const known = self.state.options.facts[self.index] orelse return "";
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
        const element = self.state.module.compound(inst.ty).list;
        const len_at = try self.fresh("%pl");
        const len = try self.fresh("%plen");
        const next = try self.fresh("%pn");
        if (inst.data == stack_push) {
            // A promoted list's room is proven (`promote.zig`): no growth call.
            try out.print(self.a(), same_pointer, .{ name, try self.value(inst.a) });
        } else try out.print(self.a(), "  {s} = call ptr @myl_core_list_reserve(ptr {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
        try out.print(self.a(), header_tagged_line, .{ len_at, name, len_offset, len, len_at });
        const slot = try self.elementSlot(out, name, len, element);
        if (element == .bool or element.isCompound()) {
            try self.storeOperand(out, element, inst.b, slot);
        } else {
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ try self.typedValue(inst.b), slot, elementSize(element) });
        }
        try out.print(self.a(), "  {s} = add nuw nsw i64 {s}, 1\n  store i64 {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ next, len, next, len_at });
    }

    /// Emit a direct or indirect call under the internal aggregate ABI.
    /// Resolve an internal function index to its quoted LLVM symbol.
    pub fn functionPointer(self: *FunctionEmitter, index: u32) Error![]const u8 {
        return symbol(self.a(), self.state.module.functions.items[index].name);
    }

    /// Emit a placeholder that traps precisely before its result can be observed.
    pub fn unsupported(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        try out.print(self.a(), "  call void @myl_core_s2_unsupported(i32 {d})\n", .{@backingInt(inst.op)});
        if (inst.ty != .void) try out.print(self.a(), "  {s} = freeze {s} poison\n", .{ name, try self.ty(inst.ty) });
    }

    /// Emit a direct or indirect call under the internal aggregate ABI.
    pub fn call(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) Error!void {
        const m = self.state.module;
        const signature = if (inst.op == .call_indirect) m.compound(self.typeOf(inst.a)).@"fn" else m.functions.items[inst.a.index()].signature;
        const external = signature.linkage == .extern_c;
        const borrowed_bytes = external and signature.ret == .bytes and signature.owned == 0;
        const text_parameter = signature.params.len == 1 and signature.params[0] == .str;
        if (inst.op == .call and borrowed_bytes and text_parameter and
            std.mem.eql(u8, m.functions.items[inst.a.index()].name, flags.text_encode_symbol))
        {
            const source = self.function.operands(inst.data)[0];
            return out.print(self.a(), same_pointer, .{ name, try self.value(source) });
        }
        const ret = signature.ret;
        const sret = !external and m.passedInMemory(ret);
        var arguments: Out = .empty;
        var first = true;
        const result_slot = if (sret) try self.stackSlot(m.size(ret)) else "";
        if (sret) {
            try arguments.print(self.a(), "ptr sret({s}) align 8 {s}", .{ try self.state.memoryType(ret), result_slot });
            first = false;
        }
        for (self.function.operands(inst.data), signature.params, 0..) |argument, param, i| {
            if (external and !c_abi.passes(param)) continue;
            const separator = if (first) "" else ", ";
            first = false;
            if (external and i < 64 and signature.views & (@as(u64, 1) << @intCast(i)) != 0) {
                const data = try self.fresh("%span");
                const len = try self.fresh("%span");
                const text = try self.value(argument);
                if (self.typeOf(argument) == .str_view) {
                    try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, text, len, text });
                } else {
                    const at = try self.fresh("%span");
                    try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 32\n  {s} = getelementptr inbounds i8, ptr {s}, i64 8\n  {s} = load i64, ptr {s}, align 8\n", .{ data, text, at, text, len, at });
                }
                try arguments.print(self.a(), "{s}ptr {s}, i64 {s}", .{ separator, data, len });
                continue;
            }
            if (!external and m.passedInMemory(param)) {
                try arguments.print(self.a(), "{s}ptr {s}", .{ separator, try self.value(argument) });
                continue;
            }
            try arguments.print(self.a(), "{s}{s}", .{ separator, try self.typedValue(argument) });
        }
        const target = if (inst.op == .call_indirect)
            try self.value(inst.a)
        else if (external)
            try std.fmt.allocPrint(self.a(), "@{s}", .{c_abi.symbol(m.functions.items[inst.a.index()].name)})
        else
            try self.functionPointer(@intCast(inst.a.index()));
        if (ret == .void or sret) {
            try out.print(self.a(), "  call void {s}({s}){s}\n", .{ target, arguments.items, try self.callLocation(inst.span) });
            if (sret) try out.print(self.a(), identity_line, .{ name, result_slot });
        } else {
            try out.print(self.a(), "  {s} = call {s} {s}({s}){s}\n", .{ name, try self.ty(ret), target, arguments.items, try self.callLocation(inst.span) });
        }
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
        .str => "ptr",
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

    const first_node = 1_000_000;

    fn node(self: *Debug, allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !u32 {
        const id = self.next;
        self.next += 1;
        try self.text.print(allocator, "!{d} = ", .{id});
        try self.text.print(allocator, format ++ "\n", args);
        return id;
    }

    /// Start the compile unit (file, unit and subroutine type) on first use.
    fn begin(self: *Debug, allocator: std.mem.Allocator) !void {
        if (self.unit != 0) return;
        _ = try self.node(allocator, "!DIFile(filename: \"program.my\", directory: \"/\")", .{});
        self.unit = try self.node(allocator, "distinct !DICompileUnit(language: DW_LANG_C99, file: !{d}, producer: \"mylang-core\", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)", .{first_node});
        _ = try self.node(allocator, "!DISubroutineType(types: !{{}})", .{});
    }

    fn subprogram(self: *Debug, allocator: std.mem.Allocator, name: []const u8, line: u32) !u32 {
        try self.begin(allocator);
        const format = "distinct !DISubprogram(name: \"{s}\", scope: !{d}, file: !{d}, line: {d}, type: !{d}, scopeLine: {d}, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !{d})";
        return self.node(allocator, format, .{ name, first_node, first_node, line, first_node + 2, line, self.unit });
    }

    fn location(self: *Debug, allocator: std.mem.Allocator, at: Location, scope: u32) !u32 {
        return self.node(allocator, "!DILocation(line: {d}, column: {d}, scope: !{d})", .{ at.line, at.column, scope });
    }

    /// The nodes and the module flags that make LLVM emit them (DWARF 4: the runtime's reader).
    fn finish(self: *Debug, allocator: std.mem.Allocator, out: *Out) !void {
        if (self.unit == 0) return;
        try out.appendSlice(allocator, self.text.items);
        try out.print(allocator, "!llvm.dbg.cu = !{{!{d}}}\n!llvm.module.flags = !{{!{d}, !{d}}}\n", .{ self.unit, self.next, self.next + 1 });
        try out.print(allocator, "!{d} = !{{i32 2, !\"Debug Info Version\", i32 3}}\n!{d} = !{{i32 7, !\"Dwarf Version\", i32 4}}\n", .{ self.next, self.next + 1 });
    }
};

/// The allocator's common cases, inlined into every caller (`runtime/core_rt.c`,
/// "allocation"): a small list taken from its size class's free list, a push into a
/// list with room, and the free of a small block that holds no blocks. Everything
/// else calls the runtime. Free-list accesses carry no TBAA tag; nothing is counted
/// here (the leak check counts free-list entries at exit).
const runtime_fast_paths =
    \\@myl_core_free_lists = external global [33 x ptr]
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

/// Attribute group `#1`: an error-trace recorder call costs nothing to inline around (ERROR-TRACE-5).
const trace_call_attributes = "attributes #1 = { \"call-inline-cost\"=\"0\" }\n";

/// The branch-weight metadata every trap branch names (`!0`: the trap is cold).
pub const metadata = "!0 = !{!\"branch_weights\", i32 1, i32 1048575}\n";
