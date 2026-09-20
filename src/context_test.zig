//! `mylang context` acceptance: selector resolution, the `agent-context-v1`
//! envelope, section priority, the byte budget and partial answers.
//!
//! Every test drives the command through its public entry points over an
//! in-memory project fixture, so what is asserted is the serialized answer the
//! CLI prints rather than an internal helper: the same `Project.load` provider
//! contract, the same checked compilation, the same `render`.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const source = @import("source.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const receipt = @import("source_receipt.zig");
const context = @import("context.zig");

/// The compiler identity every fixture answer is rendered with. The fields are
/// literals, so a test can assert the envelope republished them unchanged.
const identity: receipt.Identity = .{ .compiler_sha256 = @splat(0), .zig_version = "test", .architecture = "test", .os = "test", .abi = "test", .optimize = "test" };
/// The loaded path of the fixture's `model` module, as the loader spells it.
const model_path = "model.my";
/// The lowercase hex of `identity.compiler_sha256`, which every envelope carries.
const compiler_hex = "0000000000000000000000000000000000000000000000000000000000000000";

fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
    const self: *Files = @ptrCast(@alignCast(raw.?));
    for (self.entries) |file| {
        if (!std.mem.eql(u8, file.path, path)) continue;
        if (file.bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, file.bytes);
    }
    return error.NotFound;
}

const File = struct { path: []const u8, bytes: []const u8 };

/// An in-memory project source set behind the same provider contract `load`
/// gives a disk project, so no fixture touches the filesystem.
const Files = struct {
    entries: []const File,

    fn provider(self: *Files) graph.Provider {
        return .{ .context = self, .read = read };
    }
};

/// The two-module fixture every healthy answer is about: `model::validate` reads
/// a field of a nominal type and calls the private `model::check`, and one
/// discovered test calls `validate` directly.
const main_source =
    \\module main
    \\import model
    \\
    \\
    \\def main() -> int:
    \\    return model.entry_value()
;
const model_source =
    \\module model
    \\
    \\
    \\public class Box:
    \\    value: int
    \\
    \\
    \\public def validate(box: Box) -> int effects():
    \\    return check(box.value)
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    \\
    \\
    \\def check(value: int) -> int:
    \\    return value + 1
    \\
    \\
    \\def test_validate_increments() -> bool:
    \\    return validate(Box(value=1)) == 2
;
const healthy_entries = [_]File{
    .{ .path = "main.my", .bytes = main_source },
    .{ .path = model_path, .bytes = model_source },
};

/// `model::validate` returns `True` where its declaration promises `int`, so the
/// bodies do not check; a test still calls `validate`, so an answer that reused
/// an earlier successful check would publish the edge.
const broken_model_source =
    \\module model
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    return True
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    \\
    \\
    \\def test_validate_ignores_the_declared_type() -> bool:
    \\    return validate(1) == 1
;
const broken_entries = [_]File{
    .{ .path = "main.my", .bytes = main_source },
    .{ .path = model_path, .bytes = broken_model_source },
};

/// `model::validate`'s body is not even an expression, so no declaration merges.
const syntax_broken_model_source =
    \\module model
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    return +
;
const syntax_broken_entries = [_]File{
    .{ .path = "main.my", .bytes = main_source },
    .{ .path = model_path, .bytes = syntax_broken_model_source },
};

/// `model_source` with one added declaration: the bytes a file edit leaves.
const edited_model_source = model_source ++ "\n\ndef extra() -> int:\n    return 2\n";
const edited_entries = [_]File{
    .{ .path = "main.my", .bytes = main_source },
    .{ .path = model_path, .bytes = edited_model_source },
};

/// Two modules declare one unqualified name, so only the qualified spelling can
/// select either of them.
const ambiguous_entries = [_]File{
    .{ .path = "main.my", .bytes =
    \\module main
    \\import alpha
    \\import beta
    \\
    \\
    \\def main() -> int:
    \\    return alpha.first() + beta.second()
    },
    .{ .path = "alpha.my", .bytes =
    \\module alpha
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    return value + 1
    \\
    \\
    \\public def first() -> int:
    \\    return 1
    },
    .{ .path = "beta.my", .bytes =
    \\module beta
    \\
    \\
    \\public def validate(value: int) -> int:
    \\    return value + 2
    \\
    \\
    \\public def second() -> int:
    \\    return 2
    },
};

/// `spare` is imported and never referenced, so `main.my:3:10` is covered by the
/// `W_UNUSED_IMPORT` diagnostic and by no declaration.
const warning_entries = [_]File{
    .{ .path = "main.my", .bytes =
    \\module main
    \\import model
    \\import spare
    \\
    \\
    \\def main() -> int:
    \\    return model.entry_value()
    },
    .{ .path = model_path, .bytes =
    \\module model
    \\
    \\
    \\public def entry_value() -> int:
    \\    return 1
    },
    .{ .path = "spare.my", .bytes =
    \\module spare
    \\
    \\
    \\def helper() -> int:
    \\    return 1
    },
};

