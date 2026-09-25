//! The inspection surface of the ownership analysis (`OWNERSHIP-EXPLAIN-1`):
//! `mylang check FILE.my --explain-ownership=OUT.jsonl` writes one JSON line
//! per guest function listing its locals' roles, every transfer with its
//! class, every copy-on-write check site with the loop header it was hoisted
//! to, and the loads that move. It reads the same bytecode and the same
//! liveness solution the native emitter reads, so the answer it prints is the
//! answer codegen acts on.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const liveness = @import("qbe_liveness.zig");
const native_ir = @import("native_ir.zig");
const native_types = @import("native_types.zig");
const ownership = @import("ownership.zig");

/// Failures of rendering the explanation.
pub const Error = error{ InternalError, OutOfMemory };

/// The explanation of every guest function of `program`, one JSON object per
/// line, in function order. A host or C-ABI function has no body to explain
/// and is skipped, as is a body the native lowering does not support.
pub fn render(allocator: std.mem.Allocator, program: bytecode.Program) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var layouts = native_types.Catalog.initRecords(a, program.records) catch return error.InternalError;
    defer layouts.deinit();
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    for (program.functions) |function| {
        if (function.policy.c_abi or function.policy.host != null) continue;
        const analysis = try analyzeOne(a, program, function, &layouts) orelse continue;
        writeFunction(&out.writer, function, analysis) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice() catch return error.OutOfMemory;
}

/// Analyze one function the way the emitter does: its typed stacks, its
/// liveness with owning locals pinned, then ownership.
pub fn analyzeOne(a: std.mem.Allocator, program: bytecode.Program, function: bytecode.Function, layouts: *native_types.Catalog) Error!?ownership.Analysis {
    const ir = native_ir.analyze(a, program, function) catch |err| switch (err) {
        error.UnsupportedOperation => return null,
        error.InternalError => return error.InternalError,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const pinned = try a.alloc(bool, function.scope.locals.len);
    for (function.scope.locals, pinned) |local, *pin| pin.* = (layouts.layout(local.ty) catch return error.InternalError).drop;
    const live = try liveness.solve(a, .{ .function = function, .states = ir.states, .pinned = pinned });
    const analysis = try ownership.analyze(a, .{ .program = program, .function = function, .states = ir.states, .live = live });
    return analysis;
}

fn writeFunction(w: *std.Io.Writer, function: bytecode.Function, analysis: ownership.Analysis) std.Io.Writer.Error!void {
    var json: std.json.Stringify = .{ .writer = w };
    try json.beginObject();
    try json.objectField("function");
    try json.write(function.name);
    try json.objectField("locals");
    try json.beginArray();
    for (analysis.roles, 0..) |role, index| {
        if (role == .plain) continue;
        try json.beginObject();
        try json.objectField("index");
        try json.write(index);
        try json.objectField("name");
        try json.write(function.scope.locals[index].name);
        try json.objectField("role");
        try json.write(@tagName(role));
        if (analysis.parents[index] != ownership.none) {
            try json.objectField("parent");
            try json.write(analysis.parents[index]);
        }
        try json.endObject();
    }
    try json.endArray();
    try json.objectField("transfers");
    try json.beginArray();
    for (analysis.transfers) |transfer| try writeTransfer(&json, transfer);
    try json.endArray();
    try json.objectField("cow");
    try json.beginArray();
    for (analysis.cows) |site| try writeCow(&json, site);
    try json.endArray();
    try json.objectField("moves");
    try json.beginArray();
    for (analysis.moves, 0..) |moves, pc| if (moves) try json.write(pc);
    try json.endArray();
    try json.endObject();
    try w.writeByte('\n');
}

fn writeTransfer(json: *std.json.Stringify, transfer: ownership.Transfer) std.Io.Writer.Error!void {
    try json.beginObject();
    try json.objectField("pc");
    try json.write(transfer.pc);
    try json.objectField("kind");
    try json.write(@tagName(transfer.kind));
    if (transfer.target != ownership.none) {
        try json.objectField("target");
        try json.write(transfer.target);
    }
    try json.objectField("source");
    try json.beginObject();
    try json.objectField("origin");
    try json.write(@tagName(transfer.source.origin));
    if (transfer.source.origin == .local) {
        try json.objectField("local");
        try json.write(transfer.source.local);
        try json.objectField("part");
        try json.write(@tagName(transfer.source.part));
    }
    try json.endObject();
    try json.objectField("class");
    try json.write(@tagName(transfer.class));
    try json.endObject();
}

fn writeCow(json: *std.json.Stringify, site: ownership.Cow) std.Io.Writer.Error!void {
    try json.beginObject();
    try json.objectField("pc");
    try json.write(site.pc);
    try json.objectField("local");
    try json.write(site.local);
    try json.objectField("via");
    try json.write(site.via);
    try json.objectField("elements");
    try json.write(site.elements);
    try json.objectField("needed");
    try json.write(site.needed);
    try json.objectField("hoisted");
    if (site.hoisted == ownership.none) try json.write(null) else try json.write(site.hoisted);
    try json.endObject();
}
