//! Builtin modules obey project loading rules and execute generic, non-EDA queries.
const std = @import("std");
const product = @import("product.zig");
const t = std.testing;
const report = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const source =
    "import sort\n" ++
    "func main() -> int:\n" ++
    "    mut ordered = sort.sort_ints([9, 1, 4])\n" ++
    "    return ordered[0] + ordered[2]\n";
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-MODULES-1
test "standard modules load through embedded providers and execute reserved sources" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = read });
    defer program.deinit();
    const outcome = try native.run(&program.compilation);
    try t.expectEqual(@as(i64, 10), outcome.value);
    // `main`, `sort` and `lists`, which `sort`'s comparison sort moves elements with.
    try t.expectEqual(@as(usize, 3), program.loaded.modules.items.len);
}
// spec: STANDARD-MODULES-2
test "standard modules remain inside the total project byte budget" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(.{ .context = null, .read = read }, "main", .{ .max_total_bytes = source.len + 1 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", project.problem.?.code);
}

// spec: STANDARD-MODULES-7
test "standard generic results cannot be silently ignored" {
    try fixture.reject(t.allocator, "import strings\nfunc main() -> int:\n    strings.repeat(\"a\", 2)\n    return 0\n");
    try fixture.reject(t.allocator, "import time\nfunc main() -> int:\n    time.seconds(1)\n    return 0\n");
}

// spec-case: STANDARD-MODULES-1
test "standard fixture helpers report every assertion failure through declared errors" {
    const ordering = "import sort\nfunc main() -> int:\n    return sort.sort_ints([1, 2])[0]\n";
    try t.expectError(error.TestExpectedEqual, fixture.run(t.allocator, ordering, 41));
    const bounds = "import sort\nfunc main() -> int:\n    return sort.sort_ints([1])[5]\n";
    try t.expectError(error.TestUnexpectedResult, fixture.run(t.allocator, bounds, 0));
    try t.expectError(error.TestExpectedError, fixture.reject(t.allocator, ordering));
    try fixture.reject(t.allocator, "import sort\nfunc main() -> int:\n    return sort.sort_ints([1])\n");
}

// spec-case: STANDARD-MODULES-1
test "standard modules compose with one another inside a single project" {
    try fixture.run(t.allocator, "import strings\n" ++
        "import json\n" ++
        "import base64\n" ++
        "import path\n" ++
        "func main() -> int:\n" ++
        "    mut encoded = base64.b64encode(strings.encode(path.basename(\"/tmp/answer.txt\")))\n" ++
        "    match strings.decode(encoded):\n" ++
        "        case Ok(text):\n" ++
        "            mut fields: dict[str, json.Json] = {}\n" ++
        "            return rendered(text, mut fields)\n" ++
        "        case Err(_):\n" ++
        "            return 1\n" ++
        "func rendered(text: str, mut fields: dict[str, json.Json]) -> int:\n" ++
        "    fields[\"name\"] = json.text(text)\n" ++
        "    mut document = json.dumps(json.object(fields))\n" ++
        "    if document != \"{\\\"name\\\":\\\"YW5zd2VyLnR4dA==\\\"}\":\n" ++
        "        return 2\n" ++
        "    return strings.char_count(document) + 15\n", 42);
}

// spec: NETWORK-SURFACE-1
test "the network module wraps acquisition and one linear I/O operation" {
    const program_text =
        \\import network
        \\func main(net: Network) -> int:
        \\    with net.host("127.0.0.1:8000") as scoped:
        \\        match network.connect(scoped):
        \\            case ok(connection):
        \\                mut payload: FixedArray[u8, 4] = b"ping"
        \\                match network.write(own connection, payload):
        \\                    case ok(_):
        \\                        return 0
        \\                    case err(code):
        \\                        return code
        \\            case err(code):
        \\                return code
    ;
    var entry: fixture.Entry = .{ .text = program_text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = fixture.Entry.read });
    defer program.deinit();
    // The program, `network`, `byte_builder`, which the event loop's wrappers encode commands with, and the homes the
    // library calls as programs do since W13-S3: `lists` (`lists.clear`) and `buffers` (`byte_builder`'s appends).
    try t.expectEqual(@as(usize, 5), program.loaded.modules.items.len);
}

const ones = [_][]const u8{
    "zero", "one",    "two",    "three",    "four",     "five",    "six",     "seven",     "eight",    "nine",
    "ten",  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
};
const tens = [_][]const u8{ "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" };

/// The English word for 1..99 as the guides spell it (`twenty-three`).
fn numberWord(allocator: std.mem.Allocator, n: usize) ![]u8 {
    if (n < 20) return allocator.dupe(u8, ones[n]);
    if (n % 10 == 0) return allocator.dupe(u8, tens[n / 10]);
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ tens[n / 10], ones[n % 10] });
}

