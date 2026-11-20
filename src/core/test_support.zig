//! Helpers the new core's unit tests share: check a single-file program from
//! source text and build or render its Core IR.
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const emit_llvm = @import("emit_llvm.zig");
const facts = @import("facts.zig");
const passes = @import("passes.zig");
const driver = @import("driver.zig");
const verify_ir = @import("verify_ir.zig");
const vector = @import("vector.zig");
const options_paths = @import("core_test_options");
const stable_names = @import("stable_names.zig");

/// What declaring a compiler marker can fail with.
pub const MarkerError = error{UnsupportedInstruction} || std.mem.Allocator.Error;

/// A well-formed helper name for a hand-built fixture: the family prefix and a 32-digit key made from the type's id.
pub fn fixtureName(a: std.mem.Allocator, prefix: []const u8, ty: ir.Type) std.mem.Allocator.Error![]const u8 {
    var key: stable_names.TypeKey = undefined;
    std.crypto.hash.Blake3.hash(std.mem.asBytes(&ty), &key, .{});
    return std.fmt.allocPrint(a, "{s}{s}", .{ prefix, stable_names.keyText(key) });
}

/// Declare a borrowed provider marker named as the builder names it, keying types by structure alone.
pub fn declareProvider(a: std.mem.Allocator, module: *ir.Module, ty: ir.Type) MarkerError!u32 {
    var keys: stable_names.TypeKeys = .{};
    const providers = @import("borrowed_provider.zig");
    return providers.declare(a, module, ty, try stable_names.helperName(a, &keys, module, providers.prefixFor(module, ty), &.{ty}));
}

/// Declare a borrowed choice marker of `kind` named as the builder names it.
pub fn declareChoice(a: std.mem.Allocator, module: *ir.Module, kind: @import("borrow_selection.zig").Kind, first: ir.Type, value: ir.Type) MarkerError!u32 {
    var keys: stable_names.TypeKeys = .{};
    const selections = @import("borrow_selection.zig");
    return selections.declareChoice(a, module, first, value, try stable_names.helperName(a, &keys, module, try selections.choiceFamily(a, kind), &.{ first, value }));
}

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// Everything checking, building or emitting a test program can fail with.
pub const Error = language.diagnostic.Error || build.Error || emit_llvm.Error || verify_ir.Error || language.embedded_project.InitError;

/// Whether checking `source` needs a module table: a line that spells an
/// `import`, which only a project compilation resolves. A fixture that does not
/// import keeps the faster single-unit path, whose qualified names and
/// unknown-name diagnostics are the ones its test pinned.
pub fn needsModules(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "import ")) return true;
    return false;
}

/// Check `source` as a header-less program and build its Core IR in `arena`; the
/// IR is verified (`verify_ir.zig`) before it is returned. A fixture that imports
/// a standard module is built as an embedded project, so it may `import lists`.
pub fn buildSource(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) Error!ir.Module {
    return buildSourceFor(arena, source, refusal, 8);
}

/// `buildSource` lowered for a target whose pointers are `pointer_bytes` wide (`Target.pointerBytes`).
pub fn buildSourceFor(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal, pointer_bytes: u32) Error!ir.Module {
    if (needsModules(source)) return projectModuleFor(arena, source, refusal, pointer_bytes);
    var unit = try language.Compilation.init(arena, "test.selka", source);
    try unit.check();
    const module = try build.buildExecutable(arena, .{ .program = unit.program.?, .pointer_bytes = pointer_bytes }, refusal);
    try verified(arena, &module, &.{});
    return module;
}

