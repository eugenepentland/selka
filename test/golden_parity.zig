//! Zig-native golden parity harness for the retired `tests/qbe_*.py` drivers.
//!
//! The bytecode interpreter that produced the reference side is gone, and the
//! `tests/goldens/qbe_*.json` documents now hold the outcomes the old core
//! recorded (`golden-outcomes-v1`).  This root discovers every checked-in
//! `qbe_*.json` document, replays each reproducible case through the compiler
//! selected by `test_options.compiler_path` — `mylang`, on the new core since
//! S5 — and compares the native result with the recorded outcomes. Source
//! payloads migrate with the frontend; entry keys, outcome bytes and skip rules
//! remain unchanged apart from approved named-variant rendering. It shells out
//! only to that compiler (which in turn runs the `zig`
//! named by `test_options`); no Python is involved.
//!
//! How each entry maps
//! -------------------
//! * `case[0]` containing a newline is source text.  The harness writes it to a
//!   run-local scratch `case.my` once for each exact source payload, prepares
//!   a fresh working directory holding the `qbe_files`
//!   fixtures (`greeting.txt`, `lines.txt`), and spawns
//!   `run case.my --print-result --zig=… --cache-dir=…`, appending every
//!   string option flattened out of `case[1:]`.  (`qbe_files` records the
//!   `--gc-stress` variant as `case[2]`, so all trailing arrays are merged.)
//!   `--gc-stress` selected the retired collector's stress mode (S5-D4), which
//!   never changed a program's output, so it is dropped and the case still checks
//!   the recorded outcome.
//!   The cache directory lives outside the working directory, otherwise
//!   `listdir(fs, ".")` would count it like the retired driver never did.
//! * `case[0]` naming a repository fixture is looked up in `fixture_sources`
//!   and replayed the same way.  That covers the file-backed entries of
//!   `qbe_native_cases`.
//! * Success compares exit status and standard output byte for byte.  Failure
//!   compares exit status and the first `R_*` code on each side, so absolute
//!   paths and diagnostic prose may drift without turning the harness red.
//!
//! Retired by S5 (counted, never silently green): the five source cases that
//! record shared-alias outcomes under `--legacy-sharing` (S5-D4) and the three
//! that record `R_ARENA_ESCAPE` (managed arenas, S5-D3) assert retired features;
//! one case (`per_dispatch_cases`) asserts the old core's per-dispatch step count,
//! an old internal (the new core counts blocks).
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
    /// Cases that assert a feature S5 retired, or an old core's internals.
    retired_skipped: usize = 0,
    mismatches: usize = 0,

    /// Every entry the harness classified, checked or skipped.
    fn total(self: Report) usize {
        return self.checked + self.docs_skipped + self.fixture_skipped + self.data_skipped + self.retired_skipped;
    }
};

/// The recorded and observed process signature: exit status plus either stdout
/// (a clean run) or the first runtime `R_*` code (a trap or host failure). The
/// status no longer marks a failure — a program that returns N now exits N — so
/// `failed`, read from the diagnostics on stderr, distinguishes the two.
const Signature = struct {
    returncode: u8,
    stdout: []const u8,
    code: []const u8,
    failed: bool,
};

/// Whether a recorded or observed stderr reports a trap or host failure, as
/// opposed to a clean run (empty, or carrying only an advisory warning). A run
/// now exits with its entry result, so stderr, not the status, marks a failure.
fn failedRun(stderr: []const u8) bool {
    return std.mem.indexOf(u8, stderr, "error[") != null or
        std.mem.indexOf(u8, stderr, "host failure:") != null or
        std.mem.indexOf(u8, stderr, "QBE runtime failure") != null or
        std.mem.startsWith(u8, stderr, "mylang:") or
        std.mem.startsWith(u8, stderr, "usage:");
}

/// Absolute tool paths resolved once per run, because every case spawns the
/// compiler from inside its own scratch working directory.
const Tools = struct {
    compiler: [:0]u8,
    zig: [:0]u8,
};

/// Repository-relative locations the run needs twice or more.
const Paths = struct {
    repo_root: []const u8,
    cache_path: []const u8,
    sources: *PreparedSources,
};

