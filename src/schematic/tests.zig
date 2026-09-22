//! Trusted byte-I/O boundary tests; the independent Python suite validates complete schematics.
const std = @import("std");
const t = std.testing;
const bridge = @import("host.zig");
const application = @import("app.zig");
const declarations =
    \\module io
    \\
    \\
    \\public host def length(host: Host, file: i64) -> i64 effects(host)
    \\
    \\
    \\public host def byte(host: Host, file: i64, position: i64) -> u8 effects(host)
    \\
    \\
    \\public host def put(host: Host, value: u8) -> i64 effects(host)
    \\
    \\
    \\public host def read_block(host: Host, file: i64, position: i64) -> [256]u8 effects(host)
    \\
    \\
    \\public host def write_block(host: Host, payload: [256]u8, count: i64) -> i64 effects(host)
    \\
    \\
    \\public host def read_document(host: Host, file: i64) -> bytes effects(host)
    \\
    \\
    \\public host def write_bytes(host: Host, payload: bytes) -> i64 effects(host)
    \\
    \\
    \\public host def finish(host: Host) -> i64 effects(host)
    \\
    \\
    \\public host def output_limit(host: Host) -> i64 effects(host)
    \\
    \\
    \\public host def issue(host: Host, code: i64, file: i64, position: i64) -> i64 effects(host)
