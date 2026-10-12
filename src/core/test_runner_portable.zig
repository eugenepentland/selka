//! Conservative ordinary-test identities for a separate cross-worktree receipt store.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const receipt = @import("test_runner_receipt.zig");
const discover = @import("test_runner_discover.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const closure = @import("canonical_closure.zig");
const pipeline = @import("pipeline.zig");
const emit = @import("emit_llvm.zig");
const callable = @import("callable_digest.zig");

/// Allocation or guarded input failures; unsupported portability is a null key.
pub const Error = @import("test_runner_property.zig").Error;
/// Existing cache qualifications apply, except force may replace a freshly passed key.
pub fn eligible(context: receipt.Context) bool {
    var normal = context;
    normal.options.controls.force = false;
    if (!std.mem.eql(u8, receipt.reuseReason(normal), "no-success-receipt")) return false;
    return context.options.properties.policy == .legacy;
}

/// A fresh canonical reachable closure, with only proven project locations normalized.
/// Strings, source positions, configuration bytes and embedded values remain exact.
pub fn key(context: receipt.Context, checked: frontend.Checked, case: discover.Case) Error!?[32]u8 {
    if (!eligible(context) or !ordinary(checked, case)) return null;
    var paths = Paths{ .context = context };
    const base_paths = try paths.settings() orelse return null;
    if (!try paths.addSource(checked.src)) return null;
    var why: build.Refusal = .{};
    const codegen = context.options.build.show.codegen;
    const module = build.buildRootsCached(context.arena, &.{case.function}, .{
        .program = checked.program,
        .source = checked.src,
        .single_owner = codegen.single_owner,
        .zero_rc = codegen.zero_rc,
    }, &why, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    if (!portableModule(&module)) return null;
    var locations = Locations{ .original = pipeline.locator(&checked.src), .paths = &paths.names };
    const shared = closure.Shared.build(context.arena, &module, .{ .context = &locations, .locate = Locations.locate }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    if (locations.missing) return null;
    var hash = std.crypto.hash.Blake3.init(.{});
    text(&hash, "core-test-portable-reachable-v1");
    hash.update(&try receipt.portableSettings(context, base_paths));
    text(&hash, case.name);
    shared.reach(context.arena, &.{0}, &hash) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return digest;
}

fn ordinary(checked: frontend.Checked, case: discover.Case) bool {
    if (case.shape != .boolean or case.parameters.len != 0 or case.other_parameters != 0) return false;
    const function = checked.program.functions[@backingInt(case.function)];
    if (function.signature.parameter_count != 0 or function.policy.host != null) return false;
    const effects = language.effect_set;
    const allowed = effects.bit(.managed_allocation) | effects.bit(.mutation);
    if (function.policy.effects & ~allowed != 0) return false;
    // Source externs have no complete native provider contract in this domain.
    for (checked.program.functions) |found| if (found.policy.c_abi) return false;
    return true;
}

fn portableModule(module: *const ir.Module) bool {
    if (callable.needed(module)) return false;
    for (module.functions.items) |function| {
        if (function.signature.linkage != .internal and !std.mem.startsWith(u8, function.name, "myl_core_")) return false;
        for (function.insts.items) |inst| if (inst.op == .err_trace) return false;
    }
    return true;
}

const Paths = struct {
    context: receipt.Context,
    names: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn relative(self: *const Paths, path: []const u8) Error!?[]const u8 {
        const c = self.context;
        const full = try std.fs.path.resolve(c.arena, &.{ c.entry.root, path });
        if (!inside(c.entry.root, full)) return null;
        const actual = std.Io.Dir.cwd().realPathFileAlloc(c.io, full, c.arena) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        if (!inside(c.entry.root, actual)) return null;
        const start = c.entry.root.len + @intFromBool(c.entry.root[c.entry.root.len - 1] != '/');
        if (start > full.len) return null;
        return full[start..];
    }

    fn settings(self: *const Paths) Error!?receipt.PortablePaths {
        var paths = receipt.PortablePaths{ .entry = try self.relative(self.context.entry.path) orelse return null };
        if (self.context.options.controls.cases) |path| paths.cases = try self.relative(path) orelse return null;
        if (self.context.entry.configuration) |configured| {
            paths.configuration = try self.relative(configured.path) orelse return null;
            if (configured.policy) |policy| paths.policy = try self.relative(policy.path) orelse return null;
        }
        return paths;
    }

    fn addSource(self: *Paths, source: language.source.Source) Error!bool {
        if (source.origins.len != 0) {
            for (source.origins) |origin| if (!try self.addSource(origin.original)) return false;
            return true;
        }
        if (std.mem.startsWith(u8, source.path, "@stdlib/")) {
            if (source.embeds.len != 0) return false;
            try self.names.put(self.context.arena, source.path, source.path);
            return true;
        }
        const relative_path = try self.relative(source.path) orelse return false;
        for (source.embeds) |embedded| {
            if (embedded.status != .ok) return false;
            const asset = try std.fs.path.resolve(self.context.arena, &.{ self.context.entry.root, std.fs.path.dirname(relative_path) orelse ".", embedded.path });
            if (try self.relative(asset) == null) return false;
        }
        try self.names.put(self.context.arena, source.path, relative_path);
        return true;
    }
};

const Locations = struct {
    original: emit.Locator,
    paths: *const std.StringHashMapUnmanaged([]const u8),
    missing: bool = false,

    fn locate(pointer: *const anyopaque, offset: u32) emit.Location {
        const self: *Locations = @ptrCast(@alignCast(@constCast(pointer)));
        var at = self.original.locate(self.original.context, offset);
        if (self.paths.get(at.path)) |relative_path| at.path = relative_path else self.missing = true;
        return at;
    }
};

fn inside(root: []const u8, path: []const u8) bool {
    if (std.mem.eql(u8, root, path)) return true;
    if (!std.mem.startsWith(u8, path, root)) return false;
    return root.len != 0 and (root[root.len - 1] == '/' or path[root.len] == '/');
}

fn text(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

const test_source =
    \\func helper() -> int:
    \\    return 1
    \\public func test_value() -> bool:
    \\    return helper() == 1
    \\func unused() -> int:
    \\    return 9
    \\func main() -> int:
    \\    return 0
    \\
;
const TestInput = struct { context: receipt.Context, checked: frontend.Checked, case: discover.Case, session: *frontend.Session };

fn testInput(a: std.mem.Allocator, dir: std.Io.Dir, source: []const u8, environment: *const std.process.Environ.Map) !TestInput {
    try dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = source });
    try dir.writeFile(std.testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":2}" });
    const root = try dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    var problems: std.ArrayList(u8) = .empty;
    const located = try @import("project_entry.zig").resolve(a, std.testing.io, path, &problems);
    const session = try a.create(frontend.Session);
    session.* = frontend.Session.init(a, std.testing.io, root);
    const checked = try session.checkFile(a, path, &problems);
    const cases = try discover.discover(a, checked.program, "app", &.{.{ .name = "app", .text = source }});
    return .{
        .context = .{
            .arena = a,
            .io = std.testing.io,
            .environment = environment,
            .options = .{ .path = path, .build = .{ .zig = "unselected-tool" } },
            .entry = located,
            .identity = .{
                .tool = .{ .path = "unselected-tool", .digest = @splat(5), .generation = @splat(0), .native_target = @splat(6), .inputs = 0, .memo_hit = false, .cacheable = true },
                .cache_plan = .{ .identity = @splat(7), .mode = .reference, .io = std.testing.io, .environ = environment, .directory = null, .artifact = null },
            },
        },
        .checked = checked,
        .case = cases[0],
        .session = session,
    };
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable ordinary test keys share roots while local keys remain distinct and closure edits revert" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var left = std.testing.tmpDir(.{});
    defer left.cleanup();
    var right = std.testing.tmpDir(.{});
    defer right.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const first = try testInput(a, left.dir, test_source, &environment);
    defer first.session.deinit();
    const second = try testInput(a, right.dir, test_source, &environment);
    defer second.session.deinit();
    const original = (try key(first.context, first.checked, first.case)).?;
    try std.testing.expectEqual(original, (try key(second.context, second.checked, second.case)).?);
    var inputs: std.ArrayList(receipt.Dependency) = .empty;
    try std.testing.expect(!std.mem.eql(u8, &try receipt.settings(first.context, &inputs), &try receipt.settings(second.context, &inputs)));
    const private = try testInput(a, left.dir, try std.mem.replaceOwned(u8, a, test_source, "return 9", "return 8"), &environment);
    defer private.session.deinit();
    try std.testing.expectEqual(original, (try key(private.context, private.checked, private.case)).?);
    const changed = try testInput(a, left.dir, try std.mem.replaceOwned(u8, a, test_source, "return 1", "return 2"), &environment);
    defer changed.session.deinit();
    try std.testing.expect(!std.mem.eql(u8, &original, &(try key(changed.context, changed.checked, changed.case)).?));
    const restored = try testInput(a, left.dir, test_source, &environment);
    defer restored.session.deinit();
    try std.testing.expectEqual(original, (try key(restored.context, restored.checked, restored.case)).?);
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable ordinary test keys bind settings and reject generated policy and external paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const input = try testInput(a, directory.dir, test_source, &environment);
    defer input.session.deinit();
    const original = (try key(input.context, input.checked, input.case)).?;
    try environment.put(@import("test_runner_options.zig").shared_cache_variable, "first-store");
    try std.testing.expectEqual(original, (try key(input.context, input.checked, input.case)).?);
    try environment.put(@import("test_runner_options.zig").shared_cache_variable, "second-store");
    try std.testing.expectEqual(original, (try key(input.context, input.checked, input.case)).?);
    var context = input.context;
    context.options.controls.force = true;
    try std.testing.expectEqual(original, (try key(context, input.checked, input.case)).?);
    context.options.build.show.codegen.counters = true;
    try std.testing.expect(!std.mem.eql(u8, &original, &(try key(context, input.checked, input.case)).?));
    context.options.build.show.codegen.counters = false;
    context.options.controls.ceilings.memory += 1;
    try std.testing.expect(!std.mem.eql(u8, &original, &(try key(context, input.checked, input.case)).?));
    context.options.properties.policy = .indexed_v1;
    try std.testing.expectEqual(@as(?[32]u8, null), try key(context, input.checked, input.case));
    context = input.context;
    context.entry.root = try std.fs.path.join(a, &.{ context.entry.root, "unrelated" });
    try std.testing.expectEqual(@as(?[32]u8, null), try key(context, input.checked, input.case));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "portable module refuses observable trace paths and unknown native providers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    try module.functions.append(a, .{ .name = "pure", .signature = .{ .params = &.{}, .ret = .bool } });
    try std.testing.expect(portableModule(&module));
    try module.functions.items[0].insts.append(a, .{ .op = .err_trace, .ty = .void });
    try std.testing.expect(!portableModule(&module));
    module.functions.items[0].insts.clearRetainingCapacity();
    try module.functions.append(a, .{ .name = "foreign", .signature = .{ .params = &.{}, .ret = .bool, .linkage = .extern_c } });
    try std.testing.expect(!portableModule(&module));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "zero RC portable receipts lower borrowed views in the selected ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const source =
        \\public func test_view() -> bool:
        \\    const text = "abcd" + str(7)
        \\    const part = text.borrow(0, 2)
        \\    return len(part) == 2
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const input = try testInput(a, directory.dir, source, &environment);
    defer input.session.deinit();
    var context = input.context;
    context.options.build.show.codegen.single_owner = true;
    context.options.build.show.codegen.zero_rc = true;
    const original = (try key(context, input.checked, input.case)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(original, (try key(context, input.checked, input.case)).?);
    const changed = try testInput(a, directory.dir, try std.mem.replaceOwned(u8, a, source, "borrow(0, 2)", "borrow(1, 3)"), &environment);
    defer changed.session.deinit();
    var changed_context = changed.context;
    changed_context.options.build.show.codegen = context.options.build.show.codegen;
    try std.testing.expect(!std.mem.eql(u8, &original, &(try key(changed_context, changed.checked, changed.case)).?));
}
