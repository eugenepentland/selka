//! Which tests may share their records through the engine's per-user tier across worktrees. The tier holds the same
//! root-relative keys as the work directory (RECEIPT-PATHS-1); a test shares only when every input it names provably lies
//! inside its root (`test_runner_eligibility.zig` applies the rules here to the records the tier would take or serve).
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");
const receipt = @import("test_runner_receipt.zig");
const discover = @import("test_runner_discover.zig");
const build = @import("build.zig");
const ir = @import("ir.zig");
const closure = @import("canonical_closure.zig");
const pipeline = @import("pipeline.zig");
const emit = @import("emit_llvm.zig");
const callable = @import("callable_digest.zig");
const work = @import("test_runner_work.zig");

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
/// function or a callable digest stays private. `counters`, when given, counts the proof and the paths.
pub fn shareable(context: receipt.Context, checked: frontend.Checked, case: discover.Case, counters: ?*work.RuleCounters) Error!bool {
    if (!eligible(context) or !try reusable(context.arena, checked.program, case.function, counters)) return false;
    var paths = Paths{ .context = context, .counters = counters };
    if (!try paths.settings()) return false;
    if (!try paths.addSource(checked.src)) return false;
    return locatedInside(context, checked, case, &paths.names);
}

/// Whether the program `case` reaches builds portably and every source position it carries has a root-relative name in
/// `names`: the part of `shareable` that reads the test's own build.
fn locatedInside(context: receipt.Context, checked: frontend.Checked, case: discover.Case, names: *const std.StringHashMapUnmanaged([]const u8)) Error!bool {
    var why: build.Refusal = .{};
    const module = build.buildRootsCached(context.arena, &.{case.function}, .{
        .program = checked.program,
        .source = checked.src,
    }, &why, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    if (!portableModule(&module)) return false;
    var locations = Locations{ .original = pipeline.locator(&checked.src), .paths = names };
    _ = closure.Shared.build(context.arena, &module, .{ .context = &locations, .locate = Locations.locate }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    return !locations.missing;
}

/// `shareable` for a test whose reached functions the key derivation already read: `bare` says whether every one of them is
/// `test_runner_facts.bare` (no error trace, no extern or host function), which is what `portableModule` reads of a build of
/// the test's program. A keyed test reaches no callable digest (the key derivation refuses one), and its key holds no
/// position (D-T1-1), so the build's other reading, where each site is, has nothing to guard (D-T2-5).
pub fn shareableKnown(context: receipt.Context, checked: frontend.Checked, case: discover.Case, bare: bool, counters: ?*work.RuleCounters) Error!bool {
    if (!bare or !eligible(context)) return false;
    if (!try reusable(context.arena, checked.program, case.function, counters)) return false;
    var paths = Paths{ .context = context, .counters = counters };
    if (!try paths.settings()) return false;
    return paths.addSource(checked.src);
}

/// Why an execution receipt must remain private, or null when the linked
/// program and runner keys bind every observable input. Traces and callable
/// digests are safe here because their exact compiled bytes enter the key.
pub fn executionRefusal(context: receipt.Context, checked: frontend.Checked, case: discover.Case, counters: ?*work.RuleCounters) Error!?[]const u8 {
    if (!eligible(context)) return "shared-private-execution-policy";
    if (!try reusable(context.arena, checked.program, case.function, counters)) return "shared-private-live-or-unknown-input";
    var paths = Paths{ .context = context, .counters = counters };
    if (!try paths.settings()) return "shared-private-external-settings";
    if (!try paths.addSource(checked.src)) return "shared-private-external-source";
    return null;
}

/// What the receipt proof and the shared tier's rule read of one checked program, read once for each entry's run of it and
/// shared by every test (stage 1 of the test-loop plan): the program's first extern, the two carrier tables, the path
/// table (whether the settings lie inside the root, and each source's root-relative name or that one lies outside), and
/// each test's proof. Its answers are the per-call functions' (`refusal`, `shareable`, `shareableKnown`,
/// `executionRefusal`), which stay as the oracle a differential test holds it to; only how often they are computed
/// changes. A file that changes during a run is already an error (`SourceChanged`), so a real path read once holds for the
/// run. Its tables are built under `mutex` the first time a test needs them, in `context.arena` (the entry's, which
/// outlives every declaration of the entry), so any thread that decides a record may use it.
pub const Program = struct {
    context: receipt.Context,
    checked: frontend.Checked,
    counters: ?*work.RuleCounters = null,
    mutex: std.Io.Mutex = .init,
    carriers: ?Carriers = null,
    paths: ?PathTable = null,
    proofs: std.AutoHashMapUnmanaged(language.typed.FunctionId, ?Refusal) = .empty,

    /// The rule's reading of `checked` in the entry whose context is `context`, counted in `counters` when given.
    pub fn init(context: receipt.Context, checked: frontend.Checked, counters: ?*work.RuleCounters) Program {
        return .{ .context = context, .checked = checked, .counters = counters };
    }

    /// `refusal` of the test function `root`, walked once in the run: a later call answers from the first. `scratch` holds
    /// only the walk's own memory.
    pub fn refusal(self: *Program, scratch: std.mem.Allocator, root: language.typed.FunctionId) std.mem.Allocator.Error!?Refusal {
        const io = self.context.io;
        self.mutex.lockUncancelable(io);
        const known = self.proofs.get(root);
        self.mutex.unlock(io);
        if (known) |answer| return answer;
        const carriers = try self.carrierTables();
        if (self.counters) |counted| counted.proved();
        const program = self.checked.program;
        const found: ?Refusal = if (carriers.extern_function) |id| .{ .reason = .c_abi, .function = id } else try walk(scratch, program, carriers.host, carriers.callable, root);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        try self.proofs.put(self.context.arena, root, found);
        return found;
    }

    /// `shareable` for `case`, in the run `context` (its allocator is the call's scratch).
    pub fn shareable(self: *Program, context: receipt.Context, case: discover.Case) Error!bool {
        if (!eligible(context) or (try self.refusal(context.arena, case.function)) != null) return false;
        const table = try self.pathTable();
        if (!table.settings or !table.sources) return false;
        return locatedInside(context, self.checked, case, &table.names);
    }

    /// `shareableKnown` for `case`, in the run `context`.
    pub fn shareableKnown(self: *Program, context: receipt.Context, case: discover.Case, bare: bool) Error!bool {
        if (!bare or !eligible(context)) return false;
        if ((try self.refusal(context.arena, case.function)) != null) return false;
        const table = try self.pathTable();
        return table.settings and table.sources;
    }

    /// `executionRefusal` for `case`, in the run `context`.
    pub fn executionRefusal(self: *Program, context: receipt.Context, case: discover.Case) Error!?[]const u8 {
        if (!eligible(context)) return "shared-private-execution-policy";
        if ((try self.refusal(context.arena, case.function)) != null) return "shared-private-live-or-unknown-input";
        const table = try self.pathTable();
        if (!table.settings) return "shared-private-external-settings";
        if (!table.sources) return "shared-private-external-source";
        return null;
    }

    fn carrierTables(self: *Program) std.mem.Allocator.Error!Carriers {
        const io = self.context.io;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.carriers) |known| return known;
        const program = self.checked.program;
        var extern_function: ?language.typed.FunctionId = null;
        for (program.functions) |function| if (function.policy.c_abi) {
            extern_function = function.id;
            break;
        };
        const host = try carrierTypes(self.context.arena, program.records, .host);
        const callable_types = try carrierTypes(self.context.arena, program.records, .callable);
        self.carriers = .{ .extern_function = extern_function, .host = host, .callable = callable_types };
        return self.carriers.?;
    }

    fn pathTable(self: *Program) Error!*const PathTable {
        const io = self.context.io;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.paths) |*known| return known;
        var paths = Paths{ .context = self.context, .counters = self.counters };
        const settings = try paths.settings();
        const sources = settings and try paths.addSource(self.checked.src);
        self.paths = .{ .settings = settings, .sources = sources, .names = paths.names };
        return &self.paths.?;
    }
};

