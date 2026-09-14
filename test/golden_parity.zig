//! Zig-native golden parity harness for the retired `tests/qbe_*.py` drivers.
//!
//! The bytecode interpreter that produced the reference side is gone, and the
//! `tests/goldens/qbe_*.json` documents now hold the recorded outcomes
//! (`golden-outcomes-v1`).  This root discovers every checked-in `qbe_*.json`
//! document, replays each reproducible case through the compiler selected by
//! `test_options.compiler_path`, and compares the native result with the
//! recording.  It shells out only to that compiler (which in turn runs the
//! bundled `qbe` and `zig` named by `test_options`); no Python is involved.
//!
//! How each entry maps
//! -------------------
//! * `case[0]` containing a newline is source text.  The harness writes it to a
//!   scratch `case.my`, prepares a working directory holding the `qbe_files`
//!   fixtures (`greeting.txt`, `lines.txt`), and spawns
//!   `run case.my --print-result --qbe=… --zig=… --cache-dir=…`, appending every
//!   string option flattened out of `case[1:]`.  (`qbe_files` records the
//!   `--gc-stress` variant as `case[2]`, so all trailing arrays are merged.)
//!   The cache directory lives outside the working directory, otherwise
//!   `listdir(fs, ".")` would count it like the retired driver never did.
//! * `case[0]` naming a repository fixture is looked up in `fixture_sources`
//!   and replayed the same way.  That covers the file-backed entries of
//!   `qbe_native_cases`.
//! * Success compares exit status and standard output byte for byte.  Failure
//!   compares exit status and the first `R_*` code on each side, so absolute
//!   paths and diagnostic prose may drift without turning the harness red.
//!
//! What is intentionally skipped (counted, never silently green)
//! -------------------------------------------------------------
//! * `qbe_docs` entries are `docs/file.md:line` labels (plus two bundled
//!   example paths), not source text; the runnable-docs driver is out of scope.
//! * `qbe_native_cases` entries whose names miss `fixture_sources`: the old
//!   driver held those sources inline and never recorded them in the golden, so
//!   there is no text to replay.
//! * `qbe_resource_parity` records a structured event trace (`data`) rather
//!   than a process outcome.
//!
//! The repository root is found by walking up from the process working
//! directory to the first ancestor that owns `tests/goldens`, so both `zig
//! build` and a manual `zig test` from anywhere inside the tree work.  Every
//! skip increments an explicit counter; the test fails if the source or mapped
//! fixture coverage shrinks below what the checked-in goldens carry.

const std = @import("std");
const testing = std.testing;
const test_options = @import("test_options");

/// The compiler built by this repository.
const compiler_path = test_options.compiler_path;
/// The vendored QBE executable this build produced.
const qbe_path = test_options.qbe_path;
/// The pinned Zig executable this build used.
const zig_path = test_options.zig_path;

/// `qbe_files` materialises this exact tree for every case it replays.
const greeting_text = "hello from a granted directory\n";
/// The second fixture file the `qbe_files` corpus reads.
const lines_text = "one\ntwo\nthree\n";
/// The only golden document version this harness understands.
const expected_version = "golden-outcomes-v1";

/// One repository fixture that `qbe_native_cases` names by key.  The names come
/// from `tests/native_cases.py`; the path is read fresh so the harness follows
/// the checked-in sources rather than a stale copy.
const FixtureSource = struct {
    name: []const u8,
    relative_path: []const u8,
};

