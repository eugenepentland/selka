//! The Core IR verifier (docs/design/new-core-s1.md §2): every block reachable from
//! the entry ends in exactly one terminator with its phis first, every phi has one
//! operand per predecessor, predecessor lists match the terminators, every operand
//! has the type its operation's signature asks for, and every use is dominated by
//! its definition (a phi operand by the end of its predecessor). Debug builds of
//! `selka-core` run it after construction and after the release passes, and the
//! unit tests run it on every module they build. `verifyPlan` checks that a vector
//! plan reads nothing from inside its loop before the loop runs (the S0 splat bug).
const std = @import("std");
const ir = @import("ir.zig");
const vector = @import("vector.zig");
const elements = @import("elements.zig");
const flags = @import("flags.zig");
const copy_sites = @import("copy_sites.zig");
const language = @import("selka");
const source_location = @import("source_location.zig");

/// Verification only allocates, or finds the IR malformed.
pub const Error = error{ OutOfMemory, InvalidIr };

/// The first problem found: where, and what.
pub const Failure = struct {
    function: []const u8 = "",
    /// The block, or `none_index` for a function-level problem.
    block: u32 = none_index,
    /// The instruction, or `none_index`.
    inst: u32 = none_index,
    reason: []const u8 = "",

    /// Marks a missing block or instruction position.
    pub const none_index = std.math.maxInt(u32);

    /// One line: `function b3 %7: reason`.
    pub fn render(self: Failure, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.print(allocator, "invalid Core IR in {s}", .{self.function});
        if (self.block != none_index) try out.print(allocator, " b{d}", .{self.block});
        if (self.inst != none_index) try out.print(allocator, " %{d}", .{self.inst});
        try out.print(allocator, ": {s}", .{self.reason});
        return out.toOwnedSlice(allocator);
    }
};

/// Whether `selka-core` verifies its IR on every build: in debug builds of the compiler.
pub const enabled = @import("builtin").mode == .debug;

/// Verify `module` and, per function, the vector plans the release passes made
/// (`plans` may be empty); a failure is rendered into `report`.
pub fn check(arena: std.mem.Allocator, module: *const ir.Module, plans: []const []const vector.Plan, report: *std.ArrayList(u8)) Error!void {
    return checkPresent(arena, module, .{ .plans = plans }, report);
}

/// What `checkPresent` checks beyond the module's tables and every declaration: the vector plans of the release passes (may
/// be empty) and which bodies the build holds. `present[i]` false says function `i`'s body was never brought into this build
/// (a demand build served it from a record whose maker checked it, `passes.validatedIr`); an index past `present` is present.
/// `tables` false skips the module's tables: a demand build checks them once, after its passes, when they are complete (the passes
/// only append types).
pub const Present = struct { plans: []const []const vector.Plan = &.{}, present: []const bool = &.{}, tables: bool = true, union_tags: TagCheck = .{} };

/// What the union-tag rule does with an unjustified payload read (`verify_union_tags.Mode`, default the builds' mode), and
/// where a counting check adds the reads it accepted.
pub const TagCheck = struct { mode: union_tags.Mode = union_tags.build_mode, counted: ?*usize = null };

const union_tags = @import("verify_union_tags.zig");

/// Verify the module's tables, every function's declaration, and the body and plans of every function whose body the build
/// holds (`Present`); a failure is rendered into `report`. With every body present this is `check`.
pub fn checkPresent(arena: std.mem.Allocator, module: *const ir.Module, bodies: Present, report: *std.ArrayList(u8)) Error!void {
    var failure: Failure = .{};
    verifyBodies(arena, module, bodies, &failure) catch |err| return reported(arena, err, failure, report);
    for (bodies.plans, module.functions.items[0..bodies.plans.len], 0..) |function_plans, *f, i| {
        if (i < bodies.present.len and !bodies.present[i]) continue;
        for (function_plans) |plan| verifyPlan(arena, module, f, plan, &failure) catch |err| return reported(arena, err, failure, report);
    }
}

/// Whether function `index` of `module` passes its declaration and body rules: the check `passes.zig` runs on a final body
/// before marking its record validated. A failure is not rendered here; the build's own check of the final module reports it.
pub fn functionHolds(arena: std.mem.Allocator, module: *const ir.Module, index: usize) std.mem.Allocator.Error!bool {
    var failure: Failure = .{};
    const f = &module.functions.items[index];
    verifyHeader(module, f, &failure) catch |err| switch (err) {
        error.InvalidIr => return false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (f.signature.linkage != .internal) return true;
    verifyFunction(arena, module, f, &failure) catch |err| switch (err) {
        error.InvalidIr => return false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    return true;
}

/// Rule C's guarantee (`copy_sites.zig`): every copy site reachable in `module` is written, that is,
/// it carries `flags.written_copy` from a `copy(value)` or a named new value. Run under facts
/// verification on the final module. `locator` names each refused site's source position
/// (`locator.locate(locator.context, span)`, as `cost --sites` does).
pub fn writtenCopies(arena: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator, verifying: bool, report: *std.ArrayList(u8)) Error!void {
    return writtenCopiesWithOptions(arena, module, locator, .{ .enabled = verifying }, report);
}

/// Written-copy checking and source rendering; JSON rendering uses `source`.
pub const WrittenCopiesOptions = struct {
    enabled: bool = true,
    source: ?language.source.Source = null,
    format: language.diagnostic_output.Format = .text,
    /// Per function, the blocks the build's facts call reachable (`passes.Result.known`); a block they prove
    /// dead never runs its copies (`copy_sites.counted`).
    known: []const ?@import("facts.zig").Facts = &.{},
    /// When set, every listed site of the checked blocks is counted by its reading (`copy_sites.Census`).
    census: ?*copy_sites.Census = null,
};

/// The blocks of `f` reachable from its entry, as the verifier computes them. A branch to a block that
/// does not exist is malformed IR. A body the build served from a record alone has no blocks, and none is reachable.
pub fn reachableBlocks(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function) Error![]const bool {
    if (f.blocks.items.len == 0) return &.{};
    var failure: Failure = .{ .function = f.name };
    var v: Verifier = .{ .arena = arena, .module = module, .f = f, .failure = &failure };
    try v.reach();
    return v.graph.reachable;
}

/// Whether function `index` of `module` has no unwritten copy site (`copy_sites`) in a block reachable from its entry: the
/// hidden-copy check of one final body. A final record's `validated` includes it (`passes.validatedFinal`, N5), so a body a
/// build serves from a record alone passed the check in the build that made the record. Malformed IR does not hold.
pub fn functionWrittenCopies(arena: std.mem.Allocator, module: *const ir.Module, index: u32) std.mem.Allocator.Error!bool {
    const f = &module.functions.items[index];
    if (f.signature.linkage != .internal) return true;
    const graph = reachableBlocks(arena, module, f) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidIr => return false,
    };
    for (f.blocks.items, 0..) |block, b| {
        if (!copy_sites.counted(graph, null, b)) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (copy_sites.isSite(module, inst) and !copy_sites.isWritten(inst)) return false;
        }
    }
    return true;
}

/// Report each hidden copy with C1, using source diagnostics when source is supplied. The sites are the one
/// list of `copy_sites` (the frame block included) in the blocks `copy_sites.counted` admits, the list
/// `cost --sites` prints; only an unwritten copy that is not a frame block is refused.
pub fn writtenCopiesWithOptions(arena: std.mem.Allocator, module: *const ir.Module, locator: source_location.Locator, options: WrittenCopiesOptions, report: *std.ArrayList(u8)) Error!void {
    if (!options.enabled) return;
    // Every hidden site is reported, not the first one only, so a census counts them all (CX-6).
    var hidden = false;
    for (module.functions.items, 0..) |*f, index| {
        if (f.signature.linkage != .internal) continue;
        const graph = try reachableBlocks(arena, module, f);
        const known = if (index < options.known.len) options.known[index] else null;
        var reader: copy_sites.Reader = .{ .arena = arena, .module = module, .f = f, .source = if (options.source) |src| src.bytes else null };
        for (f.blocks.items, 0..) |block, b| {
            if (!copy_sites.counted(graph, if (known) |facts| facts.reachable else null, b)) continue;
            for (block.insts.items) |ref| {
                const inst = f.inst(ref);
                if (!copy_sites.listed(module, inst)) continue;
                const reading = try reader.read(ref);
                if (options.census) |census| census.add(reading);
                if (reading.implicit == null or reading.implicit.? != .unwritten) continue;
                const span = if (inst.span != 0) inst.span else f.span;
                const at = locator.locate(locator.context, span);
                const message = try std.fmt.allocPrint(arena, "{s} in {s} at {s}:{d}:{d} used by {s}; duplicates existing storage that no copy(value) wrote; " ++
                    "a hidden copy must be removed (a view, a borrow or a move) or written as copy(...) at its source", .{ copy_sites.siteName(module, inst), f.name, at.path, at.line, at.column, consumerName(module, f, ref) });
                defer arena.free(message);
                const item = language.diagnostic.ownership(.{ .code = "E_CORE_HIDDEN_COPY", .rule = .C1 }, .{ .start = span, .end = span }, message);
                if (options.source) |src| {
                    const rendered = try language.diagnostic_output.render(arena, item, src, options.format);
                    defer arena.free(rendered);
                    try report.appendSlice(arena, rendered);
                } else {
                    try report.print(arena, "internal error[{s}]: {s}\n  note: ownership rule {s}\n", .{ item.code, item.message, @tagName(item.provenance.rule.?) });
                }
                hidden = true;
            }
        }
    }
    if (hidden) return error.InvalidIr;
}