/// Source payloads prepared once within this run; mutable working trees remain
/// per case. Keys own exact source bytes, and values own their scratch paths.
const PreparedSources = struct {
    paths: std.StringHashMap([:0]u8),
    bytes_written: usize = 0,

    /// Release retained source bytes and paths before removing the scratch tree.
    fn deinit(self: *PreparedSources) void {
        var iterator = self.paths.iterator();
        while (iterator.next()) |entry| {
            self.paths.allocator.free(entry.key_ptr.*);
            self.paths.allocator.free(entry.value_ptr.*);
        }
        self.paths.deinit();
    }
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

    var sources = PreparedSources{ .paths = std.StringHashMap([:0]u8).init(testing.allocator) };
    defer sources.deinit();

    var context = Context{
        .allocator = testing.allocator,
        .temp = &temp,
        .paths = .{ .repo_root = repo_root, .cache_path = cache_path, .sources = &sources },
        .tools = tools,
        .report = &report,
        .failures = &failures,
        .counter = 0,
    };

    try checkAllGoldens(&context);
    std.debug.print("golden preparation: executions {d}, source writes {d}, source bytes {d}, fresh work directories {d}\n", .{ context.counter, sources.paths.count(), sources.bytes_written, context.counter });
    reportSummary(report);
    reportFailures(&failures);

    // Minimum coverage mirrors the checked-in goldens: every source-bearing
    // entry plus every file-backed `qbe_native_cases` fixture.  If a future
    // re-record shrinks a corpus, this fails instead of quietly passing.
    try testing.expect(report.source_checked >= 167);
    try testing.expect(report.fixture_checked >= 55);
    try testing.expect(report.retired_skipped >= 9);
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

/// The one recorded case that asserts the old core's per-dispatch step count: the
/// `arithmetic` fixture (`return 1 + 2 * 3`, one block) under `--max-steps=1`, which
/// the old core trapped after one instruction; the new core counts blocks.
const per_dispatch_cases = [_][]const u8{"4031fd54adafc91765248f0ee1abc6ce"};

/// Whether a recorded case asserts a feature S5 retired (`--legacy-sharing`, a managed
/// arena's `R_ARENA_ESCAPE`) or the old core's per-dispatch step count.
fn retired(key: []const u8, options: []const []const u8, entry: std.json.Value) !bool {
    for (per_dispatch_cases) |known| if (std.mem.eql(u8, key, known)) return true;
    for (options) |option| if (std.mem.eql(u8, option, "--legacy-sharing")) return true;
    const object = asObject(entry) orelse return false;
    const encoded = asString(object.get("stderr") orelse return false) orelse return false;
    var buffer: [4096]u8 = undefined;
    const size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return false;
    if (size > buffer.len) return false;
    std.base64.standard.Decoder.decode(buffer[0..size], encoded) catch return false;
    return std.mem.indexOf(u8, buffer[0..size], "R_ARENA_ESCAPE") != null;
}

/// The recorded options without `--gc-stress`, the retired collector's stress mode.
fn replayed(allocator: std.mem.Allocator, options: []const []const u8) !std.ArrayList([]const u8) {
    var kept: std.ArrayList([]const u8) = .empty;
    errdefer kept.deinit(allocator);
    for (options) |option| if (!std.mem.eql(u8, option, "--gc-stress")) try kept.append(allocator, option);
    return kept;
}

/// Run one recorded source-text case and compare its native signature.
fn checkSourceCase(context: *Context, corpus: []const u8, key: []const u8, source: []const u8, options: []const []const u8, entry: std.json.Value) !void {
    if (try retired(key, options, entry)) {
        context.report.retired_skipped += 1;
        return;
    }
    context.report.source_checked += 1;
    return runRecordedCase(context, corpus, key, source, options, entry);
}

/// Load one recorded fixture by repository path and compare its native signature.
fn checkFixtureCase(context: *Context, corpus: []const u8, key: []const u8, relative_path: []const u8, options: []const []const u8, entry: std.json.Value) !void {
    if (try retired(key, options, entry)) {
        context.report.retired_skipped += 1;
        return;
    }
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
    const work_path = try prepareWorkDir(context, index);
    defer context.allocator.free(work_path);

    var kept = try replayed(context.allocator, options);
    defer kept.deinit(context.allocator);
    const result = try invoke(context, source_path, kept.items, work_path);
    defer context.allocator.free(result.stdout);
    defer context.allocator.free(result.stderr);

    const expected = Signature{
        .returncode = expected_rc,
        .stdout = expected_stdout,
        .code = firstDiagnosticCode(expected_stderr),
        .failed = failedRun(expected_stderr),
    };
    const actual = Signature{
        .returncode = exitCode(result.term) orelse 0xff,
        .stdout = result.stdout,
        .code = firstDiagnosticCode(result.stderr),
        .failed = failedRun(result.stderr),
    };

    context.report.checked += 1;
    if (!signaturesMatch(expected, actual)) {
        context.report.mismatches += 1;
        try recordMismatch(context, corpus, key, expected, actual);
    }
}

/// Reuse an identical prepared source path; every case still invokes the live
/// compiler with its own options and fresh mutable working directory.
fn writeSource(context: *Context, index: usize, source: []const u8) ![:0]const u8 {
    return prepareSource(context.allocator, context.temp, context.paths.sources, index, source);
}

/// Prepare exact source bytes once per run, without retaining test verdicts or
/// changing the source basename. Returned paths are borrowed from `sources`.
fn prepareSource(allocator: std.mem.Allocator, temp: *testing.TmpDir, sources: *PreparedSources, index: usize, source: []const u8) ![:0]const u8 {
    if (sources.paths.get(source)) |path| return path;
    var name_buffer: [32]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "src-{d}", .{index});
    var dir = try temp.dir.createDirPathOpen(testing.io, name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "case.my", .data = source });
    const path = try dir.realPathFileAlloc(testing.io, "case.my", allocator);
    errdefer allocator.free(path);
    const key = try allocator.dupe(u8, source);
    errdefer allocator.free(key);
    try sources.paths.put(key, path);
    sources.bytes_written += source.len;
    return path;
}