/// The checked program of `source`: an embedded project when the text imports a
/// standard module, so the fixture may hold an `import`, and a single unit
/// otherwise. The caller's arena owns the program, which this returns by value.
pub fn checkedProgram(arena: std.mem.Allocator, source: []const u8) Error!language.typed.Program {
    const checked = try checkSource(arena, source);
    if (!checked.passed) {
        for (checked.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
        return error.SourceError;
    }
    return checked.program.?;
}

/// The diagnostics of checking `source` in whichever mode its shape allows, and
/// whether it checked; a rejection test keeps its single-unit expectations unless
/// its fixture needs a module.
pub const Checked = struct {
    diagnostics: []const language.diagnostic.Diagnostic,
    passed: bool,
    /// The checked program when the fixture checked, for a test that reads it.
    program: ?language.typed.Program = null,
    /// The source the checked program's spans index, when the fixture checked.
    src: ?language.source.Source = null,
};

/// Check `source`, as an embedded project when it imports and as a single unit
/// otherwise, and report every diagnostic with the checked program if any.
pub fn checkSource(arena: std.mem.Allocator, source: []const u8) Error!Checked {
    if (!needsModules(source)) {
        var unit = try language.Compilation.init(arena, "test.selka", source);
        const passed = if (unit.check()) |_| true else |err| switch (err) {
            error.SourceError => false,
            else => return err,
        };
        return .{ .diagnostics = unit.diagnostics.items, .passed = passed, .program = if (passed) unit.program else null, .src = unit.src };
    }
    var entry: ProjectSource = .{ .text = source };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &entry, .read = ProjectSource.read }, "main", .{});
    var index = language.interfaces.build(&project) catch |failure| switch (failure) {
        error.SourceError => return projectFailure(arena, &project),
        else => return failure,
    };
    var compilation = try language.project_compile.Compilation.init(&index);
    const passed = if (compilation.check()) |_| true else |failure| switch (failure) {
        error.SourceError => false,
        else => return failure,
    };
    return .{ .diagnostics = compilation.diagnostics.items.items, .passed = passed, .program = if (passed) compilation.program else null, .src = compilation.src };
}

/// A library (no `main`) and the merged source its spans index, checked as the entry module of an embedded project so
/// it may import a standard module.
pub const Library = struct { program: language.typed.Program, src: language.source.Source };

/// Check `source` as a library that may import standard modules; the arena owns every part, so the program outlives
/// the call.
pub fn libraryProject(arena: std.mem.Allocator, source: []const u8) Error!Library {
    const entry = try arena.create(ProjectSource);
    entry.* = .{ .text = source };
    const project = try arena.create(language.project.Project);
    project.* = language.project.Project.init(arena);
    try project.load(.{ .context = entry, .read = ProjectSource.read }, "main", .{});
    const index = try arena.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    const compilation = try arena.create(language.project_compile.Compilation);
    compilation.* = try language.project_compile.Compilation.init(index);
    return .{ .program = try compilation.checkLibraryProgram(), .src = compilation.src };
}

/// The `Checked` of a project that failed before its compilation existed: the
/// parser's own diagnostics against the module it read, from `project.problem`.
// twin-drift-ok: `stdlib_fixture.problemReport` is the unit root's copy and also
// carries the project's source for its `Report`; the core root cannot import that
// runner (it reaches `native_execute`), so this copy is `Checked`, which has none.
fn projectFailure(arena: std.mem.Allocator, project: *language.project.Project) Error!Checked {
    const problem = project.problem orelse return error.SourceError;
    if (problem.recovered.len != 0) return .{ .diagnostics = problem.recovered, .passed = false };
    const one = try arena.alloc(language.diagnostic.Diagnostic, 1);
    one[0] = .{
        .code = problem.code,
        .span = problem.site.span,
        .message = problem.message,
        .provenance = .{ .fix = if (problem.fix) |edit| .{ .edit = edit, .more = problem.fix_more } else null },
    };
    return .{ .diagnostics = one, .passed = false };
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

/// Carry every optimizer product to an emission fixture without dropping ancestry.
pub fn analysis(result: *const passes.Result) emit_llvm.Analysis {
    return .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance };
}

/// The textual Core IR of `source`.
pub fn irText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    return print.module(arena, &module);
}

/// Locate every offset at line 1. A debug location's column holds 16 bits, and a project that imports the standard library merges
/// more than 65,535 bytes of source before the program's own, so the column stops at the largest value LLVM accepts.
pub fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = @min(offset, 65534) + 1 };
}

/// The LLVM IR of `source`, with every trap located at line 1.
pub fn llvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try buildSource(arena, source, &refusal);
    const context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} } });
}

/// The LLVM IR of `source` compiled as an embedded project, so the program may
/// import the standard modules; every trap is located at line 1.
pub fn llvmTextOfProject(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var context: Entry = .{ .text = source };
    var program: language.embedded_project.Program = undefined;
    try program.init(arena, .{ .context = &context, .read = Entry.read });
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(arena, .{ .program = program.compilation.program.?, .source = program.compilation.src }, &refusal);
    const site_context: u8 = 0;
    return emit_llvm.emitModule(arena, &module, .{ .locator = .{ .context = &site_context, .locate = firstLine }, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} } });
}