/// What first reads the copy site `origin` in `f`, for a refusal's message: the consumer's op, or the
/// callee of a call (`call NAME`), which names the plain parameter the copy was passed to. A forwarding
/// copy is followed to the instruction that reads it.
fn consumerName(module: *const ir.Module, f: *const ir.Function, origin: ir.Ref) []const u8 {
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const user = f.inst(ref);
        // A forward is not a consumer: its readers resolve their operand to `origin` and are found here.
        if (user.op == .copy) continue;
        const operands = f.valueOperands(user);
        for (0..operands.len()) |i| {
            if (f.resolve(operands.get(i)) != origin) continue;
            if (user.op == .call) return if (user.a.index() < module.functions.items.len) module.functions.items[user.a.index()].name else "call";
            return @tagName(user.op);
        }
    };
    return "nothing";
}

fn reported(arena: std.mem.Allocator, err: Error, failure: Failure, report: *std.ArrayList(u8)) Error {
    if (err == error.InvalidIr) try report.print(arena, "internal error[E_CORE_INVALID_IR]: {s}\n", .{try failure.render(arena)});
    return err;
}

/// Verify every internal function of `module`.
pub fn verifyModule(arena: std.mem.Allocator, module: *const ir.Module, failure: *Failure) Error!void {
    return verifyBodies(arena, module, .{}, failure);
}

/// `verifyModule` with the union-tag rule's mode chosen (a test of the gate's refusing check).
pub fn verifyModuleWith(arena: std.mem.Allocator, module: *const ir.Module, failure: *Failure, tags: TagCheck) Error!void {
    return verifyBodies(arena, module, .{ .union_tags = tags }, failure);
}

/// Verify the module's tables (unless `bodies.tables` is false), and the declaration and body of every function not marked absent
/// in `bodies.present`: an absent function's declaration and body were checked together by the build that made its record.
fn verifyBodies(arena: std.mem.Allocator, module: *const ir.Module, bodies: Present, failure: *Failure) Error!void {
    if (bodies.tables) try verifyTypes(arena, module, failure);
    for (module.functions.items, 0..) |*f, i| {
        if (i < bodies.present.len and !bodies.present[i]) continue;
        try verifyHeader(module, f, failure);
        if (f.signature.linkage != .internal) continue;
        try verifyFunctionWith(arena, module, f, failure, bodies.union_tags);
    }
}

/// The module-level rules: the borrowed equality declarations and descriptor types, and no compound type that would store a view.
pub fn verifyTypes(arena: std.mem.Allocator, module: *const ir.Module, failure: *Failure) Error!void {
    // Every later rule asks questions of the types a compound names (`kind`, `managed`), which index the table.
    for (module.compounds.items) |compound| if (!namesValidTypes(module, compound)) {
        failure.* = .{ .reason = "a compound type names a type the module does not have" };
        return error.InvalidIr;
    };
    @import("build_equality.zig").validateModule(arena, module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedInstruction => {
            failure.* = .{ .reason = "invalid borrowed equality declaration or descriptor type" };
            return error.InvalidIr;
        },
    };
    for (module.compounds.items, 0..) |compound, compound_index| {
        const ty: ir.Type = @fromBackingInt(@as(u32, @intCast(ir.Type.first_compound + compound_index)));
        const escaped = switch (compound) {
            // A list of read-only overlays (RB2) lends its elements: an overlay has its storage type's layout.
            .list => |element| module.containsBorrow(element) and !module.isBorrowed(element),
            .box => |element| module.containsBorrow(element) and !taskEnvironment(module, ty),
            .list_view => false,
            .borrowed => |underlying| !module.valid(underlying) or module.storageType(underlying) != underlying or !module.managed(underlying) or module.containsBorrow(underlying),
            // A dictionary of lent values (RB2) holds read-only overlays of their storage.
            .dict => |dict| module.containsBorrow(dict.key) or (module.containsBorrow(dict.value) and !module.isBorrowed(dict.value)),
            .array => |array| module.containsBorrow(array.elem),
            .record, .@"union" => |fields| blk: {
                for (fields) |field| if (module.containsBorrow(field)) break :blk !canonicalTransient(module, ty) and !taskEnvironment(module, ty);
                break :blk false;
            },
            // A function value stores no view: its view parameters are passed to the callee (C9 S1), and a view result escapes.
            .@"fn" => |sig| sig.passing.hasViews() or sig.borrow.sources.len != 0 or module.containsBorrow(sig.ret),
        };
        if (escaped) {
            // Name the type: the problem is the module's, so no function locates it.
            const name = try @import("print.zig").typeName(arena, module, ty);
            failure.* = .{ .reason = try std.fmt.allocPrint(arena, "a view has no aggregate or function storage representation ({s})", .{name}) };
            return error.InvalidIr;
        }
    }
}

/// The rules on one function's declaration, with or without a body: compiler-only markers, parameter and result types,
/// passing conventions and the declared borrow contract.
pub fn verifyHeader(module: *const ir.Module, f: *const ir.Function, failure: *Failure) Error!void {
    _ = @import("aggregate_provider.zig").marker(module, f) catch {
        failure.* = .{ .function = f.name, .reason = "invalid compiler-only provider lifetime marker" };
        return error.InvalidIr;
    };
    _ = @import("borrowed_provider.zig").declaration(module, f) catch {
        failure.* = .{ .function = f.name, .reason = "invalid borrowed provider context declaration" };
        return error.InvalidIr;
    };
    _ = @import("borrow_selection.zig").declaration(module, f) catch {
        failure.* = .{ .function = f.name, .reason = "invalid borrowed selection marker declaration" };
        return error.InvalidIr;
    };
    for (f.signature.params, 0..) |param, i| {
        const span = f.signature.passing.viewAt(i);
        const invalid_span = span and !Verifier.admittedView(module, f.signature, i);
        const invalid_type = !module.valid(param) or invalid_span;
        const invalid_borrow = module.containsBorrow(param) and !readOnlyParameter(module, param);
        if (invalid_type or invalid_borrow) {
            failure.* = .{ .function = f.name, .reason = "invalid parameter type or extern span admission" };
            return error.InvalidIr;
        }
    }
    const out_of_range = !f.signature.passing.valid(f.signature.params.len);
    const internal_span = f.signature.linkage == .internal and f.signature.passing.hasViews();
    if (!module.valid(f.signature.ret) or out_of_range or internal_span) {
        failure.* = .{ .function = f.name, .reason = "invalid result type or extern span admission" };
        return error.InvalidIr;
    }

    if (!module.validBorrow(f.signature)) {
        failure.* = .{ .function = f.name, .reason = "invalid declared borrowed result paths or owner sources" };
        return error.InvalidIr;
    }
}

/// Whether every type `compound` names is a type of `module`.
fn namesValidTypes(module: *const ir.Module, compound: ir.Compound) bool {
    return switch (compound) {
        .list, .list_view, .box, .borrowed => |inner| module.valid(inner),
        .dict => |dict| module.valid(dict.key) and module.valid(dict.value),
        .array => |array| module.valid(array.elem),
        .record, .@"union" => |parts| for (parts) |part| {
            if (!module.valid(part)) break false;
        } else true,
        .@"fn" => |sig| module.valid(sig.ret) and for (sig.params) |param| {
            if (!module.valid(param)) break false;
        } else true,
    };
}

/// The compound kind of `ty` when it is a type of `module`; null for a scalar or a number the table does not hold.
fn validKind(module: *const ir.Module, ty: ir.Type) ?std.meta.Tag(ir.Compound) {
    if (!module.valid(ty)) return null;
    return module.kind(ty);
}

/// Whether `ty` is a task thunk's environment (FR58), or the record that environment boxes: the one place a view is
/// stored. `g.submit` lends a view parameter as the view itself; the thunk reads it once, and the group joins before the
/// lending call returns, so the view never outlives the parameter. Every other field that holds a borrow is refused.
fn taskEnvironment(module: *const ir.Module, ty: ir.Type) bool {
    for (module.functions.items) |function| {
        if (@import("stable_names.zig").generatedRole(function.name) != .task_thunk) continue;
        if (function.signature.params.len != 1) continue;
        const env = function.signature.params[0];
        if (validKind(module, env) != .box) continue;
        const record = module.compound(env).box;
        if (ty != env and ty != record) continue;
        if (validKind(module, record) != .record) return false;
        for (module.compound(record).record) |field| if (module.containsBorrow(field) and !module.isView(field)) return false;
        return true;
    }
    return false;
}

