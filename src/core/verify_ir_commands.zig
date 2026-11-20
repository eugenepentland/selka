//! `selka verify-ir PATH`: the Zig IR verifier's verdicts on `core-ir-v1` texts (`ir_text.zig`), one line per
//! function, in the form the Lean copy (`proofs/verify_ir`, `lake exe irverify`) prints, so the gate action can compare
//! the two line by line. Each function is judged on its own: the module-level rules (`verify_ir.verifyTypes`) give one
//! `types` line, and every function gets its header rules and, when it has a body, `verify_ir.verifyFunction`.
//!
//! ```text
//! FILE types accept | FILE types reject RULE
//! FILE NAME accept | FILE NAME reject RULE bB %I      (b- and %- when the failure names no block or instruction)
//! FILE error line N: REASON                          (a text that does not parse)
//! summary files=.. functions=.. accept=.. reject=.. errors=..
//! ```
//!
//! `RULE` is the class of the verifier's first failure (`ruleOf`), the names `proofs/verify_ir/NOTES.md` tabulates. A module
//! whose type table is refused gets its `types` line only (counted as one rejection): the function rules read the table.
const std = @import("std");
const ir = @import("ir.zig");
const ir_text = @import("ir_text.zig");
const verify_ir = @import("verify_ir.zig");

/// What the command can fail with beyond a status.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error || error{ReadFailed};

/// The longest text the command reads.
const file_limit: usize = 1 << 30;

/// What a run counted, for its summary line (the fields `irverify` prints).
pub const Counts = struct { files: usize = 0, functions: usize = 0, accept: usize = 0, reject: usize = 0, errors: usize = 0 };

// twin-drift-ok: the certificate validator's command also answers `--identity` and reads another format; the walk is shared (`collect`).
/// `verify-ir PATH`: PATH is one text, or a directory whose `.core-ir` files are read in path order. Exit 0 when everything
/// is accepted, 1 when something is rejected, 2 for a usage error or a text that does not parse.
pub fn verifyCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    if (arguments.len != 1) return 2;
    const allocator = init.arena.allocator();
    const single = (std.Io.Dir.cwd().statFile(init.io, arguments[0], .{}) catch return 2).kind != .directory;
    const files = try collect(init, arguments[0], single);
    var counts: Counts = .{};
    var out: std.ArrayList(u8) = .empty;
    for (files) |path| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const text = std.Io.Dir.cwd().readFileAlloc(init.io, path, scratch.allocator(), .limited(file_limit)) catch return error.ReadFailed;
        try checkText(.{ .work = scratch.allocator(), .keep = allocator, .counts = &counts, .out = &out }, path, text);
    }
    try out.print(allocator, "summary files={d} functions={d} accept={d} reject={d} errors={d}\n", .{ counts.files, counts.functions, counts.accept, counts.reject, counts.errors });
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return if (counts.errors != 0) 2 else if (counts.reject != 0) 1 else 0;
}

/// The `.core-ir` files under `target` (any file when `target` is one), in path order.
fn collect(init: std.process.Init, target: []const u8, single: bool) Error![]const []const u8 {
    const all = try @import("ownership_commands.zig").collect(init, target, single);
    if (single) return all;
    var found: std.ArrayList([]const u8) = .empty;
    for (all) |path| if (std.mem.endsWith(u8, path, ".core-ir")) try found.append(init.arena.allocator(), path);
    return found.items;
}

/// Where one text's lines go: `work` is freed after the text, `keep` holds the lines.
pub const Sink = struct { work: std.mem.Allocator, keep: std.mem.Allocator, counts: *Counts, out: *std.ArrayList(u8) };

/// The verdict lines of one text.
pub fn checkText(sink: Sink, path: []const u8, text: []const u8) Error!void {
    sink.counts.files += 1;
    var problem: ir_text.Problem = .{};
    const module = ir_text.parse(sink.work, text, &problem) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Malformed => {
            sink.counts.errors += 1;
            try sink.out.print(sink.keep, "{s} error line {d}: {s}\n", .{ path, problem.line, problem.reason });
            return;
        },
    };
    var failure: verify_ir.Failure = .{};
    if (verify_ir.verifyTypes(sink.work, &module, &failure)) {
        try sink.out.print(sink.keep, "{s} types accept\n", .{path});
    } else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        // The function rules ask the module about its types, so a module whose table is refused gets no function lines.
        sink.counts.reject += 1;
        try sink.out.print(sink.keep, "{s} types reject {s}\n", .{ path, ruleOf(failure.reason) });
        return;
    }
    for (module.functions.items) |*function| {
        sink.counts.functions += 1;
        failure = .{};
        const verdict = judge(sink.work, &module, function, &failure);
        const name = try ir_text.escapedName(sink.work, function.name);
        if (verdict) {
            sink.counts.accept += 1;
            try sink.out.print(sink.keep, "{s} {s} accept\n", .{ path, name });
        } else |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            sink.counts.reject += 1;
            try sink.out.print(sink.keep, "{s} {s} reject {s} ", .{ path, name, ruleOf(failure.reason) });
            if (failure.block != verify_ir.Failure.none_index) try sink.out.print(sink.keep, "b{d} ", .{failure.block}) else try sink.out.appendSlice(sink.keep, "b- ");
            if (failure.inst != verify_ir.Failure.none_index) try sink.out.print(sink.keep, "%{d}\n", .{failure.inst}) else try sink.out.appendSlice(sink.keep, "%-\n");
        }
    }
}