/// One loaded fixture project, checked. The scene is heap-allocated because the
/// project, the index and the compilation point at one another and must not move.
const Scene = struct {
    gpa: std.mem.Allocator,
    project: graph.Project,
    index: interfaces.Index,
    compilation: pc.Compilation,

    /// Load and check a fixture that is expected to check.
    fn open(gpa: std.mem.Allocator, files: *Files, entry: []const u8) !*Scene {
        const self = try gpa.create(Scene);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .project = graph.Project.init(gpa), .index = undefined, .compilation = undefined };
        errdefer self.project.deinit();
        try self.project.load(files.provider(), entry, .{});
        self.index = try interfaces.build(&self.project);
        self.compilation = try pc.Compilation.init(&self.index);
        try self.compilation.check();
        return self;
    }

    /// Load a fixture whose bodies do not check: the failed verdict is the
    /// fixture, so the compilation still answers with what it recovered.
    fn openUnchecked(gpa: std.mem.Allocator, files: *Files, entry: []const u8) !*Scene {
        const self = try gpa.create(Scene);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .project = graph.Project.init(gpa), .index = undefined, .compilation = undefined };
        errdefer self.project.deinit();
        try self.project.load(files.provider(), entry, .{});
        self.index = try interfaces.build(&self.project);
        self.compilation = try pc.Compilation.init(&self.index);
        self.compilation.check() catch |err| switch (err) {
            error.SourceError => {},
            else => return err,
        };
        return self;
    }

    fn close(self: *Scene) void {
        self.project.deinit();
        self.gpa.destroy(self);
    }

    /// Render one answer from the fixture's checked compilation.
    fn render(self: *Scene, options: context.Options) !context.Answer {
        return context.render(self.gpa, &self.compilation, identity, options);
    }
};

/// A project whose body syntax failed before any declaration merged: it has no
/// index and no compilation, so the partial entry point is what answers.
const PartialScene = struct {
    gpa: std.mem.Allocator,
    project: graph.Project,

    fn open(gpa: std.mem.Allocator, files: *Files, entry: []const u8) !*PartialScene {
        const self = try gpa.create(PartialScene);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .project = graph.Project.init(gpa) };
        errdefer self.project.deinit();
        try self.project.load(files.provider(), entry, .{});
        return self;
    }

    fn close(self: *PartialScene) void {
        self.project.deinit();
        self.gpa.destroy(self);
    }

    fn render(self: *PartialScene, options: context.Options) !context.Answer {
        return context.renderPartial(self.gpa, &self.project, identity, options);
    }
};

/// The loaded module with one name.
fn moduleNamed(scene: *Scene, name: []const u8) !*graph.Module {
    for (scene.project.modules.items) |*module| {
        if (std.mem.eql(u8, module.name, name)) return module;
    }
    return error.TestUnexpectedResult;
}

/// A symbol answer about one qualified name, in the fixture's entry project.
fn symbolOptions(name: []const u8) context.Options {
    return .{ .entry = "main.my", .selector = .{ .symbol = name } };
}

/// A position answer about one `path:line:column` in the fixture's entry project.
fn atOptions(spec: []const u8) context.Options {
    return .{ .entry = "main.my", .selector = .{ .at = spec } };
}

/// The `model::hub` fixture: a public declaration that calls `dependencies`
/// private helpers, so its complete answer is far wider than a small budget and
/// the envelope has to drop whole dependency records.
fn hubSource(allocator: std.mem.Allocator, dependencies: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const writer = &out.writer;
    writer.writeAll("module model\n\n\npublic def hub(value: int) -> int:\n    total = value\n") catch return error.OutOfMemory;
    for (0..dependencies) |index| writer.print("    total = step_{d:0>2}(total)\n", .{index}) catch return error.OutOfMemory;
    writer.writeAll("    return total\n\n\npublic def entry_value() -> int:\n    return 1\n") catch return error.OutOfMemory;
    for (0..dependencies) |index| writer.print("\n\ndef step_{d:0>2}(value: int) -> int:\n    return value + 1\n", .{index}) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

/// Parse one answer's JSON. The caller owns the parsed value.
fn envelope(answer: context.Answer) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, t.allocator, answer.bytes, .{});
}

fn field(value: std.json.Value, name: []const u8) std.json.Value {
    return switch (value) {
        .object => |object| object.get(name) orelse .null,
        else => .null,
    };
}

/// One field reached through a path of object keys.
fn nested(value: std.json.Value, path: []const []const u8) std.json.Value {
    var current = value;
    for (path) |name| current = field(current, name);
    return current;
}

fn stringAt(value: std.json.Value, name: []const u8) []const u8 {
    return switch (field(value, name)) {
        .string => |text| text,
        else => "",
    };
}

fn nestedString(value: std.json.Value, path: []const []const u8) []const u8 {
    return switch (nested(value, path)) {
        .string => |text| text,
        else => "",
    };
}

fn integerAt(value: std.json.Value, name: []const u8) i64 {
    return switch (field(value, name)) {
        .integer => |number| number,
        else => std.math.minInt(i64),
    };
}

