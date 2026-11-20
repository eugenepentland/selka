//! The program-level link of the callee tables (docs/design/ownership-certificates.md §9, entry 57).
//!
//! A function's callee table says what each callee is: its name, how it takes each parameter, what it returns and what its
//! result may borrow from. The per-function validator checks each call against its entry; this check is the other half: each
//! `program` entry matches the callee's own `function` and `param` lines, found by name among all the functions of the program
//! (all units of a build). It spans functions, so a per-function verdict cannot hold it; the gate runs it once per program.
//! Runtime, `extern` and marker callees are assumed (A5), and an indirect entry has no name to look up.
const std = @import("std");
const form = @import("ownership_function.zig");

const Allocator = std.mem.Allocator;

/// Why an entry does not match its callee. The first failing one is reported, in this order.
pub const Tag = enum {
    /// No function of the program has the entry's name.
    callee_missing,
    /// The entry has a different number of parameters.
    callee_arity,
    /// A parameter's mode does not match the state of the callee's `param` line.
    callee_param,
    /// The entry's result kind is not the callee's.
    callee_result,
    /// The entry's `from` positions are not the callee's.
    callee_from,

    /// The spelling in the output.
    pub fn token(self: Tag) []const u8 {
        return switch (self) {
            .callee_missing => "callee-missing",
            .callee_arity => "callee-arity",
            .callee_param => "callee-param",
            .callee_result => "callee-result",
            .callee_from => "callee-from",
        };
    }
};

/// One entry that does not match its callee: the position of the calling function in the program, the entry's id and why.
pub const Rejection = struct { caller: usize, entry: u32, tag: Tag };

/// What `link` found.
pub const Report = struct {
    /// The entries of kind `program` that were looked at.
    entries: usize,
    rejections: []const Rejection,
};

/// Link every `program` entry of every function of `functions` (one program) to the function it names.
pub fn link(a: Allocator, functions: []const form.Function) Allocator.Error!Report {
    var by_name: std.StringHashMapUnmanaged(usize) = .empty;
    for (functions, 0..) |function, i| {
        const found = try by_name.getOrPut(a, function.name);
        if (!found.found_existing) found.value_ptr.* = i;
    }
    var out: std.ArrayList(Rejection) = .empty;
    var entries: usize = 0;
    for (functions, 0..) |caller, ci| {
        for (caller.callees) |entry| {
            if (entry.kind != .program) continue;
            entries += 1;
            const at = by_name.get(entry.name) orelse {
                try out.append(a, .{ .caller = ci, .entry = entry.id, .tag = .callee_missing });
                continue;
            };
            if (mismatch(entry, functions[at])) |tag| try out.append(a, .{ .caller = ci, .entry = entry.id, .tag = tag });
        }
    }
    return .{ .entries = entries, .rejections = out.items };
}

/// Why `entry` is not what `callee` states of itself, if it is not.
fn mismatch(entry: form.Callee, callee: form.Function) ?Tag {
    if (entry.params.len != callee.params.len) return .callee_arity;
    for (entry.params, callee.params) |mode, param| {
        const state: form.State = switch (mode) {
            .take => .owned,
            .read => .borrowed,
            .take_scalar, .read_scalar => .scalar,
        };
        if (param.state != state) return .callee_param;
    }
    if (entry.result != callee.returns.kind) return .callee_result;
    if (!std.mem.eql(u32, entry.from, callee.returns.from)) return .callee_from;
    return null;
}

fn listed(id: u32, name: []const u8, params: []const form.ParamMode, result: form.ResultKind, from: []const u32) form.Callee {
    return .{ .id = id, .name = name, .kind = .program, .params = params, .result = result, .from = from };
}

fn made(name: []const u8, params: []const form.Param, returns: form.Returns, callees: []const form.Callee) form.Function {
    return .{ .name = name, .returns = returns, .unchecked = null, .params = params, .callees = callees, .pre = &.{}, .blocks = &.{} };
}

test "an entry is linked to the callee's own function line by name, and the first thing that differs is reported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const target = made("target", &.{ .{ .value = 0, .state = .owned }, .{ .value = 1, .state = .scalar }, .{ .value = 2, .state = .borrowed } }, .{ .kind = .borrowed, .from = &.{2} }, &.{});
    const modes = [_]form.ParamMode{ .take, .read_scalar, .read };
    const caller = made("caller", &.{}, .{ .kind = .scalar, .from = &.{} }, &.{
        listed(0, "target", &modes, .borrowed, &.{2}),
        listed(1, "missing", &.{}, .scalar, &.{}),
        listed(2, "target", modes[0..2], .borrowed, &.{2}),
        listed(3, "target", &.{ .read, .read_scalar, .read }, .borrowed, &.{2}),
        listed(4, "target", &modes, .owned, &.{2}),
        listed(5, "target", &modes, .borrowed, &.{1}),
    });
    const report = try link(a, &.{ target, caller });
    try std.testing.expectEqual(@as(usize, 6), report.entries);
    try std.testing.expectEqual(@as(usize, 5), report.rejections.len);
    try std.testing.expectEqual(Rejection{ .caller = 1, .entry = 1, .tag = .callee_missing }, report.rejections[0]);
    try std.testing.expectEqual(Rejection{ .caller = 1, .entry = 2, .tag = .callee_arity }, report.rejections[1]);
    try std.testing.expectEqual(Rejection{ .caller = 1, .entry = 3, .tag = .callee_param }, report.rejections[2]);
    try std.testing.expectEqual(Rejection{ .caller = 1, .entry = 4, .tag = .callee_result }, report.rejections[3]);
    try std.testing.expectEqual(Rejection{ .caller = 1, .entry = 5, .tag = .callee_from }, report.rejections[4]);
}