/// A program's first extern function (the proof refuses every test of a program that has one) and its carrier tables.
const Carriers = struct { extern_function: ?language.typed.FunctionId, host: []const bool, callable: []const bool };

/// Whether the entry's settings lie inside its root, whether every source and embedded asset does (read only when the
/// settings do), and each source's root-relative name.
const PathTable = struct { settings: bool, sources: bool, names: std.StringHashMapUnmanaged([]const u8) };

/// Why the receipt proof refused a test, and the function whose body it was reading.
pub const Refusal = struct {
    /// What the proof found.
    reason: Reason,
    /// The function the proof was in; for `c_abi` the extern itself.
    function: language.typed.FunctionId,

    /// The finding. Each names an input the test's key cannot bind, or a body the proof cannot read.
    pub const Reason = enum {
        /// A function with the C ABI (an `extern func`) exists in the program, reachable or not.
        c_abi,
        /// A reachable function takes its authority from the host (`policy.host`).
        host_function,
        /// A reachable parameter, local or expression carries a `Host` capability, directly or in an aggregate.
        host_value,
        /// A callback is invoked in a program whose callable identities (`function_digest`) or test inputs name
        /// functions outside the call tree, so the targets the proof followed need not be all of them.
        unbounded_callback,
        /// A reachable body is not available (a cached stand-in) or its identity is invalid.
        unknown_body,
        /// A reachable call reads the pool's size or the machine's CPU count (`parallel.threads`, `parallel.cpus`): `--threads`
        /// and the machine set them, and no key binds either, so an old pass says nothing of another count.
        pool_size,
    };

    /// The finding as a phrase that names the function, the tail of the cache reason `live-effects: ...`.
    pub fn describe(self: Refusal, a: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const u8 {
        const index = @backingInt(self.function);
        const name = if (index < program.functions.len) program.functions[index].name else "?";
        return switch (self.reason) {
            .c_abi => std.fmt.allocPrint(a, "the program declares the extern function {s}", .{name}),
            .host_function => std.fmt.allocPrint(a, "{s} is a host function", .{name}),
            .host_value => std.fmt.allocPrint(a, "{s} reaches a Host capability", .{name}),
            .unbounded_callback => std.fmt.allocPrint(a, "{s} calls a callback beside function_digest or a callable test input", .{name}),
            .unknown_body => std.fmt.allocPrint(a, "{s} has no checked body", .{name}),
            .pool_size => std.fmt.allocPrint(a, "{s} reads the thread count or the CPU count, which no key binds", .{name}),
        };
    }
};

/// Whether the complete typed call closure of `root` has no live or unknown Host input; `counters` counts the proof.
pub fn reusable(a: std.mem.Allocator, program: language.typed.Program, root: language.typed.FunctionId, counters: ?*work.RuleCounters) std.mem.Allocator.Error!bool {
    return (try refusal(a, program, root, counters)) == null;
}

/// Prove the complete typed call closure has no live or unknown Host input, or say what stopped the proof.
/// Every source extern is refused even when it is unreachable. Function values are followed eagerly: the
/// target of every `function_value` the closure creates joins it, and a callback can only hold such a value
/// (a value cannot come from outside the closure except through a Host input, which is refused, or a callable
/// parameter of the test itself), so a callback invocation reaches no code the proof has not read. It stays
/// unknown only beside `function_digest`, whose digest covers every function a callback could name, or when
/// the test takes a callable as input. A visited set closes recursion without assuming a cycle is pure. `counters`, when
/// given, counts the call (`rule.proofs` of the work report).
pub fn refusal(a: std.mem.Allocator, program: language.typed.Program, root: language.typed.FunctionId, counters: ?*work.RuleCounters) std.mem.Allocator.Error!?Refusal {
    if (counters) |counted| counted.proved();
    for (program.functions) |function| if (function.policy.c_abi) return .{ .reason = .c_abi, .function = function.id };
    const host_types = try carrierTypes(a, program.records, .host);
    defer a.free(host_types);
    const callable_types = try carrierTypes(a, program.records, .callable);
    defer a.free(callable_types);
    return walk(a, program, host_types, callable_types, root);
}

/// The proof's walk of `root`'s call tree, given the program's carrier tables.
fn walk(a: std.mem.Allocator, program: language.typed.Program, host_types: []const bool, callable_types: []const bool, root: language.typed.FunctionId) std.mem.Allocator.Error!?Refusal {
    const typed = language.typed;
    const visited = try a.alloc(bool, program.functions.len);
    defer a.free(visited);
    @memset(visited, false);
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    defer pending.deinit(a);
    try pending.append(a, root);
    var scan: Scan = .{ .program = program, .host_types = host_types, .callable_types = callable_types, .pending = &pending };
    while (pending.pop()) |id| {
        const index = @backingInt(id);
        if (index >= program.functions.len) return .{ .reason = .unknown_body, .function = id };
        if (visited[index]) continue;
        visited[index] = true;
        if (try scan.function(a, id, id == root)) |refused| return refused;
    }
    if (scan.unresolved) |at| if (scan.identities or scan.callable_input) return .{ .reason = .unbounded_callback, .function = at };
    return null;
}

/// What the proof carries from one function to the next: the functions still to read, and what the bodies so far did that decides at the end
/// whether an invoked callback is bounded (it is not beside `function_digest`, or when the test takes a callable).
const Scan = struct {
    program: language.typed.Program,
    host_types: []const bool,
    callable_types: []const bool,
    pending: *std.ArrayList(language.typed.FunctionId),
    /// The first function that invokes a callback through a value.
    unresolved: ?language.typed.FunctionId = null,
    /// Whether some body asks for a callable's identity.
    identities: bool = false,
    /// Whether the test function takes a function value as input.
    callable_input: bool = false,

    /// Read the body of `id`: a refusal if it holds a Host input or cannot be read, else queue the functions it reaches.
    fn function(self: *Scan, a: std.mem.Allocator, id: language.typed.FunctionId, is_root: bool) std.mem.Allocator.Error!?Refusal {
        const program = self.program;
        const function_body = program.functions[@backingInt(id)];
        if (@backingInt(function_body.scope.body) >= program.statements.len or !function_body.scope.body_complete) return .{ .reason = .unknown_body, .function = id };
        if (function_body.policy.host != null) return .{ .reason = .host_function, .function = id };
        if (function_body.signature.parameter_count > function_body.scope.locals.len) return .{ .reason = .unknown_body, .function = id };
        for (function_body.scope.locals) |local| if (possibleHost(local.ty, self.host_types)) return .{ .reason = .host_value, .function = id };
        if (is_root) for (function_body.scope.locals[0..function_body.signature.parameter_count]) |input| {
            self.callable_input = self.callable_input or carries(input.ty, self.callable_types, .callable);
        };
        var walker = try language.typed_walk.Walker.init(a, program, function_body.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            if (item != .expression) continue;
            const node = program.nodes[@backingInt(item.expression)];
            if (possibleHost(node.ty, self.host_types)) return .{ .reason = .host_value, .function = id };
            if (node.data == .call and @backingInt(node.data.call.function) < program.functions.len and readsPool(program.functions[@backingInt(node.data.call.function)]))
                return .{ .reason = .pool_size, .function = node.data.call.function };
            try self.reach(a, id, node);
        }
        return null;
    }

    /// Queue what one expression reaches and note the callback invocations and identities.
    fn reach(self: *Scan, a: std.mem.Allocator, id: language.typed.FunctionId, node: language.typed.Node) std.mem.Allocator.Error!void {
        switch (node.data) {
            .call => |call| try self.pending.append(a, call.function),
            .function_value => |target| try self.pending.append(a, target),
            .invoke => |invoke| {
                const callee = self.program.nodes[@backingInt(invoke.callee)];
                if (callee.data == .function_value) {
                    try self.pending.append(a, callee.data.function_value);
                } else if (self.unresolved == null) self.unresolved = id;
            },
            // `function_digest(callback)` is the one conversion of a function value: a `str` of its identity.
            .cast => |operand| self.identities = self.identities or carries(self.program.nodes[@backingInt(operand)].ty, self.callable_types, .callable),
            else => {},
        }
    }
};

/// Whether `function` is `parallel.threads` or `parallel.cpus`, the two reads of what `--threads` and the machine decide.
fn readsPool(function: language.typed.Function) bool {
    return function.policy.builtin and (std.mem.eql(u8, function.name, "parallel::threads") or std.mem.eql(u8, function.name, "parallel::cpus"));
}

/// What a type can carry that the receipt proof tracks.
const Carrier = enum { host, callable };

/// Types carrying `carrier`, closed to a fixed point over recursive shapes.
fn carrierTypes(a: std.mem.Allocator, records: []const language.typed.Record, carrier: Carrier) std.mem.Allocator.Error![]bool {
    const found = try a.alloc(bool, records.len);
    @memset(found, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, index| {
            if (found[index]) continue;
            var holds = carrier == .callable and record.contract.callback != null;
            for (record.fields) |field| holds = holds or carries(field.ty, found, carrier);
            if (record.shape.array) |array| holds = holds or carries(array.element, found, carrier);
            if (record.shape.buffer) |element| holds = holds or carries(element, found, carrier);
            if (record.shape.domain) |backing| holds = holds or carries(backing, found, carrier);
            if (record.shape.variants) |variants| for (variants.cases) |case| {
                if (case.payload) |payload| holds = holds or carries(payload, found, carrier);
            };
            if (holds) {
                found[index] = true;
                changed = true;
            }
        }
    }
    return found;
}

fn carries(ty: language.typed.Type, found: []const bool, carrier: Carrier) bool {
    if (carrier == .host and ty == .host_cap) return true;
    if (!ty.isAggregate()) return false;
    const index = ty.recordIndex();
    return index >= found.len or found[index];
}

fn possibleHost(ty: language.typed.Type, host_types: []const bool) bool {
    return carries(ty, host_types, .host);
}

fn portableModule(module: *const ir.Module) bool {
    if (callable.needed(module)) return false;
    for (module.functions.items) |function| if (!@import("test_runner_facts.zig").bare(function)) return false;
    return true;
}

const Paths = struct {
    context: receipt.Context,
    names: std.StringHashMapUnmanaged([]const u8) = .empty,
    counters: ?*work.RuleCounters = null,

    fn relative(self: *const Paths, path: []const u8) Error!?[]const u8 {
        if (self.counters) |counted| counted.resolved();
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
    try dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    try dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":2}" });
    return inputAt(a, dir, "app.selka", source, environment);
}

