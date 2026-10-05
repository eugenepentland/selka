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
    main_parameters: []const []const u8,
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

/// Trap kinds, in the order the runtime's code table lists them. `list_empty` is a
/// pop of an empty list (`R_LIST_BOUNDS`, operation `pop`); `trace` marks an
/// error-trace site, which never traps.
pub const TrapKind = enum(u8) { overflow, division_by_zero, list_bounds, float_conversion, cast, fact, list_empty, trace };

const Site = struct { kind: TrapKind, location: Location, width: u16, operation: []const u8, function: []const u8 };

/// Header offsets of list and string blocks.
const len_offset = 8;
const cap_offset = 16;
const data_offset = 32;

const Out = std.ArrayList(u8);

/// Why emission stopped: a construct the builder admitted but this emitter cannot lower yet.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

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
const first_range_node = 8;
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
    \\
;
/// `  %x = load i64, ptr %at` of one data word (a union's tag word or payload word).
const word_load_line = "  {s} = load i64, ptr {s}, align 8, " ++ tbaa_data ++ "\n";
/// The count load every `retain`, `release` and `is_unique` starts with.
const count_load_line = "  {s} = load i32, ptr {s}, align 8, " ++ tbaa_count ++ ", " ++ count_range ++ "\n";
/// The header field loads of a list or string, tagged as header data.
const header_tagged_line = "  {s} = getelementptr inbounds i8, ptr {s}, i64 {d}\n  {s} = load i64, ptr {s}, align 8, " ++ tbaa_header ++ "\n";

