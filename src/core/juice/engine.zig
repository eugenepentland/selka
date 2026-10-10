//! Isolated builds, immutable records, repeat validation and separate semantic runs.
const std = @import("std");
const key_compiler = "compiler";
const key_correctness = "correctness";
const key_dependencies = "dependencies";
const workspace_name = "workspace";
const d = @import("data.zig");
const p = @import("platform.zig");
const manifest = @import("manifest.zig");
const collectors = @import("collectors.zig");
const inventory = @import("inventory.zig");
const profiles = @import("profiles.zig");
const C = d.Context;
const V = d.Value;
const M = manifest.Manifest;
const native_id = "mylang-juice-native-v1";
/// Build and selection controls, grouped independently of collector options.
pub const Options = struct { cache: []const u8, compiler: ?[]const u8 = null, name: []const u8 = "", tier: []const u8 = "quick", workloads: V = .null, repeats: usize = 3, static: bool = false };
const Workspace = struct { cache: []const u8, root: []const u8, project: []const u8, run: []const u8, lock: std.Io.File };
fn workspace(c: *C, m: M, options: Options) !Workspace {
    const cache = try c.join(&.{ try p.absolute(c, options.cache), try d.str(d.get(m.data, "name")) });
    try c.mkdir(cache);
    const lock = try std.Io.Dir.cwd().createFile(c.io, try c.join(&.{ cache, ".lock" }), .{ .truncate = false });
    errdefer lock.close(c.io);
    try lock.lock(c.io, .exclusive);
    const root = try c.join(&.{ cache, workspace_name });
    try c.mkdir(root);
    return .{ .cache = cache, .root = root, .project = try c.join(&.{ root, "project" }), .run = try c.join(&.{ root, "run" }), .lock = lock };
}
fn reset(c: *C, path: []const u8) !void {
    try std.Io.Dir.cwd().deleteTree(c.io, path);
    try c.mkdir(path);
}
fn copyFiles(c: *C, root: []const u8, target: []const u8, identities: V) !void {
    for (try d.keys(c, identities)) |name| {
        const destination = try c.join(&.{ target, name });
        try p.copy(c, try p.inside(c, root, name), destination);
        if (!d.equal(try c.fileHash(destination), d.get(identities, name))) return c.fail("source/input changed while capturing");
    }
}
fn dependencies(c: *C, root: []const u8, names: V) !V {
    var result = d.object();
    for (try d.items(names)) |name| {
        const text = try d.str(name);
        const path = try p.real(c, if (std.fs.path.isAbsolute(text)) text else try c.join(&.{ root, text }));
        if (std.Io.Dir.cwd().openDir(c.io, path, .{ .iterate = true })) |opened| {
            var dir = opened;
            defer dir.close(c.io);
            var walker = try dir.walk(c.a);
            defer walker.deinit();
            while (try walker.next(c.io)) |entry| if (entry.kind == .file or entry.kind == .sym_link) {
                const file = try p.real(c, try c.join(&.{ path, entry.path }));
                try d.put(c, &result, file, try c.fileHash(file));
            };
        } else |err| {
            if (err != error.NotDir) return err;
            try d.put(c, &result, path, try c.fileHash(path));
        }
    }
    return result;
}
fn config(c: *C, m: M, override: ?[]const u8) !V {
    const b = d.get(m.data, "build");
    var compiler = override orelse (d.str(d.get(b, key_compiler)) catch try d.str((try d.items(d.get(b, "command")))[0]));
    if (d.is(d.get(m.data, "adapter"), "mylang") and std.mem.eql(u8, compiler, "mylang")) compiler = c.self;
    if (override != null and d.is(d.get(m.data, "adapter"), "native")) {
        var found = false;
        for (try d.items(d.get(b, "command"))) |arg| {
            if (std.mem.indexOf(u8, try d.str(arg), "{compiler}") != null) found = true;
        }
        if (!found) return c.fail("native --compiler requires {compiler} in build.command");
    }
    var tools = d.object();
    for (try d.items(d.get(b, "tools"))) |name| try d.put(c, &tools, try d.str(name), try p.identity(c, try d.str(name)));
    if (d.is(d.get(m.data, "adapter"), "mylang")) try d.put(c, &tools, "zig", try p.identity(c, c.env.get("ZIG") orelse c.env.get("MYLANG_ZIG") orelse "zig"));
    return c.value(.{
        .compiler = try p.identity(c, compiler),
        .tools = tools,
        .dependencies = try dependencies(c, m.root, d.get(b, key_dependencies)),
        .spec = b,
        .environment_sha256 = try p.buildEnvironment(c),
    });
}
fn addPaths(c: *C, paths: *V, identities: V) !void {
    for (try d.keys(c, identities)) |name| try d.put(c, paths, name, .null);
}
fn addInventory(c: *C, files: *V, root: []const u8, identities: V) !void {
    for (try d.keys(c, identities)) |name| try d.put(c, files, try c.join(&.{ root, name }), .null);
}
fn globScopes(c: *C, directories: *V, root: []const u8, patterns: V) !void {
    for (try d.items(patterns)) |pattern| {
        const glob = try d.str(pattern);
        const special = std.mem.indexOfAny(u8, glob, "*?[") orelse continue;
        const slash = std.mem.lastIndexOfScalar(u8, glob[0..special], '/');
        const prefix = if (slash) |at| glob[0..at] else "";
        const declared = try c.join(&.{ root, prefix });
        try d.put(c, directories, declared, .null);
        try d.put(c, directories, try p.real(c, declared), .null);
    }
}
fn dependencyScopes(c: *C, files: *V, directories: *V, root: []const u8, names: V) !void {
    for (try d.items(names)) |name| {
        const text = try d.str(name);
        const declared = if (std.fs.path.isAbsolute(text)) text else try c.join(&.{ root, text });
        const path = try p.real(c, declared);
        if (std.Io.Dir.cwd().openDir(c.io, path, .{})) |opened| {
            var dir = opened;
            dir.close(c.io);
            try d.put(c, directories, declared, .null);
            try d.put(c, directories, path, .null);
        } else |err| {
            if (err != error.NotDir) return err;
            try d.put(c, files, declared, .null);
        }
    }
}
fn pathArray(c: *C, paths: V) !V {
    var result = d.array(c);
    for (try d.keys(c, paths)) |path| try d.add(c, &result, d.string(path));
    return result;
}
fn inputScopes(c: *C, m: M, collector: collectors.Collector, configuration: V, path: []const u8) !V {
    var files = d.object();
    var directories = d.object();
    try d.put(c, &files, path, .null);
    try d.put(c, &files, try p.real(c, c.self), .null);
    try addInventory(c, &files, m.root, m.sources);
    try addInventory(c, &files, m.root, m.inputs);
    try addPaths(c, &files, d.get(configuration, key_dependencies));
    try d.put(c, &files, try d.str(d.get(d.get(configuration, key_compiler), "path")), .null);
    for (try d.keys(c, d.get(configuration, "tools"))) |name| {
        try d.put(c, &files, try d.str(d.get(d.get(d.get(configuration, "tools"), name), "path")), .null);
    }
    try d.put(c, &files, try d.str(d.get(d.get(collector.identity, "tool"), "path")), .null);
    try globScopes(c, &directories, m.root, d.get(m.data, "sources"));
    try globScopes(c, &directories, m.root, d.get(m.data, "inputs"));
    try dependencyScopes(c, &files, &directories, m.root, d.get(d.get(m.data, "build"), key_dependencies));
    const lib = d.get(collector.extra, "VALGRIND_LIB");
    if (lib != .null) try d.put(c, &directories, try d.str(lib), .null);
    return c.value(.{ .files = try pathArray(c, files), .directories = try pathArray(c, directories) });
}
fn collectorRuntime(c: *C, collector: collectors.Collector) !V {
    var required = d.array(c);
    try d.add(c, &required, d.string("Declare collector executable loader/libraries and all runtime providers in the external closed contract."));
    const explicit_lib = d.get(collector.extra, "VALGRIND_LIB") != .null;
    if (!std.mem.eql(u8, collector.kind, "perf") and !explicit_lib) {
        try d.add(c, &required, d.string("Default Valgrind engine, preload, suppression and support resources are not inventoried; declare the complete installation."));
    }
    return c.value(.{
        .environment = collector.extra,
        .provider_scope = if (explicit_lib) "explicit" else "incomplete",
        .closure_complete = false,
        .required_resources = required,
    });
}
/// Inspect native contracts and tool identities without building, locking or creating a workspace.
pub fn plan(c: *C, m: M, collector: collectors.Collector, options: Options, manifest_path: []const u8) d.Error!V {
    return planImpl(c, m, collector, options, manifest_path) catch |err| d.failure(c, err);
}
fn planImpl(c: *C, m: M, collector: collectors.Collector, options: Options, manifest_path: []const u8) !V {
    if (options.repeats < 2 or options.repeats > 30) return c.fail("plan requires 2..30 repeats");
    const selected = try manifest.select(c, m, options.tier, options.workloads);
    const configuration = try config(c, m, options.compiler);
    const cache = try c.join(&.{ try p.absolute(c, options.cache), try d.str(d.get(m.data, "name")) });
    const project = try c.join(&.{ cache, workspace_name, "project" });
    const run = try c.join(&.{ cache, workspace_name, "run" });
    const path = try p.real(c, manifest_path);
    const self = try p.real(c, c.self);
    return c.value(.{
        .version = "juice-plan-v1",
        .identity_scheme = native_id,
        .manifest_path = path,
        .root = m.root,
        .manifest = m.data,
        .sources = m.sources,
        .inputs = m.inputs,
        .selected_workloads = selected,
        .build_config = configuration,
        .implementation = .{ .embedded_identity = implementationIdentity(), .running_elf = .{ .path = self, .sha256 = try c.fileHash(self) } },
        .measurement = .{
            .repeats = options.repeats,
            .static = options.static,
            .collector = collector.identity,
            .context = try collectors.context(c, collector, run, d.object()),
            .libraries_status = "unavailable before build; validate retained executable and declared runtime providers",
        },
        .paths = .{ .cache = cache, .project = project, .run = run },
        .input_scopes = try inputScopes(c, m, collector, configuration, path),
        .collector_runtime = try collectorRuntime(c, collector),
    });
}
const Build = struct { stored: []const u8, record: V };
fn build(c: *C, m: M, w: Workspace, configuration: V, options: Options, counted: bool) !Build {
    try reset(c, w.project);
    try copyFiles(c, m.root, w.project, m.sources);
    try copyFiles(c, m.root, w.project, m.inputs);
    const tool_id = implementationIdentity();
    const key = try c.hash(try c.value(.{
        .version = native_id,
        .tool_id = tool_id,
        .sources = m.sources,
        .inputs = m.inputs,
        .adapter = d.get(m.data, "adapter"),
        .config = configuration,
        .static = options.static,
        .counted = counted,
    }));
    const stored = try c.join(&.{ w.cache, "builds", try d.str(key) });
    const receipt = try c.join(&.{ stored, "receipt.json" });
    if (c.read(receipt)) |cached| {
        var result = cached;
        for (try d.keys(c, try d.req(result, "artifacts"))) |kind| {
            if (!d.equal(try c.fileHash(try c.join(&.{ stored, kind })), d.get(d.get(result, "artifacts"), kind))) return c.fail("corrupt build cache");
        }
        try d.put(c, &result, "cached", .{ .bool = true });
        try d.put(c, &result, "build_seconds", .{ .integer = 0 });
        return .{ .stored = stored, .record = result };
    } else |err| if (err != error.FileNotFound) return err;
    try c.mkdir(stored);
    const b = d.get(m.data, "build");
    const output = try c.join(&.{ w.root, "built-program" });
    const compiler = try d.str(d.get(d.get(configuration, key_compiler), "path"));
    const values = try c.value(.{ .root = w.project, .binary = output, .compiler = compiler });
    var env = try c.env.clone(c.a);
    try env.put("LC_ALL", "C");
    try env.put("LANG", "C");
    try env.put("TZ", "UTC");
    try env.put("PWD", w.project);
    var artifacts = d.object();
    var seconds: f64 = 0;
    const mylang = d.is(d.get(m.data, "adapter"), "mylang");
    const kinds: []const []const u8 = if (mylang and counted) &.{ "plain", "counted" } else &.{"plain"};
    for (kinds) |kind| {
        std.Io.Dir.cwd().deleteFile(c.io, output) catch |err| if (err != error.FileNotFound) return err;
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(c.a, try d.expand(c, d.get(b, "prefix"), values));
        if (mylang) {
            try argv.appendSlice(c.a, &.{ compiler, "build", try c.join(&.{ w.project, try d.str(d.get(b, "entry")) }), "--release", "-o", output });
            try argv.appendSlice(c.a, try d.expand(c, d.get(b, "flags"), values));
            if (std.mem.eql(u8, kind, "counted")) try argv.append(c.a, "--counters");
        } else try argv.appendSlice(c.a, try d.expand(c, d.get(b, "command"), values));
        const run = try p.run(c, .{
            .argv = argv.items,
            .cwd = w.project,
            .env = &env,
            .prefix = try c.join(&.{
                stored,
                try std.fmt.allocPrint(c.a, "{s}-build", .{
                    kind,
                }),
            }),
            .seconds = try d.positive(d.get(b, d.key_timeout_seconds)),
        });
        seconds += try d.num(d.get(run, "wall_seconds"));
        if (try d.num(d.get(run, d.key_exit_code)) != 0) return c.fail("build failed; logs retained in build cache");
        const target = try c.join(&.{ stored, kind });
        try p.copy(c, output, target);
        try d.put(c, &artifacts, kind, try c.fileHash(target));
    }
    var result = try c.value(.{ .key = key, .cached = false, .build_seconds = seconds, .artifacts = artifacts, .code = try inventory.code(c, try c.join(&.{ stored, "plain" })) });
    if (options.static and mylang) try staticCost(c, &result, .{ .m = m, .w = w, .stored = stored, .config = configuration, .env = &env });
    try c.write(receipt, result);
    return .{ .stored = stored, .record = result };
}
const CostInput = struct { m: M, w: Workspace, stored: []const u8, config: V, env: *const std.process.Environ.Map };
fn staticCost(c: *C, result: *V, input: CostInput) !void {
    const b = d.get(input.m.data, "build");
    const flags = d.get(b, "flags");
    for (try d.items(flags)) |flag| if (!d.is(flag, "--no-facts") and !d.is(flag, "--verify-facts")) {
        try d.put(c, result, "static_cost", try c.value(.{ .status = "unavailable", .reason = "build flags unsupported by cost adapter" }));
        return;
    };
    const compiler = try d.str(d.get(d.get(input.config, key_compiler), "path"));
    const values = try c.value(.{ .root = input.w.project, .compiler = compiler, .binary = try c.join(&.{ input.w.root, "built-program" }) });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(c.a, try d.expand(c, d.get(b, "prefix"), values));
    try argv.appendSlice(c.a, &.{ compiler, "cost", try c.join(&.{ input.w.project, try d.str(d.get(b, "entry")) }), "--json" });
    try argv.appendSlice(c.a, try d.expand(c, flags, values));
    const prefix = try c.join(&.{ input.stored, "cost" });
    const row = try p.run(c, .{ .argv = argv.items, .cwd = input.w.project, .env = input.env, .prefix = prefix, .seconds = try d.positive(d.get(b, d.key_timeout_seconds)) });
    if (try d.num(d.get(row, d.key_exit_code)) != 0) return c.fail("mylang cost failed; logs retained");
    try d.put(c, result, "static_cost", try c.read(try std.fmt.allocPrint(c.a, "{s}.stdout", .{prefix})));
}
/// Build and inspect optimized code without running the application.
pub fn analyze(c: *C, m: M, options: Options) d.Error!V {
    return analyzeImpl(c, m, options) catch |err| d.failure(c, err);
}
fn analyzeImpl(c: *C, m: M, options: Options) !V {
    const w = try workspace(c, m, options);
    defer w.lock.close(c.io);
    const configuration = try config(c, m, options.compiler);
    var opts = options;
    opts.static = true;
    const result = try build(c, m, w, configuration, opts, false);
    return c.value(.{
        .version = "juice-analysis-v1",
        .tool_id = implementationIdentity(),
        .source_root = m.root,
        .sources = m.sources,
        .build_config = configuration,
        .build = result.record,
        .scope = "static sites, optimization remarks and code bytes; no execution or juice score",
    });
}
fn prepare(c: *C, m: M, w: Workspace, b: Build, kind: []const u8) !std.process.Environ.Map {
    try reset(c, w.run);
    try copyFiles(c, m.root, w.run, m.inputs);
    try p.copy(c, try c.join(&.{ b.stored, kind }), try c.join(&.{ w.run, "program" }));
    return p.environment(c, w.run, d.get(m.data, "environment"));
}
const Trial = struct { workload: V, row: V, prefix: []const u8, work: []const u8, project: []const u8, env: *const std.process.Environ.Map };
fn check(c: *C, t: Trial) !V {
    if (try d.num(d.get(t.row, d.key_exit_code)) != 0) return c.fail("workload did not complete successfully");
    const stdout = try std.fmt.allocPrint(c.a, "{s}.stdout", .{t.prefix});
    const stderr = try std.fmt.allocPrint(c.a, "{s}.stderr", .{t.prefix});
    var bytes = try c.readBytes(stdout);
    if (d.get(t.workload, "stdout_regex") != .null) bytes = try @import("normalize.zig").apply(c, try d.str(d.get(t.workload, "stdout_regex")), bytes);
    const hash = try c.hashBytes(bytes);
    const expected = d.get(t.workload, "expected_stdout");
    const sha = d.get(t.workload, "stdout_sha256");
    if (expected != .null and !d.is(expected, bytes)) return c.fail("incorrect stdout; raw output retained");
    if (sha != .null and !d.equal(sha, hash)) return c.fail("incorrect stdout digest; raw output retained");
    if (!d.is(d.get(t.workload, "expected_stderr"), try c.readBytes(stderr))) return c.fail("incorrect stderr; raw output retained");
    const command = d.get(t.workload, "check");
    if ((try d.items(command)).len > 0) {
        const values = try c.value(.{ .stdout = stdout, .stderr = stderr, .work = t.work, .root = t.project, .binary = try c.join(&.{ t.work, "program" }) });
        const row = try p.run(c, .{
            .argv = try d.expand(c, command, values),
            .cwd = t.work,
            .env = t.env,
            .prefix = try std.fmt.allocPrint(c.a, "{s}-oracle", .{
                t.prefix,
            }),
            .seconds = try d.positive(d.get(t.workload, d.key_timeout_seconds)),
        });
        if (try d.num(d.get(row, d.key_exit_code)) != 0) return c.fail("correctness command failed; raw output retained");
    }
    var files = d.object();
    for (try d.items(d.get(t.workload, "outputs"))) |file| {
        const path = try d.str(file);
        try d.put(c, &files, path, try c.fileHash(try p.inside(c, t.work, path)));
    }
    return c.value(.{ .stdout = hash, .stderr = d.get(t.row, "stderr_sha256"), .files = files });
}
fn summarize(c: *C, samples: V) !V {
    const rows = try d.items(samples);
    if (rows.len < 2) return error.InvalidExperiment;
    var result = d.object();
    for (try d.keys(c, d.get(rows[0], "metrics"))) |key| {
        const values = try c.a.alloc(f64, rows.len);
        for (rows, values) |row, *value| value.* = try d.num(try d.req(d.get(row, "metrics"), key));
        try d.put(c, &result, key, try d.summary(c, values));
    }
    return result;
}
const Capture = struct { m: M, w: Workspace, b: Build, collector: collectors.Collector, destination: []const u8, options: Options };
fn workload(c: *C, cap: Capture, work: V) !V {
    const region = d.get(work, "region");
    var cell = try c.value(.{
        .units = d.get(work, "units"),
        .unit = d.get(work, "unit"),
        .family = d.get(work, "family"),
        .tier = d.get(work, "tier"),
        .region = region,
        .scope = if (region == .null) "complete scenario" else "selected function and callees",
        .weight = d.get(work, "weight"),
    });
    var samples = d.array(c);
    const ordinary: usize = if (std.mem.eql(u8, cap.collector.kind, "perf")) 0 else 1;
    const counted: usize = if (d.is(d.get(cap.m.data, "adapter"), "mylang")) 1 else 0;
    const name = try d.str(d.get(work, "name"));
    for (0..ordinary + cap.options.repeats + counted) |i| {
        const kind = if (i < ordinary) "native" else if (i < ordinary + cap.options.repeats) "sample" else "counted";
        var env = try prepare(c, cap.m, cap.w, cap.b, if (std.mem.eql(u8, kind, "counted")) "counted" else "plain");
        const binary = try c.join(&.{ cap.w.run, "program" });
        const values = try c.value(.{ .root = cap.w.project, .work = cap.w.run, .binary = binary });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(c.a, binary);
        try argv.appendSlice(c.a, try d.expand(c, d.get(work, "args"), values));
        const prefix = try c.join(&.{ cap.destination, try std.fmt.allocPrint(c.a, "{s}-{d}-{s}", .{ name, i, kind }) });
        const counters = try c.join(&.{ cap.w.run, "counters.json" });
        if (std.mem.eql(u8, kind, "counted")) try env.put("MYLANG_COUNTERS", counters);
        const options: p.Run = .{ .argv = argv.items, .cwd = cap.w.run, .env = &env, .prefix = prefix, .seconds = try d.positive(d.get(work, d.key_timeout_seconds)), .cpu = cap.collector.cpu };
        var row = if (std.mem.eql(u8, kind, "sample")) try collectors.collect(c, cap.collector, options, work) else try p.run(c, options);
        const correct = try check(c, .{ .workload = work, .row = row, .prefix = prefix, .work = cap.w.run, .project = cap.w.project, .env = &env });
        if (d.get(cell, key_correctness) != .null and !d.equal(d.get(cell, key_correctness), correct)) return c.fail("repeated or instrumented runs disagree on output");
        try d.put(c, &cell, key_correctness, correct);
        if (std.mem.eql(u8, kind, "sample")) {
            for ([_][]const u8{ d.key_functions, "lines" }) |key| try d.put(c, &row, key, try profiles.normalize(c, d.get(row, key), cap.w.project, cap.w.run));
            try d.add(c, &samples, row);
        } else if (std.mem.eql(u8, kind, "counted")) {
            const document = try c.read(counters);
            if (!d.is(d.get(document, "version"), "mylang-counters-v1") or d.get(document, "totals") != .object) return c.fail("unsupported mylang counter document");
            if (d.get(document, "sites") != .null) for (try d.items(d.get(document, "sites"))) |*site| {
                const path = d.get(site.*, "path");
                if (path == .string) try d.put(c, site, "path", d.string(try std.mem.replaceOwned(u8, c.a, path.string, try std.fmt.allocPrint(c.a, "{s}/", .{cap.w.project}), "")));
            };
            try d.put(c, &cell, "semantic", document);
            try d.put(c, &cell, "counter_semantics", d.get(d.get(cap.m.data, "build"), "counter_semantics"));
            try p.copy(c, counters, try c.join(&.{ cap.destination, try std.fmt.allocPrint(c.a, "{s}-counters.json", .{name}) }));
        }
    }
    const summary = try summarize(c, samples);
    try d.put(c, &cell, "metrics", summary);
    try d.put(c, &cell, "samples", samples);
    const median = try d.num(d.get(d.get(summary, d.key_instructions), "median"));
    var chosen = samples.array.items[0];
    for (samples.array.items) |s| if (@abs(try d.num(d.get(d.get(s, "metrics"), d.key_instructions)) - median) < @abs(try d.num(d.get(d.get(chosen, "metrics"), d.key_instructions)) - median)) {
        chosen = s;
    };
    try d.put(c, &cell, d.key_functions, d.get(chosen, d.key_functions));
    try d.put(c, &cell, "lines", d.get(chosen, "lines"));
    return cell;
}
fn complete(c: *C, record: *V, m: M, w: Workspace, request: struct { collector: collectors.Collector, options: Options, selected: V, destination: []const u8, path: []const u8 }) !void {
    const configuration = try config(c, m, request.options.compiler);
    try d.put(c, record, "build_config", configuration);
    const built = try build(c, m, w, configuration, request.options, true);
    try d.put(c, record, "build", built.record);
    var env = try prepare(c, m, w, built, "plain");
    const libraries = try inventory.libraries(c, try c.join(&.{ w.run, "program" }), &env);
    try d.put(c, record, "context", try collectors.context(c, request.collector, w.run, libraries));
    var workloads = d.object();
    for (try d.items(request.selected)) |work| {
        const name = try d.str(d.get(work, "name"));
        try std.Io.File.stderr().writeStreamingAll(c.io, try std.fmt.allocPrint(c.a, "juice: {s} ({s}, {d} samples)\n", .{ name, request.collector.kind, request.options.repeats }));
        const cell = try workload(c, .{ .m = m, .w = w, .b = built, .collector = request.collector, .destination = request.destination, .options = request.options }, work);
        try d.put(c, &workloads, name, cell);
        try d.put(c, record, "workloads", workloads);
        try c.write(request.path, record.*);
    }
    var evidence = d.object();
    var dir = try std.Io.Dir.cwd().openDir(c.io, request.destination, .{ .iterate = true });
    defer dir.close(c.io);
    var it = dir.iterate();
    while (try it.next(c.io)) |entry| if (entry.kind == .file and !std.mem.eql(u8, entry.name, "record.json")) {
        try d.put(c, &evidence, try c.a.dupe(u8, entry.name), try c.fileHash(try c.join(&.{ request.destination, entry.name })));
    };
    try d.put(c, record, "evidence", evidence);
    try d.put(c, record, "status", d.string("complete"));
    try c.write(request.path, record.*);
}
/// Capture a new immutable record; retain incomplete records and diagnostics on failure.
pub fn capture(c: *C, m: M, collector: collectors.Collector, options: Options) d.Error![]const u8 {
    return captureImpl(c, m, collector, options) catch |err| d.failure(c, err);
}
fn captureImpl(c: *C, m: M, collector: collectors.Collector, options: Options) ![]const u8 {
    if (!d.identifier(options.name) or options.repeats < 2 or options.repeats > 30) return c.fail("record needs a simple name and 2..30 repeats");
    const selected = try manifest.select(c, m, options.tier, options.workloads);
    const w = try workspace(c, m, options);
    defer w.lock.close(c.io);
    const parent = try c.join(&.{ w.cache, "records" });
    try c.mkdir(parent);
    const destination = try c.join(&.{ parent, options.name });
    std.Io.Dir.cwd().createDir(c.io, destination, .default_dir) catch |err| {
        if (err == error.PathAlreadyExists) return c.fail("record already exists; records are immutable");
        return err;
    };
    const path = try c.join(&.{ destination, "record.json" });
    var record = try c.value(.{
        .version = "juice-v1",
        .identity_scheme = native_id,
        .tool_id = implementationIdentity(),
        .name = options.name,
        .status = "incomplete",
        .manifest = m.data,
        .source_root = m.root,
        .sources = m.sources,
        .contract = .{
            .name = d.get(m.data, "name"),
            .inputs = m.inputs,
            .environment = d.get(m.data, "environment"),
            .workloads = selected,
        },
        .collector = collector.identity,
        .workloads = d.object(),
    });
    try c.write(path, record);
    complete(c, &record, m, w, .{ .collector = collector, .options = options, .selected = selected, .destination = destination, .path = path }) catch |err| {
        const message = try std.fmt.allocPrint(c.a, "{s}: {s}; incomplete record retained: {s}", .{ @errorName(err), c.message, path });
        try d.put(c, &record, "error", d.string(message));
        try c.write(path, record);
        return c.fail(message);
    };
    return path;
}

// The same embedded production-source/toolchain identity used by compiler receipts.
fn implementationIdentity() V {
    return d.string(@import("build_identity").compiler_identity);
}