/// The input of the entry `entry` (relative to `dir`, which holds the project's `selka.json`), whose text is `source`.
fn inputAt(a: std.mem.Allocator, dir: std.Io.Dir, entry: []const u8, source: []const u8, environment: *const std.process.Environ.Map) !TestInput {
    const root = try dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, entry });
    var problems: std.ArrayList(u8) = .empty;
    const located = try @import("project_entry.zig").resolve(a, std.testing.io, path, &problems);
    const session = try a.create(frontend.Session);
    session.* = frontend.Session.init(a, std.testing.io, root);
    located.configure(session);
    // As the runner checks an entry (`test_runner.checkEntry`): a project module by name, else the file alone.
    const project = @import("selka").project.validName(located.name);
    const checked = if (project) try session.check(a, located.name, &problems) else try session.checkFile(a, path, &problems);
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
    try std.testing.expect(try shareable(first.context, first.checked, first.case, null));
    try std.testing.expect(try shareable(second.context, second.checked, second.case, null));
    var inputs: std.ArrayList(receipt.Dependency) = .empty;
    try std.testing.expectEqual(try receipt.settings(first.context, &inputs), try receipt.settings(second.context, &inputs));
    const generated = try testInput(a, left.dir, "public func test_value(value: int) -> bool:\n    return value == value\nfunc main() -> int:\n    return 0\n", &environment);
    defer generated.session.deinit();
    try std.testing.expect(try shareable(generated.context, generated.checked, generated.case, null));
}