/// A token with surrounding punctuation and backticks removed.
fn bare(token: []const u8) []const u8 {
    return std.mem.trim(u8, token, "`,.:;()\"*|");
}

/// Whether `token` spells some count from 1 to 99, in words or digits.
fn isCount(allocator: std.mem.Allocator, token: []const u8) !bool {
    const word = bare(token);
    if (word.len != 0 and std.mem.trim(u8, word, "0123456789").len == 0) return true;
    for (1..100) |n| {
        const spelled = try numberWord(allocator, n);
        defer allocator.free(spelled);
        if (std.ascii.eqlIgnoreCase(spelled, word)) return true;
    }
    return false;
}

/// Whether `token` spells exactly `expected`, in words or digits.
fn isExpected(allocator: std.mem.Allocator, token: []const u8, expected: usize) !bool {
    const word = bare(token);
    const spelled = try numberWord(allocator, expected);
    defer allocator.free(spelled);
    if (std.ascii.eqlIgnoreCase(spelled, word)) return true;
    const digits = try std.fmt.allocPrint(allocator, "{d}", .{expected});
    defer allocator.free(digits);
    return std.mem.eql(u8, digits, word);
}

/// The first stale count in `text`: a count word before "modules ship", "embedded modules"
/// or "embedded Selka modules" that is not `expected`, or null when every one agrees.
fn staleCount(allocator: std.mem.Allocator, text: []const u8, expected: usize) !?[]const u8 {
    var tokens: std.ArrayList([]const u8) = .empty;
    defer tokens.deinit(allocator);
    var split = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (split.next()) |token| try tokens.append(allocator, token);
    for (tokens.items, 0..) |token, at| {
        if (!std.mem.eql(u8, bare(token), "modules") or at == 0) continue;
        const next = if (at + 1 < tokens.items.len) bare(tokens.items[at + 1]) else "";
        const previous = bare(tokens.items[at - 1]);
        var count_at: ?usize = null;
        if (std.mem.eql(u8, next, "ship")) count_at = at - 1;
        if (std.ascii.eqlIgnoreCase(previous, "embedded") and at >= 2) count_at = at - 2;
        if (std.ascii.eqlIgnoreCase(previous, "Selka") and at >= 3) count_at = at - 3;
        const index = count_at orelse continue;
        if (!try isCount(allocator, tokens.items[index])) continue;
        if (!try isExpected(allocator, tokens.items[index], expected)) return tokens.items[index];
    }
    return null;
}

/// Read a repository file whole.
fn readPage(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(t.io, path, allocator, .limited(4 << 20));
}

/// Require every module count stated in `path` to be the table's.
fn expectCountsAgree(path: []const u8) !void {
    const text = try readPage(t.allocator, path);
    defer t.allocator.free(text);
    const stale = try staleCount(t.allocator, text, language.standard_library.count);
    if (stale) |found| report("{s} says \"{s}\" modules; the table has {d}\n", .{ path, found, language.standard_library.count });
    try t.expectEqual(@as(?[]const u8, null), stale);
}

/// Require every standard module to have a heading in the standard library guide.
fn expectEveryModuleHasAHeading() !void {
    const guide = try readPage(t.allocator, "docs/standard-library.md");
    defer t.allocator.free(guide);
    for (language.standard_library.paths) |path| {
        const name = product.chopSource(path);
        var found = false;
        var lines = std.mem.splitScalar(u8, guide, '\n');
        while (lines.next()) |line| {
            if (!std.mem.startsWith(u8, line, "#")) continue;
            var words = std.mem.tokenizeAny(u8, line, "# `,()/");
            while (words.next()) |word| if (std.mem.eql(u8, word, name)) {
                found = true;
            };
        }
        if (!found) report("docs/standard-library.md has no heading for the module {s}\n", .{name});
        try t.expect(found);
    }
}

// spec: STDLIB-COUNT-1
test "every prose count of the standard modules is the table's count" {
    try t.expect(language.standard_library.count == language.standard_library.paths.len);
    try expectCountsAgree("docs/standard-library.md");
    try expectCountsAgree("docs/current-language.md");
    try expectCountsAgree("docs/python-syntax.md");
    try expectCountsAgree("src/features.json");
}

// spec: STDLIB-DICTS-PROBES-1
test "the dicts module ships with its three probes" {
    const text = language.standard_library.source("dicts.selka") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, text, "public func find[") != null);
    try t.expect(std.mem.indexOf(u8, text, "public func add[") != null);
    try t.expect(std.mem.indexOf(u8, text, "public func append_to[") != null);
}