/// One instruction line of the shape `  %x = op type a, b`.
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
    meta: Metadata = .{},
    /// The `alloca`s of the function being emitted, placed in its entry block.
    allocas: Out = .empty,

    fn declareExtern(self: *ModuleState, function: *const ir.Function) !void {
        try self.externs.print(self.allocator, "declare {s} @{s}(", .{ try self.llvmType(function.signature.ret), c_abi.symbol(function.name) });
        var first = true;
        for (function.signature.params) |param| {
            if (!c_abi.passes(param)) continue;
            try self.externs.print(self.allocator, "{s}{s}", .{ if (first) "" else ", ", try self.llvmType(param) });
            first = false;
        }
        try self.externs.appendSlice(self.allocator, ") nounwind\n");
    }

    /// A `!range` node for `[lo, hi]` in a `bits`-wide integer.
    fn rangeNode(self: *ModuleState, bits: u16, range: facts.Interval) ![]const u8 {
        self.meta.range_count += 1;
        try self.meta.ranges.print(self.allocator, "!{d} = !{{i{d} {d}, i{d} {d}}}\n", .{ self.meta.range_count, bits, range.lo, bits, range.hi + 1 });
        return std.fmt.allocPrint(self.allocator, ", !range !{d}", .{self.meta.range_count});
    }

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
            .str => "ptr",
            _ => switch (self.module.compound(ty)) {
                .list, .box => "ptr",
                .record => |fields| blk: {
                    var text: Out = .empty;
                    try text.appendSlice(self.allocator, "{ ");
                    for (fields, 0..) |field, i| try text.print(self.allocator, "{s}{s}", .{ if (i == 0) "" else ", ", try self.llvmType(field) });
                    try text.appendSlice(self.allocator, if (fields.len == 0) "}" else " }");
                    break :blk text.items;
                },
                .@"union" => blk: {
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
            \\declare ptr @myl_core_list_new(i64, i64) nounwind
            \\declare ptr @myl_core_list_reserve(ptr, i64) nounwind
            \\declare ptr @myl_core_list_copy(ptr, i64) nounwind
            \\declare zeroext i1 @myl_core_str_parse_int(ptr, ptr) nounwind
            \\declare void @myl_core_print_i64(i64, i64) nounwind
            \\declare void @myl_core_print_u64(i64, i64) nounwind
            \\declare void @myl_core_print_bool(i64, i1 zeroext) nounwind
            \\declare void @myl_core_print_str(i64, ptr) nounwind
            \\declare void @myl_core_print_sep(i64) nounwind
            \\declare void @myl_core_print_end(i64) nounwind
            \\declare ptr @myl_core_box_new(i64) nounwind
            \\declare void @myl_core_free(ptr) nounwind cold
            \\declare void @myl_core_err_trace(i32, i32) nounwind cold
            \\
        );
        try out.appendSlice(self.allocator, self.externs.items);
    }

    fn emitSites(self: *ModuleState, out: *Out) !void {
        try out.print(self.allocator, "@myl_core_source_path = constant [{d} x i8] c\"", .{self.options.source_path.len + 1});
        try escaped(self.allocator, out, self.options.source_path);
        try out.appendSlice(self.allocator, "\\00\"\n");
        for (self.sites.items, 0..) |s, i| {
            try out.print(self.allocator, "@myl.op.{d} = private constant [{d} x i8] c\"{s}\\00\"\n", .{ i, s.operation.len + 1, s.operation });
            try out.print(self.allocator, "@myl.fn.{d} = private constant [{d} x i8] c\"", .{ i, s.function.len + 1 });
            try escaped(self.allocator, out, s.function);
            try out.appendSlice(self.allocator, "\\00\"\n");
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

    /// `int main(argc, argv)`: build the arguments `main` asks for, call it, exit with its status.
    fn emitEntry(self: *ModuleState, out: *Out) !void {
        const entry = &self.module.functions.items[self.module.entry];
        try out.appendSlice(self.allocator, "define i32 @main(i32 %argc, ptr %argv) {\nentry:\n");
        var arguments: Out = .empty;
        for (entry.signature.params, 0..) |param, i| {
            if (i != 0) try arguments.appendSlice(self.allocator, ", ");
            if (param == .cap) {
                const name = if (i < self.options.main_parameters.len) self.options.main_parameters[i] else "";
                try arguments.print(self.allocator, "i64 {d}", .{@as(u8, if (std.mem.eql(u8, name, "err")) 2 else 1)});
            } else if (param.isCompound() and self.module.compound(param) == .list and self.module.compound(param).list == .str) {
                try out.appendSlice(self.allocator, "  %args = call ptr @myl_core_args(i32 %argc, ptr %argv)\n");
                try arguments.appendSlice(self.allocator, "ptr %args");
            } else return error.UnsupportedEntry;
        }
        const ret = entry.signature.ret;
        if (ret == .void) {
            try out.print(self.allocator, "  call void {s}({s})\n  %s = call i32 @myl_core_exit(i64 0)\n", .{ try symbol(self.allocator, entry.name), arguments.items });
        } else {
            const ty = try self.llvmType(ret);
            try out.print(self.allocator, "  %r = call {s} {s}({s})\n", .{ ty, try symbol(self.allocator, entry.name), arguments.items });
            if (ret == .i64) {
                try out.appendSlice(self.allocator, "  %s = call i32 @myl_core_exit(i64 %r)\n");
            } else return error.UnsupportedEntry;
        }
        try out.appendSlice(self.allocator, "  ret i32 %s\n}\n");
    }
};

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

    fn a(self: *FunctionEmitter) std.mem.Allocator {
        return self.state.allocator;
    }

    fn fresh(self: *FunctionEmitter, prefix: []const u8) ![]const u8 {
        self.counter += 1;
        return std.fmt.allocPrint(self.a(), "{s}.{d}", .{ prefix, self.counter });
    }

    fn ty(self: *FunctionEmitter, t: ir.Type) ![]const u8 {
        return self.state.llvmType(t);
    }

    /// The LLVM operand text for a value.
    fn value(self: *FunctionEmitter, raw: ir.Ref) ![]const u8 {
        const ref = self.function.resolve(raw);
        const inst = self.function.inst(ref);
        return switch (inst.op) {
            .iconst => if (inst.ty == .bool) (if (inst.data != 0) "true" else "false") else std.fmt.allocPrint(self.a(), "{d}", .{@as(i64, @bitCast(inst.data))}),
            .fconst => std.fmt.allocPrint(self.a(), "0x{X:0>16}", .{inst.data}),
            .param => std.fmt.allocPrint(self.a(), "%p{d}", .{inst.data}),
            .undef => "poison",
            .str_const => std.fmt.allocPrint(self.a(), "@myl.str.{d}", .{inst.data}),
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
        for (f.signature.params, 0..) |param, i| {
            const separator = if (i == 0 and !sret) "" else ", ";
            if (m.passedInMemory(param)) {
                try out.print(self.a(), "{s}ptr noalias readonly align 8 %p{d}.mem", .{ separator, i });
                try self.loadValue(&entry, param, try std.fmt.allocPrint(self.a(), "%p{d}.mem", .{i}), try std.fmt.allocPrint(self.a(), "%p{d}", .{i}));
            } else try out.print(self.a(), "{s}{s} %p{d}", .{ separator, try self.ty(param), i });
        }
        try out.appendSlice(self.a(), ") nounwind {\n");
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
                if (!inst.op.terminates()) try self.assertFacts(&bodies[b], ref, inst);
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
                try out.print(self.a(), "  %v{d} = phi {s} ", .{ ref.index(), try self.ty(inst.ty) });
                for (f.operands(inst.data), block.preds.items, 0..) |operand, pred, i| {
                    const resumed = if (self.vectorPreheader(pred, @intCast(b))) self.vectors.resume_values.get(@intCast(ref.index())) else null;
                    try out.print(self.a(), "{s}[ {s}, %{s} ]", .{ if (i == 0) "" else ", ", resumed orelse try self.value(operand), self.exit_labels.items[pred.index()] });
                }
                try out.appendSlice(self.a(), "\n");
            }
            try out.appendSlice(self.a(), bodies[b].items);
        }
        try out.appendSlice(self.a(), "}\n");
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

    fn site(self: *FunctionEmitter, kind: TrapKind, inst: ir.Inst, operation: []const u8) !u32 {
        const width: u16 = if (inst.ty.integer()) |info| info.bits else 64;
        // In verify mode a check the facts proved is still emitted, and its failure is the fact's.
        const effective: TrapKind = if (inst.check == .proven) .fact else kind;
        return self.state.site(.{ .kind = effective, .location = self.state.options.locator.locate(self.state.options.locator.context, inst.span), .width = width, .operation = operation, .function = self.function.name });
    }

    /// Branch to a cold trap when `failed` (an `i1` operand) holds, and continue in a new label.
    fn trapIf(self: *FunctionEmitter, out: *Out, failed: []const u8, site_index: u32, left: []const u8, right: []const u8) !void {
        const trap = try self.fresh("trap");
        const next = try self.fresh(self.label);
        try out.print(self.a(), "  br i1 {s}, label %{s}, label %{s}, !prof !0\n{s}:\n  call void @myl_core_trap(i32 {d}, i64 {s}, i64 {s})\n  unreachable\n{s}:\n", .{ failed, trap, next, trap, site_index, left, right, next });
        self.label = next;
    }

    /// Sign- or zero-extend an integer operand to `i64` for a trap report.
    fn widened(self: *FunctionEmitter, out: *Out, raw: ir.Ref) ![]const u8 {
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
            .param, .iconst, .fconst, .undef, .str_const, .copy, .phi => {},
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
                try out.print(self.a(), "  {s} = call ptr @myl_core_list_new(i64 {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
            },
            .list_len, .str_len => {
                const at = try self.fresh("%h");
                try out.print(self.a(), header_tagged_line, .{ at, try self.value(inst.a), len_offset, name, at });
            },
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
            .union_make => try self.unionMake(out, name, inst),
            .union_tag => try self.unionTag(out, name, inst.a),
            .union_payload => try self.unionPayload(out, .{ .result = name, .union_type = self.typeOf(inst.a), .value = try self.value(inst.a), .case = @intCast(inst.data) }),
            .record_make => try self.recordMake(out, name, inst),
            .record_get => try out.print(self.a(), "  {s} = extractvalue {s}, {d}\n", .{ name, try self.typedValue(inst.a), inst.data }),
            .record_set => try out.print(self.a(), "  {s} = insertvalue {s}, {s}, {d}\n", .{ name, try self.typedValue(inst.a), try self.typedValue(inst.b), inst.data }),
            .list_set => try self.listSet(out, name, inst),
            .list_pop => try self.listPop(out, name, inst),
            .list_get_field => try self.listGetField(out, name, inst),
            .box_make => {
                const inner = self.state.module.compound(inst.ty).box;
                try out.print(self.a(), "  {s} = call ptr @myl_core_box_new(i64 {d})\n", .{ name, self.state.module.size(inner) });
                try self.storeValue(out, inner, try self.value(inst.a), try self.offsetPointer(out, name, data_offset));
            },
            .box_get => try self.loadValue(out, inst.ty, try self.offsetPointer(out, try self.value(inst.a), data_offset), name),
            .retain, .release => try self.counted(out, if (inst.op == .retain) .retain else .release, self.typeOf(inst.a), try self.value(inst.a)),
            .is_unique => {
                const count = try self.fresh("%rc");
                try out.print(self.a(), count_load_line ++ "  {s} = icmp eq i32 {s}, 1\n", .{ count, try self.value(inst.a), name, count });
            },
            .err_trace => {
                const mode: ir.TraceMode = if (inst.data == 0) .origin else .append;
                const location = self.state.options.locator.locate(self.state.options.locator.context, inst.span);
                const index = try self.state.site(.{ .kind = .trace, .location = location, .width = 0, .operation = @tagName(mode), .function = self.function.name });
                try out.print(self.a(), "  call void @myl_core_err_trace(i32 {d}, i32 {d})\n", .{ index, @backingInt(mode) });
            },
            .call => try self.call(out, name, inst),
            .print => try self.print(out, inst),
            .jump => {
                try self.vectorPrologue(out, @intCast(inst.data));
                try out.print(self.a(), "  br label %b{d}\n", .{inst.data});
            },
            .branch => {
                const targets = ir.unpackTargets(inst.data);
                try out.print(self.a(), "  br i1 {s}, label %b{d}, label %b{d}\n", .{ try self.value(inst.a), @backingInt(targets.then), @backingInt(targets.otherwise) });
            },
            .ret => if (inst.a == .none) {
                try out.appendSlice(self.a(), "  ret void\n");
            } else if (self.state.module.passedInMemory(self.function.signature.ret)) {
                try self.storeValue(out, self.function.signature.ret, try self.value(inst.a), "%ret");
                try out.appendSlice(self.a(), "  ret void\n");
            } else try out.print(self.a(), "  ret {s}\n", .{try self.typedValue(inst.a)}),
            .@"unreachable" => try out.appendSlice(self.a(), "  unreachable\n"),
        }
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
            // The fact behind `proven`: both operands non-negative, the divisor positive.
            const negative = try self.fresh("%vn");
            const nonpositive = try self.fresh("%vz");
            const either = try self.fresh("%ve");
            try out.print(self.a(), "  {s} = icmp slt {s} {s}, 0\n  {s} = icmp sle {s} {s}, 0\n", .{ negative, tyname, left, nonpositive, tyname, right });
            try out.print(self.a(), or_line, .{ either, negative, nonpositive });
            try self.trapIf(out, either, try self.site(.division_by_zero, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
        }
        if (!info.signed or inst.check == .proven) {
            const divisor = self.constantOf(inst.b);
            if (inst.check != .proven and (divisor == null or divisor.? == 0)) {
                const zero = try self.fresh("%z");
                try out.print(self.a(), "  {s} = icmp eq {s} {s}, 0\n", .{ zero, tyname, right });
                try self.trapIf(out, zero, try self.site(.division_by_zero, inst, operation), try self.widened(out, inst.a), try self.widened(out, inst.b));
            }
            try out.print(self.a(), binary_line, .{ name, if (is_rem) "urem" else "udiv", tyname, left, right });
            return;
        }
        const divisor = self.constantOf(inst.b);
        if (divisor == null or divisor.? == 0) {
            const zero = try self.fresh("%z");
            try out.print(self.a(), "  {s} = icmp eq {s} {s}, 0\n", .{ zero, tyname, right });
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
            // Unsigned targets accept (-1, 2^N): truncation maps (-1, 0) to 0.
            try out.print(self.a(), "  {s} = fcmp {s} double {s}, 0x{X:0>16}\n", .{ above_lo, if (to.signed) "oge" else "ogt", operand, @as(u64, @bitCast(lo)) });
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
    fn typeOf(self: *FunctionEmitter, raw: ir.Ref) ir.Type {
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
    fn stackSlot(self: *FunctionEmitter, bytes: u32) ![]const u8 {
        const slot = try self.fresh("%stack");
        try self.state.allocas.print(self.a(), "  {s} = alloca [{d} x i8], align 8\n", .{ slot, @max(bytes, 1) });
        return slot;
    }

    /// Load the memory image of a `ty` value at `ptr` into register value `result`: field
    /// by field for records and unions, so no aggregate load is emitted (§3).
    fn loadValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, ptr: []const u8, result: []const u8) Error!void {
        const m = self.state.module;
        if (value_type == .void) return error.UnsupportedInstruction;
        if (value_type == .bool) {
            const byte = try self.fresh("%lb");
            try out.print(self.a(), "  {s} = load i8, ptr {s}, align 1, " ++ tbaa_data ++ "\n  {s} = trunc i8 {s} to i1\n", .{ byte, ptr, result, byte });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type)) {
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
            .list, .box => unreachable,
        }
    }

    /// Store register value `value` of type `ty` as its memory image at `ptr`, field by field.
    fn storeValue(self: *FunctionEmitter, out: *Out, value_type: ir.Type, text: []const u8, ptr: []const u8) Error!void {
        const m = self.state.module;
        if (value_type == .void) return error.UnsupportedInstruction;
        if (value_type == .bool) {
            const byte = try self.fresh("%sb");
            try out.print(self.a(), "  {s} = zext i1 {s} to i8\n  store i8 {s}, ptr {s}, align 1, " ++ tbaa_data ++ "\n", .{ byte, text, byte, ptr });
            return;
        }
        if (!value_type.isCompound() or m.isBlock(value_type)) {
            try out.print(self.a(), "  store {s} {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ try self.ty(value_type), text, ptr, m.size(value_type) });
            return;
        }
        const tyname = try self.ty(value_type);
        switch (m.compound(value_type)) {
            .record => |fields| for (fields, 0..) |field, i| {
                const field_value = try self.fresh("%sf");
                try out.print(self.a(), "  {s} = extractvalue {s} {s}, {d}\n", .{ field_value, tyname, text, i });
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
            .list, .box => unreachable,
        }
    }

    fn recordMake(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
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
        try self.storeValue(out, element, try self.value(self.function.operands(inst.data)[0]), slot);
        if (managed) try self.counted(out, .release, element, old);
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ name, list });
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
        try out.print(self.a(), "  {s} = getelementptr inbounds i8, ptr {s}, i64 0\n", .{ name, list });
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
                try out.print(self.a(), "  {s} = extractvalue {s} {s}, {d}\n", .{ field_value, tyname, text, i });
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
            .list, .box => unreachable,
        }
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
        try out.print(self.a(), "  {s} = call ptr @myl_core_list_reserve(ptr {s}, i64 {d})\n", .{ name, try self.value(inst.a), self.state.stride(element) });
        try out.print(self.a(), header_tagged_line, .{ len_at, name, len_offset, len, len_at });
        const slot = try self.elementSlot(out, name, len, element);
        if (element == .bool or element.isCompound()) {
            try self.storeValue(out, element, try self.value(inst.b), slot);
        } else {
            try out.print(self.a(), "  store {s}, ptr {s}, align {d}, " ++ tbaa_data ++ "\n", .{ try self.typedValue(inst.b), slot, elementSize(element) });
        }
        try out.print(self.a(), "  {s} = add nuw nsw i64 {s}, 1\n  store i64 {s}, ptr {s}, align 8, " ++ tbaa_header ++ "\n", .{ next, len, next, len_at });
    }

    fn call(self: *FunctionEmitter, out: *Out, name: []const u8, inst: ir.Inst) !void {
        const m = self.state.module;
        const callee = &m.functions.items[inst.a.index()];
        const external = callee.signature.linkage == .extern_c;
        const ret = callee.signature.ret;
        const sret = !external and m.passedInMemory(ret);
        var arguments: Out = .empty;
        var first = true;
        const result_slot = if (sret) try self.stackSlot(m.size(ret)) else "";
        if (sret) {
            try arguments.print(self.a(), "ptr sret({s}) align 8 {s}", .{ try self.state.memoryType(ret), result_slot });
            first = false;
        }
        for (self.function.operands(inst.data), callee.signature.params) |argument, param| {
            if (external and !c_abi.passes(param)) continue;
            const separator = if (first) "" else ", ";
            first = false;
            if (!external and m.passedInMemory(param)) {
                const slot = try self.stackSlot(m.size(param));
                try self.storeValue(out, param, try self.value(argument), slot);
                try arguments.print(self.a(), "{s}ptr {s}", .{ separator, slot });
                continue;
            }
            try arguments.print(self.a(), "{s}{s}", .{ separator, try self.typedValue(argument) });
        }
        const target = if (external) try std.fmt.allocPrint(self.a(), "@{s}", .{c_abi.symbol(callee.name)}) else try symbol(self.a(), callee.name);
        if (ret == .void or sret) {
            try out.print(self.a(), "  call void {s}({s})\n", .{ target, arguments.items });
            if (sret) try self.loadValue(out, ret, result_slot, name);
        } else {
            try out.print(self.a(), "  {s} = call {s} {s}({s})\n", .{ name, try self.ty(ret), target, arguments.items });
        }
    }

    fn print(self: *FunctionEmitter, out: *Out, inst: ir.Inst) !void {
        const operands = self.function.operands(inst.data);
        const stream = try self.value(operands[0]);
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

/// The branch-weight metadata every trap branch names (`!0`: the trap is cold).
pub const metadata = "!0 = !{!\"branch_weights\", i32 1, i32 1048575}\n";
