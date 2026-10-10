//! Compile-time file embedding (`EMBED-*`): what `embed_bytes` and `embed_str`
//! accept, every diagnostic, the static data the manifest carries, and the keys
//! an edit to only the embedded file must change.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const embed = @import("embed.zig");
const semantic_key = @import("semantic_key.zig");

// spec: SELFHOST-FRONTEND-AUX-1
test "frontend auxiliary embed scan propagates component failures" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_LEXER_MODE", "invalid-mode");
    const runtime: language.lexer_component.Runtime = .{ .io = t.io, .environ = &environ };
    const plain = try language.source.Source.init(a, "main.my", "func main() -> int:\n    return 0\n");
    const embedding = try language.source.Source.init(a, "main.my", "const DATA = embed_bytes(\"data.bin\")\n");
    try t.expectError(error.ComponentMode, embed.scanWithRuntime(a, plain, runtime));
    try t.expectError(error.ComponentMode, embed.scanWithRuntime(a, embedding, runtime));
    try t.expectEqual(@as(usize, 1), (try embed.scanWithRuntime(a, embedding, null)).len);
}

/// A compilation of `text` whose embed calls were read from `directory`.
fn compile(allocator: std.mem.Allocator, directory: []const u8, text: []const u8) !language.Compilation {
    var compilation = try language.Compilation.init(allocator, "main.my", text);
    errdefer compilation.deinit();
    const arena = compilation.arena.allocator();
    const found = try embed.scan(arena, compilation.src);
    try embed.resolve(arena, .{ .io = t.io, .import_root = directory, .root = directory }, "main.my", found);
    compilation.src.embeds = found;
    return compilation;
}

/// The absolute path of a fresh temporary directory's root.
fn rootOf(temporary: *t.TmpDir) ![:0]u8 {
    return temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

/// The first diagnostic code checking `text` reports, or null when it checks.
fn rejection(allocator: std.mem.Allocator, directory: []const u8, text: []const u8) !?[]const u8 {
    var compilation = try compile(allocator, directory, text);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {
            const code = try allocator.dupe(u8, compilation.diagnostics.items[0].code);
            return code;
        },
        else => return err,
    };
    return null;
}

const Case = struct { text: []const u8, code: []const u8 };

/// Require every case to be rejected with its own code.
fn expectCodes(directory: []const u8, cases: []const Case) !void {
    for (cases) |case| {
        const found = try rejection(t.allocator, directory, case.text);
        defer if (found) |code| t.allocator.free(code);
        try t.expectEqualStrings(case.code, found orelse "accepted");
    }
}

// spec: EMBED-1
test "embed_bytes and embed_str read a file as a constant, inline and where allocation is banned" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "\x01\x02\x00" });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "text.txt", .data = "h\xc3\xa9" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    var compilation = try compile(t.allocator, root,
        \\const DATA: bytes = embed_bytes("data.bin")
        \\const TEXT: str = embed_str("text.txt")
        \\
        \\
        \\func total() -> int noalloc:
        \\    return len(DATA) + len(embed_bytes("data.bin"))
        \\
        \\
        \\func main() -> int:
        \\    return total() + len(TEXT) * 100 + DATA[1]
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 208), (try native.run(&compilation)).value);
    try t.expectEqual(@as(@import("effect_set.zig").Mask, 0), compilation.program.?.functions[0].policy.effect_bound.?.allowed);
}

// spec-case: EMBED-1
test "an embedded empty file is an empty value and an edited file changes the program" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    const text = "func main() -> int:\n    return len(embed_bytes(\"data.bin\")) + 40\n";
    var empty = try compile(t.allocator, root, text);
    defer empty.deinit();
    try t.expectEqual(@as(i64, 40), (try native.run(&empty)).value);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "xy" });
    var edited = try compile(t.allocator, root, text);
    defer edited.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&edited)).value);
}

// spec-case: EMBED-1
test "an embed call inside an f-string interpolation is read like any other" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "abcdefghij" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    var compilation = try compile(t.allocator, root, "func main() -> int:\n    mut label = f\"n={len(embed_bytes('data.bin'))}\"\n    return len(label)\n");
    defer compilation.deinit();
    try t.expectEqual(@as(usize, 1), compilation.src.embeds.len);
    try t.expectEqual(@as(i64, 4), (try native.run(&compilation)).value);
}