fn canonicalTransient(module: *const ir.Module, ty: ir.Type) bool {
    if (borrowedOption(module, ty)) return true;
    for (module.functions.items) |function| {
        for (function.signature.params) |parameter| if (parameterSpineContains(module, parameter, ty)) return true;
        const contract = function.signature.borrow;
        if (contract.sources.len == 0) continue;
        var current = function.signature.ret;
        if (current == ty) return true;
        for (contract.path) |step| {
            current = module.projectedType(current, &.{step}) orelse break;
            if (current == ty) return true;
        }
    }
    return false;
}

/// An option of a read-only borrowed overlay (`borrowed[T]` of managed storage) or of a list
/// view, wherever it appears: a `const` borrow of an optional place (`const entry = by_ref[key]`,
/// `const poly = saved.poly` over a list field) is one in a local. Storage that would hold one
/// (a list, a record field) is a compound of its own and stays refused, and a string view
/// (`str_view`) has no storable layout, so an option of one is admitted only where a signature
/// names it.
fn borrowedOption(module: *const ir.Module, ty: ir.Type) bool {
    if (!module.valid(ty) or module.kind(ty) != .@"union") return false;
    const cases = module.compound(ty).@"union";
    return cases.len == 2 and cases[0] == .void and (module.isBorrowed(cases[1]) or validKind(module, cases[1]) == .list_view);
}

fn readOnlyParameter(module: *const ir.Module, ty: ir.Type) bool {
    if (module.isView(ty) or module.isBorrowed(ty)) return true;
    if (!module.valid(ty) or module.kind(ty) != .@"union") return false;
    const cases = module.compound(ty).@"union";
    if (cases.len != 2) return false;
    for (cases) |case| {
        if (module.containsBorrow(case)) {
            if (!readOnlyParameter(module, case)) return false;
        } else if (module.managed(case)) return false;
    }
    return true;
}

fn parameterSpineContains(module: *const ir.Module, root: ir.Type, wanted: ir.Type) bool {
    if (!module.containsBorrow(root) or !readOnlyParameter(module, root)) return false;
    if (root == wanted) return true;
    if (validKind(module, root) != .@"union") return false;
    for (module.compound(root).@"union") |child| if (parameterSpineContains(module, child, wanted)) return true;
    return false;
}

/// Verify one function.
pub fn verifyFunction(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, failure: *Failure) Error!void {
    return verifyFunctionWith(arena, module, f, failure, .{});
}

/// `verifyFunction` with the union-tag rule's mode chosen (`selka verify-ir`, the gate's check, always refuses).
pub fn verifyFunctionWith(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, failure: *Failure, tags: TagCheck) Error!void {
    var v: Verifier = .{ .arena = arena, .module = module, .f = f, .failure = failure, .tags = tags };
    failure.* = .{ .function = f.name };
    try v.run();
}