// spec: STDLIB-ARGPARSE-1
test "the argparse module parses a command line through the embedded provider" {
    try fixture.run(t.allocator, "import argparse\n" ++
        "func main() -> int:\n" ++
        "    mut spec = argparse.new(\"tool\", \"A tool.\")\n" ++
        "    argparse.add_option_default(mut spec, \"times\", \"n\", \"N\", \"repeat\", \"2\")\n" ++
        "    argparse.add_positional(mut spec, \"WORD\", \"a word\")\n" ++
        "    match argparse.parse(spec, [\"-n\", \"40\", \"x\"]):\n" ++
        "        case Ok(parsed):\n" ++
        "            match argparse.get_int(parsed, \"times\"):\n" ++
        "                case Ok(times):\n" ++
        "                    return times + len(parsed.positionals) + 1\n" ++
        "                case Err(_):\n" ++
        "                    return 1\n" ++
        "        case Err(_):\n" ++
        "            return 2\n", 42);
}

// spec: STDLIB-LOGGING-1
test "the logging module writes a leveled event on a memory stream through the embedded provider" {
    try fixture.run(t.allocator, "import logging\n" ++
        "import streams\n" ++
        "func main() -> int:\n" ++
        "    const sink = streams.memory()\n" ++
        "    const log = logging.new(sink)\n" ++
        "    logging.debug(log, \"hidden\")\n" ++
        "    logging.warn(log, \"slow\", [logging.number(\"ms\", 31)])\n" ++
        "    if streams.text(sink) == \"WARN slow ms=31\\n\":\n" ++
        "        return 42\n" ++
        "    return 1\n", 42);
}

// spec: STDLIB-FLATE-1
test "the flate module decompresses a gzip member through the embedded provider" {
    try fixture.run(t.allocator, "import flate\n" ++
        "func main() -> int:\n" ++
        "    const packed = b\"\\x1f\\x8b\\x08\\x00\\x00\\x00\\x00\\x00\\x02\\xff\\xcbH\\xcd\\xc9\\xc9W\\xc8@'\\x01\\xe3Q=\\x8d\\x17\\x00\\x00\\x00\"\n" ++
        "    match flate.gunzip(packed, 1000):\n" ++
        "        case Ok(plain):\n" ++
        "            return len(plain) + 19\n" ++
        "        case Err(_):\n" ++
        "            return 1\n", 42);
}

// spec-case: STDLIB-COUNT-1
test "every standard module has a heading in the standard library guide" {
    try expectEveryModuleHasAHeading();
}

// spec-case: STDLIB-COUNT-1
test "a stale module count is found and the right one is not" {
    try t.expectEqualStrings("Ten", (try staleCount(t.allocator, "Ten modules ship inside the compiler", 23)).?);
    try t.expectEqualStrings("twenty-two", (try staleCount(t.allocator, "the twenty-two embedded modules that ship", 23)).?);
    try t.expectEqualStrings("22", (try staleCount(t.allocator, "22 embedded Selka modules, including lists", 23)).?);
    try t.expectEqual(@as(?[]const u8, null), try staleCount(t.allocator, "Twenty-three modules ship; the twenty-three embedded modules; two modules import each other", 23));
}

/// A program that imports every standard module and does nothing else.
fn everyModule(allocator: std.mem.Allocator) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (language.standard_library.paths) |file| try text.print(allocator, "import {s}\n", .{product.chopSource(file)});
    try text.appendSlice(allocator, "\nfunc main() -> int:\n    return 0\n");
    return text.items;
}

test "the standard library's own sources draw no W13 refusal: they are written in the function forms (W13-S3, W13-S5)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const checked = try fixture.check(allocator, try everyModule(allocator));
    try checked.expectAccepted();
    var retiring: usize = 0;
    for (checked.diagnostics) |item| {
        retiring += @intFromBool(std.mem.eql(u8, item.code, "E_METHOD_REMOVED") or std.mem.eql(u8, item.code, "E_REMOVED_SPELLING") or std.mem.eql(u8, item.code, "E_INTERNAL_NAME"));
    }
    // The `process` module's own calls of its channels (`process_control`) are what the channels are for: none is refused.
    try t.expectEqual(@as(usize, 0), retiring);
}

test "a text trim is the native trim, whose views have the trimmed lengths (W13-S3)" {
    const head = "import strings\n\nfunc eat(own text: str) -> int:\n    return len(text)\n\n\nfunc main() -> int:\n    mut s = \"  ab \"\n";
    // Read with its text held: accepted, and the views have the trimmed lengths.
    try fixture.run(t.allocator, head ++ "    const view = strings.strip(s)\n    return len(view) * 100 + len(strings.lstrip(s)) * 10 + len(strings.rstrip(s))\n", 234);
}