/// File-backed fixtures `qbe_native_cases` can be reconstructed from.
const fixture_sources = [_]FixtureSource{
    .{ .name = "arithmetic", .relative_path = "test/fixtures/arithmetic.my" },
    .{ .name = "sum", .relative_path = "test/fixtures/sum.my" },
    .{ .name = "gcd", .relative_path = "test/fixtures/gcd.my" },
    .{ .name = "python-calls", .relative_path = "test/fixtures/python-calls.my" },
    .{ .name = "arrays", .relative_path = "examples/arrays.my" },
    .{ .name = "records", .relative_path = "examples/records.my" },
    .{ .name = "conversions", .relative_path = "examples/conversions.my" },
    .{ .name = "tables", .relative_path = "examples/tables.my" },
    .{ .name = "propagation", .relative_path = "examples/propagation.my" },
    .{ .name = "generics", .relative_path = "examples/generics.my" },
    .{ .name = "generic-records", .relative_path = "examples/generic-records.my" },
    .{ .name = "generic-updates", .relative_path = "examples/generic-updates.my" },
    .{ .name = "generic-variants", .relative_path = "examples/generic-variants.my" },
    .{ .name = "generic-results", .relative_path = "examples/generic-results.my" },
};

/// Tally of what the harness checked and skipped.  `total()` is every golden
/// entry seen, so an accidental classification change cannot hide coverage.
const Report = struct {
    checked: usize = 0,
    source_checked: usize = 0,
    fixture_checked: usize = 0,
    docs_skipped: usize = 0,
    fixture_skipped: usize = 0,
    data_skipped: usize = 0,
    mismatches: usize = 0,

    /// Every entry the harness classified, checked or skipped.
    fn total(self: Report) usize {
        return self.checked + self.docs_skipped + self.fixture_skipped + self.data_skipped;
    }
};

/// The recorded and observed process signature: exit status plus either stdout
/// (success) or the first runtime `R_*` code (failure).
const Signature = struct {
    returncode: u8,
    stdout: []const u8,
    code: []const u8,
};

/// Absolute tool paths resolved once per run, because every case spawns the
/// compiler from inside its own scratch working directory.
const Tools = struct {
    compiler: [:0]u8,
    qbe: [:0]u8,
    zig: [:0]u8,
};

/// Repository-relative locations the run needs twice or more.
const Paths = struct {
    repo_root: []const u8,
    cache_path: []const u8,
};

/// Shared state for one harness run.  `temp` owns every scratch directory and
/// `paths.cache_path` is reused across cases so repeated builds hit the object
/// cache.
const Context = struct {
    allocator: std.mem.Allocator,
    temp: *testing.TmpDir,
    paths: Paths,
    tools: Tools,
    report: *Report,
    failures: *std.ArrayList([]const u8),
    counter: usize,
};

test "checked-in golden corpora replay natively with explicit skip counts" {
    var report = Report{};
    var failures: std.ArrayList([]const u8) = .empty;
    defer freeFailures(testing.allocator, &failures);

    var temp = testing.tmpDir(.{});
    defer temp.cleanup();

    const repo_root = try findRepositoryRoot(testing.allocator);
    defer testing.allocator.free(repo_root);
    const cache_path = try makeCacheDir(testing.allocator, &temp);
    defer testing.allocator.free(cache_path);

    const tools = try resolveTools(testing.allocator);
    defer freeTools(testing.allocator, tools);

    var context = Context{
        .allocator = testing.allocator,
        .temp = &temp,
        .paths = .{ .repo_root = repo_root, .cache_path = cache_path },
        .tools = tools,
        .report = &report,
        .failures = &failures,
        .counter = 0,
    };

    try checkAllGoldens(&context);
    reportSummary(report);
    reportFailures(&failures);

    // Minimum coverage mirrors the checked-in goldens: every source-bearing
    // entry plus every file-backed `qbe_native_cases` fixture.  If a future
    // re-record shrinks a corpus, this fails instead of quietly passing.
    try testing.expect(report.source_checked >= 175);
    try testing.expect(report.fixture_checked >= 56);
    try testing.expect(report.checked == report.source_checked + report.fixture_checked);
    try testing.expect(report.docs_skipped >= 27);
    try testing.expect(report.fixture_skipped >= 345);
    try testing.expect(report.data_skipped >= 1);
    try testing.expect(report.total() >= 604);
    try testing.expectEqual(@as(usize, 0), report.mismatches);
    try testing.expectEqual(@as(usize, 0), failures.items.len);
}

