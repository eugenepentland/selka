//! Native Juice parser, reporting and process tests independent of optional collectors.
const std = @import("std");
const t = std.testing;
const d = @import("data.zig");
const profiles = @import("profiles.zig");
const report = @import("report.zig");
const toml = @import("toml.zig");
const normalize = @import("normalize.zig");
const manifest = @import("manifest.zig");
const command = @import("command.zig");
const platform = @import("platform.zig");
fn context(a: std.mem.Allocator) !d.Context {
    const env = try a.create(std.process.Environ.Map);
    env.* = try std.testing.environ.createMap(a);
    return .{ .a = a, .io = t.io, .env = env, .self = "unused" };
}
// spec: JUICE-NATIVE-1
test "Juice native collector parsers reject partial and inconsistent work" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    const counted = try profiles.perf(&c, "100;;cpu_core/instructions/u;12;100.00\n", "cpu_core/instructions/u");
    try t.expectEqual(@as(f64, 100), try d.num(d.get(counted, "instructions")));
    try t.expectError(error.InvalidExperiment, profiles.perf(&c, "100;;instructions:u;12;99.00\n", "instructions:u"));
    try t.expectError(error.InvalidExperiment, profiles.perf(&c, "<not supported>;;instructions:u;12;100\n", "instructions:u"));
    const profile = "positions: instr line\nevents: Ir Dr Dw Ge\nob=(1) program\nfl=(1) input.c\nfn=(1) body\n0x100 3 40 10 2\ncfn=(2) callee\ncalls=1 0x200 9\n* * 99\nfn=(2)\n0x200 9 60 20 3 1\nsummary: 0\ntotals: 100 30 5 1\n";
    const parsed = try profiles.grind(&c, profile);
    try t.expectEqual(@as(f64, 100), try d.num(d.get(d.get(parsed, "metrics"), "instructions")));
    try t.expectEqual(@as(usize, 2), (try d.items(d.get(parsed, "functions"))).len);
    try t.expectError(error.InvalidExperiment, profiles.grind(&c, "events: Ir\n1 2\nsummary: 3\n"));
    const plain = try profiles.grind(&c, "events: Ir\nfn=(below main)\n0 1\nsummary: 1\n");
    try t.expectEqual(@as(f64, 1), try d.num(d.get(d.get(plain, "metrics"), "instructions")));
}
// spec-case: JUICE-NATIVE-1
test "Juice native manifest syntax and normalization fail closed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    const parsed = try toml.parse(&c, "version = 1\n[build]\nflags = [\n'--release', # comment\n]\n[[workloads]]\nname = \"one\"\nexpected_stdout = \"42\\n\"\n[[workloads]]\nname = 'two'\n");
    try t.expectEqual(@as(usize, 2), (try d.items(d.get(parsed, "workloads"))).len);
    try t.expectError(error.InvalidExperiment, toml.parse(&c, "version=1\nversion=2\n"));
    try t.expectEqualStrings("42", try normalize.apply(&c, "elapsed=\\d+ ms; value=(\\d+)\\n", "elapsed=932 ms; value=42\n"));
    try t.expectEqualStrings("abc", try normalize.apply(&c, "(?:prefix|other):([a-z]{2,4})", "prefix:abc"));
    try t.expectError(error.InvalidExperiment, normalize.apply(&c, "value=(\\d+)", "prefix value=42"));
    try t.expectError(error.InvalidExperiment, normalize.validate(&c, "no capture"));
    try t.expectError(error.InvalidExperiment, normalize.validate(&c, "(a)(b)"));
    try t.expect(manifest.matches("src/**/*.c", "src/kernel.c"));
    try t.expect(manifest.matches("src/**/*.c", "src/nested/kernel.c"));
    try t.expect(!manifest.matches("src/*.c", "src/nested/kernel.c"));
    try t.expectError(error.InvalidExperiment, command.parse(&c, &.{ "compare", "a", "b", "--typo", "value" }));
    try t.expectError(error.InvalidExperiment, d.positive(.{ .float = std.math.nan(f64) }));
}
// spec: NEW-CORE-JUICE-PLAN-1
test "Juice plan parses read-only selection and refuses capture or comparison controls" {
    const plan_name = "plan";
    const manifest_name = "input.toml";
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    const parsed = try command.parse(&c, &.{ plan_name, manifest_name, "--workload", "first", "--workload", "second", "--repeats", "5", "--profile", "runtime", "--static" });
    try t.expectEqualStrings(plan_name, parsed.command);
    try t.expectEqual(@as(usize, 2), (try d.items(d.get(parsed.options, "workload"))).len);
    try t.expectEqualStrings("5", command.option(parsed, "repeats", ""));
    try t.expect(d.equal(d.get(parsed.options, "static"), .{ .bool = true }));
    try t.expectError(error.InvalidExperiment, command.parse(&c, &.{ plan_name, manifest_name, "--name", "capture" }));
    try t.expectError(error.InvalidExperiment, command.parse(&c, &.{ plan_name, manifest_name, "--output", "capture.json" }));
    try t.expectError(error.InvalidExperiment, command.parse(&c, &.{ plan_name, manifest_name, "--fail-above", "101" }));
}
fn fixture(c: *d.Context, name: []const u8, count: f64) !d.Value {
    const metrics = try d.summary(c, &.{ count, count, count });
    const cell = try c.value(.{
        .metrics = .{
            .instructions = metrics,
        },
        .correctness = .{
            .stdout = "same",
        },
        .units = 10,
        .unit = "record",
        .family = "sum",
        .tier = "quick",
        .scope = "complete scenario",
        .weight = 1,
        .functions = d.array(c),
        .lines = d.array(c),
    });
    return c.value(.{
        .version = "juice-v1",
        .status = "complete",
        .name = name,
        .contract = .{
            .unit = "record",
        },
        .context = .{
            .cpu = "same",
            .libraries = d.object(),
        },
        .sources = .{
            .file = "same",
        },
        .build_config = .{
            .compiler = "same",
        },
        .collector = .{
            .kind = "fixture",
        },
        .build = .{
            .code = .{
                .available = true,
                .sections = d.object(),
                .functions = d.object(),
            },
        },
        .workloads = .{
            .sum = cell,
        },
    });
}
// spec-case: JUICE-NATIVE-1
test "Juice native comparison separates instructions uncertainty contracts and expensive work" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    const a = try fixture(&c, "base", 1000);
    var b = try fixture(&c, "candidate", 500);
    const result = try report.compare(&c, a, b, .{});
    const cell = d.get(d.get(result, "workloads"), "sum");
    try t.expectEqual(@as(f64, 50), try d.num(d.get(cell, "juice")));
    try t.expect(d.is(d.get(cell, "direction"), "less-work"));
    try t.expect(d.is(d.get(d.get(result, "runtime_prediction"), "status"), "uncalibrated"));
    try d.put(&c, &b, "sources", try c.value(.{ .file = "changed" }));
    try t.expectError(error.InvalidExperiment, report.compare(&c, a, b, .{ .mode = "backend" }));
    try d.put(&c, &b, "context", try c.value(.{ .cpu = "different", .libraries = d.object() }));
    try t.expectError(error.InvalidExperiment, report.compare(&c, a, b, .{}));
    try t.expectError(error.InvalidExperiment, report.validate(&c, result, try c.value(.{ .version = "juice-comparison-v1", .context_id = "wrong", .change_id = "wrong" }), 0.03));
}
fn processProbe(c: *d.Context) !void {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", c.a);
    const prefix = try c.join(&.{ root, "trial" });
    const shell = try platform.executable(c, "sh", c.env);
    const result = try platform.run(c, .{ .argv = &.{ shell, "-c", "printf ok; printf err >&2; exit 7" }, .cwd = root, .env = c.env, .prefix = prefix, .seconds = 3 });
    try t.expectEqual(@as(f64, 7), try d.num(d.get(result, "exit_code")));
    try t.expectEqualStrings("ok", try c.readBytes(try std.fmt.allocPrint(c.a, "{s}.stdout", .{prefix})));
    try t.expectError(error.InvalidExperiment, platform.run(c, .{ .argv = &.{ shell, "-c", "sleep 5 & wait" }, .cwd = root, .env = c.env, .prefix = prefix, .seconds = 0.03 }));
    try t.expectError(error.FileNotFound, c.read(try c.join(&.{ root, "absent" })));
}
// spec-case: JUICE-NATIVE-1
test "Juice native spawnPinned process output and deadline are independent of collector availability" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    try processProbe(&c);
    try t.expect(c.message.len > 0);
}

