//! Which tests may share their receipts through the cross-worktree store. The store
//! holds the same root-relative keys as the private one (RECEIPT-PATHS-1); a test
//! shares only when every input it names provably lies inside its root.
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
/// An indexed property campaign keeps no receipts, private or shared.
pub fn eligible(context: receipt.Context) bool {
    var normal = context;
    normal.options.controls.force = false;
    if (!std.mem.eql(u8, receipt.reuseReason(normal), "no-success-receipt")) return false;
    return context.options.properties.policy == .legacy;
}

/// Whether `case`'s receipt (its ordinary root-relative key) may be shared: the run is
/// admitted, the test has no live effects, and its entry, cases, configuration,
/// policy, every source and every embedded asset resolve inside the entry's root,
/// as does every source position its reachable program carries. Literal values and
/// observable traces are never remapped: a program with error traces, an extern
/// function or a callable digest stays private.
pub fn shareable(context: receipt.Context, checked: frontend.Checked, case: discover.Case) Error!bool {
    if (!eligible(context) or !ordinary(checked, case)) return false;
    var paths = Paths{ .context = context };
    if (!try paths.settings()) return false;
    if (!try paths.addSource(checked.src)) return false;
    var why: build.Refusal = .{};
    const codegen = context.options.build.show.codegen;
    const module = build.buildRootsCached(context.arena, &.{case.function}, .{
        .program = checked.program,
        .source = checked.src,
        .single_owner = codegen.single_owner,
        .zero_rc = codegen.zero_rc,
    }, &why, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    if (!portableModule(&module)) return false;
    var locations = Locations{ .original = pipeline.locator(&checked.src), .paths = &paths.names };
    _ = closure.Shared.build(context.arena, &module, .{ .context = &locations, .locate = Locations.locate }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    return !locations.missing;
}

/// A test without live effects (`Host` calls), the same rule that lets it keep a
/// private receipt, in a program without source externs, which have no complete
/// native provider contract.
fn ordinary(checked: frontend.Checked, case: discover.Case) bool {
    const function = checked.program.functions[@backingInt(case.function)];
    const effects = language.effect_set;
    if (function.policy.host != null or function.policy.effects & effects.bit(.host) != 0) return false;
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

    /// Whether the entry, cases, configuration and policy all lie inside the root.
    fn settings(self: *const Paths) Error!bool {
        _ = try self.relative(self.context.entry.path) orelse return false;
        if (self.context.options.controls.cases) |path| _ = try self.relative(path) orelse return false;
        if (self.context.entry.configuration) |configured| {
            _ = try self.relative(configured.path) orelse return false;
            if (configured.policy) |policy| _ = try self.relative(policy.path) orelse return false;
        }
        return true;
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
test "shareable tests from two roots key alike in the private store and the shared store" {
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
    try std.testing.expect(try shareable(first.context, first.checked, first.case));
    try std.testing.expect(try shareable(second.context, second.checked, second.case));
    var inputs: std.ArrayList(receipt.Dependency) = .empty;
    try std.testing.expectEqual(try receipt.settings(first.context, &inputs), try receipt.settings(second.context, &inputs));
    const generated = try testInput(a, left.dir, "public func test_value(value: int) -> bool:\n    return value == value\nfunc main() -> int:\n    return 0\n", &environment);
    defer generated.session.deinit();
    try std.testing.expect(try shareable(generated.context, generated.checked, generated.case));
}

// spec-case: NEW-CORE-TEST-SHARED-1
test "shareable refuses indexed campaigns, forced-only admission failures and entries outside their root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const input = try testInput(a, directory.dir, test_source, &environment);
    defer input.session.deinit();
    var context = input.context;
    context.options.controls.force = true;
    try std.testing.expect(try shareable(context, input.checked, input.case));
    context.options.build.links = &.{"native.c"};
    try std.testing.expect(!try shareable(context, input.checked, input.case));
    context = input.context;
    context.options.build.facts = .verify;
    try std.testing.expect(try shareable(context, input.checked, input.case));
    context.options.properties.policy = .indexed_v1;
    try std.testing.expect(!try shareable(context, input.checked, input.case));
    context = input.context;
    context.entry.root = try std.fs.path.join(a, &.{ context.entry.root, "unrelated" });
    try std.testing.expect(!try shareable(context, input.checked, input.case));
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
test "zero RC tests lower borrowed views in the selected ABI and share under an ownership-bound key" {
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
    try std.testing.expect(try shareable(context, input.checked, input.case));
    var inputs: std.ArrayList(receipt.Dependency) = .empty;
    try std.testing.expect(!std.mem.eql(u8, &try receipt.settings(input.context, &inputs), &try receipt.settings(context, &inputs)));
    const changed = try testInput(a, directory.dir, try std.mem.replaceOwned(u8, a, source, "borrow(0, 2)", "borrow(1, 3)"), &environment);
    defer changed.session.deinit();
    var changed_context = changed.context;
    changed_context.options.build.show.codegen = context.options.build.show.codegen;
    try std.testing.expect(try shareable(changed_context, changed.checked, changed.case));
}
