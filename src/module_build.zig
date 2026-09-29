//! MODULE-SCHEDULE-1..3: `mylang build` of a project, one module at a time.
//!
//! The build discovers the project's modules from their headers (a module
//! whose source digest is unchanged keeps the imports its last build read),
//! and compiles each one that is stale with `compile-module --ready` in a
//! child process, over the import graph, as many at once as the cores and
//! free memory allow. A module is stale when it has no record, its source or
//! the program's arena switch changed, or an interface its last compile read
//! (by interface, emission and positions hash) is not the one there now. A
//! compile signals as soon as its interface is written, so its dependents start
//! while its units and objects are still being built, and a dependent whose
//! inputs all held stays as it is: a body edit compiles one module, and an
//! interface edit only the modules that read what changed (early cutoff).
//!
//! The link reads one record per module (its objects in link order, the
//! digest of its share of the program-wide metadata unit, its warnings) from
//! one state file, never a unit: the objects are ordered as a whole-program
//! build orders them, the metadata unit is found by a key over the modules'
//! shares and rendered only on a miss, and a specialization several modules
//! emitted is linked once. The executable is the whole-program build's, byte
//! for byte. Anything this path does not handle — a library, the LLVM
//! backend, a provider, a `mylang.json`, a header or check error — goes to the
//! whole-program build, which reports it exactly as before.
const std = @import("std");
const language = @import("mylang");
const native_build = @import("qbe_build.zig");
const options = @import("qbe_build_options.zig");
const fs = @import("qbe_build_io.zig");
const spawn = @import("qbe_build_spawn.zig");
const outputs = @import("qbe_build_outputs.zig");
const budget = @import("memory_budget");
const interface_command = @import("module_interface_command.zig");
const compile_command = @import("module_compile_command.zig");
const project_config = @import("project_config.zig");
const module_syntax = @import("module_syntax.zig");

const Blake = std.crypto.hash.Blake3;
const Map = std.array_hash_map.String;
const state_version = "module-build-state-v2";
/// The file in a variant's directory that holds its modules' records.
const state_file = "state.json";
/// Resident memory one module compile (and the tools it starts) is budgeted
/// for when the pool is sized from `MemAvailable`.
const child_ceiling: u64 = 256 << 20;

/// What a per-module build can fail with: the driver's errors, and a module
/// header or source the build could not read.
pub const Error = native_build.Error || error{ ReadFailed, InternalError, SourceError };

/// Why a project build went to the whole-program path instead.
pub const Fallback = enum { options, entry, project, config, compile, conflict, host };

/// What a per-module build did: finished with an exit status, or handed the
/// build to the whole-program path for `Fallback`.
pub const Outcome = union(enum) { status: u8, fallback: Fallback };

/// A module's interface, emission and positions hashes.
const Hashes = struct { interface: []const u8, emission: []const u8, positions: []const u8 };

/// One interface a compile read, and its hashes then.
const Input = struct { module: []const u8, interface: []const u8, emission: []const u8, positions: []const u8 };

/// Whether a module's units open an arena scope or need the text runtime.
const Marks = struct { arena: bool = false, text: bool = false };

/// What the state file keeps about one module.
const ModuleState = struct {
    name: []const u8,
    digest: []const u8,
    imports: []const []const u8,
    arenas: bool,
    hashes: Hashes,
    inputs: []const Input = &.{},
    marks: Marks = .{},
    text_format: bool = false,
    warnings: []const u8 = "",
    placed: []const native_build.Placed = &.{},
    shared: []const u8 = "",
    entry: ?[]const u8 = null,
    objects: ?[]const u8 = null,
};

/// The state file of one build variant.
const StateFile = struct { version: []const u8 = state_version, arenas: bool = false, modules: []const ModuleState = &.{} };

const Status = enum { waiting, running, ready, done, failed };

/// One module of the program as this build found it.
const Node = struct {
    name: []const u8,
    digest: []const u8,
    imports: []const []const u8,
    /// Whether its source mentions an arena scope (the switch's first guess).
    arena_text: bool,
    /// Whether its source may declare a copied host function.
    host_text: bool,
    /// Indices of the modules it imports.
    deps: []const usize = &.{},
    status: Status = .waiting,
    /// Its interface, emission and positions hashes once they are final.
    current: ?Hashes = null,
    /// Its record once this build has one: its last compile's, or this build's.
    record: ?ModuleState = null,
    /// Whether this build compiled it, and whether that compiled any object.
    compiled: bool = false,
    objects_compiled: bool = false,
};

/// A running compile and what it wrote to standard error so far.
const Running = struct { node: usize, started: spawn.Started, stderr: std.ArrayList(u8) = .empty };

