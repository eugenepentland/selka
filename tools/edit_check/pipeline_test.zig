//! End-to-end tests of the coverage pipeline on a small instrumented program: the program
//! is built with the coverage variant's flags and runtime, run as several "tests", and the
//! map is built from what the runs wrote. They pin what the plan requires of the map
//! (EC1 step 5): an inlined helper belongs to its caller's tests, a generic function
//! to the tests of every instance, a function no test runs to no test, and a process
//! a test starts to that test, even one started with a cleared environment.
const std = @import("std");
const testing = std.testing;
const options = @import("test_options");
const coverage_map = @import("coverage_map.zig");
const zig_functions = @import("zig_functions.zig");

const fixture_source = @embedFile("fixture_program.txt");

/// The tests the fixture program is run as: each is a mode argument of the program, and
/// the test's name is `test_prefix` and the mode.
const modes = [_][]const u8{ "inline", "u32", "u64", "parent", "scrubbed" };
const test_prefix = "fixture.test.";

/// A built fixture and the map of its runs.
const Study = struct {
    temp: testing.TmpDir,
    root: [:0]u8,
    parsed: std.json.Parsed(std.json.Value),

    fn deinit(study: *Study) void {
        study.parsed.deinit();
        testing.allocator.free(study.root);
        study.temp.cleanup();
    }

    /// The names of the functions test `mode` ran, in the map's order.
    fn functionsOf(study: Study, mode: []const u8) ![]const []const u8 {
        const document = study.parsed.value.object;
        const functions = document.get("functions").?.array.items;
        var found: std.ArrayList([]const u8) = .empty;
        for (document.get("tests").?.array.items) |entry| {
            if (!std.mem.eql(u8, entry.array.items[1].string[test_prefix.len..], mode)) continue;
            for (entry.array.items[2].array.items) |id| try found.append(testing.allocator, functions[@intCast(id.integer)].array.items[1].string);
        }
        return found.toOwnedSlice(testing.allocator);
    }

    /// The names of the tests that ran function `name`.
    fn testsRunning(study: Study, name: []const u8) ![]const []const u8 {
        const document = study.parsed.value.object;
        const functions = document.get("functions").?.array.items;
        var found: std.ArrayList([]const u8) = .empty;
        for (document.get("tests").?.array.items) |entry| {
            for (entry.array.items[2].array.items) |id| {
                if (!std.mem.eql(u8, functions[@intCast(id.integer)].array.items[1].string, name)) continue;
                try found.append(testing.allocator, entry.array.items[1].string[test_prefix.len..]);
                break;
            }
        }
        return found.toOwnedSlice(testing.allocator);
    }
};

fn contains(names: []const []const u8, wanted: []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, name, wanted)) return true;
    return false;
}

fn runZig(arguments: []const []const u8, directory: []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, options.zig_path);
    try argv.appendSlice(testing.allocator, arguments);
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .path = directory } });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != 0) std.debug.print("zig failed:\n{s}\n", .{result.stderr});
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