;
const empty: [3][]const u8 = .{ "", "", "" };
const budget = [_][]const u8{@import("host_native").step_budget};
/// Give the host's `zig cc` children the parent's warm global cache. This
/// hand-built environment carries no `HOME`, so without it every guest link
/// would start from an empty Zig cache and rebuild compiler-rt.
fn forwardZigCache(environment: *std.process.Environ.Map, allocator: std.mem.Allocator) !void {
    const variable = "ZIG_GLOBAL_CACHE_DIR";
    if (t.environ.getPosix(variable)) |explicit| {
        if (explicit.len != 0) return environment.put(variable, explicit);
    }
    if (t.environ.getPosix("XDG_CACHE_HOME")) |cache_home| {
        if (cache_home.len != 0) return environment.put(variable, try std.fs.path.join(allocator, &.{ cache_home, "zig" }));
    }
    if (t.environ.getPosix("HOME")) |home| {
        if (home.len != 0) return environment.put(variable, try std.fs.path.join(allocator, &.{ home, ".cache", "zig" }));
    }
}
/// One host-application process standing in for `main`'s supplied resources.
const Harness = struct {
    arena: std.heap.ArenaAllocator,
    environment: std.process.Environ.Map,
    directory: std.testing.TmpDir,
    root: []const u8 = "",
    fn open() !*Harness {
        const self = try t.allocator.create(Harness);
        self.* = .{
            .arena = std.heap.ArenaAllocator.init(t.allocator),
            .environment = .init(t.allocator),
            .directory = t.tmpDir(.{}),
        };
        self.root = try self.directory.dir.realPathFileAlloc(t.io, ".", self.arena.allocator());
        // The host builds its guest with a real frontend, which this test binary
        // is not, and runs it under a byte ceiling like every guest process.
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(t.io, @import("schematic_test_options").compiler_path, self.arena.allocator());
        try self.environment.put("MYLANG_HOST_COMPILER", compiler);
        try self.environment.put("MYLANG_MEMORY_LIMIT", "1073741824");
        try forwardZigCache(&self.environment, self.arena.allocator());
        return self;
    }
    fn close(self: *Harness) void {
        self.directory.cleanup();
        self.environment.deinit();
        self.arena.deinit();
        t.allocator.destroy(self);
    }
    fn process(self: *Harness) std.process.Init {
        return .{
            .minimal = undefined,
            .arena = &self.arena,
            .gpa = t.allocator,
            .io = t.io,
            .environ_map = &self.environment,
            .preopens = undefined,
        };
    }
    /// Place one guest source file in this harness's private project root.
    fn source(self: *Harness, name: []const u8, bytes: []const u8) !void {
        try self.directory.dir.writeFile(t.io, .{ .sub_path = name, .data = bytes });
    }
    /// Build the staged project and render one set of documents through it.
    fn render(self: *Harness, documents: [3][]const u8) ![]const u8 {
        var app: application.App = undefined;
        try app.initDisk(self.process(), self.root);
        defer app.deinit();
        return app.run(&documents, &budget);
    }
    /// Build the staged project and report the located issue one run produced.
    fn reject(self: *Harness, documents: [3][]const u8) !?bridge.Issue {
        var app: application.App = undefined;
        try app.initDisk(self.process(), self.root);
        defer app.deinit();
        _ = app.run(&documents, &budget) catch return app.issue;
        // A successful render must not satisfy a rejection assertion.
        try t.expect(false);
        return null;
    }
};
fn staged(source: []const u8) !*Harness {
    const harness = try Harness.open();
    errdefer harness.close();
    try harness.source("io.my", declarations);
    try harness.source("main.my", source);
    return harness;
}
// spec: SCHEMATIC-1
test "schematic byte callbacks publish only on success and keep the first located issue" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.put(host, io.byte(host, 0, 1))
        \\    _ = io.put(host, 65u8)
        \\    return 0
    );
    defer harness.close();
    try t.expectEqualStrings("\xb5A", try harness.render(.{ "\xc2\xb5", "", "" }));
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.put(host, 65u8)
        \\    _ = io.issue(host, 15, 0, 9)
        \\    _ = io.issue(host, 20, 0, 10)
        \\    return 1
    );
    try t.expectEqualDeep(bridge.Issue{ .code = 15, .file = 0, .position = 9 }, (try harness.reject(empty)).?);
}
// spec-case: SCHEMATIC-1
test "schematic byte callbacks reject positions and documents the host never supplied" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.put(host, 65u8)
        \\    _ = io.byte(host, 0, 4)
        \\    return 0
    );
    defer harness.close();
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(empty));
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.length(host, 7)
        \\    return 0
    );
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(empty));
    // A nonzero result with no reported issue is bounded-storage exhaustion.
    // The entry claims no capability, because a body that calls nothing cannot
    // have the host effect its parameter would promise.
    try harness.source("main.my",
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 3
    );
    try t.expectEqual(@as(i64, 24), (try harness.reject(empty)).?.code);
}
// spec: SCHEMATIC-BULK-1
test "schematic packed blocks zero fill input tails and flush exact output counts" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    block = io.read_block(host, 0, 1)
        \\    if block[0] != 66u8 or block[1] != 0u8 or block[255] != 0u8:
        \\        return 9
        \\    _ = io.write_block(host, block, 2)
        \\    return io.finish(host)
    );
    defer harness.close();
    try t.expectEqualSlices(u8, "B\x00", try harness.render(.{ "AB", "", "" }));
}
// spec-case: SCHEMATIC-BULK-1
test "schematic packed callbacks reject invalid ranges and preserve output-limit traps" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    block = io.read_block(host, 0, 0)
        \\    _ = io.write_block(host, block, 257)
        \\    return io.finish(host)
    );
    defer harness.close();
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(.{ "A", "", "" }));
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.read_block(host, 0, 2)
        \\    return 0
    );
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(.{ "A", "", "" }));
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    return io.output_limit(host)
    );
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(empty));
}
// spec: SCHEMATIC-BULK-2
test "schematic payload calls carry a whole document in and a whole rendering out" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    document = io.read_document(host, 0)
        \\    if len(document) != 3 or document != b"ABC":
        \\        return 9
        \\    if len(io.read_document(host, 1)) != 0:
        \\        return 8
        \\    status = io.write_bytes(host, document[1:3])
        \\    if status != 0:
        \\        return 7
        \\    return io.finish(host)
    );
    defer harness.close();
    try t.expectEqualStrings("BC", try harness.render(.{ "ABC", "", "" }));
}
// spec-case: SCHEMATIC-BULK-2
test "schematic payload calls refuse unknown documents and outlive no guest storage" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.read_document(host, 7)
        \\    return 0
    );
    defer harness.close();
    try t.expectEqual(@as(?bridge.Issue, null), try harness.reject(.{ "A", "", "" }));
    // The provider's own octets are copied out, so a second read of the same
    // document is an independent byte string with the same content.
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    first = io.read_document(host, 0)
        \\    second = io.read_document(host, 0)
        \\    if first != second:
        \\        return 5
        \\    _ = io.write_bytes(host, first)
        \\    _ = io.write_bytes(host, second)
        \\    return io.finish(host)
    );
    try t.expectEqualStrings("AA", try harness.render(.{ "A", "", "" }));
}
test "schematic documents reject malformed UTF8 and XML controls with exact byte positions" {
    try t.expect(bridge.validateDocuments(&.{"ok \xc2\xb5\n\t\r"}) == null);
    for ([_][]const u8{ "\xff", "\xc0\x80", "\xed\xa0\x80", "\x00", "\xef\xbf\xbe", "\xf4\x90\x80\x80" }) |invalid| {
        const issue = bridge.validateDocuments(&.{ "valid", invalid }).?;
        try t.expectEqualDeep(bridge.Issue{ .code = 8, .file = 1, .position = 0 }, issue);
    }
    const big = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(big);
    try t.expectEqual(@as(i64, 7), bridge.validateDocuments(&.{big}).?.code);
}
// spec-case: SCHEMATIC-1
test "invalid documents are rejected before the guest executable is given any bytes" {
    const harness = try staged(
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> i64:
        \\    _ = io.put(host, 65u8)
        \\    return 0
    );
    defer harness.close();
    try t.expectEqualDeep(bridge.Issue{ .code = 8, .file = 0, .position = 0 }, (try harness.reject(.{ "\xff", "", "" })).?);
    try t.expectEqualStrings("A", try harness.render(empty));
}
// spec-case: SCHEMATIC-1
test "the reported issue transport carries exactly three located numbers" {
    try t.expectEqualDeep(bridge.Issue{ .code = 15, .file = 1, .position = 9 }, bridge.decode("15 1 9\n").?);
    try t.expectEqual(@as(?bridge.Issue, null), bridge.decode(""));
    try t.expectEqual(@as(?bridge.Issue, null), bridge.decode("15 1\n"));
    try t.expectEqual(@as(?bridge.Issue, null), bridge.decode("not a number\n"));
}
// spec-case: SCHEMATIC-1
test "only the operations a guest declares are registered with its native provider" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const manifest =
        \\{"host":{"declarations":[{"name":"io::put"},{"name":"io::circuit_input"},{"name":"other::thing"}]}}
    ;
    try t.expectEqualStrings("io::circuit_input,io::put", try bridge.declared(arena.allocator(), manifest));
    try t.expectError(error.InvalidNativeManifest, bridge.declared(arena.allocator(), "{}"));
    try t.expectEqualStrings("", try bridge.declared(arena.allocator(), "{\"host\":{\"declarations\":[]}}"));
}