// spec: EMBED-2
test "every embed error is a located diagnostic with its own code" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "outside.bin", .data = "x" });
    try temporary.dir.createDirPath(t.io, "project");
    try temporary.dir.writeFile(t.io, .{ .sub_path = "project/inside.bin", .data = "y" });
    try temporary.dir.symLink(t.io, "../outside.bin", "project/link.bin", .{});
    try temporary.dir.symLink(t.io, "inside.bin", "project/alias.bin", .{});
    const base = try rootOf(&temporary);
    defer t.allocator.free(base);
    const root = try std.fs.path.join(t.allocator, &.{ base, "project" });
    defer t.allocator.free(root);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "project/data.bin", .data = "\xff\xfe" });
    try temporary.dir.createDirPath(t.io, "project/folder");
    try expectCodes(root, &.{
        .{ .text = "func main() -> int:\n    mut path = \"inside.bin\"\n    return len(embed_bytes(path))\n", .code = "E_EMBED_ARGUMENT" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(b\"inside.bin\"))\n", .code = "E_EMBED_ARGUMENT" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"inside.bin\", \"other\"))\n", .code = "E_EMBED_ARGUMENT" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"missing.bin\"))\n", .code = "E_EMBED_MISSING" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"folder\"))\n", .code = "E_EMBED_DIRECTORY" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"/etc/hostname\"))\n", .code = "E_EMBED_ABSOLUTE" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"../outside.bin\"))\n", .code = "E_EMBED_ESCAPE" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"link.bin\"))\n", .code = "E_EMBED_ESCAPE" },
        .{ .text = "func main() -> int:\n    return len(embed_str(\"data.bin\"))\n", .code = "E_EMBED_UTF8" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"\"))\n", .code = "E_EMBED_PATH" },
        .{ .text = "const BAD: bytes = embed_str(\"inside.bin\")\n\nfunc main() -> int:\n    return len(BAD)\n", .code = "E_TYPE" },
        .{ .text = "func main() -> int:\n    return len(embed_bytes(\"alias.bin\")) + len(embed_bytes(\"./inside.bin\")) + len(embed_bytes(\"folder/../inside.bin\")) - 3\n", .code = "accepted" },
    });
}

// spec-case: EMBED-2
test "an invalid embed_str names the byte offset and an oversized file is refused" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "bad.txt", .data = "ok\xc3" });
    const oversized = try t.allocator.alloc(u8, embed.size_cap + 1);
    defer t.allocator.free(oversized);
    @memset(oversized, 'z');
    try temporary.dir.writeFile(t.io, .{ .sub_path = "huge.bin", .data = oversized });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    var text = try compile(t.allocator, root, "func main() -> int:\n    return len(embed_str(\"bad.txt\"))\n");
    defer text.deinit();
    try t.expectError(error.SourceError, text.check());
    try t.expect(std.mem.indexOf(u8, text.diagnostics.items[0].message, "offset 2") != null);
    var huge = try compile(t.allocator, root, "func main() -> int:\n    return len(embed_bytes(\"huge.bin\"))\n");
    defer huge.deinit();
    try t.expectError(error.SourceError, huge.check());
    try t.expectEqualStrings("E_EMBED_TOO_LARGE", huge.diagnostics.items[0].code);
    try t.expectEqual(@as(usize, 0), huge.src.embeds[0].contents.len);
}

// spec-case: EMBED-2
test "a source loaded without a directory reports that embeds need one" {
    var compilation = try language.Compilation.init(t.allocator, "memory.my", "func main() -> int:\n    return len(embed_bytes(\"data.bin\"))\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_EMBED_UNAVAILABLE", compilation.diagnostics.items[0].code);
}

// spec-case: EMBED-2
test "a user function named like an embed builtin keeps its own meaning" {
    var compilation = try language.Compilation.init(t.allocator, "shadow.my", "func embed_bytes(path: str) -> int:\n    return len(path)\n\n\nfunc main() -> int:\n    return embed_bytes(\"data.bin\")\n");
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 8), (try native.run(&compilation)).value);
}