/// What a build variant is keyed by; the standard modules' shared variant
/// has no entry.
const VariantKey = struct { switches: native_build.Switches, prepared: native_build.Prepared, identity: []const u8, source: ?[]const u8 };

/// The entry of a per-module build: the I/O and environment it
/// runs with, the build arguments, where its phases go, and the compiler
/// identity its outputs are keyed by.
pub const Request = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    args: []const []const u8,
    phases: ?*native_build.PhaseTimings = null,
    identity: []const u8,
};

/// Build the project `request.args` names module by module, or say why it
/// must go to the whole-program path.
pub fn build(gpa: std.mem.Allocator, request: Request) Error!Outcome {
    const parsed = options.parse(request.args) catch return .{ .fallback = .options };
    var context = try fs.Context.init(gpa, request.io, request.environ);
    defer context.deinit();
    const a = context.allocator;
    var session: Session = undefined;
    switch (try Session.open(&session, context, .{ .parsed = parsed, .switches = native_build.emissionSwitches(parsed), .identity = request.identity })) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    defer session.close();
    const program = switch (try session.compile()) {
        .ready => |ready| ready,
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    };
    return .{ .status = try native_build.linkModules(session.prepared, parsed, program, .{
        .frontend = seconds(context, session.start),
        .phases = request.phases,
        .controls = try native_build.runtimeControls(a, request.args),
        .report = try session.report(),
    }) };
}

/// What `mylang run` of a project hands the per-module build: the build
/// settings it runs with (mode, tools, cache), the emission switches its
/// policy asks for, and the compiler identity.
pub const RunRequest = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    settings: options.Options,
    switches: native_build.Switches,
    identity: []const u8,
};

/// What a per-module build for `run` did: the executable to run, an exit
/// status to stop with, or a reason to take the whole-program path.
pub const RunOutcome = union(enum) { executable: []const u8, status: u8, fallback: Fallback };

/// MODULE-SCHEDULE-3: build the project `mylang run` names module by module
/// into the run cache, named by the program's identity, so an unchanged
/// program runs the executable it already has; `gpa` owns the path.
pub fn buildForRun(gpa: std.mem.Allocator, request: RunRequest) Error!RunOutcome {
    var context = try fs.Context.init(gpa, request.io, request.environ);
    defer context.deinit();
    var session: Session = undefined;
    switch (try Session.open(&session, context, .{ .parsed = request.settings, .switches = request.switches, .identity = request.identity })) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    defer session.close();
    const program = switch (try session.compile()) {
        .ready => |ready| ready,
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    };
    const home = try native_build.generation(context, session.prepared.root, "run", native_build.generation_identity);
    const path = try std.fs.path.join(context.allocator, &.{ home, try std.fmt.allocPrint(context.allocator, "modules-{s}", .{program.identity}) });
    if (!context.runnable(path)) {
        var settings = request.settings;
        settings.run = false;
        settings.report = false;
        settings.output = path;
        const status = try native_build.linkModules(session.prepared, settings, program, .{ .frontend = seconds(context, session.start), .phases = null, .controls = &.{} });
        if (status != 0) return .{ .status = status };
    }
    return .{ .executable = try gpa.dupe(u8, path) };
}

/// What one step of a session did: done (with its value), an exit status to
/// stop with, or a reason to take the whole-program path.
fn Step(comptime T: type) type {
    return union(enum) { ready: T, status: u8, fallback: Fallback };
}

/// What a session is opened with.
const Settings = struct { parsed: options.Options, switches: native_build.Switches, identity: []const u8 };