// spec: DISK-PROJECT-1
test "disk initDisk rejects failed compilations and reloads bounded sources" {
    const harness = try Harness.open();
    defer harness.close();
    var app: application.App = undefined;
    try t.expectError(error.SourceError, app.initDisk(harness.process(), harness.root));
    try harness.source("main.my", "module main\n\n\ndef main(host: Host) -> i64:\n    return True\n");
    try t.expectError(error.SourceError, app.initDisk(harness.process(), harness.root));
    try harness.source("io.my", "module io; broken");
    try t.expectError(error.SourceError, app.initDisk(harness.process(), harness.root));
    try harness.source("io.my", declarations);
    try harness.source("main.my", "module main\nimport io\n\n\ndef main(host: Host) -> i64:\n    _ = io.put(host, 65u8)\n    return 0\n");
    try t.expectEqualStrings("A", try harness.render(empty));
}

/// The full circuit plus its footprint and interface documents.
fn fixture(a: std.mem.Allocator) ![3][]const u8 {
    const names = [_][]const u8{ "straps-synth-lmx2595.sexp", "lmx2595rhar.sexp", "spi.sexp" };
    var documents: [3][]const u8 = undefined;
    for (names, &documents) |name, *document| {
        const path = try std.fmt.allocPrint(a, "experiments/schematic/fixtures/{s}", .{name});
        document.* = try std.Io.Dir.cwd().readFileAlloc(t.io, path, a, .limited(1024 * 1024));
    }
    return documents;
}

// Native collection is far cheaper than the interpreter's was, so the whole
// circuit renders byte for byte both normally and under collection at every
// allocation safepoint in seconds. The independent Python oracle checks this
// same fixture's electrical geometry.
// spec: SCHEMATIC-MODEL-1
test "schematic renders the whole fixture identically, normally and under collection stress" {
    const harness = try Harness.open();
    defer harness.close();
    const a = harness.arena.allocator();
    const documents = try fixture(a);
    var app: application.App = undefined;
    try app.initDisk(harness.process(), "src/schematic/guest");
    defer app.deinit();
    const expected = try std.Io.Dir.cwd().readFileAlloc(t.io, "experiments/schematic/straps-synth-lmx2595.svg", a, .limited(1024 * 1024));
    try t.expectEqualStrings(expected, try app.run(&documents, &budget));
    try t.expectEqualStrings(expected, try app.run(&documents, &.{ budget[0], "--gc-stress" }));
}