/// Discover every `tests/goldens/qbe_*.json` file and walk it.
fn checkAllGoldens(context: *Context) !void {
    const directory_path = try std.fs.path.join(context.allocator, &.{ context.paths.repo_root, "tests", "goldens" });
    defer context.allocator.free(directory_path);
    var directory = try std.Io.Dir.cwd().openDir(testing.io, directory_path, .{ .iterate = true });
    defer directory.close(testing.io);
    var iterator = directory.iterate();
    while (try iterator.next(testing.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isGoldenName(entry.name)) continue;
        const relative_path = try std.fs.path.join(context.allocator, &.{ "tests", "goldens", entry.name });
        defer context.allocator.free(relative_path);
        const corpus = entry.name[0 .. entry.name.len - ".json".len];
        try checkGolden(context, corpus, relative_path);
    }
}

/// True when `name` is one of the checked-in `qbe_*.json` golden documents.
fn isGoldenName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "qbe_") and std.mem.endsWith(u8, name, ".json");
}

/// Read one `golden-outcomes-v1` document and check or skip each entry.
fn checkGolden(context: *Context, name: []const u8, relative_path: []const u8) !void {
    const json = try loadRepositoryFile(context, relative_path);
    defer context.allocator.free(json);
    var parsed = try std.json.parseFromSlice(std.json.Value, context.allocator, json, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    const root = asObject(parsed.value) orelse return error.InvalidGoldenDocument;
    const version = asString(root.get("version") orelse return error.InvalidGoldenDocument) orelse return error.InvalidGoldenDocument;
    if (!std.mem.eql(u8, version, expected_version)) return error.InvalidGoldenDocument;
    const entries = asObject(root.get("entries") orelse return error.InvalidGoldenDocument) orelse return error.InvalidGoldenDocument;
    var iterator = entries.iterator();
    while (iterator.next()) |pair| try checkEntry(context, name, pair.key_ptr.*, pair.value_ptr.*);
}

/// Classify one golden entry: replay source or a mapped fixture, or count it as
/// an explicit skip.
fn checkEntry(context: *Context, corpus: []const u8, key: []const u8, entry: std.json.Value) !void {
    const object = asObject(entry) orelse {
        context.report.data_skipped += 1;
        return;
    };
    const case_value = object.get("case") orelse {
        context.report.data_skipped += 1;
        return;
    };
    const case_array = asArray(case_value) orelse {
        context.report.data_skipped += 1;
        return;
    };
    if (case_array.items.len == 0) {
        context.report.data_skipped += 1;
        return;
    }
    const label = asString(case_array.items[0]) orelse {
        context.report.data_skipped += 1;
        return;
    };
    if (std.mem.indexOfScalar(u8, label, '\n') != null) {
        var options = try flattenOptions(context.allocator, case_value);
        defer options.deinit(context.allocator);
        return checkSourceCase(context, corpus, key, label, options.items, entry);
    }
    if (fixtureSource(label)) |relative_path| {
        var options = try flattenOptions(context.allocator, case_value);
        defer options.deinit(context.allocator);
        return checkFixtureCase(context, corpus, key, relative_path, options.items, entry);
    }
    if (object.get("returncode") == null) {
        context.report.data_skipped += 1;
    } else if (std.mem.eql(u8, corpus, "qbe_docs") or std.mem.startsWith(u8, label, "docs/")) {
        context.report.docs_skipped += 1;
    } else {
        context.report.fixture_skipped += 1;
    }
}

/// Run one recorded source-text case and compare its native signature.
fn checkSourceCase(context: *Context, corpus: []const u8, key: []const u8, source: []const u8, options: []const []const u8, entry: std.json.Value) !void {
    context.report.source_checked += 1;
    return runRecordedCase(context, corpus, key, source, options, entry);
}

/// Load one recorded fixture by repository path and compare its native signature.
fn checkFixtureCase(context: *Context, corpus: []const u8, key: []const u8, relative_path: []const u8, options: []const []const u8, entry: std.json.Value) !void {
    context.report.fixture_checked += 1;
    const source = try loadRepositoryFile(context, relative_path);
    defer context.allocator.free(source);
    return runRecordedCase(context, corpus, key, source, options, entry);
}

/// Write `source` to a scratch file, prepare the `qbe_files` working tree, run
/// the compiler there, and compare the result with the recording.
fn runRecordedCase(context: *Context, corpus: []const u8, key: []const u8, source: []const u8, options: []const []const u8, entry: std.json.Value) !void {
    const object = asObject(entry) orelse return error.InvalidGoldenEntry;
    const expected_rc = asU8(object.get("returncode") orelse return error.InvalidGoldenEntry) orelse return error.InvalidGoldenEntry;
    const expected_stdout = try decodeBase64Field(context.allocator, object, "stdout");
    defer context.allocator.free(expected_stdout);
    const expected_stderr = try decodeBase64Field(context.allocator, object, "stderr");
    defer context.allocator.free(expected_stderr);

    const index = context.counter;
    context.counter += 1;
    const source_path = try writeSource(context, index, source);
    defer context.allocator.free(source_path);
    const work_path = try prepareWorkDir(context, index);
    defer context.allocator.free(work_path);

    const result = try invoke(context, source_path, options, work_path);
    defer context.allocator.free(result.stdout);
    defer context.allocator.free(result.stderr);

    const expected = Signature{
        .returncode = expected_rc,
        .stdout = expected_stdout,
        .code = firstDiagnosticCode(expected_stderr),
    };
    const actual = Signature{
        .returncode = exitCode(result.term) orelse 0xff,
        .stdout = result.stdout,
        .code = firstDiagnosticCode(result.stderr),
    };

    context.report.checked += 1;
    if (!signaturesMatch(expected, actual)) {
        context.report.mismatches += 1;
        try recordMismatch(context, corpus, key, expected, actual);
    }
}

/// Create `src-<index>/case.my` under the run root and return its absolute path.
fn writeSource(context: *Context, index: usize, source: []const u8) ![:0]u8 {
    var name_buffer: [32]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "src-{d}", .{index});
    var dir = try context.temp.dir.createDirPathOpen(testing.io, name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "case.my", .data = source });
    return dir.realPathFileAlloc(testing.io, "case.my", context.allocator);
}