// spec-case: EMBED-2
test "paths are spelled relative to the embedding source's directory" {
    const nested = try embed.relativeTarget(t.allocator, "lib/deep", "../assets/./x.txt");
    defer t.allocator.free(nested);
    try t.expectEqualStrings("lib/assets/x.txt", nested);
    const above = try embed.relativeTarget(t.allocator, "lib", "../../shared/y.bin");
    defer t.allocator.free(above);
    try t.expectEqualStrings("../shared/y.bin", above);
    try t.expectEqual(embed.spelledStatus("/etc/x").?, .absolute);
    try t.expectEqual(embed.spelledStatus("a\\b").?, .invalid_path);
    try t.expectEqual(@as(?language.source.EmbedStatus, null), embed.spelledStatus("a/b"));
}

// spec: EMBED-3
test "a declaration keys on the embedded files inside it and on nothing else's" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "one" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    const text = "func user() -> int:\n    return len(embed_bytes(\"data.bin\"))\n\n\nfunc other() -> int:\n    return 7\n\n\nfunc main() -> int:\n    return user() + other()\n";
    var before = try compile(t.allocator, root, text);
    defer before.deinit();
    try before.parse();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "two" });
    var after = try compile(t.allocator, root, text);
    defer after.deinit();
    try after.parse();
    const contracts: semantic_key.Contracts = .{ .build = "test", .mutation = "test" };
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const first = try semantic_key.prepare(arena.allocator(), before.src, before.syntax.?, contracts, null, null);
    const second = try semantic_key.prepare(arena.allocator(), after.src, after.syntax.?, contracts, null, null);
    try t.expect(!std.mem.eql(u8, &first.contexts[0], &second.contexts[0]));
    try t.expectEqualSlices(u8, &first.contexts[1], &second.contexts[1]);
    try t.expectEqualSlices(u8, &first.contexts[2], &second.contexts[2]);
    try t.expectEqual(@as(usize, 1), before.src.embedsWithin(first.regions[0]).len);
    try t.expectEqual(@as(usize, 0), before.src.embedsWithin(first.regions[1]).len);
}

// spec-case: EMBED-3
test "an embed's identity covers its outcome, its path and its content" {
    var one: language.source.Embed = .{ .literal = .{ .start = 0, .end = 3 }, .path = "a", .status = .ok };
    embed.digest("one", &one.digest);
    var two = one;
    embed.digest("two", &two.digest);
    var lost = one;
    lost.status = .missing;
    lost.digest = @splat(0);
    var renamed = one;
    renamed.path = "b";
    const identities = [_][32]u8{ mix(one), mix(two), mix(lost), mix(renamed), mix(one) };
    try t.expectEqualSlices(u8, &identities[0], &identities[4]);
    try t.expect(!std.mem.eql(u8, &identities[0], &identities[1]));
    try t.expect(!std.mem.eql(u8, &identities[0], &identities[2]));
    try t.expect(!std.mem.eql(u8, &identities[0], &identities[3]));
}

fn mix(file: language.source.Embed) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    embed.hashInto(&hash, &.{file});
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

test "a module constant of an embedded file allocates nothing when read" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "abc" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    var compilation = try compile(t.allocator, root,
        \\const DATA: bytes = embed_bytes("data.bin")
        \\
        \\
        \\func read() -> int noalloc:
        \\    return len(DATA)
        \\
        \\
        \\func main() -> int:
        \\    return read()
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 3), (try native.run(&compilation)).value);
    const getter = compilation.program.?.functions[0];
    try t.expectEqual(@as(@import("effect_set.zig").Mask, 0), getter.policy.effects);
}

/// Read one module's embed through a provider that serves `main.my` and one file.
fn embedProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    return allocator.dupe(u8, "\nconst DATA: bytes = embed_bytes(\"data.bin\")\n\nfunc main() -> int:\n    return len(DATA)\n");
}

fn embedFile(_: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8, _: usize) std.mem.Allocator.Error!embed.Read {
    if (!std.mem.eql(u8, module_path, "main.my") or !std.mem.eql(u8, path, "data.bin")) return .{ .status = .missing };
    return .{ .status = .ok, .contents = try allocator.dupe(u8, "abcd") };
}