/// Verify that `plan`'s vector part, emitted on the edge from its preheader, reads
/// only values that exist there: every operand of a lane instruction that is not
/// itself a lane value, every select arm, and the loop's start, bound and initial
/// sum must be constants or dominate the preheader.
pub fn verifyPlan(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, plan: vector.Plan, failure: *Failure) Error!void {
    var v: Verifier = .{ .arena = arena, .module = module, .f = f, .failure = failure };
    failure.* = .{ .function = f.name };
    try v.structure();
    const carried = plan.carried;
    for ([_]ir.Ref{ carried.start, carried.bound, carried.acc_init }) |value| try v.beforeLoop(plan, value);
    for (plan.body) |ref| {
        const inst = f.inst(ref);
        if (inst.op == .phi) continue;
        // A lane read indexes by the vector counter; only its list comes from outside.
        if (inst.op == .list_get) {
            try v.beforeLoop(plan, inst.a);
            continue;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| {
            if (std.mem.indexOfScalar(ir.Ref, plan.body, f.resolve(operands.get(i))) != null) continue;
            try v.beforeLoop(plan, operands.get(i));
        }
    }
    for (plan.selects) |select| {
        for ([_]ir.Ref{ select.condition, select.then_value, select.else_value }) |value| {
            if (std.mem.indexOfScalar(ir.Ref, plan.body, f.resolve(value)) != null) continue;
            try v.beforeLoop(plan, value);
        }
    }
}

/// One instruction with its operand types resolved, for the signature checks.
const Shape = struct { inst: ir.Inst, extra: []const ir.Ref, a: ir.Type, b: ir.Type };

/// Where an instruction sits.
const Position = struct { block: u32, index: u32 };

/// The control-flow facts the checks need.
const Graph = struct {
    reachable: []bool = &.{},
    /// Immediate dominators of reachable blocks (the entry's is itself).
    idom: []u32 = &.{},
    /// Reverse-postorder number of each reachable block.
    order: []u32 = &.{},
    /// Whether a block, reachable or not, lists the instruction.
    listed: []bool = &.{},
};

const Verifier = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    failure: *Failure,
    graph: Graph = .{},
    /// Where each instruction listed in a reachable block sits.
    position: []?Position = &.{},
    /// The union-tag rule's mode.
    tags: TagCheck = .{},

    fn fail(self: *Verifier, block: ?usize, inst: ?ir.Ref, comptime format: []const u8, args: anytype) Error {
        self.failure.block = if (block) |b| @intCast(b) else Failure.none_index;
        self.failure.inst = if (inst) |i| @intCast(i.index()) else Failure.none_index;
        self.failure.reason = try std.fmt.allocPrint(self.arena, format, args);
        return error.InvalidIr;
    }

    fn run(self: *Verifier) Error!void {
        try self.structure();
        // Constants and parameters are defined outside every block, so no block lists them: check each one of the table.
        for (self.f.insts.items, 0..) |inst, i| {
            if (inst.op.isConstant()) try self.signature(0, @fromBackingInt(@intCast(i)), inst);
        }
        for (self.f.blocks.items, 0..) |block, b| {
            if (!self.graph.reachable[b]) continue;
            for (block.insts.items, 0..) |ref, at| {
                const inst = self.f.inst(ref);
                if (inst.op == .copy) continue;
                try self.signature(b, ref, inst);
                if (inst.data != flags.place_copy and @import("zero_rc.zig").shallowManagedCopy(self.module, inst))
                    return self.fail(b, ref, "zero-RC managed children cannot be duplicated by a shallow container copy", .{});
                try self.dominance(b, @intCast(at), ref, inst);
            }
        }
        // A union payload is read only under its own tag (F-VL-10, `verify_union_tags.zig`).
        const reads = try union_tags.countReads(self.arena, self.module, self.f, self.graph.reachable);
        if (reads.first) |site| switch (self.tags.mode) {
            .refuse => {
                const where: ?ir.Ref = if (site.ref == .none) null else site.ref;
                return self.fail(site.block, where, "union payload read without a test of its tag", .{});
            },
            .count => if (self.tags.counted) |counted| {
                counted.* += reads.unjustified;
            },
        };
    }

    // ---- structure ------------------------------------------------------------------

    /// Blocks, terminators, predecessor lists and phi arity; then reachability and dominators.
    fn structure(self: *Verifier) Error!void {
        const f = self.f;
        if (f.blocks.items.len == 0) return self.fail(null, null, "a function with a body has no blocks", .{});
        // The function starts in its entry with no edge taken, so a phi there would have no operand to read.
        if (f.blocks.items[0].preds.items.len != 0) return self.fail(0, null, "the entry block has predecessors", .{});
        for (f.signature.params) |param| if (!self.module.valid(param)) return self.fail(null, null, "parameter type is not interned", .{});

        try self.reach();
        self.graph.listed = try self.arena.alloc(bool, f.insts.items.len);
        @memset(self.graph.listed, false);
        for (f.blocks.items) |block| for (block.insts.items) |ref| {
            if (ref != .none and ref.index() < f.insts.items.len) self.graph.listed[ref.index()] = true;
        };
        self.position = try self.arena.alloc(?Position, f.insts.items.len);
        @memset(self.position, null);
        for (f.blocks.items, 0..) |block, b| {
            if (!self.graph.reachable[b]) continue;
            const insts = block.insts.items;
            if (insts.len == 0) return self.fail(b, null, "empty block", .{});
            var phis_done = false;
            for (insts, 0..) |ref, at| {
                if (ref == .none or ref.index() >= f.insts.items.len) return self.fail(b, null, "block lists an instruction that does not exist", .{});
                if (self.position[ref.index()] != null) return self.fail(b, ref, "instruction listed in two places", .{});
                self.position[ref.index()] = .{ .block = @intCast(b), .index = @intCast(at) };
                const inst = f.inst(ref);
                const last = at + 1 == insts.len;
                if (inst.op.terminates() != last) return self.fail(b, ref, "{s}", .{if (last) "block does not end in a terminator" else "terminator before the end of its block"});
                if (inst.op == .copy) continue;
                if (inst.op == .phi) {
                    if (phis_done) return self.fail(b, ref, "phi after a non-phi instruction", .{});
                    const arity = ir.ExtraSlice.unpack(inst.data).len;
                    if (arity != block.preds.items.len) return self.fail(b, ref, "phi has {d} operands for {d} predecessors", .{ arity, block.preds.items.len });
                } else phis_done = true;
            }
            try self.edges(b);
        }
        try self.dominators();
    }

    fn successors(self: *Verifier, b: usize) [2]?u32 {
        const insts = self.f.blocks.items[b].insts.items;
        if (insts.len == 0) return .{ null, null };
        // A reference out of range is refused when its block is listed (`structure`); here it ends nothing.
        const ref = insts[insts.len - 1];
        if (ref == .none or ref.index() >= self.f.insts.items.len) return .{ null, null };
        const last = self.f.inst(ref);
        return switch (last.op) {
            .jump => .{ @truncate(last.data), null },
            .branch => blk: {
                const targets = ir.unpackTargets(last.data);
                break :blk .{ @backingInt(targets.then), @backingInt(targets.otherwise) };
            },
            else => .{ null, null },
        };
    }

    fn reach(self: *Verifier) Error!void {
        const count = self.f.blocks.items.len;
        self.graph.reachable = try self.arena.alloc(bool, count);
        @memset(self.graph.reachable, false);
        var stack: std.ArrayList(u32) = .empty;
        self.graph.reachable[0] = true;
        try stack.append(self.arena, 0);
        while (stack.pop()) |b| {
            for (self.successors(b)) |maybe| {
                const s = maybe orelse continue;
                if (s >= count) return self.fail(b, null, "branch to block b{d}, which does not exist", .{s});
                if (self.graph.reachable[s]) continue;
                self.graph.reachable[s] = true;
                try stack.append(self.arena, s);
            }
        }
    }

    /// Each edge `b -> s` appears in `s`'s predecessors as often as `b` targets `s`,
    /// and every predecessor of a reachable block targets it.
    fn edges(self: *Verifier, b: usize) Error!void {
        const out = self.successors(b);
        for (out, 0..) |maybe, i| {
            const s = maybe orelse continue;
            const both = out[0] != null and out[1] != null and out[0].? == out[1].?;
            if (i == 1 and both) continue;
            const wanted: usize = if (both) 2 else 1;
            const listed = std.mem.count(ir.BlockId, self.f.blocks.items[s].preds.items, &.{@fromBackingInt(@intCast(b))});
            if (listed != wanted) return self.fail(b, null, "edge to b{d} appears {d} times in its predecessors", .{ s, listed });
        }
        for (self.f.blocks.items[b].preds.items) |pred| {
            if (pred.index() >= self.f.blocks.items.len) return self.fail(b, null, "predecessor b{d} does not exist", .{pred.index()});
            if (!self.graph.reachable[pred.index()]) continue;
            const targets = self.successors(pred.index());
            const here: u32 = @intCast(b);
            if (targets[0] != here and targets[1] != here) return self.fail(b, null, "predecessor b{d} does not branch here", .{pred.index()});
        }
    }

    /// Cooper, Harvey and Kennedy's iterative dominators over reachable blocks.
    fn dominators(self: *Verifier) Error!void {
        const count = self.f.blocks.items.len;
        const undefined_order = std.math.maxInt(u32);
        self.graph.order = try self.arena.alloc(u32, count);
        @memset(self.graph.order, undefined_order);
        // Postorder by an explicit DFS.
        var post: std.ArrayList(u32) = .empty;
        const visited = try self.arena.alloc(bool, count);
        @memset(visited, false);
        var stack: std.ArrayList(struct { block: u32, next: u8 }) = .empty;
        try stack.append(self.arena, .{ .block = 0, .next = 0 });
        visited[0] = true;
        while (stack.items.len != 0) {
            const top = &stack.items[stack.items.len - 1];
            const out = self.successors(top.block);
            if (top.next < 2) {
                const which = top.next;
                top.next += 1;
                const s = out[which] orelse continue;
                if (visited[s]) continue;
                visited[s] = true;
                try stack.append(self.arena, .{ .block = s, .next = 0 });
                continue;
            }
            try post.append(self.arena, top.block);
            _ = stack.pop();
        }
        const rpo = post.items;
        std.mem.reverse(u32, rpo);
        for (rpo, 0..) |b, i| self.graph.order[b] = @intCast(i);
        self.graph.idom = try self.arena.alloc(u32, count);
        @memset(self.graph.idom, undefined_order);
        self.graph.idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            for (rpo[1..]) |b| {
                var chosen: u32 = undefined_order;
                for (self.f.blocks.items[b].preds.items) |pred_id| {
                    const pred: u32 = @intCast(pred_id.index());
                    if (!self.graph.reachable[pred] or self.graph.idom[pred] == undefined_order) continue;
                    chosen = if (chosen == undefined_order) pred else self.intersect(pred, chosen);
                }
                if (chosen != self.graph.idom[b]) {
                    self.graph.idom[b] = chosen;
                    changed = true;
                }
            }
        }
    }

    fn intersect(self: *Verifier, x: u32, y: u32) u32 {
        var a = x;
        var b = y;
        while (a != b) {
            while (self.graph.order[a] > self.graph.order[b]) a = self.graph.idom[a];
            while (self.graph.order[b] > self.graph.order[a]) b = self.graph.idom[b];
        }
        return a;
    }

    /// Whether block `a` dominates block `b` (both reachable).
    fn dominatesBlock(self: *Verifier, a: u32, b: u32) bool {
        var x = b;
        while (true) {
            if (x == a) return true;
            if (x == 0) return false;
            x = self.graph.idom[x];
        }
    }

    // ---- dominance --------------------------------------------------------------------

    fn dominance(self: *Verifier, b: usize, at: u32, ref: ir.Ref, inst: ir.Inst) Error!void {
        const f = self.f;
        if (inst.op == .phi) {
            for (f.operands(inst.data), f.blocks.items[b].preds.items) |operand, pred| {
                if (!self.graph.reachable[pred.index()]) continue;
                // A phi operand is read at the end of its predecessor.
                const end: u32 = @intCast(f.blocks.items[pred.index()].insts.items.len);
                try self.available(b, ref, operand, .{ .block = @intCast(pred.index()), .index = end });
            }
            return;
        }
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| try self.available(b, ref, operands.get(i), .{ .block = @intCast(b), .index = at });
    }

    /// Whether `operand` is defined before `use` on every path from the entry.
    fn available(self: *Verifier, b: usize, user: ir.Ref, raw: ir.Ref, use: Position) Error!void {
        if (raw == .none) return self.fail(b, user, "missing operand", .{});
        if (raw.index() >= self.f.insts.items.len) return self.fail(b, user, "operand %{d} does not exist", .{raw.index()});
        const operand = self.resolved(raw) orelse return self.fail(b, user, "operand %{d} forwards to nothing", .{raw.index()});
        // A constant no block lists is materialized at each use. One a block lists (a comparison the facts folded) is an
        // instruction of that block, as the fact certificate describes it, so its uses follow dominance like any other's.
        if (self.f.inst(operand).op.isConstant() and !self.graph.listed[operand.index()]) return;
        const def = self.position[operand.index()] orelse return self.fail(b, user, "operand %{d} is not defined in a reachable block", .{operand.index()});
        if (def.block == use.block) {
            if (def.index < use.index) return;
            return self.fail(b, user, "operand %{d} is used before its definition", .{operand.index()});
        }
        if (!self.dominatesBlock(def.block, use.block)) return self.fail(b, user, "operand %{d} (b{d}) does not dominate its use in b{d}", .{ operand.index(), def.block, use.block });
    }

    /// A vector plan's outside value must exist on the preheader's edge.
    fn beforeLoop(self: *Verifier, plan: vector.Plan, raw: ir.Ref) Error!void {
        const pre: u32 = @intCast(plan.preheader.index());
        const end: u32 = @intCast(self.f.blocks.items[pre].insts.items.len);
        if (!self.graph.reachable[pre]) return self.fail(pre, null, "vector plan preheader is unreachable", .{});
        try self.available(pre, raw, raw, .{ .block = pre, .index = end });
    }

    // ---- types ------------------------------------------------------------------------

    /// The type of the value `raw` stands for; `no_type`, which no module has, when it resolves to nothing.
    fn typeOf(self: *Verifier, raw: ir.Ref) ir.Type {
        const value = self.resolved(raw) orelse return no_type;
        return self.f.inst(value).ty;
    }

    /// A number no module interns: the type of a value that does not exist.
    const no_type: ir.Type = @fromBackingInt(std.math.maxInt(u32));

    /// `ir.Function.resolve` bounded: null for a forwarding chain that leaves the table, ends in nothing or comes back to itself.
    fn resolved(self: *Verifier, raw: ir.Ref) ?ir.Ref {
        var current = raw;
        for (0..self.f.insts.items.len + 1) |_| {
            if (current == .none or current.index() >= self.f.insts.items.len) return null;
            const inst = self.f.inst(current);
            if (inst.op != .copy) return current;
            current = inst.a;
        }
        return null;
    }

    fn isInteger(ty: ir.Type) bool {
        return ty.integer() != null;
    }

    /// The compound structure of `ty` when it is of kind `k`.
    /// Whether reading `inst_ty` out of a `source` (a list, a list view, or a
    /// raw-octet value read as one byte) is the element read the source declares.
    fn elementRead(self: *Verifier, source: ir.Type, inst_ty: ir.Type) bool {
        if (self.compoundOf(source, .list)) |element| return element == inst_ty;
        if (self.compoundOf(source, .list_view)) |element| return element == inst_ty;
        return (source == .bytes or source == .byte_buffer or source == .str_view or source == .bytes_view) and inst_ty == .u8;
    }

    /// Whether `ty` is a list, a list view, or one of the raw-octet values whose
    /// length is a block length.
    fn listOrView(self: *Verifier, ty: ir.Type) bool {
        if (ty == .bytes or ty == .byte_buffer or ty.isSpan()) return true;
        return self.compoundOf(ty, .list) != null or self.compoundOf(ty, .list_view) != null;
    }

    /// A binary64 or binary32 scalar, or a vector of either: the operand types of `fadd` and friends.
    fn floatLanes(self: *Verifier, ty: ir.Type) bool {
        if (ty == .f64 or ty == .f32) return true;
        const lanes = self.compoundOf(ty, .array) orelse return false;
        return lanes.vector and (lanes.elem == .f64 or lanes.elem == .f32);
    }

    /// A vector of Booleans: the mask a `Simd` comparison answers.
    fn maskOf(self: *Verifier, ty: ir.Type) bool {
        const lanes = self.compoundOf(ty, .array) orelse return false;
        return lanes.vector and lanes.elem == .bool;
    }

    /// A vector of fixed-width integers: the operand type of checked and wrapping lane arithmetic.
    fn integerLanes(self: *Verifier, ty: ir.Type) bool {
        const lanes = self.compoundOf(ty, .array) orelse return false;
        return lanes.vector and isInteger(lanes.elem);
    }

    /// Whether `from` and `to` are vectors of one length whose lanes convert between binary32 and binary64.
    fn convertsLanes(self: *Verifier, to: ir.Type, from: ir.Type) bool {
        const target = self.compoundOf(to, .array) orelse return false;
        const source = self.compoundOf(from, .array) orelse return false;
        return target.vector and source.vector and target.n == source.n and
            ((target.elem == .f64 and source.elem == .f32) or (target.elem == .f32 and source.elem == .f64));
    }

    /// The mask over integer lanes `operand`: a Boolean vector of the same length.
    fn maskOver(self: *Verifier, mask: ir.Type, operand: ir.Type) bool {
        const lanes = self.compoundOf(operand, .array) orelse return false;
        const bools = self.compoundOf(mask, .array) orelse return false;
        return bools.vector and bools.elem == .bool and bools.n == lanes.n;
    }

    fn compoundOf(self: *Verifier, ty: ir.Type, comptime k: std.meta.Tag(ir.Compound)) ?@FieldType(ir.Compound, @tagName(k)) {
        const stored = self.module.storageType(ty);
        if (!self.module.valid(stored) or self.module.kind(stored) != k) return null;
        return @field(self.module.compound(stored), @tagName(k));
    }

    fn signature(self: *Verifier, b: usize, ref: ir.Ref, inst: ir.Inst) Error!void {
        const f = self.f;
        if (!self.module.valid(inst.ty)) return self.fail(b, ref, "result type is not interned", .{});
        if (inst.op.hasExtra()) {
            const extra = ir.ExtraSlice.unpack(inst.data);
            if (extra.start > f.extra.items.len or extra.len > f.extra.items.len - extra.start) return self.fail(b, ref, "extra operands are out of range", .{});
        }
        // An operation that reads only its extra list has nothing in `a` and `b` (a call's `a` is its callee): the fact
        // certificate lists every field it finds there as a register the instruction reads.
        const extra_only = inst.op == .print or inst.op == .record_make or inst.op == .call;
        if (extra_only and ((inst.op != .call and inst.a != .none) or inst.b != .none)) return self.fail(b, ref, "{s} reads no operand in a or b", .{@tagName(inst.op)});
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| {
            const operand = operands.get(i);
            if (operand == .none or operand.index() >= f.insts.items.len) return self.fail(b, ref, "missing or out-of-range operand", .{});
        }
        // Every rule below reads its operands' types and asks the module about them.
        for (0..operands.len()) |i| {
            const value = self.resolved(operands.get(i)) orelse return self.fail(b, ref, "operand %{d} forwards to nothing", .{operands.get(i).index()});
            if (!self.module.valid(f.inst(value).ty)) return self.fail(b, ref, "operand %{d} has no type of the module", .{value.index()});
        }
        // `a` and `b` are typed where they are value operands: not for a jump, nor for the operations that read only their
        // extra list (a call's `a` is its callee).
        const direct = inst.op != .jump and inst.op != .phi and inst.op != .call and inst.op != .print and inst.op != .record_make;
        const shape: Shape = .{
            .inst = inst,
            .extra = operands.extra,
            .a = if (direct and inst.a != .none) self.typeOf(inst.a) else .void,
            .b = if (direct and inst.b != .none) self.typeOf(inst.b) else .void,
        };
        try self.viewUses(b, ref, shape);
        if (inst.op == .dict_insert and !self.insertProbe(shape)) return self.fail(b, ref, "dict_insert probe must come from dict_find of the same dictionary and key", .{});
        const ok = self.s3Signature(shape) orelse self.s2Signature(shape) orelse self.scalarSignature(shape) orelse self.aggregateSignature(shape) orelse self.controlSignature(shape);
        if (!ok) return self.fail(b, ref, "{s} does not match its signature", .{@tagName(inst.op)});
        if (inst.op == .ret and self.f.signature.borrow.sources.len != 0) {
            if (!try @import("borrow_result.zig").valid(self.arena, self.module, self.f, inst.a))
                return self.fail(b, ref, "returned borrowed payload is not derived from its declared argument or final owner", .{});
        }
    }

    fn viewUses(self: *Verifier, b: usize, ref: ir.Ref, s: Shape) Error!void {
        const boundary_view = (s.inst.op == .param or s.inst.op == .call or s.inst.op == .undef);
        const local_view = s.inst.op == .str_view_of or s.inst.op == .str_slice_view or s.inst.op == .str_slice_bytes_view or
            s.inst.op == .list_view_of or s.inst.op == .list_slice_view or s.inst.op == .copy or s.inst.op == .phi or
            s.inst.op == .record_get or s.inst.op == .union_payload;
        if (self.module.isView(s.inst.ty) and !(boundary_view or local_view))
            return self.fail(b, ref, "a view may only be defined by a view operation, a copy or a phi", .{});
        const operands = self.f.valueOperands(s.inst);
        for (0..operands.len()) |i| {
            const operand = self.typeOf(operands.get(i));
            if (!self.module.isView(operand)) continue;
            // A bytes view prints as bytes: only a text view is printed in place (view_materialize.admitted).
            const bytes_print = s.inst.op == .print and @import("view_materialize.zig").viewIsBytes(self.f, operands.get(i), 0);
            const admitted = if (operand == .str_view) self.textViewUse(s, i) and !bytes_print else if (operand == .bytes_view) self.bytesViewUse(s, i) else self.listViewUse(s, i);
            if (!admitted) return self.fail(b, ref, "a view escapes through {s}", .{@tagName(s.inst.op)});
        }
    }

    /// A borrowed text span is read by the text operations, a dictionary probe, a
    /// print, or a parameter that takes a span.
    fn textViewUse(self: *Verifier, s: Shape, i: usize) bool {
        return switch (s.inst.op) {
            .str_from_view, .str_len, .list_len, .str_parse_int, .str_view_of, .copy => i == 0,
            // A parameter's frame header reads its span in place (C9 S1).
            .text_frame => i == 1,
            // A borrowed record's frame block reads the parameter's view in place (RB1).
            .block_frame => i == 0,
            .list_get => i == 0 and s.inst.ty == .u8,
            .buffer_append => i == 1,
            // A character read of a view decodes in place (C9 S1, fuse_text_scalar).
            .str_code => i == 0,
            .str_width => i == 0,
            // A fixed-width read of a view loads its octets in place (the viewUses list in view_materialize.zig).
            .byte_load => i == 0,
            .str_append_char => i == 1,
            // A view merged at a branch: every incoming slot is the phi's value.
            .phi => s.inst.ty == .str_view,
            .ret, .print => true,
            .union_make, .record_make => self.module.containsBorrow(s.inst.ty),
            .dict_find => i == 1 and if (self.compoundOf(s.a, .dict)) |dict| dict.key == .str else false,
            .call => s.inst.a.index() < self.module.functions.items.len and admittedView(self.module, self.module.functions.items[s.inst.a.index()].signature, i),
            // Operand 0 is the function value; the arguments follow, so argument `i - 1` is the callable's parameter.
            .call_indirect => i >= 1 and if (self.compoundOf(s.a, .@"fn")) |sig| i - 1 < sig.params.len and sig.params[i - 1] == .str_view else false,
            else => false,
        };
    }

    /// A borrowed bytes span (C9 bytes) is read by the octet operations: its length, an element read, a nested
    /// view of part of it, a copy, a phi, or a parameter that takes a span. It is never printed or returned as an owned value.
    /// `block_frame` (RB1): a text, bytes or list block of view `a`, with the view's C9 owner `b` (none for bytes).
    fn blockFrameSignature(self: *Verifier, inst: ir.Inst, s: Shape) bool {
        if (inst.ty == .str) return s.a == .str_view and inst.b != .none and s.b == .str;
        if (inst.ty == .bytes) return s.a == .bytes_view and inst.b == .none;
        const element = (self.compoundOf(inst.ty, .list) orelse return false);
        const viewed = self.compoundOf(s.a, .list_view) orelse return false;
        return element == viewed and inst.b != .none and s.b == inst.ty;
    }

    fn bytesViewUse(self: *Verifier, s: Shape, i: usize) bool {
        return switch (s.inst.op) {
            // A borrowed record's frame block reads the parameter's view in place (RB1).
            .block_frame => i == 0,
            .str_len, .list_len, .list_get, .str_view_of, .copy => i == 0,
            .ret => true,
            .union_make, .record_make => self.module.containsBorrow(s.inst.ty),
            // A fixed-width read of a bytes view loads its octets in place (build_byte_load).
            .byte_load => i == 0,
            // The source of an inline append is read in place (C9 bytes), as a text source is.
            .buffer_append => i == 1,
            // A bytes view is a dictionary probe key of a bytes table: the span probe hashes and compares its octets (CX2).
            .dict_find => i == 1 and if (self.compoundOf(s.a, .dict)) |dict| dict.key == .bytes else false,
            .phi => s.inst.ty.isSpan(),
            .call => s.inst.a.index() < self.module.functions.items.len and admittedView(self.module, self.module.functions.items[s.inst.a.index()].signature, i),
            .call_indirect => i >= 1 and if (self.compoundOf(s.a, .@"fn")) |sig| i - 1 < sig.params.len and sig.params[i - 1] == .bytes_view else false,
            else => false,
        };
    }

    /// A list view names a list's elements: `len`, an element read, a nested view
    /// of part of it, a phi, or a parameter that takes a view. It is never stored,
    /// printed or returned as an owned list.
    fn listViewUse(self: *Verifier, s: Shape, i: usize) bool {
        return switch (s.inst.op) {
            // A borrowed record's frame block reads the parameter's view in place (RB1).
            .block_frame => i == 0,
            .list_len, .list_get, .list_get_field, .list_slice_view, .copy, .list_copy => i == 0,
            .ret => true,
            .union_make, .record_make => self.module.containsBorrow(s.inst.ty),
            .phi => self.compoundOf(s.inst.ty, .list_view) != null,
            .call => s.inst.a.index() < self.module.functions.items.len and admittedView(self.module, self.module.functions.items[s.inst.a.index()].signature, i),
            // Operand 0 is the function value; a list view is admitted at a callable's list-view parameter (C9 lists).
            .call_indirect => i >= 1 and if (self.compoundOf(s.a, .@"fn")) |sig| i - 1 < sig.params.len and validKind(self.module, sig.params[i - 1]) == .list_view else false,
            else => false,
        };
    }

    fn admittedView(module: *const ir.Module, sig: ir.Signature, index: usize) bool {
        // A callee's parameter types are checked by its own header, which may come after this caller: ask only valid types.
        if (sig.linkage == .internal and index < sig.params.len and (sig.params[index].isSpan() or validKind(module, sig.params[index]) == .list_view)) return true;
        // A `str` or `bytes` span parameter: both are one block layout (C9 2b, the split helper takes bytes too).
        const text_or_bytes = index < sig.params.len and (sig.params[index] == .str or sig.params[index] == .bytes or validKind(module, sig.params[index]) == .list_view);
        return sig.linkage != .internal and text_or_bytes and sig.passing.viewAt(index) and !sig.passing.takes(index);
    }

    fn insertProbe(self: *Verifier, s: Shape) bool {
        if (s.inst.b == .none or s.extra.len != 2) return false;
        const probe = self.f.inst(self.resolved(s.inst.b) orelse return false);
        if (probe.op != .dict_find or self.resolved(probe.a) != self.resolved(s.inst.a)) return false;
        const looked_up = self.resolved(probe.b);
        const key = self.resolved(s.extra[0]) orelse return false;
        if (looked_up == key) return true;
        // A borrowed span's probe serves the key materialized from that same span: both
        // hash and compare the same octets (NEW-CORE-S1-VIEW-1).
        const materialized = self.f.inst(key);
        return materialized.op == .str_from_view and self.resolved(materialized.a) == looked_up;
    }

    fn s2Signature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .dict_new => self.compoundOf(inst.ty, .dict) != null and s.a == .u64,
            .dict_len, .dict_entries => self.compoundOf(s.a, .dict) != null and inst.ty == .u64,
            .dict_find => if (self.compoundOf(s.a, .dict)) |dict| inst.ty == .i64 and (s.b == dict.key or (dict.key == .str and s.b == .str_view) or (dict.key == .bytes and s.b == .bytes_view)) else false,
            .dict_entry_key => if (self.compoundOf(s.a, .dict)) |dict| inst.ty == dict.key and s.b == .i64 else false,
            .dict_entry_value => if (self.compoundOf(s.a, .dict)) |dict| inst.ty == dict.value and s.b == .i64 else false,
            .dict_set_value => if (self.compoundOf(s.a, .dict)) |dict| inst.ty == s.a and s.b == .i64 and self.typesMatch(s.extra, &.{dict.value}) else false,
            .dict_insert => if (self.compoundOf(s.a, .dict)) |dict| inst.ty == s.a and s.b == .i64 and self.typesMatch(s.extra, &.{ dict.key, dict.value }) else false,
            .dict_remove => self.compoundOf(s.a, .dict) != null and inst.ty == s.a and s.b == .i64,
            .dict_entry_live => self.compoundOf(s.a, .dict) != null and inst.ty == .bool and s.b == .i64,
            .dict_copy, .dict_clear => self.compoundOf(s.a, .dict) != null and inst.ty == s.a,
            .str_char => s.a == .str and s.b == .u64 and inst.ty == .str,
            .str_width => (s.a == .str or s.a == .str_view) and s.b == .u64 and inst.ty == .u64,
            .str_code => (s.a == .str or s.a == .str_view) and s.b == .u64 and inst.ty == .u32,
            .str_append => inst.ty == .str and s.a == .str and s.b == .str,
            .str_append_char => inst.ty == .str and s.a == .str and (s.b == .str or s.b == .str_view) and self.typesMatch(s.extra, &.{.u64}),
            .str_slice => inst.ty == .str and s.a == .str and s.b == .i64 and self.typesMatch(s.extra, &.{.i64}),
            .str_view_of => ((inst.ty == .str_view and (s.a == .str or s.a == .byte_buffer or s.a == .str_view)) or (inst.ty == .bytes_view and (s.a == .bytes or s.a == .bytes_view))) and s.b == .u64 and self.typesMatch(s.extra, &.{.u64}),
            .str_slice_view => ((inst.ty == .str_view and s.a == .str) or (inst.ty == .bytes_view and (s.a == .bytes or s.a == .byte_buffer))) and s.b == .i64 and self.typesMatch(s.extra, &.{.i64}),
            .str_slice_bytes_view => inst.ty == .str_view and s.a == .str and s.b == .i64 and self.typesMatch(s.extra, &.{.i64}),
            .str_from_view => inst.ty == .str and s.a == .str_view,
            // One fixed-width read of a view at an unsigned offset; floats are little-endian only (`data` 0).
            .byte_load => s.a == .bytes_view and s.b == .u64 and inst.data <= 1 and switch (inst.ty) {
                .u16, .i16, .u32, .i32, .u64, .i64 => true,
                .u8, .i8, .f32, .f64 => inst.data == 0,
                else => false,
            },
            .text_frame => inst.ty == .str and s.a == .str and s.b == .str_view,
            .list_sort => self.compoundOf(s.a, .list) != null and inst.ty == s.a and s.b == .bool,
            .array_get => if (self.compoundOf(s.a, .array)) |array| inst.ty == array.elem and isInteger(s.b) else false,
            .array_from_bytes => if (self.compoundOf(inst.ty, .array)) |array| array.elem == .u8 and s.a == .bytes else false,
            .array_set => if (self.compoundOf(s.a, .array)) |array| inst.ty == s.a and isInteger(s.b) and self.typesMatch(s.extra, &.{array.elem}) else false,
            .func_ref => if (self.compoundOf(inst.ty, .@"fn")) |sig| inst.data < self.module.functions.items.len and sameSignature(sig, self.module.functions.items[@intCast(inst.data)].signature) and sig.linkage == .internal else false,
            .call_indirect => if (self.compoundOf(s.a, .@"fn")) |sig| sig.linkage == .internal and inst.ty == sig.ret and self.typesMatch(s.extra, sig.params) else false,
            else => null,
        };
    }

    fn s3Signature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .buffer_new => inst.ty == .byte_buffer and s.a == .u64,
            .buffer_copy, .buffer_pop => inst.ty == .byte_buffer and s.a == .byte_buffer,
            .buffer_push => inst.ty == .byte_buffer and s.a == .byte_buffer and s.b == switch (inst.data) {
                0 => ir.Type.u8,
                flags.buffer_append_int => ir.Type.i64,
                flags.buffer_append_float => ir.Type.f64,
                else => return false,
            },
            .buffer_set => inst.ty == .byte_buffer and s.a == .byte_buffer and isInteger(s.b) and self.typesMatch(s.extra, &.{.u8}),
            .shift_left, .shift_right, .saturating_add => isInteger(inst.ty) and s.a == inst.ty and s.b == inst.ty,
            .float_unary => ((inst.ty == .f64 or inst.ty == .f32) or (self.floatLanes(inst.ty) and inst.data == @backingInt(ir.FloatUnary.sqrt))) and s.a == inst.ty and inst.data < std.meta.tags(ir.FloatUnary).len,
            .float_fma => self.floatLanes(inst.ty) and s.a == inst.ty and s.b == inst.ty and self.typesMatch(s.extra, &.{inst.ty}),
            .vector_select => self.maskOf(s.a) and s.b == inst.ty and (self.floatLanes(inst.ty) or self.integerLanes(inst.ty) or self.maskOf(inst.ty)) and self.typesMatch(s.extra, &.{inst.ty}),
            else => null,
        };
    }

    /// Whether `ty` is or holds a function type, through records, unions, arrays, boxes, lists, overlays and dictionaries:
    /// whether a function type is reachable from `ty` in the module's compound graph (`holdsFunctionType`). Each question
    /// gets its own visited bits, so it walks each compound at most once; without memory for them it walks by depth alone.
    fn holdsFunction(self: *Verifier, ty: ir.Type, depth: usize) bool {
        var seen = std.DynamicBitSetUnmanaged.initEmpty(self.arena, self.module.compounds.items.len) catch
            return holdsFunctionType(self.module, ty, null, depth, null);
        defer seen.deinit(self.arena);
        return holdsFunctionType(self.module, ty, &seen, depth, null);
    }

    fn sameSignature(a: ir.Signature, b: ir.Signature) bool {
        return a.eql(b);
    }

    /// Whether `result` reads collection of borrows `source` (RB2) as a whole: the read-only overlay of the owned collection
    /// whose layout it shares (`list[borrowed T]` read as `borrowed[list[T]]`).
    fn lentWhole(self: *Verifier, result: ir.Type, source: ir.Type) bool {
        const element = self.module.lentElement(source) orelse return false;
        if (!self.module.isBorrowed(result)) return false;
        const stored = self.module.storageType(result);
        if (!self.module.valid(stored)) return false;
        if (self.module.kind(source) == .dict) {
            const shape = self.module.dictShape(stored) orelse return false;
            return shape.key == self.module.compound(source).dict.key and shape.value == self.module.storageType(element);
        }
        return self.module.kind(stored) == .list and self.module.compound(stored).list == self.module.storageType(element);
    }

    /// Constants, arithmetic, comparisons and conversions; null for any other operation.
    fn scalarSignature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .copy => true,
            // A parameter reads the argument the caller passed for parameter `data`, at that parameter's type.
            .param => inst.data < self.f.signature.params.len and self.f.signature.params[@intCast(inst.data)] == inst.ty,
            .fconst => self.floatLanes(inst.ty),
            .str_const => inst.ty == .str or inst.ty == .bytes,
            // A function value is made only by `func_ref`, so no value an undefined one holds is one (trust point A17).
            .undef => !self.holdsFunction(inst.ty, 0),
            .borrow => (self.module.storageType(inst.ty) == self.module.storageType(s.a) and
                self.module.managed(self.module.storageType(s.a)) and
                (self.module.isBorrowed(inst.ty) != self.module.isBorrowed(s.a))) or self.lentWhole(inst.ty, s.a),
            .text_sentinel => inst.ty == .str or self.compoundOf(inst.ty, .list) != null,
            // A capability token (a stream handle) is an integer constant too.
            .iconst => isInteger(inst.ty) or inst.ty == .bool or inst.ty == .cap,
            .phi => for (self.f.operands(inst.data)) |operand| {
                if (self.typeOf(operand) != inst.ty) break false;
            } else true,
            .add, .sub, .mul => (isInteger(inst.ty) or self.integerLanes(inst.ty)) and s.a == inst.ty and s.b == inst.ty,
            .div, .rem, .floor_div, .floor_rem => isInteger(inst.ty) and s.a == inst.ty and s.b == inst.ty,
            .neg => (isInteger(inst.ty) or self.integerLanes(inst.ty)) and s.a == inst.ty,
            .bit_and, .bit_or, .bit_xor => (isInteger(inst.ty) or inst.ty == .bool or self.integerLanes(inst.ty) or self.maskOf(inst.ty)) and s.a == inst.ty and s.b == inst.ty,
            .not => (inst.ty == .bool and s.a == .bool) or (self.maskOf(inst.ty) and s.a == inst.ty),
            .cmp => self.comparisonSignature(s),
            .fadd, .fsub, .fmul, .fdiv => self.floatLanes(inst.ty) and s.a == inst.ty and s.b == inst.ty,
            .fneg => self.floatLanes(inst.ty) and s.a == inst.ty,
            .fcmp => (inst.ty == .bool or self.maskOf(inst.ty)) and self.floatLanes(s.a) and s.b == s.a and inst.data < 6,
            .int_to_float => (inst.ty == .f64 or inst.ty == .f32) and isInteger(s.a),
            .float_to_int => isInteger(inst.ty) and (s.a == .f64 or s.a == .f32),
            .float_convert => (inst.ty == .f64 and s.a == .f32) or (inst.ty == .f32 and s.a == .f64) or self.convertsLanes(inst.ty, s.a),
            .bitcast => (inst.ty == .f64 and s.a == .u64) or (inst.ty == .u64 and s.a == .f64) or (inst.ty == .f32 and s.a == .u32) or (inst.ty == .u32 and s.a == .f32),
            .convert => isInteger(inst.ty) and isInteger(s.a),
            .str_len => isInteger(inst.ty) and (s.a == .str or s.a == .str_view or s.a == .bytes_view),
            .str_parse_int => (s.a == .str or s.a == .str_view) and self.compoundOf(inst.ty, .@"union") != null,
            else => null,
        };
    }

    fn comparisonSignature(self: *Verifier, s: Shape) bool {
        if (s.a == s.b and self.integerLanes(s.a)) return s.inst.data < 6 and self.maskOver(s.inst.ty, s.a);
        if (s.inst.ty != .bool or s.a != s.b) return false;
        if (self.compoundOf(s.a, .@"fn") != null)
            return s.inst.data == @backingInt(ir.Predicate.eq) or s.inst.data == @backingInt(ir.Predicate.ne);
        return (isInteger(s.a) or s.a == .bool) and s.inst.data < 6;
    }

    /// Lists, records, unions, boxes and counting; null for any other operation.
    fn aggregateSignature(self: *Verifier, s: Shape) ?bool {
        const inst = s.inst;
        return switch (inst.op) {
            .list_new => self.compoundOf(inst.ty, .list) != null and isInteger(s.a),
            .list_len => isInteger(inst.ty) and self.listOrView(s.a),
            .list_get => isInteger(s.b) and self.elementRead(s.a, inst.ty),
            .list_view_of => if (self.compoundOf(inst.ty, .list_view)) |element| self.compoundOf(s.a, .list) == element else false,
            .list_slice_view => if (self.compoundOf(inst.ty, .list_view)) |element| blk: {
                const source = self.compoundOf(s.a, .list) orelse self.compoundOf(s.a, .list_view) orelse break :blk false;
                break :blk source == element and s.b == .i64 and self.typesMatch(s.extra, &.{.i64});
            } else false,
            .list_push => if (self.compoundOf(s.a, .list)) |element| inst.ty == s.a and s.b == element else false,
            // A copy of a list view is an owned list of the same elements (C9 lists): its elements are copied in place.
            .list_copy => if (self.compoundOf(s.a, .list)) |_| inst.ty == s.a else if (self.compoundOf(s.a, .list_view)) |element| self.compoundOf(inst.ty, .list) == element else false,
            .list_pop => self.compoundOf(s.a, .list) != null and inst.ty == s.a,
            .list_set => if (self.compoundOf(s.a, .list)) |element| inst.ty == s.a and isInteger(s.b) and s.extra.len == 1 and self.typeOf(s.extra[0]) == element else false,
            .list_get_field => self.fieldSignature(s),
            .list_set_field => self.setFieldSignature(s),
            .buffer_append => self.bufferAppendSignature(s),
            .union_make, .union_tag, .union_payload, .union_take => self.unionSignature(s),
            .record_make => if (self.compoundOf(inst.ty, .record)) |fields| self.typesMatch(s.extra, fields) else if (self.compoundOf(inst.ty, .array)) |array| blk: {
                if (s.extra.len != array.n) break :blk false;
                for (s.extra) |element| if (self.typeOf(element) != array.elem) break :blk false;
                break :blk true;
            } else false,
            .record_get => if (self.compoundOf(s.a, .record)) |fields| inst.data < fields.len and fields[@intCast(inst.data)] == inst.ty else false,
            .record_take => if (self.compoundOf(s.a, .record)) |fields| !self.module.containsBorrow(s.a) and self.module.managed(s.a) and inst.data < fields.len and fields[@intCast(inst.data)] == inst.ty else false,
            .record_set => if (self.compoundOf(s.a, .record)) |fields| inst.ty == s.a and inst.data < fields.len and fields[@intCast(inst.data)] == s.b else false,
            .box_make => if (self.compoundOf(inst.ty, .box)) |inner| s.a == inner else false,
            .box_get => if (self.compoundOf(s.a, .box)) |inner| inner == inst.ty else false,
            .box_frame => if (self.compoundOf(inst.ty, .box)) |inner| s.a == inner and self.module.kind(inner) == .record else false,
            .block_frame => self.blockFrameSignature(inst, s),
            .box_take => if (self.compoundOf(s.a, .box)) |inner| inner == inst.ty else false,
            .drop => inst.ty == .void and self.module.managed(s.a),
            // Mode 3 (`converted`) names the case in a `str` operand; the others take none.
            .err_trace => inst.ty == .void and inst.data <= 4 and if (inst.data == 3) inst.a != .none and s.a == .str else inst.a == .none,
            else => null,
        };
    }

    fn bufferAppendSignature(self: *Verifier, s: Shape) bool {
        if (s.inst.ty != .byte_buffer or s.a != .byte_buffer or s.extra.len != 2) return false;
        const span = s.b.isSpan();
        if (s.b != .bytes and s.b != .byte_buffer and !span) return false;
        return self.typeOf(s.extra[0]) == .i64 and self.typeOf(s.extra[1]) == .i64;
    }

    /// Calls, printing and terminators.
    fn controlSignature(self: *Verifier, s: Shape) bool {
        const inst = s.inst;
        const m = self.module;
        return switch (inst.op) {
            .call => blk: {
                if (inst.a == .none or inst.a.index() >= m.functions.items.len) break :blk false;
                const callee = m.functions.items[inst.a.index()].signature;
                if (inst.ty != callee.ret or s.extra.len != callee.params.len) break :blk false;
                for (s.extra, callee.params, 0..) |argument, param, i| {
                    const ty = self.typeOf(argument);
                    // A span stands for a text or bytes parameter only: a list view (or any compound) takes its own type.
                    const span_input = (ty.isSpan() or ty == .bytes) and admittedView(m, callee, i) and !param.isCompound();
                    if (ty != param and !span_input) break :blk false;
                }
                _ = @import("aggregate_provider.zig").call(m, self.f, inst) catch break :blk false;
                _ = @import("borrowed_provider.zig").call(m, self.f, inst) catch break :blk false;
                _ = @import("borrow_selection.zig").call(m, self.f, inst) catch break :blk false;
                break :blk true;
            },
            .print => inst.ty == .void and s.extra.len != 0 and self.typeOf(s.extra[0]) == .cap,
            .jump => inst.data < self.f.blocks.items.len,
            .branch => s.a == .bool,
            .ret => if (self.f.signature.ret == .void) inst.a == .none else inst.a != .none and s.a == self.f.signature.ret,
            .@"unreachable" => inst.ty == .void and if (inst.a == .none and inst.b == .none)
                true
            else
                inst.data & flags.text_trap != 0 and inst.a != .none and inst.b != .none and s.a.integer() != null and s.b.integer() != null,
            else => false,
        };
    }

    /// Whether `values` have exactly the types `types`, in order.
    fn typesMatch(self: *Verifier, values: []const ir.Ref, types: []const ir.Type) bool {
        if (values.len != types.len) return false;
        for (values, types) |value, ty| if (self.typeOf(value) != ty) return false;
        return true;
    }

    fn fieldSignature(self: *Verifier, s: Shape) bool {
        // The element of a list or of a list view (C9 lists): a field read of either reads the same element type.
        const element = self.compoundOf(s.a, .list) orelse self.compoundOf(s.a, .list_view) orelse return false;
        const path = ir.FieldPath.unpack(s.inst.data);
        if (path.len == 0) return false;
        const target = self.module.pathTarget(element, path) orelse return false;
        return isInteger(s.b) and target.ty == s.inst.ty;
    }

    /// `list_set_field`: a list, an integer index, and a value of the type the path reaches.
    fn setFieldSignature(self: *Verifier, s: Shape) bool {
        const element = self.compoundOf(s.a, .list) orelse return false;
        if (s.inst.ty != s.a or !isInteger(s.b) or s.extra.len != 2) return false;
        const path = elements.setPath(self.f, s.inst) orelse return false;
        if (path.len == 0) return false;
        const target = self.module.pathTarget(element, path) orelse return false;
        return target.tag_of == .void and target.ty == self.typeOf(s.extra[0]);
    }

    fn unionSignature(self: *Verifier, s: Shape) bool {
        const inst = s.inst;
        if (inst.op == .union_tag) return inst.ty == .u32 and self.compoundOf(s.a, .@"union") != null;
        const union_type = if (inst.op == .union_make) inst.ty else s.a;
        const cases = self.compoundOf(union_type, .@"union") orelse return false;
        if (inst.data >= cases.len) return false;
        const payload = cases[@intCast(inst.data)];
        if (inst.op == .union_take) {
            const inner = self.compoundOf(payload, .box) orelse payload;
            return inner != .void and inner == inst.ty;
        }
        if (inst.op == .union_payload) return payload != .void and payload == inst.ty;
        return if (payload == .void) inst.a == .none else inst.a != .none and s.a == payload;
    }
};