/// Create `work-<index>` holding the `qbe_files` fixtures and return its path.
fn prepareWorkDir(context: *Context, index: usize) ![:0]u8 {
    var name_buffer: [32]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "work-{d}", .{index});
    var dir = try context.temp.dir.createDirPathOpen(testing.io, name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "greeting.txt", .data = greeting_text });
    try dir.writeFile(testing.io, .{ .sub_path = "lines.txt", .data = lines_text });
    return dir.realPathFileAlloc(testing.io, ".", context.allocator);
}

/// Spawn the compiler under test for one case and capture its process result.
fn invoke(context: *Context, source_path: []const u8, options: []const []const u8, cwd: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(context.allocator);
    try args.append(context.allocator, context.tools.compiler);
    try args.append(context.allocator, "run");
    try args.append(context.allocator, source_path);
    try args.append(context.allocator, "--print-result");

    const qbe_arg = try std.fmt.allocPrint(context.allocator, "--qbe={s}", .{context.tools.qbe});
    defer context.allocator.free(qbe_arg);
    try args.append(context.allocator, qbe_arg);
    const zig_arg = try std.fmt.allocPrint(context.allocator, "--zig={s}", .{context.tools.zig});
    defer context.allocator.free(zig_arg);
    try args.append(context.allocator, zig_arg);
    const cache_arg = try std.fmt.allocPrint(context.allocator, "--cache-dir={s}", .{context.paths.cache_path});
    defer context.allocator.free(cache_arg);
    try args.append(context.allocator, cache_arg);

    try args.appendSlice(context.allocator, options);
    return std.process.run(context.allocator, testing.io, .{
        .argv = args.items,
        .cwd = .{ .path = cwd },
        .reserve_amount = 1 << 16,
    });
}