// spec: T2-PORTABLE-KNOWN-1
test "the portability rule told the reach is bare decides as the rule that builds the program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const plain = try testInput(a, directory.dir, test_source, &environment);
    defer plain.session.deinit();
    try std.testing.expect(try shareable(plain.context, plain.checked, plain.case, null));
    try std.testing.expect(try shareableKnown(plain.context, plain.checked, plain.case, true, null));
    try std.testing.expect(!try shareableKnown(plain.context, plain.checked, plain.case, false, null));
    // An error return trace: the built program has the trace instruction, which is what `bare` refuses.
    const traced_source = "func helper() -> int fails str:\n    fail \"no\"\npublic func test_value() -> bool fails str:\n    const value = try helper()\n    return value == 1\nfunc main() -> int:\n    return 0\n";
    const traced = try testInput(a, directory.dir, traced_source, &environment);
    defer traced.session.deinit();
    try std.testing.expect(!try shareable(traced.context, traced.checked, traced.case, null));
    var why: build.Refusal = .{};
    const module = try build.buildRootsCached(a, &.{traced.case.function}, .{ .program = traced.checked.program, .source = traced.checked.src }, &why, null);
    var any_traced = false;
    for (module.functions.items) |function| any_traced = any_traced or !@import("test_runner_facts.zig").bare(function);
    try std.testing.expect(any_traced);
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
    try std.testing.expect(try shareable(context, input.checked, input.case, null));
    context.options.build.links = &.{"native.c"};
    try std.testing.expect(!try shareable(context, input.checked, input.case, null));
    context = input.context;
    context.options.build.facts = .verify;
    try std.testing.expect(try shareable(context, input.checked, input.case, null));
    context.options.properties.policy = .indexed_v1;
    try std.testing.expect(!try shareable(context, input.checked, input.case, null));
    context = input.context;
    context.entry.root = try std.fs.path.join(a, &.{ context.entry.root, "unrelated" });
    try std.testing.expect(!try shareable(context, input.checked, input.case, null));
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

