//! Friction records through the public CLI: every command that renders a diagnostic
//! records its code, whichever layer rendered it (FRICTION-LOG-4).
const std = @import("std");
const testing = std.testing;

/// An element read returned as an owned `str`, which only the ownership checker rejects.
const borrowed_element =
    // migrate-embedded: skip intentional FRICTION-LOG-4 ownership refusal input
    \\func first(xs: str[]) -> str:
    \\    mut a = xs[0]
    \\    a += "y"
    \\    return a
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, first(["x"]))
    \\    return 0
    \\
;

/// An import the module loader cannot satisfy, which no checker pass ever sees.
const missing_import =
    \\import nothere
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

/// What one compiler run left behind: its exit status and the friction log text.
const Outcome = struct {
    status: u8,
    stderr: []const u8,
    log: []const u8,

    fn deinit(self: Outcome) void {
        testing.allocator.free(self.stderr);
        testing.allocator.free(self.log);
    }
};

/// Run `selka ARGS` over `main.selka` holding `source`, with `SELKA_FRICTION_LOG`
/// naming `friction.jsonl` beside it, and return what the run printed and what
/// `log_name` held afterwards. A run that wrote no such log yields an empty `log`.
fn recorded(source: []const u8, args: []const []const u8, log_name: []const u8) !Outcome {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "main.selka", .data = source });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, @import("test_paths").corePath(), testing.allocator);
    defer testing.allocator.free(compiler);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(testing.allocator);
    try argv.append(testing.allocator, compiler);
    try argv.appendSlice(testing.allocator, args);
    var environment = try @import("test_paths").privateEnvironment(testing.allocator);
    defer environment.deinit();
    try environment.put("SELKA_FRICTION_LOG", "friction.jsonl");
    const result = try std.process.run(testing.allocator, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = temp.dir }, .environ_map = &environment });
    defer testing.allocator.free(result.stdout);
    const log = temp.dir.readFileAlloc(testing.io, log_name, testing.allocator, .limited(1 << 20)) catch try testing.allocator.dupe(u8, "");
    return .{ .status = switch (result.term) {
        .exited => |status| status,
        else => 255,
    }, .stderr = result.stderr, .log = log };
}

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// Run `args` over `source`, expecting one failing record that names `command` and `code`.
fn expectRecord(source: []const u8, args: []const []const u8, command: []const u8, code: []const u8) !void {
    const outcome = try recorded(source, args, "friction.jsonl");
    defer outcome.deinit();
    try testing.expectEqual(@as(u8, 1), outcome.status);
    try testing.expect(contains(outcome.stderr, code));
    const command_field = try std.fmt.allocPrint(testing.allocator, "\"command\":\"{s}\"", .{command});
    defer testing.allocator.free(command_field);
    const code_field = try std.fmt.allocPrint(testing.allocator, "\"code\":\"{s}\"", .{code});
    defer testing.allocator.free(code_field);
    try testing.expect(contains(outcome.log, command_field));
    try testing.expect(contains(outcome.log, code_field));
    try testing.expect(contains(outcome.log, "\"status\":1"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, outcome.log, "\n"));
}

// spec: FRICTION-LOG-4
test "friction record: check names an ownership diagnostic the checker never lists" {
    try expectRecord(borrowed_element, &.{ "check", "main.selka", "--no-cache" }, "check", "E_SINGLE_OWNER_BORROW");
    try expectRecord(borrowed_element, &.{ "check-project", "main.selka", "--no-cache" }, "check-project", "E_SINGLE_OWNER_BORROW");
}

// spec-case: FRICTION-LOG-4
test "friction record: build, run and test carry the diagnostics they render" {
    try expectRecord(borrowed_element, &.{ "build", "main.selka", "-o", "out", "--no-cache" }, "build", "E_SINGLE_OWNER_BORROW");
    try expectRecord(borrowed_element, &.{ "run", "main.selka", "--no-cache" }, "run", "E_SINGLE_OWNER_BORROW");
    try expectRecord(borrowed_element, &.{ "test", "main.selka", "--no-cache" }, "test", "E_SINGLE_OWNER_BORROW");
}

// spec-case: FRICTION-LOG-4
test "friction record: a module the loader cannot read appears though the checker never ran" {
    try expectRecord(missing_import, &.{ "check-project", "main.selka", "--no-cache" }, "check-project", "E_MODULE_READ");
    try expectRecord(missing_import, &.{ "run", "main.selka", "--no-cache" }, "run", "E_MODULE_READ");
}

// spec-case: FRICTION-LOG-4
test "friction record: the flag names a build's log and a repeated flag is refused" {
    const flagged = try recorded(borrowed_element, &.{ "build", "main.selka", "-o", "out", "--no-cache", "--friction-log=flagged.jsonl" }, "flagged.jsonl");
    defer flagged.deinit();
    try testing.expectEqual(@as(u8, 1), flagged.status);
    try testing.expect(contains(flagged.stderr, "E_SINGLE_OWNER_BORROW"));
    try testing.expect(contains(flagged.log, "\"code\":\"E_SINGLE_OWNER_BORROW\""));
    const twice = try recorded(borrowed_element, &.{ "run", "main.selka", "--friction-log=a.jsonl", "--friction-log=b.jsonl" }, "a.jsonl");
    defer twice.deinit();
    try testing.expectEqual(@as(u8, 2), twice.status);
    try testing.expect(contains(twice.stderr, "--friction-log=PATH takes one non-empty path"));
    try testing.expectEqualStrings("", twice.log);
}

// spec-case: FRICTION-LOG-4
test "friction record: a usage error writes nothing and a clean program lists nothing" {
    const usage = try recorded(borrowed_element, &.{"run"}, "friction.jsonl");
    defer usage.deinit();
    try testing.expectEqual(@as(u8, 2), usage.status);
    try testing.expectEqualStrings("", usage.log);
    const clean = try recorded("func main() -> int:\n    return 0\n", &.{ "check", "main.selka", "--no-cache" }, "friction.jsonl");
    defer clean.deinit();
    try testing.expectEqual(@as(u8, 0), clean.status);
    try testing.expect(contains(clean.log, "\"diagnostics\":[]"));
    try testing.expect(contains(clean.log, "\"status\":0"));
}
