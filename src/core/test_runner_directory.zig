//! Directory programs run in bounded child processes. Every test-declaring
//! source must appear in a child's checked inventory, including orphan libraries.
const std = @import("std");
const language = @import("mylang");
const project_entry = @import("project_entry.zig");
const frontend = @import("frontend.zig");
const options = @import("test_runner_options.zig");
const report = @import("test_runner_report.zig");
const tool_identity = @import("tool_identity.zig");
const tool_ticket = @import("tool_ticket.zig");
const case_settings = @import("test_runner_cases.zig");
const receipt = @import("test_runner_receipt.zig");
const Error = @import("test_runner_property.zig").Error;

const Input = struct { path: []const u8, digest: ?[32]u8 };
const Location = struct { path: []const u8, root: []const u8, name: []const u8, configuration: ?[]const u8 };
const Selection = struct { entries: []const []const u8, tested: []const []const u8, inputs: []const Input, discovered: []const []const u8, locations: []const Location = &.{} };
const Orphan = struct { path: []const u8, closure: []const []const u8 };
const Outcome = struct { code: u8 = 1, bytes: []const u8 = "" };
const Fanout = struct { compiler: []const u8, directory: []const u8, controls: options.Options, jobs: usize, ticket: []const u8 };
const Discovery = struct { allocator: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io };
const Snapshot = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    inputs: std.ArrayList(Input) = .empty,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    locations: std.ArrayList(Location) = .empty,

    fn record(self: *Snapshot, path: []const u8, digest: ?[32]u8) error{ OutOfMemory, SourceChanged }!void {
        if (self.index.get(path)) |position| {
            if (!sameDigest(self.inputs.items[position].digest, digest)) return error.SourceChanged;
            return;
        }
        try self.inputs.append(self.allocator, .{ .path = path, .digest = digest });
        try self.index.put(self.allocator, path, self.inputs.items.len - 1);
    }

    fn content(self: *Snapshot, path: []const u8, bytes: []const u8) error{ OutOfMemory, SourceChanged }!void {
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        try self.record(path, digest);
    }

    fn disk(self: *Snapshot, path: []const u8) !void {
        if (self.index.contains(path)) return;
        try self.record(path, try receipt.readDigest(self.allocator, self.io, path));
    }

    fn source(self: *Snapshot, path: []const u8, src: language.source.Source, overridden: bool) !void {
        if (!overridden) try self.content(path, src.bytes);
        for (src.embeds) |embed| {
            if (embed.status != .ok and embed.status != .missing) continue;
            const asset = try std.fs.path.resolve(self.allocator, &.{ std.fs.path.dirname(path).?, embed.path });
            try self.record(asset, if (embed.status == .ok) embed.digest else null);
        }
    }
};