/// Whether a function type is reachable from `ty` through the parts of `module`'s compounds: `Verifier.holdsFunction`.
/// With `seen` (one bit per compound, all clear when the question starts) each compound is walked at most once, since a part
/// already seen is either being walked or holds no function; the cost is then linear in the compounds, recursive unions
/// included. Without it only the depth bound stops the walk; no simple path is longer than the bound, so the verdict is the
/// same, at a cost exponential in the compounds of a recursive type. `expanded`, when given, counts the compounds walked.
pub fn holdsFunctionType(module: *const ir.Module, ty: ir.Type, seen: ?*std.DynamicBitSetUnmanaged, depth: usize, expanded: ?*usize) bool {
    if (depth > module.compounds.items.len) return false;
    _ = validKind(module, ty) orelse return false;
    if (seen) |bits| {
        const index = @backingInt(ty) - ir.Type.first_compound;
        if (bits.isSet(index)) return false;
        bits.set(index);
    }
    if (expanded) |count| count.* += 1;
    return switch (module.compound(ty)) {
        .@"fn" => true,
        .record, .@"union" => |parts| for (parts) |part| {
            if (holdsFunctionType(module, part, seen, depth + 1, expanded)) break true;
        } else false,
        .array => |array| holdsFunctionType(module, array.elem, seen, depth + 1, expanded),
        .box, .list, .list_view, .borrowed => |inner| holdsFunctionType(module, inner, seen, depth + 1, expanded),
        .dict => |dict| holdsFunctionType(module, dict.key, seen, depth + 1, expanded) or
            holdsFunctionType(module, dict.value, seen, depth + 1, expanded),
    };
}