fn failedCapture(c: *d.Context) !void {
    const engine = @import("engine.zig");
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", c.a);
    const compiler = try platform.executable(c, "false", c.env);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "input.c", .data = "unused by intentionally failing build" });
    const path = try c.join(&.{ root, "juice.json" });
    try c.write(path, try c.value(.{
        .version = 1,
        .name = "failure",
        .adapter = "native",
        .sources = .{"input.c"},
        .build = .{ .compiler = compiler, .command = .{ "{compiler}", "{binary}" } },
        .workloads = .{.{ .name = "quick", .unit = "record", .units = 1, .expected_stdout = "" }},
    }));
    const m = try manifest.load(c, path);
    const options: engine.Options = .{ .cache = root, .name = "failed", .repeats = 2 };
    const collector: @import("collectors.zig").Collector = .{ .kind = "perf", .cpu = 0, .identity = d.object(), .extra = d.object() };
    try t.expectError(error.InvalidExperiment, engine.capture(c, m, collector, options));
    const record = try c.read(try c.join(&.{ root, "failure", "records", "failed", "record.json" }));
    try t.expect(d.is(d.get(record, "status"), "incomplete"));
    try t.expectError(error.InvalidExperiment, engine.capture(c, m, collector, options));
    try t.expect(std.mem.indexOf(u8, c.message, "immutable") != null);
}
// spec-case: JUICE-NATIVE-1
test "Juice native captureImpl retains failed builds and refuses record overwrite" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    try failedCapture(&c);
    try t.expect(c.message.len > 0);
}

