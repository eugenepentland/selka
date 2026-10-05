//! Helpers the new core's unit tests share: check a single-file program from
//! source text and build or render its Core IR.
const std = @import("std");
const language = @import("mylang");
const ir = @import("ir.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const emit_llvm = @import("emit_llvm.zig");
const facts = @import("facts.zig");
const passes = @import("passes.zig");
const driver = @import("driver.zig");
const verify_ir = @import("verify_ir.zig");
const vector = @import("vector.zig");

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// Everything checking, building or emitting a test program can fail with.
pub const Error = language.diagnostic.Error || build.Error || emit_llvm.Error || verify_ir.Error;

/// Check `source` as a header-less program and build its Core IR in `arena`; the
/// IR is verified (`verify_ir.zig`) before it is returned.
pub fn buildSource(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) Error!ir.Module {
    var unit = try language.Compilation.init(arena, "test.my", source);
    try unit.check();
    const module = try build.buildModule(arena, unit.program.?, refusal);
    try verified(arena, &module, &.{});
    return module;
}

/// Verify `module` and its vector plans; a failure prints the verifier's report.
pub fn verified(arena: std.mem.Allocator, module: *const ir.Module, plans: []const []const vector.Plan) verify_ir.Error!void {
    var text: std.ArrayList(u8) = .empty;
    verify_ir.check(arena, module, plans, &text) catch |err| {
        report("{s}", .{text.items});
        return err;
    };
}

/// Run the release passes in `mode` and verify the result, plans included.
pub fn runPasses(arena: std.mem.Allocator, module: *ir.Module, mode: passes.Mode) Error!passes.Result {
    const result = try passes.run(arena, module, mode);
    try verified(arena, module, result.plans);
    return result;
}

/// The textual Core IR of `source`.
pub fn irText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    return print.module(arena, &module);
}

fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

/// The LLVM IR of `source`, with every trap located at line 1.
pub fn llvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "test.my", .main = .{ .parameters = &.{"out"} } });
}

/// The textual Core IR of `source` after the release fact pass marked what it proved.
pub fn factsText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    for (module.functions.items) |*function| {
        if (function.signature.linkage == .internal) _ = try facts.analyze(arena, function, .{});
    }
    try verified(arena, &module, &.{});
    return print.module(arena, &module);
}

/// The textual Core IR of `source` after the release passes.
pub fn optimizedText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    _ = try runPasses(arena, &module, .trusted);
    return print.module(arena, &module);
}

/// The LLVM IR a release build of `source` emits.
pub fn releaseLlvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    return releaseLlvmTextFor(arena, source, @import("target.zig").current);
}

/// The LLVM IR a `--verify-facts` release build of `source` emits.
pub fn verifyLlvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    const result = try runPasses(arena, &module, .verify);
    const context: u8 = 0;
    const locator: emit_llvm.Locator = .{ .context = &context, .locate = firstLine };
    return emit_llvm.emitModule(arena, &module, .{ .locator = locator, .source_path = "test.my", .main = .{ .parameters = &.{"out"} }, .facts = result.known, .verify = true });
}

/// The LLVM IR a release build of `source` emits for target description `target`.
pub fn releaseLlvmTextFor(arena: std.mem.Allocator, source: []const u8, target: @import("target.zig").Target) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    const result = try runPasses(arena, &module, .trusted);
    const context: u8 = 0;
    const locator: emit_llvm.Locator = .{ .context = &context, .locate = firstLine };
    return emit_llvm.emitModule(arena, &module, .{ .locator = locator, .source_path = "test.my", .main = .{ .parameters = &.{ "args", "out" } }, .facts = result.known, .vectors = result.plans, .target = target });
}

// ---- hand-built IR ------------------------------------------------------------------

