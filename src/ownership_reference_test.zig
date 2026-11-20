//! OR1 and OR6: final rule metadata and executable examples agree with the compiler.
const std = @import("std");
const rules = @import("ownership_rules.zig");
const coverage = @import("doc_coverage.zig");
const options = @import("test_paths");
const t = std.testing;
const report = std.debug.print;
const count = std.meta.tags(rules.Rule).len;
const DocumentError = error{
    InvalidHeading,
    DuplicateRule,
    MissingRule,
    UnterminatedFence,
    InvalidLayer,
    InvalidCodes,
    InvalidExample,
    MissingAcceptedExample,
    MissingRefusedExample,
    UnfiledRule,
};
const Sections = [count][]const u8;
const Example = struct { source: []const u8, code: ?[]const u8, build: bool };

fn nextLine(rest: *[]const u8) ?[]const u8 {
    if (rest.len == 0) return null;
    const end = std.mem.indexOfScalar(u8, rest.*, '\n') orelse rest.len;
    const line = std.mem.trimEnd(u8, rest.*[0..end], "\r");
    rest.* = rest.*[@min(end + 1, rest.len)..];
    return line;
}

fn sectionHeading(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "# ")) return true;
    if (std.mem.startsWith(u8, line, "## ")) return true;
    return std.mem.startsWith(u8, line, "### ");
}

/// The headings that file the numbered rules, in the order of the model: the three rules, the limits, the applications and the
/// appendix of accepted behaviour. A rule section sits under exactly one of them.
const families = [_][]const u8{
    "Rule 1: Escape",
    "Rule 2: Exclusion",
    "Rule 3: Gone",
    "Current limits",
    "Applications",
    "Appendix: accepted behaviour and retired restrictions",
};
const unfiled: u8 = 255;

fn familyIndex(line: []const u8) u8 {
    if (!std.mem.startsWith(u8, line, "## ")) return unfiled;
    const text = std.mem.trim(u8, line[3..], " \t");
    for (families, 0..) |name, index| {
        if (std.mem.eql(u8, text, name)) return @intCast(index);
    }
    return unfiled;
}

/// The heading each rule section sits under, as an index into `families`. A rule section outside every family heading, a rule
/// filed twice and a rule nobody files are errors, so each of the 54 ids is filed under exactly one heading.
fn filing(document: []const u8) DocumentError![count]u8 {
    var filed: [count]u8 = @splat(unfiled);
    var rest = document;
    var fenced = false;
    var family: u8 = unfiled;
    while (nextLine(&rest)) |line| {
        if (std.mem.startsWith(u8, line, "```")) {
            fenced = !fenced;
            continue;
        }
        if (fenced or !sectionHeading(line)) continue;
        if (!std.mem.startsWith(u8, line, "### ")) {
            family = familyIndex(line);
            continue;
        }
        const heading = line[4..];
        const separator = std.mem.indexOf(u8, heading, " — ") orelse return error.InvalidHeading;
        const rule = std.meta.stringToEnum(rules.Rule, heading[0..separator]) orelse return error.InvalidHeading;
        if (family == unfiled) return error.UnfiledRule;
        if (filed[@backingInt(rule)] != unfiled) return error.DuplicateRule;
        filed[@backingInt(rule)] = family;
    }
    if (std.mem.indexOfScalar(u8, &filed, unfiled) != null) return error.MissingRule;
    return filed;
}

fn sections(document: []const u8) DocumentError!Sections {
    var result: Sections = @splat("");
    var seen: [count]bool = @splat(false);
    var rest = document;
    var fenced = false;
    var current: ?rules.Rule = null;
    var start: usize = 0;
    while (rest.len != 0) {
        const before = document.len - rest.len;
        const line = nextLine(&rest).?;
        if (std.mem.startsWith(u8, line, "```")) {
            fenced = !fenced;
            continue;
        }
        if (fenced) continue;
        const rule_heading = std.mem.startsWith(u8, line, "### ");
        if (!sectionHeading(line)) continue;
        if (current) |rule| result[@backingInt(rule)] = document[start..before];
        current = null;
        if (!rule_heading) continue;
        const heading = line[4..];
        const separator = std.mem.indexOf(u8, heading, " — ") orelse return error.InvalidHeading;
        const rule = std.meta.stringToEnum(rules.Rule, heading[0..separator]) orelse return error.InvalidHeading;
        if (std.mem.trim(u8, heading[separator + " — ".len ..], " \t").len == 0) return error.InvalidHeading;
        if (seen[@backingInt(rule)]) return error.DuplicateRule;
        seen[@backingInt(rule)] = true;
        current = rule;
        start = document.len - rest.len;
    }
    if (fenced) return error.UnterminatedFence;
    if (current) |rule| result[@backingInt(rule)] = document[start..];
    if (!std.mem.allEqual(bool, &seen, true)) return error.MissingRule;
    return result;
}