// spec-case: NEW-CORE-TEST-SHARED-1
test "ownership tests lower borrowed views and share portable receipts" {
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
        \\    const part = text[0:2]
        \\    return len(part) == 2
        \\func main() -> int:
        \\    return 0
        \\
    ;
    const input = try testInput(a, directory.dir, source, &environment);
    defer input.session.deinit();
    try std.testing.expect(try shareable(input.context, input.checked, input.case, null));
    const changed = try testInput(a, directory.dir, try std.mem.replaceOwned(u8, a, source, "borrow(0, 2)", "borrow(1, 3)"), &environment);
    defer changed.session.deinit();
    try std.testing.expect(try shareable(changed.context, changed.checked, changed.case, null));
}

// spec-case: EXEC-RECEIPT-1
test "execution sharing permits callable identities but reports C extern and policy refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const callable_input = try testInput(a, directory.dir, "func compute() -> int:\n    return 3\npublic func test_value() -> bool:\n" ++
        "    return strings.char_count(function_digest(compute)) == 64\nfunc main() -> int:\n    return 0\n", &environment);
    defer callable_input.session.deinit();
    try std.testing.expect(!try shareable(callable_input.context, callable_input.checked, callable_input.case, null));
    try std.testing.expectEqual(@as(?[]const u8, null), try executionRefusal(callable_input.context, callable_input.checked, callable_input.case, null));
    var linked = callable_input.context;
    linked.options.build.links = &.{"native.c"};
    try std.testing.expectEqualStrings("shared-private-execution-policy", (try executionRefusal(linked, callable_input.checked, callable_input.case, null)).?);
    const external = try testInput(a, directory.dir, "extern func stamp(host: Host) -> int\npublic func test_value() -> bool:\n    return True\nfunc main() -> int:\n    return 0\n", &environment);
    defer external.session.deinit();
    try std.testing.expectEqualStrings("shared-private-live-or-unknown-input", (try executionRefusal(external.context, external.checked, external.case, null)).?);
}

/// Exercise the receipt proof on checked language programs, without lowering.
fn expectReusable(a: std.mem.Allocator, source: []const u8, expected: bool) !void {
    var compilation = try language.Compilation.init(a, "capability-receipts.selka", source);
    defer compilation.deinit();
    try compilation.check();
    const program = compilation.program.?;
    for (program.functions) |function| if (std.mem.eql(u8, function.name, "subject")) {
        try std.testing.expectEqual(expected, try reusable(a, program, function.id, null));
        return;
    };
    return error.TestUnexpectedResult;
}