/// One embedded `main.selka` source, served through the project loader so the
/// program may import the standard modules; every other path is the loader's.
const ProjectSource = struct {
    text: []const u8,

    /// Supply `main.selka`; any other path belongs to the standard loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
    }
};

/// The verified Core IR of `source` compiled as an embedded project, so the
/// program may import the standard modules.
pub fn projectModule(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal) Error!ir.Module {
    return projectModuleFor(arena, source, refusal, 8);
}

/// `projectModule` lowered for a target whose pointers are `pointer_bytes` wide (`Target.pointerBytes`).
pub fn projectModuleFor(arena: std.mem.Allocator, source: []const u8, refusal: *build.Refusal, pointer_bytes: u32) Error!ir.Module {
    var entry: ProjectSource = .{ .text = source };
    var program: language.embedded_project.Program = undefined;
    try program.init(arena, .{ .context = &entry, .read = ProjectSource.read });
    const module = try build.buildExecutable(arena, .{ .program = program.compilation.program.?, .source = program.compilation.src, .pointer_bytes = pointer_bytes }, refusal);
    try verified(arena, &module, &.{});
    return module;
}

/// The textual Core IR of `source` compiled as an embedded project.
fn irTextOfProject(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    const module = try projectModule(arena, source, &refusal);
    return print.module(arena, &module);
}

/// The textual Core IR of `source`, compiled as an embedded project, after the
/// release fact pass marked what it proved.
fn factsTextOfProject(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try projectModule(arena, source, &refusal);
    for (module.functions.items) |*function| {
        if (function.signature.linkage == .internal) _ = try facts.analyze(arena, function, .{});
    }
    try verified(arena, &module, &.{});
    return print.module(arena, &module);
}

/// The textual Core IR of `source`, compiled as an embedded project, after the
/// release passes.
pub fn optimizedTextOfProject(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try projectModule(arena, source, &refusal);
    _ = try runPasses(arena, &module, .trusted);
    return print.module(arena, &module);
}

/// The LLVM IR a release build of the project `source` emits.
pub fn releaseLlvmTextOfProject(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try projectModule(arena, source, &refusal);
    const result = try runPasses(arena, &module, .trusted);
    const context: u8 = 0;
    const locator: emit_llvm.Locator = .{ .context = &context, .locate = firstLine };
    return emit_llvm.emitModule(arena, &module, .{ .locator = locator, .source_path = "test.selka", .main = .{ .parameters = &.{ "args", "out" } }, .analysis = analysis(&result) });
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
    return releaseLlvmTextFor(arena, source, @import("target.zig").host);
}

/// The LLVM IR a `--verify-facts` release build of `source` emits.
pub fn verifyLlvmText(arena: std.mem.Allocator, source: []const u8) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSource(arena, source, &refusal);
    const result = try runPasses(arena, &module, .verify);
    const context: u8 = 0;
    const locator: emit_llvm.Locator = .{ .context = &context, .locate = firstLine };
    return emit_llvm.emitModule(arena, &module, .{ .locator = locator, .source_path = "test.selka", .main = .{ .parameters = &.{"out"} }, .analysis = analysis(&result), .verify = true });
}