const Overlay = struct {
    files: *language.project_files.Files,
    providers: []const frontend.Provider,

    fn provider(self: *Overlay) language.project.Provider {
        return .{ .context = self, .read = read, .embed = readEmbed };
    }
    fn read(context: ?*anyopaque, a: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        for (self.providers) |item| if (std.mem.eql(u8, item.path, relative)) {
            if (item.text.len > limit) return error.TooLarge;
            return a.dupe(u8, item.text);
        };
        return language.project_files.Files.read(self.files, a, relative, limit);
    }
    fn readEmbed(context: ?*anyopaque, a: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!language.embed.Read {
        const self: *Overlay = @ptrCast(@alignCast(context.?));
        return language.project_files.Files.readEmbed(self.files, a, module_path, path, limit);
    }
};

/// Whether the command names a directory rather than a single project entry.
pub fn selected(io: std.Io, path: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return info.kind == .directory;
}

/// Discover roots and launch them with one shared bounded worker budget.
pub fn run(init: std.process.Init, opts: options.Options) Error!u8 {
    const a = init.arena.allocator();
    if (opts.controls.cases != null) {
        try write(init.io, std.Io.File.stderr(), "error: --cases requires a single test entry\n");
        return 2;
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    const selection = programs(init, opts, &diagnostics) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try diagnostics.print(a, "error: directory test discovery failed: {s}\n", .{@errorName(err)});
        try write(init.io, std.Io.File.stderr(), diagnostics.items);
        return 1;
    };
    if (selection.entries.len == 0) {
        try write(init.io, std.Io.File.stdout(), if (opts.json) try report.jsonSources(a, &.{}, &.{}) else try report.text(a, &.{}));
        return 3;
    }
    const compiler = std.Io.Dir.cwd().realPathFileAlloc(init.io, "/proc/self/exe", a) catch return error.ReadFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(init.io, &nonce);
    const directory = try std.fmt.allocPrint(a, "{s}/tests/directory-{s}", .{ opts.build.cache, std.fmt.bytesToHex(nonce, .lower) });
    std.Io.Dir.cwd().createDirPath(init.io, directory) catch return error.WriteFailed;
    defer retire(init.io, directory);
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = opts.build.zig, .cache = opts.build.cache };
    const guest = tool_identity.captureReplayParent(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, std.Io.File.stderr(), try std.fmt.allocPrint(a, "error: cannot identify guest toolchain: {s}\n", .{@errorName(err)}));
        return 1;
    };
    const ticket = try std.fs.path.join(a, &.{ directory, "tool-ticket.json" });
    const encoded = tool_ticket.encode(.{ .tool = request, .compiler_identity = frontend.compiler_identity }, guest) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.ReadFailed;
    };
    std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = ticket, .data = encoded }) catch return error.WriteFailed;
    var controls = opts;
    controls.build.zig = guest.path;
    const workers = options.width(opts.controls, init.environ_map, selection.entries.len);
    const overall = options.width(opts.controls, init.environ_map, std.math.maxInt(usize));
    const fanout: Fanout = .{ .compiler = compiler, .directory = directory, .controls = controls, .jobs = @max(1, overall / workers), .ticket = ticket };
    const outcomes = try a.alloc(Outcome, selection.entries.len);
    var begin: usize = 0;
    while (begin < selection.entries.len) : (begin += workers) {
        const end = @min(selection.entries.len, begin + workers);
        try wave(init, fanout, selection.entries[begin..end], outcomes[begin..end]);
    }
    const unchanged = tool_identity.unchanged(request, guest) catch |err| unchanged: {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        break :unchanged false;
    };
    return summarize(init, opts, selection, outcomes, unchanged);
}

fn programs(init: std.process.Init, opts: options.Options, diagnostics: *std.ArrayList(u8)) !Selection {
    const a = init.arena.allocator();
    const found = try inventory(a, init.io, opts);
    var roots: std.ArrayList([]const u8) = .empty;
    var tested: std.ArrayList([]const u8) = .empty;
    var libraries: std.ArrayList([]const u8) = .empty;
    var snapshot: Snapshot = .{ .allocator = a, .io = init.io };
    defer snapshot.index.deinit(a);
    for (found) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
        try snapshot.content(path, bytes);
        const tests = declaresTests(bytes);
        if (tests) try tested.append(a, path);
        if (language.project_config.declaresMain(bytes) or std.mem.endsWith(u8, path, "_test.my")) {
            try roots.append(a, path);
        } else if (tests) try libraries.append(a, path);
    }
    var reached: std.StringHashMapUnmanaged(void) = .empty;
    defer reached.deinit(a);
    for (roots.items) |path| for (try closure(init, path, diagnostics, &snapshot, opts.filter)) |loaded| try reached.put(a, loaded, {});
    var orphans: std.ArrayList(Orphan) = .empty;
    for (libraries.items) |path| if (!reached.contains(path)) {
        try orphans.append(a, .{ .path = path, .closure = try closure(init, path, diagnostics, &snapshot, opts.filter) });
    };
    for (orphans.items, 0..) |orphan, index| {
        var imported = false;
        for (orphans.items, 0..) |other, other_index| {
            if (index == other_index) continue;
            for (other.closure) |path| if (std.mem.eql(u8, path, orphan.path)) {
                imported = true;
            };
        }
        if (!imported) try roots.append(a, orphan.path);
    }
    if (roots.items.len > 4096) return error.TooManyTestPrograms;
    std.mem.sort([]const u8, roots.items, {}, before);
    return .{ .entries = roots.items, .tested = tested.items, .inputs = snapshot.inputs.items, .discovered = found, .locations = snapshot.locations.items };
}