/// Create `work-<index>` holding the `qbe_files` fixtures and return its path.
fn prepareWorkDir(context: *Context, index: usize) ![:0]u8 {
    return freshWorkDir(context.allocator, context.temp, index);
}

/// Materialise a new mutable fixture tree, even when source preparation is reused.
fn freshWorkDir(allocator: std.mem.Allocator, temp: *testing.TmpDir, index: usize) ![:0]u8 {
    var name_buffer: [32]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "work-{d}", .{index});
    var dir = try temp.dir.createDirPathOpen(testing.io, name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "greeting.txt", .data = greeting_text });
    try dir.writeFile(testing.io, .{ .sub_path = "lines.txt", .data = lines_text });
    return dir.realPathFileAlloc(testing.io, ".", allocator);
}

test "golden preparation shares exact source bytes while preserving changed payloads" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var sources = PreparedSources{ .paths = std.StringHashMap([:0]u8).init(testing.allocator) };
    defer sources.deinit();
    const first = try prepareSource(testing.allocator, &temp, &sources, 0, "first");
    const repeated = try prepareSource(testing.allocator, &temp, &sources, 1, "first");
    const changed = try prepareSource(testing.allocator, &temp, &sources, 2, "other");
    const stored = try std.Io.Dir.cwd().readFileAlloc(testing.io, changed, testing.allocator, .limited(100));
    defer testing.allocator.free(stored);
    try testing.expectEqualStrings(first, repeated);
    try testing.expect(!std.mem.eql(u8, first, changed));
    try testing.expectEqualStrings("case.my", std.fs.path.basename(first));
    try testing.expectEqualStrings("other", stored);
    try testing.expectEqual(@as(usize, 2), sources.paths.count());
    try testing.expectEqual(@as(usize, 10), sources.bytes_written);
}