// spec: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof follows calls and closes recursive cycles" {
    try expectReusable(std.testing.allocator, "func a(n: int) -> bool:\n    if n == 0:\n        return True\n    return b(n - 1)\n\nfunc b(n: int) -> bool:\n" ++
        "    return a(n)\n\nfunc subject() -> bool:\n    return a(3)\n\nfunc main() -> int:\n    return 0\n", true);
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof refuses direct and nested Host inputs" {
    try expectReusable(std.testing.allocator, "func subject(host: Host) -> bool:\n    _ = host\n    return True\n\nfunc main() -> int:\n    return 0\n", false);
    try expectReusable(std.testing.allocator, "record Input:\n    host: Host\n\nfunc subject(input: Input) -> bool:\n    _ = input\n    return True\n\nfunc main() -> int:\n    return 0\n", false);
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof refuses unreachable extern declarations" {
    try expectReusable(std.testing.allocator, "extern func unused(host: Host) -> int\n\nfunc subject() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n", false);
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof follows function values and refuses unresolved callbacks" {
    try expectReusable(std.testing.allocator, "func hidden(host: Host) -> bool:\n    _ = host\n    return True\n\nfunc subject() -> bool:\n    _ = hidden\n    return True\n\nfunc main() -> int:\n    return 0\n", false);
    try expectReusable(std.testing.allocator, "func subject(callback: func() -> bool) -> bool:\n    return callback()\n\nfunc main() -> int:\n    return 0\n", false);
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof follows a callback invoked through a local, a field or a parameter to the values it can hold" {
    // The evaluator pattern: function values are stored in a record and invoked through its field; every one is created by a
    // `function_value` inside the call tree, so the proof has read each target.
    try expectReusable(std.testing.allocator, "func one() -> int:\n    return 1\n\nfunc pick() -> func() -> int:\n    return one\n\nfunc subject() -> bool:\n" ++
        "    const callback = pick()\n    return callback() == 1\n\nfunc main() -> int:\n    return 0\n", true);
    try expectReusable(std.testing.allocator, "record Hooks:\n    run: func(int) -> int\n\nfunc twice(value: int) -> int:\n    return value * 2\n\n" ++
        "func apply(hooks: Hooks, value: int) -> int:\n    const run = hooks.run\n    return run(value)\n\nfunc subject() -> bool:\n" ++
        "    const hooks = Hooks(run=twice)\n    return apply(hooks, 4) == 8\n\nfunc main() -> int:\n    return 0\n", true);
    // A function value that names a Host-taking function is followed even though the invoked callback is another one.
    try expectReusable(std.testing.allocator, "func hidden(host: Host) -> bool:\n    _ = host\n    return True\n\nfunc one() -> int:\n    return 1\n\n" ++
        "func pick() -> func() -> int:\n    return one\n\nfunc subject() -> bool:\n    _ = hidden\n    const callback = pick()\n    return callback() == 1\n\nfunc main() -> int:\n    return 0\n", false);
}

/// The refusal for `source`'s `subject`, or null when its call tree may publish a receipt.
fn refusalFor(a: std.mem.Allocator, source: []const u8, compilation: *language.Compilation) !?Refusal {
    compilation.* = try language.Compilation.init(a, "refusal.selka", source);
    try compilation.check();
    const program = compilation.program.?;
    for (program.functions) |function| if (std.mem.eql(u8, function.name, "subject")) return refusal(a, program, function.id, null);
    return error.TestUnexpectedResult;
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof names what stopped it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var compilation: language.Compilation = undefined;
    const direct = (try refusalFor(a, "func subject(host: Host) -> bool:\n    _ = host\n    return True\n\nfunc main() -> int:\n    return 0\n", &compilation)).?;
    try std.testing.expectEqual(Refusal.Reason.host_value, direct.reason);
    try std.testing.expectEqualStrings("subject reaches a Host capability", try direct.describe(a, compilation.program.?));
    const extern_text = (try refusalFor(a, "extern func stamp(host: Host) -> int\n\nfunc subject() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n", &compilation)).?;
    try std.testing.expectEqual(Refusal.Reason.c_abi, extern_text.reason);
    try std.testing.expectEqualStrings("the program declares the extern function stamp", try extern_text.describe(a, compilation.program.?));
    // A callback beside `function_digest` is the one invocation the proof cannot bound.
    const digest = (try refusalFor(a, "func one() -> int:\n    return 1\n\nfunc apply(callback: func() -> int) -> int:\n    return callback()\n\nfunc subject() -> bool:\n" ++
        "    return apply(one) == 1 and len(function_digest(one)) == 64\n\nfunc main() -> int:\n    return 0\n", &compilation)).?;
    try std.testing.expectEqual(Refusal.Reason.unbounded_callback, digest.reason);
    try std.testing.expectEqualStrings("apply calls a callback beside function_digest or a callable test input", try digest.describe(a, compilation.program.?));
    // The same program without the digest, and a digest without a callback invocation, publish.
    try std.testing.expect((try refusalFor(a, "func one() -> int:\n    return 1\n\nfunc apply(callback: func() -> int) -> int:\n    return callback()\n\nfunc subject() -> bool:\n" ++
        "    return apply(one) == 1\n\nfunc main() -> int:\n    return 0\n", &compilation)) == null);
    try std.testing.expect((try refusalFor(a, "func one() -> int:\n    return 1\n\nfunc subject() -> bool:\n    return len(function_digest(one)) == 64\n\nfunc main() -> int:\n    return 0\n", &compilation)) == null);
}

/// The subject in either lexical or module-qualified checked graphs.
fn subject(program: language.typed.Program) !language.typed.Function {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, "subject") or std.mem.endsWith(u8, function.name, "::subject")) return function;
    return error.TestUnexpectedResult;
}

/// Check a cached module once, so the second session can use real summary stubs.
fn summaryInput(a: std.mem.Allocator, root: []const u8, cache: []const u8) !*frontend.Session {
    const session = try a.create(frontend.Session);
    session.* = frontend.Session.init(a, std.testing.io, root);
    try session.enableCache(a, cache);
    session.validationOnly();
    var problems: std.ArrayList(u8) = .empty;
    _ = try session.check(a, "app", &problems);
    return session;
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof distinguishes materialized empty bodies from cached summary stubs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const source = "public func subject() -> Unit:\n    pass\n\nfunc main() -> int:\n    return 0\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.selka", .data = source });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "private" });
    const cold = try summaryInput(a, root, cache);
    defer cold.deinit();
    const cold_program = cold.graph.compilation.program.?;
    const cold_subject = try subject(cold_program);
    try std.testing.expect(cold_subject.scope.body_complete);
    try std.testing.expect(try reusable(a, cold_program, cold_subject.id, null));
    const warm = try summaryInput(a, root, cache);
    defer warm.deinit();
    const warm_program = warm.graph.compilation.program.?;
    const warm_subject = try subject(warm_program);
    try std.testing.expect(warm.statistics().summaries > 0);
    try std.testing.expect(!warm_subject.scope.body_complete);
    try std.testing.expect(!try reusable(a, warm_program, warm_subject.id, null));
}