/// Flatten every trailing string array of a golden `case` into one option list.
fn flattenOptions(allocator: std.mem.Allocator, case_value: std.json.Value) !std.ArrayList([]const u8) {
    var options: std.ArrayList([]const u8) = .empty;
    errdefer options.deinit(allocator);
    const array = asArray(case_value) orelse return options;
    if (array.items.len <= 1) return options;
    for (array.items[1..]) |part| {
        const list = asArray(part) orelse continue;
        for (list.items) |item| {
            const option = asString(item) orelse continue;
            try options.append(allocator, option);
        }
    }
    return options;
}

/// Look up a `qbe_native_cases` fixture name in the repository map.
fn fixtureSource(name: []const u8) ?[]const u8 {
    for (fixture_sources) |fixture| {
        if (std.mem.eql(u8, fixture.name, name)) return fixture.relative_path;
    }
    return null;
}

/// Compare two signatures exactly the way the retired `qbe_parity.signature`
/// did: stdout on success, first `R_*` code on failure.
fn signaturesMatch(expected: Signature, actual: Signature) bool {
    if (expected.returncode != actual.returncode) return false;
    if (expected.returncode == 0) return std.mem.eql(u8, expected.stdout, actual.stdout);
    return std.mem.eql(u8, expected.code, actual.code);
}

/// The first `R_*` diagnostic code in `text`, or an empty slice when absent.
fn firstDiagnosticCode(text: []const u8) []const u8 {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, "R_")) |start| {
        var end = start + 2;
        while (end < text.len and (std.ascii.isUpper(text[end]) or text[end] == '_')) : (end += 1) {}
        if (end > start + 2) return text[start..end];
        search_from = start + 2;
    }
    return "";
}

/// The process exit code, or null when the child died another way.
fn exitCode(term: std.process.Child.Term) ?u8 {
    return switch (term) {
        .exited => |code| code,
        else => null,
    };
}

/// Append a human-readable description of one mismatch to the failure list.
fn recordMismatch(context: *Context, corpus: []const u8, key: []const u8, expected: Signature, actual: Signature) !void {
    const message = try std.fmt.allocPrint(
        context.allocator,
        "golden mismatch {s}/{s}: expected rc={d} code={s} stdout={s}; actual rc={d} code={s} stdout={s}",
        .{ corpus, key, expected.returncode, expected.code, expected.stdout, actual.returncode, actual.code, actual.stdout },
    );
    errdefer context.allocator.free(message);
    try context.failures.append(context.allocator, message);
}

/// Decode one required base64 output field from a golden entry.
fn decodeBase64Field(allocator: std.mem.Allocator, object: std.json.ObjectMap, field: []const u8) ![]u8 {
    const value = object.get(field) orelse return error.InvalidGoldenEntry;
    const encoded = asString(value) orelse return error.InvalidGoldenEntry;
    return decodeBase64(allocator, encoded);
}

/// Decode standard base64, allocating the exact byte length.
fn decodeBase64(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const size = try decoder.calcSizeForSlice(encoded);
    const output = try allocator.alloc(u8, size);
    errdefer allocator.free(output);
    try decoder.decode(output, encoded);
    return output;
}

/// Narrow a JSON string, if the value is one.
fn asString(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |string| string,
        else => null,
    };
}

/// Narrow a JSON object map, if the value is one.
fn asObject(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}

/// Narrow a JSON array, if the value is one.
fn asArray(value: std.json.Value) ?std.json.Array {
    return switch (value) {
        .array => |array| array,
        else => null,
    };
}