test "golden preparation keeps mutable fixture trees isolated" {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const first = try freshWorkDir(testing.allocator, &temp, 0);
    defer testing.allocator.free(first);
    var first_dir = try std.Io.Dir.cwd().openDir(testing.io, first, .{});
    defer first_dir.close(testing.io);
    try first_dir.writeFile(testing.io, .{ .sub_path = "greeting.txt", .data = "mutated" });
    try first_dir.writeFile(testing.io, .{ .sub_path = "new.txt", .data = "case output" });
    const next = try freshWorkDir(testing.allocator, &temp, 1);
    defer testing.allocator.free(next);
    var next_dir = try std.Io.Dir.cwd().openDir(testing.io, next, .{});
    defer next_dir.close(testing.io);
    const greeting = try next_dir.readFileAlloc(testing.io, "greeting.txt", testing.allocator, .limited(100));
    defer testing.allocator.free(greeting);
    const lines = try next_dir.readFileAlloc(testing.io, "lines.txt", testing.allocator, .limited(100));
    defer testing.allocator.free(lines);
    try testing.expect(!std.mem.eql(u8, first, next));
    try testing.expectEqualStrings(greeting_text, greeting);
    try testing.expectEqualStrings(lines_text, lines);
    try testing.expectError(error.FileNotFound, next_dir.access(testing.io, "new.txt", .{}));
}

/// Spawn the compiler under test for one case and capture its process result.
fn invoke(context: *Context, source_path: []const u8, options: []const []const u8, cwd: []const u8) !std.process.RunResult {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(context.allocator);
    try args.append(context.allocator, context.tools.compiler);
    try args.append(context.allocator, "run");
    try args.append(context.allocator, source_path);
    try args.append(context.allocator, "--print-result");

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

/// Compare two signatures: stdout on a clean run, first `R_*` code on a trap or
/// host failure (whose partial stdout is not stable). A run now exits with its
/// entry's `int` result, so the status no longer marks a failure; the diagnostics
/// on stderr do. The recorded status is always part of the signature, so a
/// program that returns N is expected to exit N (truncated to a byte).
fn signaturesMatch(expected: Signature, actual: Signature) bool {
    if (expected.returncode != actual.returncode) return false;
    if (expected.failed or actual.failed) return std.mem.eql(u8, expected.code, actual.code);
    return std.mem.eql(u8, expected.stdout, actual.stdout);
}

/// The first runtime code in a diagnostic or JSON code field, ignoring paths.
fn firstDiagnosticCode(text: []const u8) []const u8 {
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, text, search_from, "R_")) |start| {
        search_from = start + 2;
        const diagnostic_code = start > 0 and text[start - 1] == '[';
        const json_code = std.mem.endsWith(u8, text[0..start], "\"code\":\"") or
            std.mem.endsWith(u8, text[0..start], "\"code\": \"");
        if (!diagnostic_code and !json_code) continue;
        var end = start + 2;
        while (end < text.len and (std.ascii.isUpper(text[end]) or std.ascii.isDigit(text[end]) or text[end] == '_')) : (end += 1) {}
        const closing: u8 = if (diagnostic_code) ']' else '"';
        if (end > start + 2 and end < text.len and text[end] == closing) return text[start..end];
    }
    return "";
}

test "runtime code extraction ignores scratch directory names containing R underscore" {
    try testing.expectEqualStrings("R_FILE", firstDiagnosticCode("/tmp/R_PJ_random/case.my:2:4: error[R_FILE]: open failed"));
    try testing.expectEqualStrings("", firstDiagnosticCode("/tmp/R_PJ_random/case.my:2:4: error[E_TYPE]: invalid type"));
    try testing.expectEqualStrings("R_UTF8", firstDiagnosticCode("{\"code\":\"R_UTF8\",\"path\":\"/tmp/R_PJ_random/case.my\"}"));
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
    const zig = try cwd.realPathFileAlloc(testing.io, zig_path, allocator);
    return .{ .compiler = compiler, .zig = zig };
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
        "golden parity: checked {d} (source {d}, fixtures {d}), skipped {d} (docs {d}, unmatched fixtures {d}, data-only {d}, retired or old internals {d}), mismatches {d}\n",
        .{
            report.checked,
            report.source_checked,
            report.fixture_checked,
            report.docs_skipped + report.fixture_skipped + report.data_skipped + report.retired_skipped,
            report.docs_skipped,
            report.fixture_skipped,
            report.data_skipped,
            report.retired_skipped,
            report.mismatches,
        },
    );
}