// spec-case: TEST-RECEIPT-CAPABILITY-1
test "persistent receipt proof refuses an unknown body and invalid body identity" {
    var compilation = try language.Compilation.init(std.testing.allocator, "unknown-body.selka", "func subject() -> Unit:\n    pass\n\nfunc main() -> int:\n    return 0\n");
    defer compilation.deinit();
    try compilation.check();
    var program = compilation.program.?;
    const function = try subject(program);
    const functions = try std.testing.allocator.dupe(language.typed.Function, program.functions);
    defer std.testing.allocator.free(functions);
    program.functions = functions;
    functions[@backingInt(function.id)].scope.body_complete = false;
    try std.testing.expect(!try reusable(std.testing.allocator, program, function.id, null));
    functions[@backingInt(function.id)].scope.body_complete = true;
    functions[@backingInt(function.id)].scope.body = @fromBackingInt(program.statements.len);
    try std.testing.expect(!try reusable(std.testing.allocator, program, function.id, null));
}

/// Hold `Program` to the per-call functions on every test of `checked` in `context`: equal proofs and refusal texts, equal
/// answers of the three rules (`shareableKnown` told both ways), each asked twice so that the second answer comes from what
/// the first made. The reading walks each test once, and resolves exactly the paths one call of the per-call rule resolves.
fn expectSameAnswers(a: std.mem.Allocator, context: receipt.Context, checked: frontend.Checked, cases: []const discover.Case) !void {
    var counters: work.RuleCounters = .{};
    var program = Program.init(context, checked, &counters);
    for ([_]u8{ 0, 1 }) |_| for (cases) |case| {
        const old = try refusal(a, checked.program, case.function, null);
        const new = try program.refusal(a, case.function);
        try std.testing.expectEqual(old == null, new == null);
        if (old) |found| {
            try std.testing.expectEqual(found.reason, new.?.reason);
            try std.testing.expectEqual(found.function, new.?.function);
            try std.testing.expectEqualStrings(try found.describe(a, checked.program), try new.?.describe(a, checked.program));
        }
        try std.testing.expectEqual(try shareable(context, checked, case, null), try program.shareable(context, case));
        try std.testing.expectEqual(try shareableKnown(context, checked, case, true, null), try program.shareableKnown(context, case, true));
        try std.testing.expectEqual(try shareableKnown(context, checked, case, false, null), try program.shareableKnown(context, case, false));
        const old_reason = try executionRefusal(context, checked, case, null);
        const new_reason = try program.executionRefusal(context, case);
        try std.testing.expectEqualStrings(old_reason orelse "shareable", new_reason orelse "shareable");
    };
    try std.testing.expectEqual(cases.len, counters.snapshot().proofs);
    var once: work.RuleCounters = .{};
    for (cases) |case| {
        once = .{};
        _ = try executionRefusal(context, checked, case, &once);
        if (once.snapshot().paths != 0) break;
    }
    try std.testing.expectEqual(once.snapshot().paths, counters.snapshot().paths);
}

/// Every test of `input`'s program, whose entry module `app` has the text `source`, sorted by name.
fn casesOf(a: std.mem.Allocator, input: TestInput, source: []const u8) ![]const discover.Case {
    return discover.discover(a, input.checked.program, "app", &.{.{ .name = "app", .text = source }});
}

const traced_two = "func helper() -> int fails str:\n    fail \"no\"\npublic func test_value() -> bool fails str:\n" ++
    "    const value = try helper()\n    return value == 1\npublic func test_other() -> bool:\n    return True\nfunc main() -> int:\n    return 0\n";
const extern_two = "extern func stamp(host: Host) -> int\npublic func test_value() -> bool:\n    return True\n" ++
    "public func test_other() -> bool:\n    return 1 == 1\nfunc main() -> int:\n    return 0\n";
const host_two = "func hidden(host: Host) -> bool:\n    _ = host\n    return True\n\npublic func test_value() -> bool:\n" ++
    "    _ = hidden\n    return True\n\npublic func test_plain() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n";
const digest_two = "func one() -> int:\n    return 1\n\nfunc apply(callback: func() -> int) -> int:\n    return callback()\n\n" ++
    "public func test_value() -> bool:\n    return apply(one) == 1 and len(function_digest(one)) == 64\n\npublic func test_named() -> bool:\n" ++
    "    return len(function_digest(one)) == 64\n\nfunc main() -> int:\n    return 0\n";
const asset_two = "public func test_asset() -> bool:\n    return len(embed_bytes(\"data.bin\")) == 1\n" ++
    "public func test_plain() -> bool:\n    return True\nfunc main() -> int:\n    return 0\n";
const linked_two = "import dep\n\npublic func test_dependency() -> bool:\n    return dep.value() == 3\n\n" ++
    "public func test_plain() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n";