fn nestedInteger(value: std.json.Value, path: []const []const u8) i64 {
    return switch (nested(value, path)) {
        .integer => |number| number,
        else => std.math.minInt(i64),
    };
}

fn arrayAt(value: std.json.Value, name: []const u8) []std.json.Value {
    return switch (field(value, name)) {
        .array => |items| items.items,
        else => &.{},
    };
}

fn nestedArray(value: std.json.Value, path: []const []const u8) []std.json.Value {
    return switch (nested(value, path)) {
        .array => |items| items.items,
        else => &.{},
    };
}

/// The `sections` entry named `name`, or null when the answer omits it.
fn section(root: std.json.Value, name: []const u8) ?std.json.Value {
    for (arrayAt(root, "sections")) |entry| {
        if (std.mem.eql(u8, stringAt(entry, "name"), name)) return entry;
    }
    return null;
}

/// The records of one section, or an empty slice when the section is absent.
fn records(root: std.json.Value, name: []const u8) []std.json.Value {
    const found = section(root, name) orelse return &.{};
    return arrayAt(found, "records");
}

/// The first record of one section, or JSON null when it is empty.
fn record(root: std.json.Value, name: []const u8) std.json.Value {
    const items = records(root, name);
    return if (items.len == 0) .null else items[0];
}

/// The snapshot input row for one module, or null when it is not published.
fn inputFor(root: std.json.Value, module: []const u8) ?std.json.Value {
    for (nestedArray(root, &.{ "snapshot", "inputs" })) |entry| {
        if (std.mem.eql(u8, stringAt(entry, "module"), module)) return entry;
    }
    return null;
}

/// The snapshot republishes the digest of the bytes the module was loaded from.
fn expectInputDigest(root: std.json.Value, module: []const u8, bytes: []const u8) !void {
    const input = inputFor(root, module) orelse return error.TestUnexpectedResult;
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &hash, .{});
    const hex = std.fmt.bytesToHex(hash, .lower);
    try t.expectEqualStrings(&hex, stringAt(input, "sha256"));
    try t.expect(std.mem.endsWith(u8, stringAt(input, "path"), ".my"));
}

/// A lowercase SHA-256 rendering: 64 hexadecimal scalars.
fn expectHexDigest(text: []const u8) !void {
    try t.expectEqual(@as(usize, 64), text.len);
    for (text) |scalar| try t.expect(std.ascii.isHex(scalar) and !std.ascii.isUpper(scalar));
}

/// The fixed priority order the answer publishes its sections in.
const section_order = [_][]const u8{ "declaration", "contract", "types", "dependencies", "tests", "changes" };

fn expectSectionOrder(root: std.json.Value, names: []const []const u8) !void {
    const sections = arrayAt(root, "sections");
    try t.expectEqual(names.len, sections.len);
    for (names, 0..) |name, index| try t.expectEqualStrings(name, stringAt(sections[index], "name"));
}

/// The omission of one section, with the whole-record count it gave up.
fn expectOmission(root: std.json.Value, name: []const u8, dropped: usize) !void {
    for (arrayAt(root, "omissions")) |item| {
        if (!std.mem.eql(u8, stringAt(item, "section"), name)) continue;
        try t.expectEqualStrings("budget", stringAt(item, "reason"));
        try t.expectEqual(dropped, @as(usize, @intCast(integerAt(item, "records_omitted"))));
        return;
    }
    return error.TestUnexpectedResult;
}

/// A continuation query for the same question with more room than `asked`.
fn expectContinuation(root: std.json.Value, asked: usize) !void {
    const query = stringAt(root, "continuation");
    try t.expect(std.mem.startsWith(u8, query, "mylang context "));
    const at = std.mem.indexOf(u8, query, "--context-bytes=") orelse return error.TestUnexpectedResult;
    const larger = try std.fmt.parseInt(usize, std.mem.trim(u8, query[at + "--context-bytes=".len ..], " \t\r\n"), 10);
    try t.expect(larger > asked);
}

/// One dependency record in one direction naming `id`.
fn expectDependency(root: std.json.Value, direction: []const u8, id: []const u8) !void {
    for (records(root, "dependencies")) |item| {
        if (!std.mem.eql(u8, stringAt(item, "direction"), direction)) continue;
        if (!std.mem.eql(u8, stringAt(item, "id"), id)) continue;
        try t.expectEqualStrings("call", stringAt(item, "edge"));
        try t.expectEqualStrings("checked", stringAt(item, "analysis"));
        return;
    }
    return error.TestUnexpectedResult;
}

/// One diagnostic record with `code` in the declaration section.
fn expectDiagnostic(root: std.json.Value, code: []const u8) !void {
    for (records(root, "declaration")) |item| {
        if (!std.mem.eql(u8, stringAt(item, "kind"), "diagnostic")) continue;
        if (!std.mem.eql(u8, stringAt(item, "code"), code)) continue;
        try t.expectEqualStrings("err", stringAt(item, "severity"));
        try t.expectEqualStrings(model_path, nestedString(item, &.{ "location", "path" }));
        try t.expect(nestedInteger(item, &.{ "location", "line" }) > 0);
        return;
    }
    return error.TestUnexpectedResult;
}