/// The LLVM IR a release build of `source` emits for target description `target`.
pub fn releaseLlvmTextFor(arena: std.mem.Allocator, source: []const u8, target: @import("target.zig").Target) Error![]u8 {
    var refusal: build.Refusal = .{};
    var module = try buildSourceFor(arena, source, &refusal, target.pointerBytes());
    const result = try runPasses(arena, &module, .trusted);
    const context: u8 = 0;
    const locator: emit_llvm.Locator = .{ .context = &context, .locate = firstLine };
    return emit_llvm.emitModule(arena, &module, .{ .locator = locator, .source_path = "test.selka", .main = .{ .parameters = &.{ "args", "out" } }, .analysis = analysis(&result), .target = target });
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
pub const RunError = Error || driver.Error || error{ AnalyzedOwnership, SkipZigTest };

/// The release-mode switch of the tests: `-Dtest-release=true` runs their release builds, which the gate does not (it builds
/// debug only). The build's `test_release_options` module carries it.
const release_switch = @import("test_release_options");

/// Whether the tests' release builds run (`-Dtest-release=true`).
pub fn releaseEnabled() bool {
    return release_switch.enabled;
}

/// Skips the calling test while release builds are off. A release build calls this before it starts, after the debug
/// assertions the same test makes: the test is then reported as skipped, never as passed, and its debug half has run.
pub fn requireRelease() error{SkipZigTest}!void {
    if (!release_switch.enabled) return error.SkipZigTest;
}

/// Skips the calling test while release builds are off, when a command line given to the compiler asks for `--release`.
pub fn requireReleaseArgs(argv: []const []const u8) error{SkipZigTest}!void {
    for (argv) |arg| {
        if (std.mem.eql(u8, arg, "--release")) return requireRelease();
    }
}

/// Verify `module`, emit it (traps at line 1), compile it with `zig cc` at -O0
/// (or -O3 when `release`) and run it with no arguments.
pub fn runModule(arena: std.mem.Allocator, module: *const ir.Module, release: bool) RunError!Run {
    if (release) try requireRelease();
    try verified(arena, module, &.{});
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "hand.selka", .main = .{ .parameters = &.{"out"} } });
    return runLlvm(arena, llvm, .{ .release = release, .leakcheck = false });
}

/// How `runOwned` builds and runs a hand-built module.
pub const RunOptions = struct {
    release: bool = false,
    /// Verify mode: form-1 updates are asserted unique (`R_CORE_FACT`).
    verify: bool = false,
    /// Run with `SELKA_CORE_LEAKCHECK=1`, so blocks live at exit are reported on stderr.
    leakcheck: bool = true,
    /// Run the ownership pass first (off: the module counts by hand, or leaks).
    own: bool = true,
    /// `main`'s parameter names and, when it returns a `Result`, its case tags.
    main: emit_llvm.Main = .{ .parameters = &.{"out"} },
    /// Verify the IR first; off only for operand forms the verifier does not admit yet.
    check_ir: bool = true,
    /// Facts, vector plans and source ancestry, including injected test premises.
    analysis: emit_llvm.Analysis = .{},
};

/// Run the ownership pass over `module` (as a build would, after construction),
/// verify, emit, compile and run it, by default with the leak check on.
pub fn runOwned(arena: std.mem.Allocator, module: *ir.Module, options: RunOptions) RunError!Run {
    if (options.release) try requireRelease();
    // Pass output is already owned; a second pass lacks its mutable origin table.
    if (options.own and options.analysis.provenance != null) return error.AnalyzedOwnership;
    if (options.check_ir) try verified(arena, module, &.{});
    if (options.own) _ = try @import("own.zig").run(arena, module, .{ .verify = options.verify });
    if (options.check_ir) try verified(arena, module, &.{});
    const context: u8 = 0;
    const llvm = try emit_llvm.emitModule(arena, module, .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = "hand.selka", .main = options.main, .verify = options.verify, .analysis = options.analysis });
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
    if (release) try requireRelease();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = dir.dir.realPathFileAlloc(std.testing.io, ".", arena) catch return error.ToolFailed;
    var environment = std.testing.environ.createMap(arena) catch return error.ToolFailed;
    const zig = environment.get("ZIG") orelse "zig";
    const output = try std.fs.path.join(arena, &.{ root, "hand" });
    var log: std.ArrayList(u8) = .empty;
    // The program is linked from objects the per-user store keys by the unit's text, so a
    // work directory of the suite's own serves the same program to a later run of the same
    // text; the output below is a copy in this test's directory, run fresh.
    const work = options_paths.suiteCache(arena, @src()) catch return error.ToolFailed;
    _ = driver.link(arena, std.testing.io, &environment, .{
        .zig = zig,
        .work = work,
        .output = output,
        .family = .{ .mode = if (release) .release else .debug },
        .links = &.{},
        .units = &.{driver.wholeUnit(llvm)},
    }, &log) catch |err| {
        report("zig cc rejected the emitted module:\n{s}\n{s}\n", .{ log.items, llvm });
        return err;
    };
    if (options.leakcheck) environment.put("SELKA_CORE_LEAKCHECK", "1") catch return error.ToolFailed;
    const result = std.process.run(arena, std.testing.io, .{ .argv = &.{output}, .environ_map = &environment }) catch return error.ToolFailed;
    const status: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return .{ .stdout = result.stdout, .stderr = result.stderr, .status = status, .llvm = llvm };
}