fn hashFiles(c: *d.Context) !void {
    const artifact_name = "artifact";
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", c.a);
    const path = try c.join(&.{ root, artifact_name });
    try temporary.dir.writeFile(t.io, .{ .sub_path = artifact_name, .data = "abc" });
    try t.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", try d.str(try c.fileHash(path)));
    const bytes = try c.a.alloc(u8, 65539);
    @memset(bytes, 'x');
    bytes[bytes.len - 1] = 'z';
    try temporary.dir.writeFile(t.io, .{ .sub_path = artifact_name, .data = bytes });
    try t.expect(d.equal(try c.hashBytes(bytes), try c.fileHash(path)));
    try temporary.dir.writeFile(t.io, .{ .sub_path = artifact_name, .data = "" });
    try t.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", try d.str(try c.fileHash(path)));
}
// spec-case: JUICE-NATIVE-1
test "Juice SHA256 covers empty short and final partial streaming buffers" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    try hashFiles(&c);
    try t.expectEqual(@as(usize, 0), c.message.len);
}

// spec: JUICE-RUNTIME-1
test "Juice runtime counters require the entire unscaled group" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var c = try context(arena.allocator());
    const complete = "100;;instructions:u;12;100.00\n200;;cycles:u;12;100.00\n150;;ref-cycles:u;12;100.00\n";
    const measured = try profiles.runtime(&c, complete, "instructions:u");
    try t.expectEqual(@as(f64, 150), try d.num(d.get(measured, "reference_cycles")));
    try t.expectError(error.InvalidExperiment, profiles.runtime(&c, "100;;instructions:u;12;100\n200;;cycles:u;12;100\n", "instructions:u"));
    try t.expectError(error.InvalidExperiment, profiles.runtime(&c, complete ++ "150;;ref-cycles:u;12;100\n", "instructions:u"));
    try t.expectError(error.InvalidExperiment, profiles.runtime(&c, "100;;instructions:u;12;100\n200;;cycles:u;12;100\n150;;ref-cycles:u;12;99.99\n", "instructions:u"));
    try t.expectError(error.InvalidExperiment, profiles.runtime(&c, "100;;instructions:u;12;100\n200;;cycles:u;12;100\n0;;ref-cycles:u;12;100\n", "instructions:u"));
}