/// The tests section labels every caller as static reachability, never coverage.
fn expectTestRecords(root: std.json.Value, direct_name: []const u8) !void {
    const items = records(root, "tests");
    try t.expect(items.len >= 1);
    var direct = false;
    for (items) |item| {
        try t.expectEqualStrings("static-reachability", stringAt(item, "basis"));
        if (std.mem.eql(u8, stringAt(item, "relation"), "direct") and std.mem.eql(u8, stringAt(item, "test"), direct_name)) direct = true;
    }
    try t.expect(direct);
}

/// Exactly one of `--symbol` and `--at` is required: `Options.selector` has no
/// default, and the union it must hold has exactly the two forms, so a request
/// that asks for neither or for both is not representable. The CLI parser turns
/// an absent or duplicated flag into the usage error an operator sees.
fn expectSelectorChoiceIsRequired() !void {
    const options = @typeInfo(context.Options).@"struct";
    var required = false;
    for (options.field_names, options.field_attrs) |name, attrs| {
        if (!std.mem.eql(u8, name, "selector")) continue;
        required = attrs.default_value_ptr == null;
    }
    try t.expect(required);
    const selector = @typeInfo(context.Selector).@"union";
    try t.expectEqual(@as(usize, 2), selector.field_names.len);
    try t.expectEqualStrings("symbol", selector.field_names[0]);
    try t.expectEqualStrings("at", selector.field_names[1]);
}

// spec: CONTEXT-ENVELOPE-1
test "context answers one declaration with a single agent-context-v1 envelope" {
    var files: Files = .{ .entries = &healthy_entries };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    const answer = try scene.render(symbolOptions("model::validate"));
    defer t.allocator.free(answer.bytes);
    try t.expectEqual(context.Status.ok, answer.status);
    const parsed = try envelope(answer);
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqualStrings("agent-context-v1", stringAt(root, "version"));
    try t.expectEqualStrings("ok", stringAt(root, "status"));
    try t.expectEqualStrings("main.my", stringAt(root, "entry"));
    try t.expectEqualStrings("symbol", nestedString(root, &.{ "selector", "kind" }));
    try t.expectEqualStrings("model::validate", nestedString(root, &.{ "selector", "symbol" }));
    try t.expectEqualStrings("model::validate", nestedString(root, &.{ "selector", "resolved" }));
    try t.expectEqual(@as(i64, context.default_context_bytes), integerAt(root, "context_bytes"));
    try t.expectEqualStrings("checked", nestedString(root, &.{ "analysis", "status" }));
    // The compiler's build identity, republished exactly as it was rendered with.
    try t.expectEqualStrings(compiler_hex, nestedString(root, &.{ "snapshot", "compiler", "compiler_sha256" }));
    try t.expectEqualStrings("test", nestedString(root, &.{ "snapshot", "compiler", "zig_version" }));
    try t.expectEqualStrings("test", nestedString(root, &.{ "snapshot", "compiler", "architecture" }));
    // The loaded sources' identities are the digests of the bytes they came from.
    try t.expectEqual(@as(i64, 2), nestedInteger(root, &.{ "snapshot", "modules" }));
    try expectInputDigest(root, "main", main_source);
    try expectInputDigest(root, "model", model_source);
    try expectHexDigest(nestedString(root, &.{"snapshot_sha256"}));
    // The emitted byte count is the serialized response's own length.
    const emitted = std.math.cast(usize, nestedInteger(root, &.{"emitted_bytes"})) orelse return error.TestUnexpectedResult;
    try t.expectEqual(answer.bytes.len, emitted);
    try t.expectEqual(@as(u8, '\n'), answer.bytes[answer.bytes.len - 1]);
    // A complete answer carries every section and reports no omission.
    try t.expectEqual(@as(usize, 5), arrayAt(root, "sections").len);
    try t.expectEqual(@as(usize, 0), arrayAt(root, "omissions").len);
    try t.expect(field(root, "continuation") == .null);
}

