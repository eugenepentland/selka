//! The ownership validation of a refused check (F-RC-214): a program whose failed bodies the checker stood in
//! (`HoleMode.recover`) is validated function by function, leaving out the stand-ins and every function that calls one, so
//! the ownership errors of the bodies that checked are reported beside the errors that refused the check.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const Diagnostic = language.diagnostic.Diagnostic;
const single_owner = @import("single_owner.zig");

/// Whether `program` holds a stand-in for a body that failed to check.
pub fn recovered(program: typed.Program) bool {
    for (program.functions) |function| if (typed.recoveredStandIn(function)) return true;
    return false;
}

/// Validate every function of `program` that neither is a stand-in nor calls one, and render every refusal into `report`;
/// false when any was refused. A program without stand-ins is validated whole, as `single_owner.validate` does. The refusals
/// and the report are allocated from `a`, which may be an arena; each function's transient work from `work`, a
/// general-purpose allocator (`single_owner.Every.work`).
pub fn validate(a: std.mem.Allocator, work: std.mem.Allocator, program: typed.Program, src: language.source.Source, format: language.diagnostic_output.Format, report: *std.ArrayList(u8)) error{OutOfMemory}!bool {
    var every: single_owner.Every = .{ .work = work };
    try checkSelected(a, program, src, &every);
    if (every.failures.items.len == 0) return true;
    try single_owner.judgeStandIns(a, program, src, &every);
    try single_owner.renderEvery(a, src, &every, format, report);
    return false;
}

/// The refusals `validate` reports, as diagnostics in source order, allocated from `a`, which may be an arena; the check's
/// transient work is made in `work`, as `validate` does. Whoever renders them notes them for the friction record.
pub fn collect(a: std.mem.Allocator, work: std.mem.Allocator, program: typed.Program, src: language.source.Source) error{OutOfMemory}![]const Diagnostic {
    var every: single_owner.Every = .{ .work = work };
    try checkSelected(a, program, src, &every);
    const failures = single_owner.distinct(&every);
    const found = try a.alloc(Diagnostic, failures.len);
    for (failures, found) |failure, *item| item.* = (try single_owner.diagnosticOf(a, src, failure)).diagnostic;
    return found;
}

/// `items` with `found` placed among them by source position: each before the first error of `items` that starts after it,
/// so the refused check's own diagnostics keep their order. Allocated from `a`.
pub fn merged(a: std.mem.Allocator, items: []const Diagnostic, found: []const Diagnostic) error{OutOfMemory}![]Diagnostic {
    var out: std.ArrayList(Diagnostic) = try .initCapacity(a, items.len + found.len);
    var next: usize = 0;
    for (items) |item| {
        while (next < found.len and item.severity == .err and found[next].span.start < item.span.start) : (next += 1) out.appendAssumeCapacity(found[next]);
        out.appendAssumeCapacity(item);
    }
    out.appendSliceAssumeCapacity(found[next..]);
    return out.items;
}

fn checkSelected(a: std.mem.Allocator, program: typed.Program, src: language.source.Source, every: *single_owner.Every) error{OutOfMemory}!void {
    const selected = try selection(a, program);
    defer a.free(selected);
    try single_owner.checkEvery(a, program, selected, src, every);
}

/// The functions a recovered program's ownership can be judged on. A caller of a stand-in is left out: the stand-in's facts
/// (the writes its body makes, the borrows it returns) are not the failed body's, so the caller's check could differ from the
/// one the repaired source gets.
fn selection(a: std.mem.Allocator, program: typed.Program) error{OutOfMemory}![]bool {
    const selected = try a.alloc(bool, program.functions.len);
    for (program.functions, selected) |function, *bit| bit.* = !typed.recoveredStandIn(function);
    for (program.functions, selected) |function, *bit| {
        if (!bit.*) continue;
        bit.* = !try callsStandIn(a, program, function);
    }
    return selected;
}

fn callsStandIn(a: std.mem.Allocator, program: typed.Program, function: typed.Function) error{OutOfMemory}!bool {
    var walker = try language.typed_walk.Walker.init(a, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        if (item != .expression) continue;
        const callee: usize = switch (program.nodes[@backingInt(item.expression)].data) {
            .call => |call| @backingInt(call.function),
            .function_value => |value| @backingInt(value),
            else => continue,
        };
        if (callee < program.functions.len and typed.recoveredStandIn(program.functions[callee])) return true;
    }
    return false;
}