fn inventory(a: std.mem.Allocator, io: std.Io, opts: options.Options) ![]const []const u8 {
    const root = try std.Io.Dir.cwd().realPathFileAlloc(io, opts.path, a);
    const working = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", a);
    const cache = std.Io.Dir.cwd().realPathFileAlloc(io, opts.build.cache, a) catch try std.fs.path.resolve(a, &.{ working, opts.build.cache });
    const cache_prefix = try std.fmt.allocPrint(a, "{s}/", .{cache});
    var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |item| {
        const absolute = try std.fs.path.join(a, &.{ root, item.path });
        if (std.mem.eql(u8, absolute, cache) or std.mem.startsWith(u8, absolute, cache_prefix)) {
            if (item.kind == .directory) walker.leave(io);
            continue;
        }
        if (generated(item.basename)) {
            if (item.kind == .directory) walker.leave(io);
            continue;
        }
        if (item.kind == .file and std.mem.endsWith(u8, item.path, ".my")) try found.append(a, try std.fs.path.join(a, &.{ root, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, before);
    return found.items;
}

fn closure(init: std.process.Init, path: []const u8, diagnostics: *std.ArrayList(u8), snapshot: *Snapshot, filter: []const u8) ![]const []const u8 {
    const a = init.arena.allocator();
    const located = try project_entry.resolve(a, init.io, path, diagnostics);
    try snapshot.locations.append(a, .{ .path = located.path, .root = located.root, .name = located.name, .configuration = if (located.configuration) |file| file.path else null });
    try configurationInputs(snapshot, located);
    const cases = try case_settings.load(a, init.io, located.path, null);
    const cases_path = try case_settings.defaultPath(a, located.path);
    if (cases.path != null) try snapshot.content(cases_path, cases.bytes) else try snapshot.record(cases_path, null);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20));
    if (!language.opensAsModule(bytes)) {
        var src = try language.source.Source.init(a, std.fs.path.basename(path), bytes);
        src.embeds = try language.embed.scan(a, src);
        const module_path = try language.project.modulePath(a, located.name);
        try language.embed.resolve(a, .{ .io = init.io, .import_root = located.root, .root = if (located.configuration) |file| std.fs.path.dirname(file.path).? else located.root }, module_path, @constCast(src.embeds));
        try snapshot.source(located.path, src, false);
        return a.dupe([]const u8, &.{located.path});
    }
    const resources: Discovery = .{ .allocator = a, .gpa = init.gpa, .io = init.io };
    const paths = try loadedClosure(resources, located, &.{}, snapshot);
    for (try case_settings.providerSets(a, cases, filter)) |providers| _ = try loadedClosure(resources, located, providers, snapshot);
    return paths;
}

fn loadedClosure(resources: Discovery, located: project_entry.Entry, providers: []const frontend.Provider, snapshot: *Snapshot) ![]const []const u8 {
    const a = resources.allocator;
    var session = frontend.Session.init(resources.gpa, resources.io, located.root);
    defer session.deinit();
    located.configure(&session);
    var overlay: Overlay = .{ .files = &session.files, .providers = providers };
    try session.project.load(overlay.provider(), located.name, located.limits());
    var paths: std.ArrayList([]const u8) = .empty;
    for (session.project.modules.items) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const path = try std.fs.path.join(a, &.{ located.root, module.src.path });
        try paths.append(a, path);
        var overridden = false;
        for (providers) |provider| overridden = overridden or std.mem.eql(u8, provider.path, module.src.path);
        try snapshot.source(path, module.src, overridden);
        if (located.configuration) |file| if (file.document.interface_files) {
            try snapshot.disk(try std.fmt.allocPrint(a, "{s}.api", .{path[0 .. path.len - 3]}));
        };
    }
    return paths.items;
}

fn configurationInputs(snapshot: *Snapshot, entry: project_entry.Entry) !void {
    if (entry.configuration) |file| {
        try snapshot.content(file.path, file.bytes);
        if (file.policy) |policy| try snapshot.content(policy.path, policy.bytes);
    }
    var directory = std.fs.path.dirname(entry.path).?;
    while (true) {
        const path = try std.fs.path.join(snapshot.allocator, &.{ directory, language.project_config.config_name });
        try snapshot.disk(path);
        if (entry.configuration) |file| if (std.mem.eql(u8, path, file.path)) return;
        const parent = std.fs.path.dirname(directory) orelse return;
        if (std.mem.eql(u8, parent, directory)) return;
        directory = parent;
    }
}