// spec: CONTEXT-SELECT-1
test "context selects the qualified name and reports ambiguity and absence" {
    var files: Files = .{ .entries = &healthy_entries };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    const qualified = try scene.render(symbolOptions("model::validate"));
    defer t.allocator.free(qualified.bytes);
    const qualified_parsed = try envelope(qualified);
    defer qualified_parsed.deinit();
    try t.expectEqualStrings("model::validate", nestedString(qualified_parsed.value, &.{ "selector", "resolved" }));
    try t.expectEqualStrings("model::validate", stringAt(record(qualified_parsed.value, "declaration"), "id"));

    const missing = try scene.render(symbolOptions("model::no_such_declaration"));
    defer t.allocator.free(missing.bytes);
    const missing_parsed = try envelope(missing);
    defer missing_parsed.deinit();
    try t.expectEqual(context.Status.missing, missing.status);
    try t.expectEqualStrings("missing", stringAt(missing_parsed.value, "status"));
    try t.expect(field(missing_parsed.value, "candidates") == .null);
    try t.expect(field(nested(missing_parsed.value, &.{"selector"}), "resolved") == .null);
    try t.expectEqual(@as(usize, 0), records(missing_parsed.value, "declaration").len);

    var ambiguous_files: Files = .{ .entries = &ambiguous_entries };
    const ambiguous_scene = try Scene.open(t.allocator, &ambiguous_files, "main");
    defer ambiguous_scene.close();
    const ambiguous = try ambiguous_scene.render(symbolOptions("validate"));
    defer t.allocator.free(ambiguous.bytes);
    const ambiguous_parsed = try envelope(ambiguous);
    defer ambiguous_parsed.deinit();
    try t.expectEqual(context.Status.ambiguous, ambiguous.status);
    try t.expectEqualStrings("ambiguous", stringAt(ambiguous_parsed.value, "status"));
    try t.expectEqual(@as(usize, 2), arrayAt(ambiguous_parsed.value, "candidates").len);
    try expectCandidate(ambiguous_parsed.value, 0, "alpha::validate");
    try expectCandidate(ambiguous_parsed.value, 1, "beta::validate");
    try t.expect(field(nested(ambiguous_parsed.value, &.{"selector"}), "resolved") == .null);
    try t.expect(std.mem.indexOf(u8, stringAt(ambiguous_parsed.value, "reason"), "module-qualified") != null);
    try t.expectEqual(@as(usize, 0), records(ambiguous_parsed.value, "declaration").len);

    // The qualified spelling each candidate needs still selects exactly one.
    const alpha = try ambiguous_scene.render(symbolOptions("alpha::validate"));
    defer t.allocator.free(alpha.bytes);
    const alpha_parsed = try envelope(alpha);
    defer alpha_parsed.deinit();
    try t.expectEqual(context.Status.ok, alpha.status);
    try t.expectEqualStrings("alpha::validate", nestedString(alpha_parsed.value, &.{ "selector", "resolved" }));

    try expectSelectorChoiceIsRequired();
}

/// One `candidates` entry by position.
fn expectCandidate(root: std.json.Value, index: usize, id: []const u8) !void {
    const items = arrayAt(root, "candidates");
    try t.expect(index < items.len);
    try t.expectEqualStrings(id, switch (items[index]) {
        .string => |text| text,
        else => "",
    });
}

// spec: CONTEXT-AT-1
test "context resolves a position to the innermost declaration or its diagnostic" {
    var files: Files = .{ .entries = &healthy_entries };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    // Line 9 column 12 is inside `validate`'s body, which its span covers.
    const body = try scene.render(atOptions("model.my:9:12"));
    defer t.allocator.free(body.bytes);
    const body_parsed = try envelope(body);
    defer body_parsed.deinit();
    try t.expectEqual(context.Status.ok, body.status);
    try t.expectEqualStrings("model::validate", nestedString(body_parsed.value, &.{ "selector", "resolved" }));
    try t.expectEqualStrings("model::validate", stringAt(record(body_parsed.value, "declaration"), "id"));
    try t.expectEqualStrings("model.my:9:12", nestedString(body_parsed.value, &.{ "selector", "at" }));
    try t.expectEqualStrings("at", nestedString(body_parsed.value, &.{ "selector", "kind" }));

    // The parameter declared inside that body is the innermost declaration.
    const parameter = try scene.render(atOptions("model.my:8:22"));
    defer t.allocator.free(parameter.bytes);
    const parameter_parsed = try envelope(parameter);
    defer parameter_parsed.deinit();
    try t.expectEqual(context.Status.ok, parameter.status);
    try t.expect(std.mem.startsWith(u8, nestedString(parameter_parsed.value, &.{ "selector", "resolved" }), "model::validate/local:box@"));
    try t.expectEqualStrings("parameter", stringAt(record(parameter_parsed.value, "declaration"), "declaration_kind"));

    // A field of the nominal type is selected at its own name, not at its owner.
    const field_at = try scene.render(atOptions("model.my:5:5"));
    defer t.allocator.free(field_at.bytes);
    const field_parsed = try envelope(field_at);
    defer field_parsed.deinit();
    try t.expectEqualStrings("model::Box.value", nestedString(field_parsed.value, &.{ "selector", "resolved" }));
    try t.expectEqualStrings("field", stringAt(record(field_parsed.value, "declaration"), "declaration_kind"));

    // Nothing declares the unused import's line, so its diagnostic is selected.
    var warning_files: Files = .{ .entries = &warning_entries };
    const warning_scene = try Scene.open(t.allocator, &warning_files, "main");
    defer warning_scene.close();
    const warning = try warning_scene.render(atOptions("main.my:3:10"));
    defer t.allocator.free(warning.bytes);
    const warning_parsed = try envelope(warning);
    defer warning_parsed.deinit();
    try t.expectEqual(context.Status.ok, warning.status);
    try t.expect(field(nested(warning_parsed.value, &.{"selector"}), "resolved") == .null);
    try t.expectEqualStrings("diagnostic", stringAt(record(warning_parsed.value, "declaration"), "kind"));
    try t.expectEqualStrings("W_UNUSED_IMPORT", stringAt(record(warning_parsed.value, "declaration"), "code"));
    try t.expectEqual(@as(usize, 0), records(warning_parsed.value, "contract").len);

    // A declaration whose body is larger than the published excerpt limit names
    // a truncated snippet, and a position past the cut still resolves to the
    // whole declaration rather than to nothing.
    const wide = try hubSource(t.allocator, 1200);
    defer t.allocator.free(wide);
    var wide_files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main_source }, .{ .path = model_path, .bytes = wide } } };
    const wide_scene = try Scene.open(t.allocator, &wide_files, "main");
    defer wide_scene.close();
    var wide_options = atOptions("model.my:1206:5");
    // The 1200 dependencies carry the answer past the default budget; this test
    // is about the span, so it asks for room for the whole answer.
    wide_options.context_bytes = 1024 * 1024;
    const wide_answer = try wide_scene.render(wide_options);
    defer t.allocator.free(wide_answer.bytes);
    const wide_parsed = try envelope(wide_answer);
    defer wide_parsed.deinit();
    try t.expectEqual(context.Status.ok, wide_answer.status);
    try t.expectEqualStrings("model::hub", nestedString(wide_parsed.value, &.{ "selector", "resolved" }));
    try t.expectEqual(true, field(record(wide_parsed.value, "declaration"), "snippet_truncated").bool);

    // A position the project does not contain, and a malformed coordinate, are
    // reported rather than resolved to a near match.
    const outside = try scene.render(atOptions("ghost.my:1:1"));
    defer t.allocator.free(outside.bytes);
    const outside_parsed = try envelope(outside);
    defer outside_parsed.deinit();
    try t.expectEqual(context.Status.missing, outside.status);
    try t.expectEqualStrings("missing", stringAt(outside_parsed.value, "status"));
    try t.expect(std.mem.indexOf(u8, stringAt(outside_parsed.value, "reason"), "outside every loaded module") != null);

    const malformed = try scene.render(atOptions(model_path));
    defer t.allocator.free(malformed.bytes);
    const malformed_parsed = try envelope(malformed);
    defer malformed_parsed.deinit();
    try t.expectEqual(context.Status.missing, malformed.status);
    try t.expect(std.mem.indexOf(u8, stringAt(malformed_parsed.value, "reason"), "PATH:LINE:COLUMN") != null);
}