/// Builds one function's Core IR by hand, for tests of operations the builder
/// does not produce yet. Instructions go into the current block in order.
pub const Hand = struct {
    arena: std.mem.Allocator,
    module: *ir.Module,
    function: ir.Function,
    block: ir.BlockId = @fromBackingInt(0),

    /// A function `name(params) -> ret` with one empty entry block.
    pub fn init(arena: std.mem.Allocator, module: *ir.Module, name: []const u8, signature: ir.Signature) Error!Hand {
        var hand: Hand = .{ .arena = arena, .module = module, .function = .{ .name = name, .signature = signature } };
        _ = try hand.newBlock();
        return hand;
    }

    /// Append `inst` to the current block; returns its value.
    pub fn emit(self: *Hand, inst: ir.Inst) Error!ir.Ref {
        const ref = try self.loose(inst);
        try self.function.blocks.items[self.block.index()].insts.append(self.arena, ref);
        return ref;
    }

    /// An instruction outside every block: a constant or parameter.
    pub fn loose(self: *Hand, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.arena, inst);
        return ref;
    }

    /// An integer constant of type `ty`.
    pub fn int(self: *Hand, ty: ir.Type, value: i64) Error!ir.Ref {
        return self.loose(.{ .op = .iconst, .ty = ty, .data = @bitCast(value) });
    }

    /// Parameter `index`.
    pub fn param(self: *Hand, index: u32) Error!ir.Ref {
        return self.loose(.{ .op = .param, .ty = self.function.signature.params[index], .data = index });
    }

    /// Pack `refs` as an instruction's `extra` list.
    pub fn extra(self: *Hand, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.arena, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }

    /// A new empty block (not entered).
    pub fn newBlock(self: *Hand) Error!ir.BlockId {
        try self.function.blocks.append(self.arena, .{});
        return @fromBackingInt(@intCast(self.function.blocks.items.len - 1));
    }

    /// End the current block with a jump to `target`, recording the edge.
    pub fn jump(self: *Hand, target: ir.BlockId) Error!void {
        _ = try self.emit(.{ .op = .jump, .ty = .void, .data = @backingInt(target) });
        try self.function.blocks.items[target.index()].preds.append(self.arena, self.block);
    }

    /// End the current block with `if condition: then else otherwise`.
    pub fn branch(self: *Hand, condition: ir.Ref, then: ir.BlockId, otherwise: ir.BlockId) Error!void {
        _ = try self.emit(.{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(then, otherwise) });
        try self.function.blocks.items[then.index()].preds.append(self.arena, self.block);
        try self.function.blocks.items[otherwise.index()].preds.append(self.arena, self.block);
    }

    /// Print `values` (integers, booleans or strings) on the stream parameter `stream`.
    pub fn printValues(self: *Hand, stream: ir.Ref, values: []const ir.Ref) Error!void {
        var operands: std.ArrayList(ir.Ref) = .empty;
        try operands.append(self.arena, stream);
        try operands.appendSlice(self.arena, values);
        _ = try self.emit(.{ .op = .print, .ty = .void, .data = try self.extra(operands.items) });
    }

    /// Add the finished function to the module; returns its index.
    pub fn finish(self: *Hand) Error!u32 {
        try self.module.functions.append(self.arena, self.function);
        return @intCast(self.module.functions.items.len - 1);
    }
};

/// What running a hand-built program printed and returned.
pub const Run = struct { stdout: []const u8, stderr: []const u8, status: u8, llvm: []const u8 };

/// Why a hand-built program could not be built or run.
pub const RunError = Error || driver.Error;

/// Verify `module`, emit it (traps at line 1), compile it with `zig cc` at -O0
/// (or -O3 when `release`) and run it with no arguments.
pub fn runModule(arena: std.mem.Allocator, module: *const ir.Module, release: bool) RunError!Run {
    try verified(arena, module, &.{});
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "hand.my", .main = .{ .parameters = &.{"out"} } });
    return runLlvm(arena, llvm, .{ .release = release, .leakcheck = false });
}

/// How `runOwned` builds and runs a hand-built module.
pub const RunOptions = struct {
    release: bool = false,
    /// Verify mode: form-1 updates are asserted unique (`R_CORE_FACT`).
    verify: bool = false,
    /// Run with `MYL_CORE_LEAKCHECK=1`, so blocks live at exit are reported on stderr.
    leakcheck: bool = true,
    /// Run the ownership pass first (off: the module counts by hand, or leaks).
    own: bool = true,
    /// `main`'s parameter names and, when it returns a `Result`, its case tags.
    main: emit_llvm.Main = .{ .parameters = &.{"out"} },
};

/// Run the ownership pass over `module` (as a build would, after construction),
/// verify, emit, compile and run it, by default with the leak check on.
pub fn runOwned(arena: std.mem.Allocator, module: *ir.Module, options: RunOptions) RunError!Run {
    try verified(arena, module, &.{});
    if (options.own) _ = try @import("own.zig").run(arena, module, .{ .verify = options.verify });
    try verified(arena, module, &.{});
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "hand.my", .main = options.main, .verify = options.verify });
    return runLlvm(arena, llvm, options);
}

/// The textual Core IR of `source` after the debug pipeline's ownership pass.
pub fn ownedText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    _ = try passes.ownership(arena, &module);
    try verified(arena, &module, &.{});
    return print.module(arena, &module);
}

/// Compile emitted LLVM IR with `zig cc` and run it with no arguments.
fn runLlvm(arena: std.mem.Allocator, llvm: []const u8, options: RunOptions) RunError!Run {
    const release = options.release;
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = dir.dir.realPathFileAlloc(std.testing.io, ".", arena) catch return error.ToolFailed;
    var environment = std.testing.environ.createMap(arena) catch return error.ToolFailed;
    const zig = environment.get("ZIG") orelse "zig";
    const output = try std.fs.path.join(arena, &.{ root, "hand" });
    var log: std.ArrayList(u8) = .empty;
    driver.link(arena, std.testing.io, &environment, .{
        .zig = zig,
        .work = root,
        .program = try std.fs.path.join(arena, &.{ root, "hand.ll" }),
        .output = output,
        .release = release,
        .links = &.{},
        .llvm = llvm,
    }, &log) catch |err| {
        report("zig cc rejected the emitted module:\n{s}\n{s}\n", .{ log.items, llvm });
        return err;
    };
    if (options.leakcheck) environment.put("MYL_CORE_LEAKCHECK", "1") catch return error.ToolFailed;
    const result = std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment }) catch return error.ToolFailed;
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .status = status, .llvm = llvm };
}