fn judge(arena: std.mem.Allocator, module: *const ir.Module, function: *const ir.Function, failure: *verify_ir.Failure) verify_ir.Error!void {
    try verify_ir.verifyHeader(module, function, failure);
    // The gate's check refuses an unjustified union payload read whatever the builds' mode (D-VL-18).
    if (function.signature.linkage == .internal) try verify_ir.verifyFunctionWith(arena, module, function, failure, .{ .mode = .refuse });
}

/// The rule a failure's reason names: each reason `verify_ir.zig` writes, by its distinctive words. An unknown reason is
/// `unknown`, which the Lean copy never prints, so a new reason without a class shows up as a disagreement.
pub fn ruleOf(reason: []const u8) []const u8 {
    const table = [_]struct { []const u8, []const u8 }{
        .{ "names a type the module does not have", "type-table" },
        .{ "borrowed equality declaration", "equality" },
        .{ "a view has no aggregate", "view-storage" },
        .{ "provider lifetime marker", "marker-provider" },
        .{ "borrowed provider context", "marker-borrowed" },
        .{ "borrowed selection marker", "marker-selection" },
        .{ "invalid parameter type", "param-type" },
        .{ "parameter type is not interned", "param-type" },
        .{ "invalid result type", "result-type" },
        .{ "borrowed result paths", "borrow-contract" },
        .{ "has no blocks", "no-blocks" },
        .{ "entry block has predecessors", "entry-preds" },
        .{ "has no type of the module", "operand-type" },
        .{ "which does not exist", "target" },
        .{ "empty block", "empty-block" },
        .{ "instruction that does not exist", "listed-range" },
        .{ "listed in two places", "listed-twice" },
        .{ "terminator", "terminator" },
        .{ "phi after a non-phi", "phi-order" },
        .{ "operands for", "phi-arity" },
        .{ "times in its predecessors", "edge-preds" },
        .{ "predecessor b", "pred-edge" },
        .{ "result type is not interned", "type-valid" },
        .{ "extra operands are out of range", "extra-range" },
        .{ "reads no operand in a or b", "unused-operand" },
        .{ "missing or out-of-range operand", "operand-range" },
        .{ "a view may only be defined", "view-def" },
        .{ "a view escapes", "view-use" },
        .{ "dict_insert probe", "insert-probe" },
        .{ "does not match its signature", "signature" },
        .{ "without a test of its tag", "union-tag" },
        .{ "returned borrowed payload", "borrow-result" },
        .{ "shallow container copy", "shallow-copy" },
        .{ "missing operand", "dom-missing" },
        .{ "forwards to nothing", "dom-forward" },
        .{ "not defined in a reachable block", "dom-undefined" },
        .{ "used before its definition", "dom-order" },
        .{ "does not dominate", "dom-block" },
        .{ "does not exist", "dom-range" },
    };
    for (table) |entry| if (std.mem.indexOf(u8, reason, entry[0]) != null) return entry[1];
    return "unknown";
}

test "each verifier reason names its rule" {
    try std.testing.expectEqualStrings("terminator", ruleOf("terminator before the end of its block"));
    try std.testing.expectEqualStrings("terminator", ruleOf("block does not end in a terminator"));
    try std.testing.expectEqualStrings("target", ruleOf("branch to block b9, which does not exist"));
    try std.testing.expectEqualStrings("pred-edge", ruleOf("predecessor b3 does not exist"));
    try std.testing.expectEqualStrings("dom-range", ruleOf("operand %4 does not exist"));
    try std.testing.expectEqualStrings("dom-block", ruleOf("operand %4 (b2) does not dominate its use in b1"));
    try std.testing.expectEqualStrings("unknown", ruleOf("a reason nobody wrote"));
}

test "a parsed text gets a types line and one verdict per function" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\core-ir-v1
        \\types 0
        \\functions 2
        \\function good 0 0
        \\sig internal 5 0 0 0 0 0 0 0 0 0
        \\insts 2
        \\iconst 5 - - 7 none
        \\ret 0 0 - 0 none
        \\extra 0
        \\blocks 1
        \\block 1 1 0
        \\end
        \\function bad 0 0
        \\sig internal 5 0 0 0 0 0 0 0 0 0
        \\insts 2
        \\ret 0 1 - 0 none
        \\add 5 - - 0 none
        \\extra 0
        \\blocks 1
        \\block 1 0 0
        \\end
        \\
    ;
    var counts: Counts = .{};
    var out: std.ArrayList(u8) = .empty;
    try checkText(.{ .work = a, .keep = a, .counts = &counts, .out = &out }, "p", text);
    try std.testing.expectEqualStrings("p types accept\np good accept\np bad reject dom-undefined b0 %0\n", out.items);
    try std.testing.expectEqual(@as(usize, 1), counts.reject);
}