/// One per-module build from its entry to the program it links: the build
/// state, the prepared toolchain and cache, and the locks it holds on the
/// program's variant and on the standard modules' shared one.
const Session = struct {
    state: Build,
    prepared: native_build.Prepared,
    locks: [2]std.Io.File,
    start: std.Io.Timestamp,

    /// Check the build can go this way, prepare the toolchain and take the
    /// variant.
    fn open(self: *Session, context: fs.Context, settings: Settings) !Step(void) {
        const parsed = settings.parsed;
        if (!eligible(parsed)) return .{ .fallback = .options };
        const a = context.allocator;
        const source = try context.absolute(parsed.source);
        const raw = context.read(source) catch return .{ .fallback = .entry };
        if (!parsed.project and !module_syntax.usesModuleSyntax(raw)) return .{ .fallback = .entry };
        if (!project_config.declaresMain(raw)) return .{ .fallback = .entry };
        if (project_config.discover(a, context.io, source) catch return .{ .fallback = .config }) |_| return .{ .fallback = .config };
        const entry = (try interface_command.entryOf(a, context.io, source)) orelse return .{ .fallback = .entry };
        const prepared = native_build.prepare(context, parsed) catch |err| switch (err) {
            error.NativeToolFailed => return .{ .status = 2 },
            else => return err,
        };
        const key: VariantKey = .{ .switches = settings.switches, .prepared = prepared, .identity = settings.identity, .source = source };
        self.* = .{
            .prepared = prepared,
            .start = std.Io.Timestamp.now(context.io, .awake),
            .locks = undefined,
            .state = .{
                .context = context,
                .parsed = parsed,
                .entry = .{ .root = entry.root, .name = entry.name, .bytes = entry.bytes, .path = source },
                .variant = try variantDirectory(context, key),
                .standard = try variantDirectory(context, .{ .switches = key.switches, .prepared = prepared, .identity = key.identity, .source = null }),
                .switches = settings.switches,
            },
        };
        errdefer context.remove(prepared.cache.temporary);
        try context.mkdir(self.state.variant);
        try context.mkdir(self.state.standard);
        // Always the program's variant first: two builds never wait on each other in turn.
        self.locks[0] = try lockVariant(context, self.state.variant);
        self.locks[1] = try lockVariant(context, self.state.standard);
        return .{ .ready = {} };
    }

    fn close(self: *Session) void {
        for (self.locks) |lock| lock.close(self.state.context.io);
        self.state.context.remove(self.prepared.cache.temporary);
    }

    /// Compile every stale module and assemble the program to link.
    fn compile(self: *Session) !Step(native_build.ModuleProgram) {
        const state = &self.state;
        try state.loadState();
        if (!try state.discover()) return .{ .fallback = .project };
        // The copied host bridge orders its type and declaration rows by the
        // whole program's record and function tables, which no module sees.
        for (state.nodes.items) |node| if (node.host_text) return .{ .fallback = .host };
        state.arenas = state.guessArenas();
        if (!try state.schedule()) {
            try state.saveState();
            return .{ .fallback = .compile };
        }
        // The arena switch is the program's: when the compiles say it is other
        // than the one they were compiled under, every module compiles again.
        if (state.programArenas() != state.arenas) {
            state.arenas = !state.arenas;
            try state.restart();
            if (!try state.schedule()) {
                try state.saveState();
                return .{ .fallback = .compile };
            }
        }
        // An object a sweep removed since its module's last compile is rebuilt
        // with that module.
        if (try state.markMissingObjects()) {
            if (!try state.schedule()) {
                try state.saveState();
                return .{ .fallback = .compile };
            }
        }
        try state.saveState();
        try state.printWarnings();
        const program = (try state.program()) orelse return .{ .fallback = .conflict };
        return .{ .ready = program };
    }

    /// The scheduler's own `--report` fields.
    fn report(self: *Session) !std.json.Value {
        const state = &self.state;
        const a = state.context.allocator;
        return std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, .{
            .modules = state.nodes.items.len,
            .compiled = state.compiled,
            .reused = state.nodes.items.len - state.compiled,
            .arenas = state.arenas,
        }, .{}), .{});
    }
};

/// Whether these build options can go through the per-module path: an
/// executable of the QBE backend with a cache, and no provider, selection,
/// checked manifest or `--whole-program`.
fn eligible(parsed: options.Options) bool {
    if (parsed.library or parsed.provider != null) return false;
    if (options.noCache(parsed)) return false;
    if (parsed.codegen == .llvm) return false;
    for (parsed.link_arguments) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (std.mem.eql(u8, argument, options.whole_program_flag) or std.mem.eql(u8, argument, "--module-objects")) return false;
        if (std.mem.startsWith(u8, argument, "--select-file") or std.mem.startsWith(u8, argument, "--manifest-file")) return false;
        if (std.mem.startsWith(u8, argument, "--diagnostics=")) return false;
    }
    return true;
}

/// The directory of one build variant under the cache: the compiler identity,
/// the entry, the emission switches and the objects' build environment.
fn variantDirectory(context: fs.Context, key: VariantKey) ![]const u8 {
    var hash = Blake.init(.{});
    frame(&hash, state_version);
    frame(&hash, key.identity);
    frame(&hash, key.source orelse "\x00standard");
    frame(&hash, language.runtime_mode.identity());
    hash.update(&.{ @intFromBool(language.value_semantics.enabled()), @intFromBool(language.value_semantics.counting()) });
    const switches = key.switches;
    hash.update(&.{ @intFromBool(switches.drop_debug), @intFromBool(switches.step_checks), @intFromBool(switches.frame_checks) });
    frame(&hash, key.prepared.cache.environment);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const name = if (key.source == null) try std.fmt.allocPrint(context.allocator, "standard-{x}", .{digest}) else try std.fmt.allocPrint(context.allocator, "{x}", .{digest});
    return std.fs.path.join(context.allocator, &.{ key.prepared.root, "modules", name });
}