// spec-case: EMBED-3
test "the project loader reads the files a module embeds through its provider" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = embedProvider, .embed = embedFile }, "main", .{});
    const embeds = project.modules.items[0].src.embeds;
    try t.expectEqual(@as(usize, 1), embeds.len);
    try t.expectEqual(language.source.EmbedStatus.ok, embeds[0].status);
    try t.expectEqualStrings("abcd", embeds[0].contents);
    try t.expectEqualStrings("data.bin", embeds[0].path);
    var again = language.project.Project.init(t.allocator);
    defer again.deinit();
    try again.load(.{ .context = null, .read = embedProvider }, "main", .{});
    try t.expectEqual(language.source.EmbedStatus.unresolved, again.modules.items[0].src.embeds[0].status);
}

/// One payload served for `table.bin` to a two-module project.
const Served = struct { payload: []const u8 };

fn servedSource(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, "import data\n\nfunc main() -> int:\n    return len(data.TABLE)\n");
    if (std.mem.eql(u8, path, "data.my")) return allocator.dupe(u8, "\npublic const TABLE: bytes = embed_bytes(\"table.bin\")\n");
    return error.NotFound;
}

fn servedFile(context: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8, _: usize) std.mem.Allocator.Error!embed.Read {
    const served: *const Served = @ptrCast(@alignCast(context.?));
    if (!std.mem.eql(u8, module_path, "data.my") or !std.mem.eql(u8, path, "table.bin")) return .{ .status = .missing };
    return .{ .status = .ok, .contents = try allocator.dupe(u8, served.payload) };
}

/// The interface file text of `data` when `table.bin` holds `payload`.
fn interfaceOf(allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
    var served: Served = .{ .payload = payload };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &served, .read = servedSource, .embed = servedFile }, "main", .{});
    var index = try @import("interfaces.zig").build(&project);
    return @import("interface_files.zig").render(allocator, &index, project.names.get("data").?);
}

// spec: EMBED-5
test "formatting keeps embed calls, an interface names the file, and a receipt lists it" {
    const source_text = "const TABLE: bytes = embed_bytes(\"table.bin\")\n\n\nfunc main() -> int:\n    return len(embed_str(\"note.txt\"))\n";
    var compilation = try language.Compilation.init(t.allocator, "format.my", source_text);
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source_text, formatted);
    const first = try interfaceOf(t.allocator, "PAYLOAD-MARKER");
    defer t.allocator.free(first);
    const second = try interfaceOf(t.allocator, "another payload");
    defer t.allocator.free(second);
    try t.expect(std.mem.indexOf(u8, first, "public const TABLE: bytes = embed_bytes(\"table.bin\")\n") != null);
    try t.expect(std.mem.indexOf(u8, first, "PAYLOAD-MARKER") == null);
    try t.expectEqualStrings(first, second);
    var served: Served = .{ .payload = "abcdef" };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &served, .read = servedSource, .embed = servedFile }, "main", .{});
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const listed = try language.source_receipt.embeds(arena.allocator(), &project);
    try t.expectEqual(@as(usize, 1), listed.len);
    try t.expectEqualStrings("data", listed[0].module);
    try t.expectEqualStrings("table.bin", listed[0].path);
    try t.expectEqualStrings("ok", listed[0].status);
    try t.expectEqual(@as(usize, 6), listed[0].bytes);
    var digest: [32]u8 = undefined;
    embed.digest("abcdef", &digest);
    try t.expectEqualStrings(&std.fmt.bytesToHex(digest, .lower), listed[0].blake3);
}

const BudgetFiles = struct {
    payload: []const u8,
    received_limit: usize = 0,
    honor_limit: bool = true,
    status: language.source.EmbedStatus = .ok,
};

fn boundedEmbed(raw: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, limit: usize) std.mem.Allocator.Error!embed.Read {
    const files: *BudgetFiles = @ptrCast(@alignCast(raw.?));
    files.received_limit = limit;
    if (files.status != .ok) return .{ .status = files.status };
    if (files.honor_limit and files.payload.len > limit) return .{ .status = .too_large };
    return .{ .status = .ok, .contents = try allocator.dupe(u8, files.payload) };
}