test {
    _ = @import("dev_session.zig");
}

const named_main =
    \\module main
    \\import io
    \\
    \\
    \\def main(host: Host) -> Result[None, int]:
    \\    inputs = io.inputs(host)?
    \\    _ = io.put(host, io.byte(host, io.id(inputs.circuit), 0))
    \\    _ = io.put(host, io.byte(host, io.id(inputs.pinout), 0))
    \\    _ = io.put(host, io.byte(host, io.id(inputs.interface), 0))
    \\    return Ok(None)
;
// spec: SCHEMATIC-INPUTS-1
test "named schematic input handles select their host documents" {
    const harness = try Harness.open();
    defer harness.close();
    try harness.source("io.my", @embedFile("guest/io.my"));
    try harness.source("main.my", named_main);
    try t.expectEqualStrings("CPI", try harness.render(.{ "Circuit", "Pinout", "Interface" }));
}

// spec: SCHEMATIC-INPUTS-2
test "named schematic input providers reject documents the host never supplied" {
    const harness = try Harness.open();
    defer harness.close();
    try harness.source("io.my", @embedFile("guest/io.my"));
    try harness.source("main.my",
        \\module main
        \\import io
        \\
        \\
        \\def main(host: Host) -> Result[None, int]:
        \\    inputs = io.inputs(host)?
        \\    _ = io.byte(host, io.id(inputs.interface), 0)
        \\    return Ok(None)
    );
    var app: application.App = undefined;
    try app.initDisk(harness.process(), harness.root);
    defer app.deinit();
    try t.expectError(error.GuestTrap, app.run(&.{ "Circuit", "Pinout", "" }, &budget));
    // A document the host cannot hand to the guest is refused before it starts.
    try t.expectError(error.InvalidSchematic, app.run(&.{ "Circuit", "Pinout", "\xff" }, &budget));
    try t.expectEqual(@as(i64, 8), app.issue.?.code);
}

const decimal_main =
    \\module main
    \\import io
    \\import text
    \\def main(host: Host) -> int:
    \\    out = io.output()
    \\    text.decimal(mut out, -12)
    \\    io.appendByte(mut out, 44u8)
    \\    text.decimal(mut out, -9223372036854775808)
    \\    io.appendByte(mut out, 44u8)
    \\    text.decimal(mut out, 0)
    \\    return io.flush(host, out)
;

// spec-case: SCHEMATIC-BULK-1
test "schematic bulk buffer boundaries hold normally and under collection stress" {
    const harness = try Harness.open();
    defer harness.close();
    try harness.source("io.my", @embedFile("guest/io.my"));
    try harness.source("bulk_io_test.my", @embedFile("guest/bulk_io_test.my"));
    try harness.source("main.my",
        \\module main
        \\import bulk_io_test
        \\
        \\
        \\def main() -> int:
        \\    if not bulk_io_test.test_minimum_integer_decimal():
        \\        return 1
        \\    if not bulk_io_test.test_negative_decimal_width_boundaries():
        \\        return 2
        \\    if not bulk_io_test.test_output_limit_fails_without_oversized_buffer():
        \\        return 3
        \\    if not bulk_io_test.test_decimal_uses_exact_remaining_capacity():
        \\        return 4
        \\    if not bulk_io_test.test_payload_snapshot_matches_the_appended_buffer():
        \\        return 5
        \\    return 0
    );
    var app: application.App = undefined;
    try app.initDisk(harness.process(), harness.root);
    defer app.deinit();
    try t.expectEqualStrings("", try app.run(&empty, &budget));
    try t.expectEqualStrings("", try app.run(&empty, &.{ budget[0], "--gc-stress" }));
}

// spec: SCHEMATIC-PYTHON-1
test "Python schematic decimal output preserves negative numbers and minimum integer" {
    const harness = try Harness.open();
    defer harness.close();
    try harness.source("io.my", @embedFile("guest/io.my"));
    try harness.source("text.my", @embedFile("guest/text.my"));
    try harness.source("main.my", decimal_main);
    var app: application.App = undefined;
    try app.initDisk(harness.process(), harness.root);
    defer app.deinit();
    try t.expectEqualStrings("-12,-9223372036854775808,0", try app.run(&empty, &.{ budget[0], "--gc-stress" }));
}