test "a standard module's own bare call of its home is the operation, with no instance of the home (W13-S3)" {
    // `sets.include`'s body calls `add(mut values, copy(value))`: the module's own spelling of the home, which a module
    // cannot qualify. It is the set operation, as `sets.add(...)` in a program is, so no `sets::add[str]` is checked
    // again in every program that reaches `sets.include`.
    const text = "import sets\n\nfunc main() -> int:\n    mut s: set[str] = set()\n    sets.include(mut s, \"a\")\n    sets.include(mut s, \"a\")\n    return len(s)\n";
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, text);
    defer program.deinit();
    var homes: usize = 0;
    for (program.compilation.program.?.functions) |function| homes += @intFromBool(std.mem.startsWith(u8, function.name, "sets::add"));
    try t.expectEqual(@as(usize, 0), homes);
    try fixture.run(t.allocator, text, 1);
}

test "a bytes read takes a byte buffer's slice and hints its needle from the buffer, as the methods do (W13-S3)" {
    // FR25's finding: `bytes.find(buf[0:3], b"z")`, the rewrite of `buf[0:3].find(b"z")`, typed its literal as `bytes`
    // against a buffer receiver; and `bytes.rfind(buf, b"d")`, `index` and `rindex` did so on a named buffer too.
    try fixture.run(t.allocator,
        \\import buffers
        \\import bytes
        \\
        \\func main() -> int:
        \\    mut buf = buffers.empty()
        \\    buffers.append(mut buf, b"abc def")
        \\    const slices = bytes.find(buf[0:3], b"z") + 10 * len(bytes.words(buf[0:7])) + 100 * bytes.count(buf[1:7], b"c")
        \\    return slices + 1000 * bytes.rfind(buf[:], b"d") + 10000 * bytes.index(buf, b"d") + 100000 * bytes.rindex(buf, b"c")
    , 244119);
}

test "the math module's float twins are refused for the prelude's forms, and the message says a zero keeps its sign (W13-S5)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const checked = try fixture.check(allocator,
        \\import math
        \\
        \\func main() -> int:
        \\    return int(math.round(2.5) + math.round(-0.5))
        \\
    );
    try t.expect(!checked.passed);
    var refused: usize = 0;
    for (checked.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "E_REMOVED_SPELLING")) continue;
        refused += 1;
        try t.expect(std.mem.indexOf(u8, item.message, "`math.round` is a second spelling and was removed; write `round(") != null);
        try t.expect(std.mem.indexOf(u8, item.message, "a result of zero keeps its sign") != null);
        try t.expectEqualStrings("round", item.provenance.fix.?.edit.text);
    }
    try t.expectEqual(@as(usize, 2), refused);
}

// FR34: a method call on a value without methods is told the one module whose function of that name takes the receiver's type first.
test "the library names the one module that declares a function of a name for a first parameter type (FR34)" {
    try t.expectEqualStrings("time", language.standard_library.declaringFirstParameter("now", "Clock").?);
    try t.expectEqualStrings("time", language.standard_library.declaringFirstParameter("monotonic", "Clock").?);
    try t.expectEqualStrings("streams", language.standard_library.declaringFirstParameter("text", "Stream").?);
    try t.expectEqualStrings("random", language.standard_library.declaringFirstParameter("from_entropy", "Entropy").?);
    // Two modules declare `decode` of `bytes`; a `mut` first parameter is written differently at the call; the type must match.
    try t.expect(language.standard_library.declaringFirstParameter("decode", "bytes") == null);
    try t.expect(language.standard_library.declaringFirstParameter("add", "set[T]") == null);
    try t.expect(language.standard_library.declaringFirstParameter("now", "Stream") == null);
    try t.expect(language.standard_library.declaringFirstParameter("no_such_function", "Clock") == null);
}

// A capability's own module answers its method even when another module declares the name for the type too.
test "a capability's own module answers first when another module declares the same function for the type" {
    // `process.run` and `buildkit.run` both take a `Process` first, so the one-module search has no answer.
    try t.expect(language.standard_library.declaringFirstParameter("run", "Process") == null);
    try t.expectEqualStrings("process", language.standard_library.declaringFirstParameterHome("run", "Process", "process").?);
    // A home that does not declare it falls back to the one-module search.
    try t.expectEqualStrings("time", language.standard_library.declaringFirstParameterHome("now", "Clock", "process").?);
    try t.expect(language.standard_library.declaringFirstParameterHome("run", "Process", "time") == null);
}