fn metadata(body: []const u8, prefix: []const u8) ?[]const u8 {
    var rest = body;
    var fenced = false;
    var found: ?[]const u8 = null;
    while (nextLine(&rest)) |line| {
        if (std.mem.startsWith(u8, line, "```")) {
            fenced = !fenced;
            continue;
        }
        if (fenced or !std.mem.startsWith(u8, line, prefix)) continue;
        if (found != null) return null;
        found = line[prefix.len..];
    }
    return found;
}

fn checkCodes(rule: rules.Rule, text: []const u8) DocumentError!void {
    var seen: [rules.entries.len]bool = @splat(false);
    if (!std.mem.eql(u8, text, "none.")) {
        if (!std.mem.endsWith(u8, text, ".")) return error.InvalidCodes;
        var names = std.mem.tokenizeAny(u8, text[0 .. text.len - 1], " `,");
        var found = false;
        while (names.next()) |name| {
            var matched = false;
            for (rules.entries, 0..) |entry, index| {
                if (!std.mem.eql(u8, entry.code, name)) continue;
                if (!rules.valid(.{ .code = name, .rule = rule }) or seen[index]) return error.InvalidCodes;
                seen[index] = true;
                matched = true;
            }
            if (!matched) return error.InvalidCodes;
            found = true;
        }
        if (!found) return error.InvalidCodes;
    }
    for (rules.entries, 0..) |entry, index| {
        if (rules.valid(.{ .code = entry.code, .rule = rule }) != seen[index]) return error.InvalidCodes;
    }
}

fn example(rule: rules.Rule, fence: coverage.Fence) DocumentError!?Example {
    if (!std.mem.eql(u8, fence.info, "selka")) {
        if (std.mem.startsWith(u8, fence.info, "selka")) return error.InvalidExample;
        return null;
    }
    var rest = fence.body;
    var code: ?[]const u8 = null;
    var accepted = false;
    var build = false;
    while (rest.len != 0) {
        const saved = rest;
        const line = std.mem.trim(u8, nextLine(&rest).?, " \t");
        if (line.len == 0) continue;
        if (!std.mem.startsWith(u8, line, "# doc: ")) {
            rest = saved;
            break;
        }
        const directive = line[7..];
        if (std.mem.startsWith(u8, directive, "expect-error ")) {
            if (code != null or accepted) return error.InvalidExample;
            code = directive["expect-error ".len..];
            if (!rules.valid(.{ .code = code.?, .rule = rule })) return error.InvalidExample;
        } else if (std.mem.startsWith(u8, directive, "expect ")) {
            if (code != null or directive.len == "expect ".len) return error.InvalidExample;
            accepted = true;
        } else if (std.mem.eql(u8, directive, "build")) {
            if (build) return error.InvalidExample;
            build = true;
        } else if (!std.mem.startsWith(u8, directive, "allow-")) return error.InvalidExample;
    }
    if (!accepted and code == null) return error.InvalidExample;
    if (build and code == null) return error.InvalidExample;
    var program = rest;
    var main = false;
    while (nextLine(&program)) |line| {
        if (std.mem.startsWith(u8, line, "func main(") or std.mem.startsWith(u8, line, "public func main(")) main = true;
    }
    if (!main) return error.InvalidExample;
    return .{ .source = rest, .code = code, .build = build };
}

fn checkRule(rule: rules.Rule, body: []const u8) DocumentError!void {
    const layer = metadata(body, "Layer: ") orelse return error.InvalidLayer;
    if (!std.mem.endsWith(u8, layer, ".")) return error.InvalidLayer;
    if (!std.mem.eql(u8, rules.layerText(rule), layer[0 .. layer.len - 1])) return error.InvalidLayer;
    try checkCodes(rule, metadata(body, "Codes: ") orelse return error.InvalidCodes);
    var accepted = false;
    var refused = false;
    var fences = coverage.fences(body);
    while (fences.next()) |fence| {
        const item = try example(rule, fence) orelse continue;
        if (item.code == null) accepted = true else refused = true;
    }
    if (!accepted) return error.MissingAcceptedExample;
    for (rules.entries) |entry| {
        if (rules.valid(.{ .code = entry.code, .rule = rule }) and !refused) return error.MissingRefusedExample;
    }
}

fn checkDocument(document: []const u8) DocumentError!Sections {
    const found = try sections(document);
    for (rules.definitions) |definition| {
        checkRule(definition.rule, found[@backingInt(definition.rule)]) catch |err| {
            report("ownership reference {s}: {s}\n", .{ @tagName(definition.rule), @errorName(err) });
            return err;
        };
    }
    return found;
}