/// Narrow a non-negative JSON integer to an exit status, if possible.
fn asU8(value: std.json.Value) ?u8 {
    return switch (value) {
        .integer => |integer| if (integer >= 0 and integer <= 255) @intCast(integer) else null,
        else => null,
    };
}

/// Create the shared object-cache directory and return its absolute path.
fn makeCacheDir(allocator: std.mem.Allocator, temp: *testing.TmpDir) ![:0]u8 {
    var dir = try temp.dir.createDirPathOpen(testing.io, "cache", .{});
    defer dir.close(testing.io);
    return temp.dir.realPathFileAlloc(testing.io, "cache", allocator);
}

/// Resolve the selected tools to absolute paths, since cases run elsewhere.
fn resolveTools(allocator: std.mem.Allocator) !Tools {
    const cwd = std.Io.Dir.cwd();
    const compiler = try cwd.realPathFileAlloc(testing.io, compiler_path, allocator);
    errdefer allocator.free(compiler);
    const qbe = try cwd.realPathFileAlloc(testing.io, qbe_path, allocator);
    errdefer allocator.free(qbe);
    const zig = try cwd.realPathFileAlloc(testing.io, zig_path, allocator);
    return .{ .compiler = compiler, .qbe = qbe, .zig = zig };
}

/// Walk up from the working directory to the first ancestor owning `tests/goldens`.
fn findRepositoryRoot(allocator: std.mem.Allocator) ![:0]u8 {
    var current = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, ".", allocator);
    errdefer allocator.free(current);
    while (true) {
        const probe = try std.fs.path.join(allocator, &.{ current, "tests", "goldens" });
        const found = directoryExists(probe);
        allocator.free(probe);
        if (found) return current;
        const parent = std.fs.path.dirname(current) orelse return error.RepositoryRootNotFound;
        if (std.mem.eql(u8, parent, current)) return error.RepositoryRootNotFound;
        const next = try allocator.dupeSentinel(u8, parent, 0);
        allocator.free(current);
        current = next;
    }
}

/// True when `path` exists and can be opened as a directory.
fn directoryExists(path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(testing.io, path, .{}) catch return false;
    dir.close(testing.io);
    return true;
}

/// Read a repository-relative file into memory.
fn loadRepositoryFile(context: *Context, relative_path: []const u8) ![]u8 {
    const path = try std.fs.path.join(context.allocator, &.{ context.paths.repo_root, relative_path });
    defer context.allocator.free(path);
    return std.Io.Dir.cwd().readFileAlloc(testing.io, path, context.allocator, .unlimited);
}

/// Release the absolute tool paths.
fn freeTools(allocator: std.mem.Allocator, tools: Tools) void {
    allocator.free(tools.compiler);
    allocator.free(tools.qbe);
    allocator.free(tools.zig);
}

/// Release every stored mismatch description.
fn freeFailures(allocator: std.mem.Allocator, failures: *std.ArrayList([]const u8)) void {
    for (failures.items) |message| allocator.free(message);
    failures.deinit(allocator);
}

/// Print every stored mismatch so a red run explains itself.
fn reportFailures(failures: *const std.ArrayList([]const u8)) void {
    for (failures.items) |message| std.debug.print("{s}\n", .{message});
}

/// Print the checked/skipped tally, including the explicit skip reasons.
fn reportSummary(report: Report) void {
    std.debug.print(
        "golden parity: checked {d} (source {d}, fixtures {d}), skipped {d} (docs {d}, unmatched fixtures {d}, data-only {d}), mismatches {d}\n",
        .{
            report.checked,
            report.source_checked,
            report.fixture_checked,
            report.docs_skipped + report.fixture_skipped + report.data_skipped,
            report.docs_skipped,
            report.fixture_skipped,
            report.data_skipped,
            report.mismatches,
        },
    );
}