fn wave(init: std.process.Init, fanout: Fanout, paths: []const []const u8, outcomes: []Outcome) Error!void {
    const a = init.arena.allocator();
    var environment = try init.environ_map.clone(a);
    defer environment.deinit();
    try environment.put(tool_ticket.hint, "1");
    const children = try a.alloc(std.process.Child, paths.len);
    const files = try a.alloc(std.Io.File, paths.len);
    const names = try a.alloc([]const u8, paths.len);
    var started: usize = 0;
    defer for (children[0..started], files[0..started]) |*child, file| {
        child.kill(init.io);
        file.close(init.io);
    };
    for (paths, 0..) |path, slot| {
        names[slot] = try std.fmt.allocPrint(a, "{s}/{d}.json", .{ fanout.directory, slot });
        files[slot] = std.Io.Dir.cwd().createFile(init.io, names[slot], .{}) catch return error.WriteFailed;
        // Each child gets its own open-file offset, never a shared stdin stream.
        const input = std.Io.Dir.cwd().openFile(init.io, fanout.ticket, .{}) catch {
            files[slot].close(init.io);
            return error.ReadFailed;
        };
        defer input.close(init.io);
        children[slot] = std.process.spawn(init.io, .{ .argv = try argv(a, fanout, path), .environ_map = &environment, .stdin = .{ .file = input }, .stdout = .{ .file = files[slot] } }) catch {
            files[slot].close(init.io);
            return error.WriteFailed;
        };
        started += 1;
    }
    for (children, names, outcomes) |*child, name, *outcome| {
        const term = child.wait(init.io) catch return error.ReadFailed;
        outcome.* = .{ .code = switch (term) {
            .exited => |code| code,
            else => 1,
        }, .bytes = std.Io.Dir.cwd().readFileAlloc(init.io, name, a, .limited(64 << 20)) catch "" };
    }
}

fn argv(a: std.mem.Allocator, fanout: Fanout, path: []const u8) Error![]const []const u8 {
    const opts = fanout.controls;
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.appendSlice(a, &.{ fanout.compiler, "test", path, "--json", "--filter", opts.filter, "--cache-dir", opts.build.cache, "--zig", opts.build.zig, "--jobs", try std.fmt.allocPrint(a, "{d}", .{fanout.jobs}) });
    try arguments.appendSlice(a, &.{ "--timeout-ms", try std.fmt.allocPrint(a, "{d}", .{opts.controls.timeout_ms}) });
    if (opts.controls.ceilings.explicit_steps) try arguments.appendSlice(a, &.{ "--max-steps", try std.fmt.allocPrint(a, "{d}", .{opts.controls.max_steps}) });
    const ceilings = opts.controls.ceilings;
    if (ceilings.explicit_frames) try arguments.appendSlice(a, &.{ "--max-frames", try std.fmt.allocPrint(a, "{d}", .{ceilings.frames}) });
    if (ceilings.explicit_memory) try arguments.appendSlice(a, &.{ "--max-memory", try std.fmt.allocPrint(a, "{d}", .{ceilings.memory}) });
    try arguments.appendSlice(a, &.{ "--property-runs", try std.fmt.allocPrint(a, "{d}", .{opts.property_runs}) });
    if (opts.build.release) try arguments.append(a, "--release");
    if (opts.build.facts == .verify) try arguments.append(a, "--verify-facts");
    if (opts.build.facts == .off) try arguments.append(a, "--no-facts");
    if (opts.controls.force) try arguments.append(a, "--force");
    if (opts.controls.against) |reference| try arguments.appendSlice(a, &.{ "--affected", "--against", reference });
    if (opts.seed) |seed| try arguments.appendSlice(a, &.{ "--seed", try std.fmt.allocPrint(a, "{d}", .{seed}) });
    for (opts.build.links) |link| try arguments.appendSlice(a, &.{ "--link", link });
    return arguments.items;
}