// spec: EMBED-PROJECT-BUDGET-1
test "project budgets bound embedded reads before allocation and charge imported payloads" {
    const payload: [128]u8 = @splat('x');
    var files: BudgetFiles = .{ .payload = &payload };
    const provider: language.project.Provider = .{ .context = &files, .read = servedSource, .embed = boundedEmbed };
    var baseline = language.project.Project.init(t.allocator);
    defer baseline.deinit();
    try baseline.load(provider, "main", .{});
    try t.expectEqual(@as(usize, 128), baseline.counts.embedded_bytes);
    const total = baseline.counts.bytes + baseline.counts.embedded_bytes;
    var exact = language.project.Project.init(t.allocator);
    defer exact.deinit();
    try exact.load(provider, "main", .{ .max_file_bytes = 128, .max_total_bytes = total });
    try t.expectEqual(@as(usize, 128), files.received_limit);
    var over_total = language.project.Project.init(t.allocator);
    defer over_total.deinit();
    try t.expectError(error.SourceError, over_total.load(provider, "main", .{ .max_file_bytes = 128, .max_total_bytes = total - 1 }));
    try t.expectEqual(@as(usize, 127), files.received_limit);
    try t.expectEqualStrings("E_PROJECT_BYTES", over_total.problem.?.code);
    try t.expectEqualStrings("\"table.bin\"", over_total.modules.items[over_total.problem.?.site.module].src.text(over_total.problem.?.site.span));
    var over_file = language.project.Project.init(t.allocator);
    defer over_file.deinit();
    try t.expectError(error.SourceError, over_file.load(provider, "main", .{ .max_file_bytes = 100 }));
    try t.expectEqual(@as(usize, 100), files.received_limit);
    try t.expectEqualStrings("E_PROJECT_BYTES", over_file.problem.?.code);
    files.honor_limit = false;
    var broken_provider = language.project.Project.init(t.allocator);
    defer broken_provider.deinit();
    try t.expectError(error.SourceError, broken_provider.load(provider, "main", .{ .max_file_bytes = 100 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", broken_provider.problem.?.code);
    files.status = .too_large;
    var embed_cap = language.project.Project.init(t.allocator);
    defer embed_cap.deinit();
    try embed_cap.load(provider, "main", .{ .max_file_bytes = embed.size_cap, .max_total_bytes = embed.size_cap * 2 });
    try t.expectEqual(language.source.EmbedStatus.too_large, embed_cap.modules.items[embed_cap.names.get("data").?].src.embeds[0].status);
    try t.expectEqualStrings("E_EMBED_TOO_LARGE", embed.codeOf(.too_large).?);
}

// spec-case: EMBED-PROJECT-BUDGET-1
test "a bounded disk embed refuses an overlong file before reading its contents" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "abcde" });
    const root = try rootOf(&temporary);
    defer t.allocator.free(root);
    const roots: embed.Roots = .{ .io = t.io, .root = root, .import_root = root };
    const over = try embed.readLimited(t.allocator, roots, "main.my", "data.bin", 4);
    try t.expectEqual(language.source.EmbedStatus.too_large, over.status);
    try t.expectEqual(@as(usize, 0), over.contents.len);
    const exact = try embed.readLimited(t.allocator, roots, "main.my", "data.bin", 5);
    defer t.allocator.free(exact.contents);
    try t.expectEqualStrings("abcde", exact.contents);
}

fn repeatedEmbedSource(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, limit: usize) language.project.ReadError![]u8 {
    const text = "\nconst A: bytes = embed_bytes(\"data.bin\")\nconst B: bytes = embed_bytes(\"data.bin\")\n";
    if (text.len > limit) return error.TooLarge;
    return allocator.dupe(u8, text);
}

// spec-case: EMBED-PROJECT-BUDGET-1
test "repeated embedded calls share one provider identity and byte charge" {
    var files: BudgetFiles = .{ .payload = "abcd" };
    const provider: language.project.Provider = .{ .context = &files, .read = repeatedEmbedSource, .embed = boundedEmbed };
    var baseline = language.project.Project.init(t.allocator);
    defer baseline.deinit();
    try baseline.load(provider, "main", .{});
    try t.expectEqual(@as(usize, 4), baseline.counts.embedded_bytes);
    var refused = language.project.Project.init(t.allocator);
    defer refused.deinit();
    try t.expectError(error.SourceError, refused.load(provider, "main", .{ .max_total_bytes = baseline.counts.bytes + 3 }));
    try t.expectEqual(@as(usize, 3), files.received_limit);
    try t.expectEqual(@as(usize, 0), refused.counts.embedded_bytes);
    try t.expectEqualStrings("E_PROJECT_BYTES", refused.problem.?.code);
}