/// One `api-diff-baseline-v1` snapshot that records no declaration, so every
/// current declaration is classified additive against it.
const empty_baseline = "# api-diff-baseline-v1\n";

// spec: CONTEXT-SECTIONS-1
test "context publishes its fixed section order with labeled contract and test facts" {
    var files: Files = .{ .entries = &healthy_entries };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    var options = symbolOptions("model::validate");
    options.baseline = .{ .path = "baseline.txt", .bytes = empty_baseline };
    const answer = try scene.render(options);
    defer t.allocator.free(answer.bytes);
    const parsed = try envelope(answer);
    defer parsed.deinit();
    const root = parsed.value;
    try expectSectionOrder(root, &section_order);

    // The contract labels the declared bound and the checked inferred facts.
    const contract = record(root, "contract");
    try t.expectEqualStrings("model::validate", stringAt(contract, "id"));
    try t.expectEqualStrings("validate(box: Box) -> int effects()", stringAt(contract, "signature"));
    try t.expectEqualStrings("i64", stringAt(contract, "return_type"));
    try t.expectEqualStrings("checked", stringAt(contract, "analysis"));
    try t.expect(field(contract, "declared_effects") == .array);
    try t.expectEqual(@as(usize, 0), arrayAt(contract, "declared_effects").len);
    try t.expect(field(contract, "effects") == .array);
    try t.expect(field(contract, "mutates") == .array);
    try t.expect(field(contract, "mutation_writes") == .bool);
    try t.expectEqualStrings("unknown", stringAt(contract, "return_origin"));

    // The types section carries the shape a caller would otherwise open a file for.
    const types = record(root, "types");
    try t.expectEqualStrings("model::Box", stringAt(types, "id"));
    try t.expectEqualStrings("checked", stringAt(types, "analysis"));
    try t.expectEqualStrings("model::Box.value", stringAt(arrayAt(types, "members")[0], "id"));

    // The dependencies section carries the resolved call out of the declaration
    // and the resolved caller into it.
    try expectDependency(root, "outgoing", "model::check");
    try expectDependency(root, "incoming", "model::test_validate_increments");
    try expectTestRecords(root, "model::test_validate_increments");

    // The changes section exists only for a baseline request, and classifies the
    // declaration against it.
    const change = record(root, "changes");
    try t.expectEqualStrings("model::validate", stringAt(change, "declaration"));
    try t.expectEqualStrings("additive", stringAt(change, "class"));
    try t.expectEqualStrings("api-diff", stringAt(change, "basis"));

    // Without a baseline the section is absent from the same fixed order.
    const without = try scene.render(symbolOptions("model::validate"));
    defer t.allocator.free(without.bytes);
    const without_parsed = try envelope(without);
    defer without_parsed.deinit();
    try expectSectionOrder(without_parsed.value, section_order[0 .. section_order.len - 1]);
}