test "ownership reference gives all54 rules final layers codes and runnable examples" {
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/ownership-rules.md", t.allocator, .limited(1 << 20));
    defer t.allocator.free(document);
    _ = try checkDocument(document);
}

/// Whether the first diagnostic of `code` in `output` is an error of `rule`. Only the first is the example's: a check reports
/// every independent error of a file (F-RC-214), so a later one is what the program reads with the first repaired.
fn expectedRule(a: std.mem.Allocator, output: []const u8, code: []const u8, rule: rules.Rule) !bool {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "{")) continue;
        var parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const diagnostic = parsed.value.object.get("diagnostic") orelse continue;
        if (diagnostic != .object) continue;
        const actual_code = diagnostic.object.get("code") orelse continue;
        if (actual_code != .string) continue;
        if (!std.mem.eql(u8, code, actual_code.string)) continue;
        const severity = diagnostic.object.get("severity") orelse return false;
        if (severity != .string or !std.mem.eql(u8, severity.string, "error")) return false;
        const actual_rule = diagnostic.object.get("rule") orelse return false;
        return actual_rule == .string and std.mem.eql(u8, @tagName(rule), actual_rule.string);
    }
    return false;
}

fn checkRefused(a: std.mem.Allocator, directory: std.Io.Dir, root: []const u8, rule: rules.Rule, item: Example) !void {
    const name = try std.fmt.allocPrint(a, "{s}.selka", .{@tagName(rule)});
    try directory.writeFile(t.io, .{ .sub_path = name, .data = item.source });
    const path = try std.fs.path.join(a, &.{ root, name });
    const artifact = try std.fs.path.join(a, &.{ root, "example" });
    const check = [_][]const u8{ options.corePath(), "check", path, "--no-cache", "--diagnostics=json" };
    const build = [_][]const u8{ options.corePath(), "build", path, "-o", artifact, "--no-cache", "--diagnostics=json" };
    const result = try std.process.run(a, t.io, .{ .argv = if (item.build) &build else &check });
    if (result.term != .exited or result.term.exited != 1 or !try expectedRule(a, result.stderr, item.code.?, rule)) {
        report("ownership reference {s}: expected {s}/{s}\n{s}\n{s}\n", .{
            @tagName(rule), item.code.?, @tagName(rule), result.stdout, result.stderr,
        });
        return error.TestUnexpectedResult;
    }
}

/// Every rule the code table names is filed, and each of the six headings holds at least one rule.
fn expectFiled(document: []const u8) !void {
    const filed = try filing(document);
    for (rules.entries) |entry| {
        for (entry.rules) |rule| try t.expect(filed[@backingInt(rule)] < families.len);
    }
    var held: [families.len]usize = @splat(0);
    for (filed) |heading| held[heading] += 1;
    for (held) |rules_held| try t.expect(rules_held != 0);
}

test "ownership reference files every rule of the code table under exactly one heading of the model" {
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/ownership-rules.md", t.allocator, .limited(1 << 20));
    defer t.allocator.free(document);
    try expectFiled(document);
}

/// Every rule is filed in the document under the heading the compiler's own table (`rules.family`) names, which is what
/// `selka reference --query` prints.
fn expectFamilies(document: []const u8) !void {
    const filed = try filing(document);
    for (rules.definitions) |definition| {
        try t.expectEqual(@backingInt(rules.family(definition.rule)), filed[@backingInt(definition.rule)]);
    }
}

test "ownership reference files each rule under the heading the compiler's family table names" {
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/ownership-rules.md", t.allocator, .limited(1 << 20));
    defer t.allocator.free(document);
    try expectFamilies(document);
    try t.expectEqual(families.len, rules.family_names.len);
}

test "ownership reference filing rejects an unfiled, a twice filed and a missing rule" {
    try t.expectError(error.UnfiledRule, filing("### T1 — Managed types\n"));
    try t.expectError(error.UnfiledRule, filing("## Checking layers\n### T1 — Managed types\n"));
    try t.expectError(error.UnfiledRule, filing("## Rule 1: Escapes\n### T1 — Managed types\n"));
    try t.expectError(error.DuplicateRule, filing("## Rule 1: Escape\n### T1 — A\n## Rule 2: Exclusion\n### T1 — B\n"));
    try t.expectError(error.MissingRule, filing("## Rule 1: Escape\n### T1 — Managed types\n"));
    try t.expectError(error.InvalidHeading, filing("## Rule 1: Escape\n### T5 — Unknown\n"));
}