/// Build the fixture in `optimize` mode with the coverage flags, run it as each of `modes`,
/// and build the map of the runs.
fn buildStudy(optimize: []const u8) !Study {
    var temp = testing.tmpDir(.{});
    errdefer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    errdefer testing.allocator.free(root);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "fixture.zig", .data = fixture_source });
    const repo = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(repo);
    for ([_][]const u8{ "coverage_rt", "coverage_hooks" }) |name| {
        const source = try std.fmt.allocPrint(testing.allocator, "{s}/tools/edit_check/{s}.zig", .{ repo, name });
        defer testing.allocator.free(source);
        const output = try std.fmt.allocPrint(testing.allocator, "-femit-bin={s}/{s}.o", .{ root, name });
        defer testing.allocator.free(output);
        try runZig(&.{ "build-obj", "-O", "ReleaseSafe", "-fno-fuzz", "-lc", source, output }, root);
    }
    const rt = try std.fmt.allocPrint(testing.allocator, "{s}/coverage_rt.o", .{root});
    defer testing.allocator.free(rt);
    const hooks = try std.fmt.allocPrint(testing.allocator, "{s}/coverage_hooks.o", .{root});
    defer testing.allocator.free(hooks);
    try runZig(&.{ "build-exe", "-ffuzz", "-fllvm", "-lc", "-O", optimize, "--build-id=fast", "fixture.zig", rt, hooks, "-femit-bin=fixture" }, root);

    var environment = try std.process.Environ.createMap(testing.environ, testing.allocator);
    defer environment.deinit();
    const cov = try std.fmt.allocPrint(testing.allocator, "{s}/run/cov", .{root});
    defer testing.allocator.free(cov);
    try environment.put("SELKA_COVERAGE_DIR", cov);
    const program = try std.fmt.allocPrint(testing.allocator, "{s}/fixture", .{root});
    defer testing.allocator.free(program);
    for (modes, 0..) |mode, index| {
        const token = try std.fmt.allocPrint(testing.allocator, "units-{d:0>5}", .{index});
        defer testing.allocator.free(token);
        try environment.put("SELKA_COVERAGE_TEST", token);
        const result = try std.process.run(testing.allocator, testing.io, .{ .argv = &.{ program, mode }, .environ_map = &environment });
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try testing.expect(result.term == .exited);
    }
    var named: [modes.len][]const u8 = undefined;
    for (modes, &named) |mode, *slot| slot.* = try std.fmt.allocPrint(testing.allocator, test_prefix ++ "{s}", .{mode});
    defer for (named) |name| testing.allocator.free(name);
    const names = try std.json.Stringify.valueAlloc(testing.allocator, named, .{});
    defer testing.allocator.free(names);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "run/tests-units.json", .data = names });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "run/unrecorded.json", .data = "[]" });
    const run_directory = try std.fmt.allocPrint(testing.allocator, "{s}/run", .{root});
    defer testing.allocator.free(run_directory);
    const map_path = try std.fmt.allocPrint(testing.allocator, "{s}/map.json", .{root});
    defer testing.allocator.free(map_path);
    _ = try coverage_map.build(testing.allocator, testing.io, .{ .repo = root, .commit = "fixture", .runs = &.{run_directory}, .out = map_path });
    const text = try temp.dir.readFileAlloc(testing.io, "map.json", testing.allocator, .limited(16 << 20));
    defer testing.allocator.free(text);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, text, .{});
    return .{ .temp = temp, .root = root, .parsed = parsed };
}

test "an inlined helper belongs to the tests of its caller, in both build modes" {
    for ([_][]const u8{ "Debug", "ReleaseSafe" }) |optimize| {
        var built = try buildStudy(optimize);
        defer built.deinit();
        const owners = try built.testsRunning("helper");
        defer testing.allocator.free(owners);
        try testing.expect(contains(owners, "inline"));
        try testing.expect(!contains(owners, "u32"));
        // Changing the helper's body is a change to exactly the function the map names.
        var before = try zig_functions.parse(testing.allocator, fixture_source);
        defer before.deinit(testing.allocator);
        const edited = try std.mem.replaceOwned(u8, testing.allocator, fixture_source, "x *% 7 +% 1", "x *% 9 +% 1");
        defer testing.allocator.free(edited);
        var after = try zig_functions.parse(testing.allocator, edited);
        defer after.deinit(testing.allocator);
        const comparison = try zig_functions.compare(testing.allocator, before, after);
        defer testing.allocator.free(comparison.items);
        try testing.expectEqual(@as(usize, 1), comparison.items.len);
        try testing.expectEqualStrings("helper", comparison.items[0].name);
        try testing.expect(!comparison.rest_changed);
    }
}

test "a generic function belongs to the tests of every instance" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    const owners = try built.testsRunning("bump");
    defer testing.allocator.free(owners);
    try testing.expect(contains(owners, "u32"));
    try testing.expect(contains(owners, "u64"));
    try testing.expect(!contains(owners, "inline"));
}

