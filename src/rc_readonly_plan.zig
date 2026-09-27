//! Optional physical preflight shared by every closed readonly certificate.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const native = @import("native_types.zig");
const cow = @import("cow_plan.zig");

/// Input-volume allowances shared by every dependency of one root query.
/// These charge matrix dimensions, not individual inner planner operations.
pub const Budget = struct { cells: usize = 65536, volume: usize = 4194304 };

/// Use the emitter's actual stack, pinning, liveness, ownership and COW inputs.
/// A rejected conservative capture remains an ordinary owned-body fallback.
pub fn certify(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, budget: *Budget) native.Error!bool {
    const n = function.scope.instructions.len;
    const count = function.scope.locals.len;
    if (n > 1024 or count > 256) return false;
    const cells = n * (n + count);
    const volume = cells * (count + 1);
    if (cells > budget.cells or volume > budget.volume) return false;
    budget.cells -= cells;
    budget.volume -= volume;
    var arena = std.heap.ArenaAllocator.init(catalog.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program: bytecode.Program = .{ .functions = functions, .records = catalog.native.records };
    const ir = @import("native_ir.zig").analyze(a, program, function) catch |err| return translate(err);
    const pinned = try a.alloc(bool, count);
    for (function.scope.locals, pinned) |local, *pin| pin.* = (try catalog.native.layout(local.ty)).drop;
    const live = try @import("qbe_liveness.zig").solve(a, .{ .function = function, .states = ir.states, .pinned = pinned });
    const ownership = @import("ownership.zig").analyze(a, .{ .program = program, .function = function, .states = ir.states, .live = live }) catch |err| return translate(err);
    const plan = cow.plan(a, .{
        .program = program,
        .function = function,
        .states = ir.states,
        .analysis = ownership,
        .shares = !@import("value_semantics.zig").enabled(),
    }) catch |err| return translate(err);
    // No places means retainPlaces cannot add implicit liveness. No checks
    // means RC's pre-plan dehoisting has no effect on this accepted plan.
    return quiet(plan);
}

/// The accepted plan has no implicit ownership operation or saved writing path.
pub fn quiet(plan: cow.Plan) bool {
    for (plan.places) |place| if (place != null) return false;
    for (plan.sites) |site| {
        if (site.unique.len != 0 or site.unique_field != null or site.fill or site.capture) return false;
        if (site.shares.len != 0 or site.read_captures.len != 0) return false;
    }
    for (plan.loops.entries) |entries| if (entries.len != 0) return false;
    return true;
}

fn translate(err: anyerror) native.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidType;
}