test "ownership reference refused examples diagnose their actual rule including shared codes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const document = try std.Io.Dir.cwd().readFileAlloc(t.io, "docs/ownership-rules.md", a, .limited(1 << 20));
    const found = try checkDocument(document);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    for (rules.definitions) |definition| {
        var fences = coverage.fences(found[@backingInt(definition.rule)]);
        while (fences.next()) |fence| {
            const item = try example(definition.rule, fence) orelse continue;
            if (item.code != null) try checkRefused(a, directory.dir, root, definition.rule, item);
        }
    }
}

test "ownership reference rejects missing duplicate and unknown rule headings" {
    try t.expectError(error.MissingRule, sections("### T1 — Managed types\n\n"));
    try t.expectError(error.DuplicateRule, sections("### T1 — First\n### T1 — Again\n"));
    try t.expectError(error.InvalidHeading, sections("### T5 — Unknown\n"));
    try t.expectError(error.InvalidHeading, sections("### T1 — \n"));
}

test "ownership reference requires exact code sets and final checking layers" {
    try t.expectError(error.InvalidCodes, checkCodes(.B3, "none."));
    try t.expectError(error.InvalidCodes, checkCodes(.B3, "`E_SINGLE_OWNER_MOVED`, `E_SINGLE_OWNER_MOVED`."));
    try t.expectError(error.InvalidCodes, checkCodes(.B3, "`E_SINGLE_OWNER_MOVED`, `E_IMMUTABLE`."));
    try t.expectError(error.InvalidCodes, checkCodes(.Z1, "`E_SINGLE_OWNER_UNSUPPORTED`."));
    try t.expectError(error.InvalidLayer, checkRule(.B3, "Layer: Frontend.\nCodes: `E_SINGLE_OWNER_MOVED`.\n"));
    try t.expectEqual(rules.Layer.both, rules.layer(.W2));
}

test "ownership reference examples cannot count skipped empty or mislabeled programs" {
    const prefix = "Layer: Core.\nCodes: `E_SINGLE_OWNER_MOVED`.\n";
    const accepted = "```selka\n# doc: expect 0\nfunc main() -> int:\n    return 0\n```\n";
    try t.expectError(error.MissingRefusedExample, checkRule(.B3, prefix ++ accepted));
    const refused = "```selka\n# doc: expect-error E_SINGLE_OWNER_MOVED\nfunc main() -> int:\n    return 0\n```\n";
    try t.expectError(error.MissingAcceptedExample, checkRule(.B3, prefix ++ refused));
    for ([_][]const u8{ "skip reason", "check", "expect-error E_IMMUTABLE", "expect 0\n# doc: build" }) |directive| {
        const body = try std.fmt.allocPrint(t.allocator, "# doc: {s}\nfunc main() -> int:\n    return 0\n", .{directive});
        defer t.allocator.free(body);
        try t.expectError(error.InvalidExample, example(.B3, .{ .info = "selka", .body = body }));
    }
    try t.expectError(error.InvalidExample, example(.B3, .{ .info = "selka", .body = "# doc: expect 0\n" }));
    try t.expectError(error.InvalidExample, example(.B3, .{ .info = "selka notest", .body = accepted }));
    try t.expectError(error.UnterminatedFence, sections("### T1 — Managed types\n```selka\n"));
}

test "ownership reference requires the actual shared code predicate rather than a matching code alone" {
    const right = "{\"diagnostic\":{\"code\":\"E_SINGLE_OWNER_OVERLAP\",\"severity\":\"error\",\"rule\":\"M5\"}}\n";
    const wrong = "{\"diagnostic\":{\"code\":\"E_SINGLE_OWNER_OVERLAP\",\"severity\":\"error\",\"rule\":\"R2\"}}\n";
    const missing = "{\"diagnostic\":{\"code\":\"E_SINGLE_OWNER_OVERLAP\",\"severity\":\"error\"}}\n";
    try t.expect(try expectedRule(t.allocator, right, "E_SINGLE_OWNER_OVERLAP", .M5));
    try t.expect(!try expectedRule(t.allocator, wrong, "E_SINGLE_OWNER_OVERLAP", .M5));
    try t.expect(!try expectedRule(t.allocator, missing, "E_SINGLE_OWNER_OVERLAP", .M5));
}

test "ownership reference judges the first diagnostic of an example's code, not the next error a check reports after it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const output =
        \\{"kind":"diagnostic","diagnostic":{"code":"E_SLICE_ESCAPES","severity":"error","rule":"V5"}}
        \\{"kind":"diagnostic","diagnostic":{"code":"E_SLICE_ESCAPES","severity":"error","rule":"V2"}}
        \\
    ;
    try t.expect(try expectedRule(arena.allocator(), output, "E_SLICE_ESCAPES", .V5));
    try t.expect(!try expectedRule(arena.allocator(), output, "E_SLICE_ESCAPES", .V2));
    try t.expect(!try expectedRule(arena.allocator(), output, "E_OWN_MARKER", .V5));
}