test "a function no test runs belongs to no test" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    const owners = try built.testsRunning("untested");
    defer testing.allocator.free(owners);
    try testing.expectEqual(@as(usize, 0), owners.len);
}

test "a process a test starts contributes to that test" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    const owners = try built.testsRunning("childOnly");
    defer testing.allocator.free(owners);
    try testing.expectEqual(@as(usize, 1), owners.len);
    try testing.expectEqualStrings("parent", owners[0]);
    const own = try built.functionsOf("parent");
    defer testing.allocator.free(own);
    try testing.expect(contains(own, "main"));
}

test "a process started with a cleared environment contributes to the test that started it" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    const owners = try built.testsRunning("scrubbedOnly");
    defer testing.allocator.free(owners);
    try testing.expectEqual(@as(usize, 1), owners.len);
    try testing.expectEqualStrings("scrubbed", owners[0]);
    const own = try built.functionsOf("scrubbed");
    defer testing.allocator.free(own);
    try testing.expect(contains(own, "main"));
}

test "a process whose binary is gone is mapped through the same binary in the checkout" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    // The program the runs started is moved away; an identical copy stands in the checkout's instrumented binaries.
    try built.temp.dir.createDirPath(testing.io, "zig-out/coverage/bin");
    try built.temp.dir.copyFile("fixture", built.temp.dir, "zig-out/coverage/bin/fixture", testing.io, .{});
    try built.temp.dir.deleteFile(testing.io, "fixture");
    const run_directory = try std.fmt.allocPrint(testing.allocator, "{s}/run", .{built.root});
    defer testing.allocator.free(run_directory);
    const map_path = try std.fmt.allocPrint(testing.allocator, "{s}/moved-map.json", .{built.root});
    defer testing.allocator.free(map_path);
    _ = try coverage_map.build(testing.allocator, testing.io, .{ .repo = built.root, .commit = "fixture", .runs = &.{run_directory}, .out = map_path });
    const text = try built.temp.dir.readFileAlloc(testing.io, "moved-map.json", testing.allocator, .limited(16 << 20));
    defer testing.allocator.free(text);
    built.parsed.deinit();
    built.parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, text, .{});
    const owners = try built.testsRunning("scrubbedOnly");
    defer testing.allocator.free(owners);
    try testing.expectEqual(@as(usize, 1), owners.len);
    try testing.expectEqualStrings("scrubbed", owners[0]);
}

test "a map needs a traced run: untraced runs alone are refused, and a traced one may be joined by an untraced one" {
    var built = try buildStudy("Debug");
    defer built.deinit();
    const run_directory = try std.fmt.allocPrint(testing.allocator, "{s}/run", .{built.root});
    defer testing.allocator.free(run_directory);
    const map_path = try std.fmt.allocPrint(testing.allocator, "{s}/untraced-map.json", .{built.root});
    defer testing.allocator.free(map_path);
    try built.temp.dir.writeFile(testing.io, .{ .sub_path = "run/unrecorded.json", .data = "{\"traced\":false}" });
    try testing.expectError(error.NoTracedRun, coverage_map.build(testing.allocator, testing.io, .{ .repo = built.root, .commit = "fixture", .runs = &.{run_directory}, .out = map_path }));
    // A second, traced run joins the untraced one: the map is written, and its unrecorded list is the traced run's.
    try built.temp.dir.createDirPath(testing.io, "traced/cov");
    try built.temp.dir.writeFile(testing.io, .{ .sub_path = "traced/unrecorded.json", .data = "[\"units-00002\"]" });
    const traced_directory = try std.fmt.allocPrint(testing.allocator, "{s}/traced", .{built.root});
    defer testing.allocator.free(traced_directory);
    _ = try coverage_map.build(testing.allocator, testing.io, .{ .repo = built.root, .commit = "fixture", .runs = &.{ run_directory, traced_directory }, .out = map_path });
}