/// Hold the variant for this build: a concurrent build of the same program
/// waits rather than interleaving its compiles and state with this one's.
fn lockVariant(context: fs.Context, variant: []const u8) !std.Io.File {
    const path = try std.fs.path.join(context.allocator, &.{ variant, ".lock" });
    const file = std.Io.Dir.cwd().createFile(context.io, path, .{ .truncate = false }) catch return error.WriteFailed;
    file.lock(context.io, .exclusive) catch {
        file.close(context.io);
        return error.WriteFailed;
    };
    return file;
}

fn frame(hash: *Blake, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn seconds(context: fs.Context, start: std.Io.Timestamp) f64 {
    const elapsed = start.durationTo(std.Io.Timestamp.now(context.io, .awake)).nanoseconds;
    return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
}

/// The program's entry: its import root, module name, source (as the compile
/// reads it) and absolute path.
const Entry = struct { root: []const u8, name: []const u8, bytes: []const u8, path: []const u8 };

/// Everything one per-module build works with.
const Build = struct {
    context: fs.Context,
    parsed: options.Options,
    entry: Entry,
    variant: []const u8,
    /// MODULE-SCHEDULE-4: the standard modules' variant, shared by every
    /// program built with this compiler, switches and toolchain.
    standard: []const u8,
    switches: native_build.Switches,
    nodes: std.ArrayList(Node) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    /// Modules in dependency order: each after everything it imports.
    order: std.ArrayList(usize) = .empty,
    previous: std.StringHashMapUnmanaged(ModuleState) = .empty,
    had_state: bool = false,
    previous_arenas: bool = false,
    arenas: bool = false,
    compiled: usize = 0,

    /// The variant a module's outputs live in: the shared standard one for a
    /// standard module, the program's otherwise.
    fn home(self: *Build, module: []const u8) []const u8 {
        return if (standardModule(module)) self.standard else self.variant;
    }

    fn outFile(self: *Build, module: []const u8, suffix: []const u8) ![]const u8 {
        return std.fs.path.join(self.context.allocator, &.{ self.home(module), "out", try std.fmt.allocPrint(self.context.allocator, "{s}{s}", .{ module, suffix }) });
    }

    /// The last successful builds' module records: the program's, and the
    /// standard modules' shared ones.
    fn loadState(self: *Build) !void {
        const a = self.context.allocator;
        for ([_][]const u8{ self.standard, self.variant }, [_]bool{ true, false }) |directory, standard| {
            const bytes = self.context.read(try std.fs.path.join(a, &.{ directory, state_file })) catch continue;
            const file = std.json.parseFromSliceLeaky(StateFile, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch continue;
            if (!std.mem.eql(u8, file.version, state_version)) continue;
            if (!standard) {
                self.had_state = true;
                self.previous_arenas = file.arenas;
            }
            for (file.modules) |module| try self.previous.put(a, module.name, module);
        }
    }

    /// Write the program's records, and the standard modules' records into
    /// their shared state (keeping those of standard modules this program
    /// does not import).
    fn saveState(self: *Build) !void {
        const a = self.context.allocator;
        var own: std.ArrayList(ModuleState) = .empty;
        var standard: Map(ModuleState) = .empty;
        if (self.context.read(try std.fs.path.join(a, &.{ self.standard, state_file }))) |bytes| {
            if (std.json.parseFromSliceLeaky(StateFile, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always })) |file| {
                if (std.mem.eql(u8, file.version, state_version)) for (file.modules) |module| try standard.put(a, module.name, module);
            } else |_| {}
        } else |_| {}
        for (self.nodes.items) |node| {
            const record = node.record orelse self.previous.get(node.name) orelse continue;
            if (standardModule(record.name)) try standard.put(a, record.name, record) else try own.append(a, record);
        }
        try self.context.atomic(try std.fs.path.join(a, &.{ self.variant, state_file }), try std.json.Stringify.valueAlloc(a, StateFile{ .arenas = self.arenas, .modules = own.items }, .{}));
        try self.context.atomic(try std.fs.path.join(a, &.{ self.standard, state_file }), try std.json.Stringify.valueAlloc(a, StateFile{ .arenas = self.arenas, .modules = standard.values() }, .{}));
    }

    fn intern(self: *Build, name: []const u8) !?usize {
        return self.names.get(name);
    }

    /// Re-read real source and embeds under loader budgets before any early cutoff.
    fn capture(self: *Build) !bool {
        var loaded: language.project.Project = .init(self.context.parent);
        defer loaded.deinit();
        var files: language.project_files.Files = .{ .io = self.context.io, .root = self.entry.root };
        loaded.load(files.provider(), self.entry.name, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        };
        const a = self.context.allocator;
        for (loaded.modules.items) |module| {
            var hash = Blake.init(.{});
            hash.update(module.src.bytes);
            language.embed.hashInto(&hash, module.src.embeds);
            var digest: [32]u8 = undefined;
            hash.final(&digest);
            const imports = try a.alloc([]const u8, module.imports.len);
            for (module.imports, imports) |imported, *name| name.* = try a.dupe(u8, imported.name);
            const id = self.nodes.items.len;
            try self.nodes.append(a, .{
                .name = try a.dupe(u8, module.name),
                .digest = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
                .imports = imports,
                .arena_text = std.mem.indexOf(u8, module.src.bytes, "arena(") != null,
                .host_text = hostText(module.src.bytes),
            });
            try self.names.put(a, self.nodes.items[id].name, id);
        }
        return true;
    }

    /// Find every module from the entry's imports, as the project loader
    /// does, and order them so each follows what it imports. A module that
    /// cannot be read, a header problem or an import cycle is the
    /// whole-program path's to report.
    fn discover(self: *Build) !bool {
        if (!try self.capture()) return false;
        const a = self.context.allocator;
        const Visit = struct { id: usize, next: usize = 0 };
        const root = (try self.intern(self.entry.name)) orelse return false;
        var visiting: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var complete: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var work: std.ArrayList(Visit) = .empty;
        try work.append(a, .{ .id = root });
        try visiting.put(a, root, {});
        while (work.items.len != 0) {
            const top = &work.items[work.items.len - 1];
            const imports = self.nodes.items[top.id].imports;
            if (top.next == imports.len) {
                const deps = try a.alloc(usize, imports.len);
                for (imports, deps) |name, *dep| dep.* = self.names.get(name).?;
                self.nodes.items[top.id].deps = deps;
                try self.order.append(a, top.id);
                try complete.put(a, top.id, {});
                _ = visiting.remove(top.id);
                _ = work.pop();
                continue;
            }
            const name = imports[top.next];
            top.next += 1;
            const target = (try self.intern(name)) orelse return false;
            if (complete.contains(target)) continue;
            if (visiting.contains(target)) return false;
            try visiting.put(a, target, {});
            try work.append(a, .{ .id = target });
        }
        return true;
    }

    /// The arena switch to compile under first: the last build's, or, with no
    /// last build, whether any module's source mentions an arena scope.
    fn guessArenas(self: *Build) bool {
        if (self.had_state) return self.previous_arenas;
        for (self.nodes.items) |node| if (node.arena_text) return true;
        return false;
    }

    /// Whether any module's units open an arena: the program's switch.
    fn programArenas(self: *Build) bool {
        for (self.nodes.items) |node| if (node.record.?.marks.arena) return true;
        return false;
    }

    /// Compile every module again under a new arena switch.
    fn restart(self: *Build) !void {
        for (self.nodes.items) |*node| {
            node.status = .waiting;
            node.current = null;
            if (node.record) |record| try self.previous.put(self.context.allocator, record.name, record);
            node.record = null;
        }
    }

    /// Mark every module one of whose objects is gone for another compile;
    /// whether there was one.
    fn markMissingObjects(self: *Build) !bool {
        var any = false;
        for (self.nodes.items) |*node| {
            const record = node.record.?;
            const gone = for (record.placed) |placed| {
                if (!self.context.exists(placed.object)) break true;
            } else false;
            if (!gone) continue;
            any = true;
            _ = self.previous.remove(record.name);
            node.record = null;
            node.status = .waiting;
            node.current = null;
        }
        if (!any) return false;
        // Everything else stands as it is: a recompile keeps its interface.
        for (self.nodes.items) |*node| if (node.record) |record| {
            try self.previous.put(self.context.allocator, record.name, record);
            node.status = .waiting;
            node.current = null;
            node.record = null;
        };
        return true;
    }

    /// Whether module `id` must compile: null while an input it read is not
    /// final yet.
    fn stale(self: *Build, id: usize) bool {
        const node = self.nodes.items[id];
        const known = self.previous.get(node.name) orelse return true;
        if (!std.mem.eql(u8, known.digest, node.digest) or known.arenas != self.arenas) return true;
        for (known.inputs) |input| {
            const at = self.names.get(input.module) orelse return true;
            const now = self.nodes.items[at].current orelse return true;
            if (!std.mem.eql(u8, now.interface, input.interface) or !std.mem.eql(u8, now.emission, input.emission)) return true;
            // Positions matter only to a compile whose units spliced or
            // instantiated a body of that interface's text.
            if (input.positions.len != 0 and !std.mem.eql(u8, now.positions, input.positions)) return true;
        }
        return false;
    }

    /// Whether every module `id` imports has its final interface.
    fn importsReady(self: *Build, id: usize) bool {
        for (self.nodes.items[id].deps) |dep| switch (self.nodes.items[dep].status) {
            .ready, .done => {},
            else => return false,
        };
        return true;
    }

    /// Compile every stale module over the import graph, as many at once as
    /// the cores and free memory allow; whether every module ended with a
    /// record. After a failed compile no new one starts, and the ones running
    /// finish.
    fn schedule(self: *Build) !bool {
        const a = self.context.allocator;
        const width = budget.workers(.{
            .programs = @max(1, self.nodes.items.len),
            .cores = std.Thread.getCpuCount() catch 1,
            .free = budget.available(self.context.io),
            .ceiling = child_ceiling,
            .jobs = if (self.context.environ.get("MYLANG_JOBS")) |text| budget.jobs(text) catch null else null,
        });
        var running: std.ArrayList(Running) = .empty;
        var failed = false;
        while (true) {
            var progress = true;
            while (progress) {
                progress = false;
                for (self.order.items) |id| {
                    if (self.nodes.items[id].status != .waiting or !self.importsReady(id)) continue;
                    if (!self.stale(id)) {
                        const known = self.previous.get(self.nodes.items[id].name).?;
                        self.nodes.items[id].record = known;
                        self.nodes.items[id].current = known.hashes;
                        self.nodes.items[id].status = .done;
                        progress = true;
                        continue;
                    }
                    if (failed or running.items.len >= width) continue;
                    try running.append(a, .{ .node = id, .started = try self.start(id) });
                    self.nodes.items[id].status = .running;
                }
            }
            if (running.items.len == 0) break;
            const started = try a.alloc(spawn.Started, running.items.len);
            for (running.items, started) |one, *slot| slot.* = one.started;
            const index = try spawn.ready(a, started);
            const one = &running.items[index];
            const ended = try spawn.pump(a, one.started, &one.stderr);
            try self.noticeReady(one);
            if (!ended) continue;
            const finished = running.swapRemove(index);
            const term = spawn.reap(finished.started);
            if (fs.exitCode(term) == 0 and try self.finish(finished.node)) continue;
            self.nodes.items[finished.node].status = .failed;
            failed = true;
        }
        for (self.nodes.items) |node| if (node.status != .done) return false;
        return !failed;
    }

    /// Start the compile of module `id`.
    fn start(self: *Build, id: usize) !spawn.Started {
        const a = self.context.allocator;
        const node = self.nodes.items[id];
        var argv: std.ArrayList([]const u8) = .empty;
        const home_directory = self.home(node.name);
        try argv.appendSlice(a, &.{
            try std.Io.Dir.cwd().realPathFileAlloc(self.context.io, "/proc/self/exe", a),
            "compile-module",
            self.entry.path,
            try std.fmt.allocPrint(a, "--module={s}", .{node.name}),
            try std.fmt.allocPrint(a, "--interfaces={s}/if", .{home_directory}),
            try std.fmt.allocPrint(a, "--standard-interfaces={s}/if", .{self.standard}),
            try std.fmt.allocPrint(a, "--out={s}/out", .{home_directory}),
            try std.fmt.allocPrint(a, "--cache-dir={s}", .{self.parsed.cache}),
            if (self.arenas) "--arenas=on" else "--arenas=off",
        });
        try argv.appendSlice(a, try native_build.frontendSwitches(a, self.switches));
        try argv.appendSlice(a, &.{ "--objects", "--ready", "--", "--mode", self.parsed.mode, "--target", self.parsed.target, try std.fmt.allocPrint(a, "--zig={s}", .{self.parsed.zig}) });
        switch (self.parsed.codegen) {
            .qbe => |tool| try argv.append(a, try std.fmt.allocPrint(a, "--qbe={s}", .{tool})),
            else => {},
        }
        return spawn.start(a, .{ .argv = argv.items });
    }

    /// Take a compile's interface hashes from its ready line, once.
    fn noticeReady(self: *Build, one: *Running) !void {
        const node = &self.nodes.items[one.node];
        if (node.status != .running) return;
        const at = std.mem.indexOf(u8, one.stderr.items, compile_command.ready_marker) orelse return;
        const line_end = std.mem.indexOfScalarPos(u8, one.stderr.items, at, '\n') orelse return;
        var fields = std.mem.tokenizeScalar(u8, one.stderr.items[at + compile_command.ready_marker.len .. line_end], ' ');
        const a = self.context.allocator;
        node.current = .{
            .interface = try a.dupe(u8, fields.next() orelse return),
            .emission = try a.dupe(u8, fields.next() orelse return),
            .positions = try a.dupe(u8, fields.next() orelse return),
        };
        node.status = .ready;
    }

    /// Record a finished compile of module `id` from its result files;
    /// whether they were complete.
    fn finish(self: *Build, id: usize) !bool {
        const a = self.context.allocator;
        const node = &self.nodes.items[id];
        const bytes = self.context.read(try self.outFile(node.name, ".result.json")) catch return false;
        const Result = struct {
            hashes: struct { interface: []const u8, emission: []const u8, positions: []const u8, inputs: []const Input = &.{} },
            warnings: []const u8 = "",
            marks: Marks = .{},
            text_format: bool = false,
            entry: ?[]const u8 = null,
            shared: []const u8 = "",
            objects: ?[]const u8 = null,
        };
        const result = std.json.parseFromSliceLeaky(Result, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return false;
        const listed = result.objects orelse return false;
        const Objects = struct { compiled: bool = false, placed: []const native_build.Placed = &.{} };
        const objects = std.json.parseFromSliceLeaky(Objects, a, self.context.read(listed) catch return false, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return false;
        node.record = .{
            .name = node.name,
            .digest = node.digest,
            .imports = node.imports,
            .arenas = self.arenas,
            .hashes = .{ .interface = result.hashes.interface, .emission = result.hashes.emission, .positions = result.hashes.positions },
            .inputs = result.hashes.inputs,
            .marks = result.marks,
            .text_format = result.text_format,
            .warnings = result.warnings,
            .placed = objects.placed,
            .shared = result.shared,
            .entry = result.entry,
            .objects = listed,
        };
        node.current = node.record.?.hashes;
        node.status = .done;
        node.compiled = true;
        node.objects_compiled = objects.compiled;
        self.compiled += 1;
        return true;
    }

    /// Replay every module's warnings, in the order the modules were found.
    fn printWarnings(self: *Build) !void {
        for (self.nodes.items) |node| {
            const warnings = node.record.?.warnings;
            if (warnings.len != 0) std.Io.File.stderr().writeStreamingAll(self.context.io, warnings) catch return error.WriteFailed;
        }
    }

    /// The program to link: every module's objects in whole-program link
    /// order (a specialization several modules emitted once), the metadata
    /// unit's key, the entry's fields, and the report records when asked;
    /// null when two modules emitted one batch with different objects.
    fn program(self: *Build) !?native_build.ModuleProgram {
        const a = self.context.allocator;
        var placed: Map(native_build.Placed) = .empty;
        var compiled = false;
        var text = false;
        var entry: ?[]const u8 = null;
        var shared = Blake.init(.{});
        frame(&shared, "module-metadata-parts-v1");
        const sorted = try a.dupe(usize, self.order.items);
        std.mem.sort(usize, sorted, self, nameBefore);
        for (sorted) |id| {
            const node = self.nodes.items[id];
            const record = node.record.?;
            compiled = compiled or node.objects_compiled;
            text = text or record.text_format;
            if (record.entry) |fields| entry = fields;
            frame(&shared, record.name);
            frame(&shared, record.shared);
            for (record.placed) |one| {
                const slot = try placed.getOrPut(a, try std.fmt.allocPrint(a, "{s}\x00{s}\x00{s}", .{ @tagName(one.kind), one.group, one.first }));
                if (slot.found_existing) {
                    if (!std.mem.eql(u8, slot.value_ptr.key, one.key)) return null;
                } else slot.value_ptr.* = one;
            }
        }
        const ordered = try a.dupe(native_build.Placed, placed.values());
        std.mem.sort(native_build.Placed, ordered, {}, placedBefore);
        const objects = try a.alloc([]const u8, ordered.len);
        var identity = Blake.init(.{});
        frame(&identity, "module-program-v1");
        for (ordered, objects) |one, *object| {
            object.* = one.object;
            frame(&identity, one.key);
        }
        var key: [32]u8 = undefined;
        shared.final(&key);
        const shared_key = try a.dupe(u8, &std.fmt.bytesToHex(key, .lower));
        frame(&identity, shared_key);
        const fields = entry orelse return null;
        frame(&identity, fields);
        identity.update(&.{@intFromBool(text)});
        var manifest = (std.json.parseFromSliceLeaky(std.json.Value, a, fields, .{}) catch return null);
        if (manifest != .object) return null;
        try manifest.object.put(a, "text_format", .{ .bool = text });
        try manifest.object.put(a, "functions", .{ .array = std.json.Array.init(a) });
        var digest: [32]u8 = undefined;
        identity.final(&digest);
        const render = try a.create(SharedRender);
        render.* = .{ .build = self, .order = sorted };
        return .{
            .objects = objects,
            .compiled = compiled,
            .records = if (self.parsed.report) try self.records() else &.{},
            .shared = .{ .key = shared_key, .render = .{ .context = render, .run = SharedRender.run } },
            .manifest = manifest,
            .identity = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
        };
    }

    /// Every function's report record, from each module's object list: a
    /// module this build did not compile reused every object.
    fn records(self: *Build) ![]const native_build.Record {
        const a = self.context.allocator;
        var seen: Map(native_build.Record) = .empty;
        for (self.nodes.items) |node| {
            const listed = node.record.?.objects orelse continue;
            const Objects = struct { functions: []const native_build.Record = &.{} };
            const bytes = self.context.read(listed) catch continue;
            const objects = std.json.parseFromSliceLeaky(Objects, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch continue;
            for (objects.functions) |record| {
                const slot = try seen.getOrPut(a, record.symbol);
                if (slot.found_existing) continue;
                slot.value_ptr.* = record;
                if (!node.compiled) slot.value_ptr.reused = true;
            }
        }
        const out = try a.dupe(native_build.Record, seen.values());
        std.mem.sort(native_build.Record, out, {}, recordBefore);
        return out;
    }
};

/// Whether a source may declare a copied host function: `host` and `def`
/// separated by blanks anywhere in it (a comment too, which only costs the
/// per-module path).
fn hostText(bytes: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, from, "host")) |at| {
        from = at + 4;
        var next = from;
        while (next < bytes.len and (bytes[next] == ' ' or bytes[next] == '\t')) next += 1;
        if (next > from and std.mem.startsWith(u8, bytes[next..], "def")) return true;
    }
    return false;
}

/// Whether a module is one of the compiler's standard modules.
fn standardModule(name: []const u8) bool {
    var buffer: [256]u8 = undefined;
    if (name.len + 3 > buffer.len) return false;
    @memcpy(buffer[0..name.len], name);
    @memcpy(buffer[name.len..][0..3], ".my");
    for (buffer[0..name.len]) |*byte| if (byte.* == '.') {
        byte.* = '/';
    };
    return language.module_compile.standardSource(buffer[0 .. name.len + 3]) != null;
}

fn nameBefore(self: *Build, left: usize, right: usize) bool {
    return std.mem.lessThan(u8, self.nodes.items[left].name, self.nodes.items[right].name);
}

/// Whole-program link order: code batches, then metadata groups, each by plan
/// group and first symbol.
fn placedBefore(_: void, left: native_build.Placed, right: native_build.Placed) bool {
    if (left.kind != right.kind) return left.kind == .code;
    const group = std.mem.order(u8, left.group, right.group);
    if (group != .eq) return group == .lt;
    return std.mem.lessThan(u8, left.first, right.first);
}

fn recordBefore(_: void, left: native_build.Record, right: native_build.Record) bool {
    return std.mem.lessThan(u8, left.symbol, right.symbol);
}

/// Renders the program-wide metadata unit from the modules' shares: their
/// descriptor and renderer blocks by name, their frozen literals and their
/// host bridges, as a whole-program emission renders them.
const SharedRender = struct {
    build: *Build,
    order: []const usize,

    fn run(context: *anyopaque, allocator: std.mem.Allocator) native_build.Error![]const u8 {
        const self: *SharedRender = @ptrCast(@alignCast(context));
        const state = self.build;
        var shares: std.ArrayList(std.json.Value) = .empty;
        for (self.order) |id| {
            const name = state.nodes.items[id].name;
            const bytes = try state.context.read(try state.outFile(name, ".shared.json"));
            try shares.append(allocator, try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always }));
        }
        const encoded = language.module_link.merge(allocator, shares.items) catch |err| return invalidBlocks(err);
        const manifest = try std.json.parseFromSliceLeaky(std.json.Value, allocator, encoded, .{ .allocate = .alloc_always });
        return outputs.sharedMetadata(allocator, manifest);
    }
};

fn invalidBlocks(err: anyerror) native_build.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidNativeManifest;
}