fn summarize(init: std.process.Init, opts: options.Options, selection: Selection, outcomes: []const Outcome, tool_unchanged: bool) Error!u8 {
    const a = init.arena.allocator();
    var verdicts: std.ArrayList(report.Verdict) = .empty;
    var accounted: std.StringHashMapUnmanaged(void) = .empty;
    defer accounted.deinit(a);
    for (selection.entries, outcomes) |path, outcome| {
        const first_verdict = verdicts.items.len;
        const parsed = std.json.parseFromSlice(std.json.Value, a, outcome.bytes, .{ .allocate = .alloc_always }) catch {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test program produced no usable report" });
            continue;
        };
        const value = parsed.value;
        if (value != .object or !std.mem.eql(u8, string(value, "version"), "native-tests-v1")) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "invalid test report version" });
            continue;
        }
        const tests = value.object.get("tests") orelse .null;
        const sources = value.object.get("sources") orelse .null;
        if (tests != .array or sources != .array) {
            try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "incomplete test report" });
            continue;
        }
        for (sources.array.items) |source| if (source == .string) {
            try accounted.put(a, source.string, {});
        };
        for (tests.array.items) |test_value| {
            const status = std.meta.stringToEnum(report.Status, string(test_value, "status")) orelse .failed;
            var item: report.Verdict = .{ .name = string(test_value, "name"), .status = status, .reason = string(test_value, "reason"), .at = string(test_value, "at") };
            if (test_value == .object) if (test_value.object.get("property")) |evidence| {
                const parsed_evidence = std.json.parseFromValueLeaky(@import("test_runner_property.zig").Evidence, a, evidence, .{}) catch {
                    item.status = .failed;
                    item.reason = "invalid property evidence in test report";
                    try verdicts.append(a, item);
                    continue;
                };
                item.property = parsed_evidence;
            };
            try verdicts.append(a, item);
        }
        if (outcome.code != report.exitStatus(verdicts.items[first_verdict..])) try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test program exit status disagrees with its report" });
    }
    if (!tool_unchanged) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: toolchain changed during directory execution" });
    if (try sourceChanged(a, init.io, opts, selection)) try verdicts.append(a, .{ .name = opts.path, .status = .failed, .reason = "SourceChanged: directory discovery inputs changed during execution" });
    for (selection.tested) |path| if (!accounted.contains(path)) {
        try verdicts.append(a, .{ .name = path, .status = .failed, .reason = "test-declaring source was not loaded by any test program" });
    };
    var sources: std.ArrayList([]const u8) = .empty;
    var keys = accounted.keyIterator();
    while (keys.next()) |key| try sources.append(a, key.*);
    std.mem.sort([]const u8, sources.items, {}, before);
    try write(init.io, std.Io.File.stdout(), if (opts.json) try report.jsonSources(a, verdicts.items, sources.items) else try report.text(a, verdicts.items));
    return report.exitStatus(verdicts.items);
}

fn sourceChanged(a: std.mem.Allocator, io: std.Io, opts: options.Options, selection: Selection) Error!bool {
    const current = inventory(a, io, opts) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return true;
    };
    if (current.len != selection.discovered.len) return true;
    for (current, selection.discovered) |path, original| if (!std.mem.eql(u8, path, original)) return true;
    for (selection.inputs) |input| {
        const digest = receipt.readDigest(a, io, input.path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return true;
        };
        if (!sameDigest(digest, input.digest)) return true;
    }
    var diagnostics: std.ArrayList(u8) = .empty;
    for (selection.locations) |original| {
        const located = project_entry.resolve(a, io, original.path, &diagnostics) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return true;
        };
        if (!std.mem.eql(u8, original.root, located.root) or !std.mem.eql(u8, original.name, located.name)) return true;
        const config = if (located.configuration) |file| file.path else null;
        if (!samePath(config, original.configuration)) return true;
    }
    return false;
}

fn sameDigest(left: ?[32]u8, right: ?[32]u8) bool {
    if (left == null or right == null) return (left == null) == (right == null);
    return std.mem.eql(u8, &left.?, &right.?);
}
fn samePath(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return (left == null) == (right == null);
    return std.mem.eql(u8, left.?, right.?);
}

fn string(value: std.json.Value, key: []const u8) []const u8 {
    if (value != .object) return "";
    const field = value.object.get(key) orelse return "";
    return if (field == .string) field.string else "";
}

fn write(io: std.Io, file: std.Io.File, bytes: []const u8) Error!void {
    file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

fn before(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
fn generated(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or std.mem.startsWith(u8, name, ".mylang-cache") or std.mem.eql(u8, name, ".zig-cache") or std.mem.eql(u8, name, "zig-out") or std.mem.eql(u8, name, "node_modules");
}
fn declaresTests(bytes: []const u8) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) return true;
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line[7..], " \t");
        if (std.mem.startsWith(u8, line, "def test_")) return true;
    }
    return false;
}