// spec: CONTEXT-BUDGET-1
test "context never exceeds its byte budget and reports every omitted section" {
    const hub = try hubSource(t.allocator, 30);
    defer t.allocator.free(hub);
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main_source }, .{ .path = model_path, .bytes = hub } } };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    var options = symbolOptions("model::hub");
    options.context_bytes = 3000;
    const trimmed = try scene.render(options);
    defer t.allocator.free(trimmed.bytes);
    try t.expect(trimmed.bytes.len <= 3000);
    const parsed = try envelope(trimmed);
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqual(trimmed.bytes.len, @as(usize, @intCast(nestedInteger(root, &.{"emitted_bytes"}))));

    // Whole dependency records are kept up to the budget and the rest are named.
    const kept = records(root, "dependencies");
    try t.expect(kept.len >= 1);
    try t.expect(kept.len < 30);
    try expectOmission(root, "dependencies", 30 - kept.len);

    // The contract is never cut into a fragment: the whole signature stays.
    const contract = record(root, "contract");
    try t.expectEqualStrings("hub(value: int) -> int", stringAt(contract, "signature"));
    try t.expectEqualStrings("checked", stringAt(contract, "analysis"));

    // The continuation asks for the same question with more room.
    try expectContinuation(root, 3000);

    // The identity-only rung still answers, and still names what it left out.
    var tiny = symbolOptions("model::hub");
    tiny.context_bytes = context.minimum_context_bytes;
    const minimal = try scene.render(tiny);
    defer t.allocator.free(minimal.bytes);
    try t.expect(minimal.bytes.len <= context.minimum_context_bytes);
    const minimal_parsed = try envelope(minimal);
    defer minimal_parsed.deinit();
    try t.expectEqual(context.Status.ok, minimal.status);
    try t.expectEqualStrings("ok", stringAt(minimal_parsed.value, "status"));
    try t.expectEqual(@as(usize, 0), arrayAt(minimal_parsed.value, "sections").len);
    try t.expect(arrayAt(minimal_parsed.value, "omissions").len >= 3);
    try expectOmission(minimal_parsed.value, "dependencies", 30);
    try expectContinuation(minimal_parsed.value, context.minimum_context_bytes);

    // A budget that cannot even carry the identity is rejected, not truncated.
    const oversized = try oversizedName(t.allocator);
    defer t.allocator.free(oversized);
    var huge = symbolOptions(oversized);
    huge.context_bytes = context.minimum_context_bytes;
    try t.expectError(error.BudgetTooSmall, scene.render(huge));
    var below_minimum = symbolOptions("model::hub");
    below_minimum.context_bytes = context.minimum_context_bytes - 1;
    try t.expectError(error.BudgetTooSmall, scene.render(below_minimum));
}

/// A selector name larger than the smallest whole envelope, so no rung fits it.
fn oversizedName(allocator: std.mem.Allocator) ![]u8 {
    const name = try allocator.alloc(u8, 4096);
    @memset(name, 'x');
    return name;
}

// spec: CONTEXT-STALE-1
// spec: CONTEXT-CONFIRM-1
test "context rejects an answer when a source changes while it is assembled" {
    // The provider is the file system: it serves the fixture while the project
    // loads, then the edited body, which is what a disk edit looks like to a
    // command that loaded the project a moment earlier.
    var files: Files = .{ .entries = &healthy_entries };
    const scene = try Scene.open(t.allocator, &files, "main");
    defer scene.close();
    files.entries = &edited_entries;
    var options = symbolOptions("model::validate");
    options.sources = files.provider();
    const answer = try scene.render(options);
    defer t.allocator.free(answer.bytes);
    try t.expectEqual(context.Status.stale, answer.status);
    const parsed = try envelope(answer);
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqualStrings("agent-context-v1", stringAt(root, "version"));
    try t.expectEqualStrings("stale", stringAt(root, "status"));
    try t.expect(std.mem.indexOf(u8, stringAt(root, "reason"), "changed while this answer was being assembled") != null);
    // The identity the rejected answer names is still the identity it checked
    // against, and neither version's facts are published.
    try t.expectEqualStrings("test", nestedString(root, &.{ "snapshot", "compiler", "zig_version" }));
    try t.expect(field(nested(root, &.{"snapshot"}), "inputs") == .null);
    try expectHexDigest(nestedString(root, &.{"snapshot_sha256"}));
    try t.expectEqual(@as(usize, 0), arrayAt(root, "sections").len);
    try t.expectEqual(@as(usize, 0), arrayAt(root, "omissions").len);
    try t.expect(field(root, "continuation") == .null);
    try t.expectEqual(answer.bytes.len, @as(usize, @intCast(nestedInteger(root, &.{"emitted_bytes"}))));

    // A provider that can no longer answer for one of its inputs leaves the
    // answer unconfirmed: that is its own outcome, not a changed source.
    var absent: Files = .{ .entries = &.{.{ .path = "main.my", .bytes = main_source }} };
    var unconfirmed = symbolOptions("model::validate");
    unconfirmed.sources = absent.provider();
    try t.expectError(error.RecheckUnavailable, scene.render(unconfirmed));

    // A project whose recorded source was replaced in place, with no provider to
    // re-read, is rejected from the bytes it holds.
    var swap_files: Files = .{ .entries = &healthy_entries };
    const swap = try Scene.open(t.allocator, &swap_files, "main");
    defer swap.close();
    const model = try moduleNamed(swap, "model");
    const edited = try std.fmt.allocPrint(t.allocator, "{s}\n\ndef extra() -> int:\n    return 2\n", .{model_source});
    defer t.allocator.free(edited);
    model.src = try source.Source.init(swap.project.arena.allocator(), model_path, edited);
    const swapped = try swap.render(symbolOptions("model::validate"));
    defer t.allocator.free(swapped.bytes);
    try t.expectEqual(context.Status.stale, swapped.status);
}