// spec: TEST-LOOP-PROGRAM-READ-1
test "the program read once answers as the per-call rule: plain, an error trace, an extern, a Host value, a callback beside function_digest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const plain = try testInput(a, directory.dir, test_source, &environment);
    defer plain.session.deinit();
    try expectSameAnswers(a, plain.context, plain.checked, try casesOf(a, plain, test_source));
    const traced = try testInput(a, directory.dir, traced_two, &environment);
    defer traced.session.deinit();
    try expectSameAnswers(a, traced.context, traced.checked, try casesOf(a, traced, traced_two));
    const external = try testInput(a, directory.dir, extern_two, &environment);
    defer external.session.deinit();
    try expectSameAnswers(a, external.context, external.checked, try casesOf(a, external, extern_two));
    const host = try testInput(a, directory.dir, host_two, &environment);
    defer host.session.deinit();
    try expectSameAnswers(a, host.context, host.checked, try casesOf(a, host, host_two));
    const digest = try testInput(a, directory.dir, digest_two, &environment);
    defer digest.session.deinit();
    try expectSameAnswers(a, digest.context, digest.checked, try casesOf(a, digest, digest_two));
    // The fixtures hold what they are about: a refused case beside one that is not, and a case only the build refuses.
    try std.testing.expectEqual(@as(usize, 2), (try casesOf(a, traced, traced_two)).len);
    try std.testing.expect(!try shareable(traced.context, traced.checked, (try casesOf(a, traced, traced_two))[1], null));
    try std.testing.expect(try shareable(traced.context, traced.checked, (try casesOf(a, traced, traced_two))[0], null));
    try std.testing.expectEqual(Refusal.Reason.c_abi, (try refusal(a, external.checked.program, external.case.function, null)).?.reason);
    try std.testing.expectEqual(Refusal.Reason.host_value, (try refusal(a, host.checked.program, (try casesOf(a, host, host_two))[1].function, null)).?.reason);
    try std.testing.expect((try refusal(a, host.checked.program, (try casesOf(a, host, host_two))[0].function, null)) == null);
    const unbounded = (try refusal(a, digest.checked.program, (try casesOf(a, digest, digest_two))[1].function, null)).?;
    try std.testing.expectEqual(Refusal.Reason.unbounded_callback, unbounded.reason);
}

// spec-case: TEST-LOOP-PROGRAM-READ-1
test "the program read once answers as the per-call rule: settings, an asset and a symlinked source outside the root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    // The settings outside the root: the root names a directory that holds none of the project.
    const plain = try testInput(a, temporary.dir, test_source, &environment);
    defer plain.session.deinit();
    var elsewhere = plain.context;
    elsewhere.entry.root = try std.fs.path.join(a, &.{ elsewhere.entry.root, "unrelated" });
    try expectSameAnswers(a, elsewhere, plain.checked, try casesOf(a, plain, test_source));
    try std.testing.expectEqualStrings("shared-private-external-settings", (try executionRefusal(elsewhere, plain.checked, plain.case, null)).?);
    // An asset outside the root: the project holds `sub/app.selka`, whose `data.bin` links to `real/data.bin`, and the run's root
    // is `sub` (the configuration above it is left out, so only the asset lies outside).
    try temporary.dir.createDirPath(std.testing.io, "asset/sub");
    try temporary.dir.createDirPath(std.testing.io, "asset/real");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "asset/selka.json", .data = "{\"version\":2}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "asset/real/data.bin", .data = "x" });
    try temporary.dir.symLink(std.testing.io, "../real/data.bin", "asset/sub/data.bin", .{});
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "asset/sub/app.selka", .data = asset_two });
    var asset_dir = try temporary.dir.openDir(std.testing.io, "asset", .{});
    defer asset_dir.close(std.testing.io);
    const asset = try inputAt(a, asset_dir, "sub/app.selka", asset_two, &environment);
    defer asset.session.deinit();
    var inner = asset.context;
    inner.entry.root = try std.fs.path.join(a, &.{ inner.entry.root, "sub" });
    inner.entry.configuration = null;
    const asset_cases = try discover.discover(a, asset.checked.program, "app", &.{});
    try std.testing.expectEqual(@as(usize, 2), asset_cases.len);
    try expectSameAnswers(a, inner, asset.checked, asset_cases);
    try std.testing.expectEqualStrings("shared-private-external-source", (try executionRefusal(inner, asset.checked, asset_cases[0], null)).?);
    // A source outside the root: the imported module is a link to a file beside the project.
    try temporary.dir.createDirPath(std.testing.io, "linked");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.selka", .data = "public func value() -> int:\n    return 3\n" });
    try temporary.dir.symLink(std.testing.io, "../dep.selka", "linked/dep.selka", .{});
    var linked_dir = try temporary.dir.openDir(std.testing.io, "linked", .{});
    defer linked_dir.close(std.testing.io);
    const linked = try testInput(a, linked_dir, linked_two, &environment);
    defer linked.session.deinit();
    try expectSameAnswers(a, linked.context, linked.checked, try casesOf(a, linked, linked_two));
    try std.testing.expectEqualStrings("shared-private-external-source", (try executionRefusal(linked.context, linked.checked, linked.case, null)).?);
}