// spec-case: NEW-CORE-S4-TEST-2
test "directory inventory recognizes test declarations and generated subtrees" {
    try std.testing.expect(declaresTests("public def test_x() -> bool:\n    return True\n"));
    try std.testing.expect(declaresTests("@test\ndef property(x: int) -> bool:\n    return True\n"));
    try std.testing.expect(!declaresTests("# def test_x()\n"));
    try std.testing.expect(generated(".mylang-cache-new"));
    try std.testing.expect(!generated("types"));
}

fn retire(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged detects edited or removed discovery inputs and allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "original" });
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash("original", &digest, .{});
    const inputs = &.{Input{ .path = path, .digest = digest }};
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = inputs, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.deleteFile(std.testing.io, "app.my");
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, sourceChanged(failing.allocator(), std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged detects external dependencies absent cases and required API creation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "tests");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = "entry" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "original" });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.my" });
    const dependency = try std.fs.path.join(a, &.{ root, "dep.my" });
    const cases = try case_settings.defaultPath(a, path);
    const api = try std.fs.path.join(a, &.{ root, "dep.api" });
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.disk(path);
    try snapshot.disk(dependency);
    try snapshot.record(cases, null);
    try snapshot.record(api, null);
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = try std.fs.path.join(a, &.{ root, "tests" }), .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "changed" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "original" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.cases.json", .data = "{}" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.deleteFile(std.testing.io, "tests/app.cases.json");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.api", .data = "new interface" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "Snapshot deduplicates content and refuses SourceChanged during discovery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.content("dep.my", "first");
    try snapshot.content("dep.my", "first");
    try std.testing.expectEqual(@as(usize, 1), snapshot.inputs.items.len);
    try std.testing.expectError(error.SourceChanged, snapshot.content("dep.my", "other"));
}

// spec-case: NEW-CORE-S4-TEST-2
test "sourceChanged preserves inventory additions and ignores unrelated outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "original" });
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try snapshot.disk(path);
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = root, .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "output.json", .data = "{}" });
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "new.my", .data = "new source" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}

// spec-case: NEW-CORE-S4-TEST-2
test "loadedClosure snapshots provider imports embeds config policy cases and required APIs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "tests");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.my", .data = "module tests.app\nimport dep\npublic def test_x() -> bool:\n    return True\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "dep.my", .data = "module dep\npublic def value() -> str:\n    return \"old\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "ext.my", .data = "module ext\npublic def value() -> str:\n    return \"external\"\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "original asset" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = language.project_config.config_name, .data = "{\"version\":1,\"interface_files\":true,\"import_policy\":\"policy.json\"}" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "policy.json", .data = "{}" });
    const configured_cases = "{\"test_x\":{\"providers\":{\"dep.my\":\"module dep\\nimport ext\\n" ++
        "public def value() -> str:\\n    return embed_str(\\\"data.txt\\\")\\n\"}}}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tests/app.cases.json", .data = configured_cases });
    const path = try std.fs.path.join(a, &.{ root, "tests/app.my" });
    var diagnostics: std.ArrayList(u8) = .empty;
    const entry = try project_entry.resolve(a, std.testing.io, path, &diagnostics);
    var snapshot: Snapshot = .{ .allocator = a, .io = std.testing.io };
    defer snapshot.index.deinit(a);
    try configurationInputs(&snapshot, entry);
    const cases = try case_settings.load(a, std.testing.io, path, null);
    try snapshot.content(cases.path.?, cases.bytes);
    const resources: Discovery = .{ .allocator = a, .gpa = std.testing.allocator, .io = std.testing.io };
    _ = try loadedClosure(resources, entry, &.{}, &snapshot);
    const sets = try case_settings.providerSets(a, cases, "");
    _ = try loadedClosure(resources, entry, sets[0], &snapshot);
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "ext.my" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "data.txt" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "dep.api" })));
    try std.testing.expect(snapshot.index.contains(try std.fs.path.join(a, &.{ root, "policy.json" })));
    const selection: Selection = .{ .entries = &.{}, .tested = &.{}, .inputs = snapshot.inputs.items, .discovered = &.{path} };
    const opts: options.Options = .{ .path = try std.fs.path.join(a, &.{ root, "tests" }), .build = .{ .zig = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) } };
    try std.testing.expect(!try sourceChanged(a, std.testing.io, opts, selection));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "data.txt", .data = "changed asset" });
    try std.testing.expect(try sourceChanged(a, std.testing.io, opts, selection));
}