// spec: CONTEXT-PARTIAL-1
test "context answers an incomplete project and never reuses checked edges" {
    var files: Files = .{ .entries = &healthy_entries };
    const healthy = try Scene.open(t.allocator, &files, "main");
    defer healthy.close();
    const checked = try healthy.render(symbolOptions("model::validate"));
    defer t.allocator.free(checked.bytes);
    const checked_parsed = try envelope(checked);
    defer checked_parsed.deinit();
    try t.expectEqual(@as(usize, 2), records(checked_parsed.value, "dependencies").len);

    // The same question about a project whose bodies do not check: the answer
    // names the declarations it recovered and the status of every fact.
    var broken_files: Files = .{ .entries = &broken_entries };
    const broken = try Scene.openUnchecked(t.allocator, &broken_files, "main");
    defer broken.close();
    const answer = try broken.render(symbolOptions("model::validate"));
    defer t.allocator.free(answer.bytes);
    try t.expectEqual(context.Status.partial, answer.status);
    const parsed = try envelope(answer);
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqualStrings("partial", stringAt(root, "status"));
    try t.expectEqualStrings("declaration-only", nestedString(root, &.{ "analysis", "status" }));
    try t.expect(std.mem.indexOf(u8, nestedString(root, &.{ "analysis", "reason" }), "not check") != null);
    try t.expectEqualStrings("model::validate", stringAt(record(root, "declaration"), "id"));
    try expectDiagnostic(root, "E_TYPE");
    // The relationships it could not resolve are empty, never another version's.
    try t.expectEqual(@as(usize, 0), records(root, "dependencies").len);
    try t.expectEqual(@as(usize, 0), records(root, "tests").len);
    // The contract states the status instead of publishing an inferred set.
    const contract = record(root, "contract");
    try t.expectEqualStrings("validate(value: int) -> int", stringAt(contract, "signature"));
    try t.expectEqualStrings("declaration-only", stringAt(contract, "analysis"));
    try t.expect(field(contract, "effects") == .null);
    try t.expect(field(contract, "mutates") == .null);
    try t.expect(field(contract, "return_origin") == .null);
    try t.expect(field(contract, "mutation_writes") == .null);

    // A project whose body syntax failed before any declaration merged still
    // answers with its selector and says only lexical candidates were recovered.
    var syntax_files: Files = .{ .entries = &syntax_broken_entries };
    const lexical = try PartialScene.open(t.allocator, &syntax_files, "main");
    defer lexical.close();
    const lexical_answer = try lexical.render(symbolOptions("model::validate"));
    defer t.allocator.free(lexical_answer.bytes);
    try t.expectEqual(context.Status.partial, lexical_answer.status);
    const lexical_parsed = try envelope(lexical_answer);
    defer lexical_parsed.deinit();
    const lexical_root = lexical_parsed.value;
    try t.expectEqualStrings("partial", stringAt(lexical_root, "status"));
    try t.expectEqualStrings("lexical-only", nestedString(lexical_root, &.{ "analysis", "status" }));
    try t.expect(std.mem.indexOf(u8, stringAt(lexical_root, "reason"), "syntax failed") != null);
    try t.expectEqualStrings("model::validate", nestedString(lexical_root, &.{ "selector", "symbol" }));
    try t.expect(field(nested(lexical_root, &.{"selector"}), "resolved") == .null);
    try t.expectEqual(@as(usize, 0), records(lexical_root, "declaration").len);
    try t.expectEqual(@as(usize, 0), records(lexical_root, "dependencies").len);
    try t.expectEqual(@as(usize, 0), records(lexical_root, "tests").len);
    try expectHexDigest(nestedString(lexical_root, &.{"snapshot_sha256"}));
    try expectInputDigest(lexical_root, "model", syntax_broken_model_source);
}
