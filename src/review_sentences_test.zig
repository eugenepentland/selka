//! Pure tests for the review sentences: one test per row of the plan's sentence table,
//! the three real cases from the prototype, and the empty result for an unchanged declaration.
const std = @import("std");
const t = std.testing;
const types = @import("overview_types.zig");
const language = @import("compiler.zig");

const sentences = language.review_sentences;
const Declaration = types.Declaration;
const Details = types.Details;
const Field = types.Field;
const Case = types.Case;
const Function = types.Function;

const no_function: Function = .{ .writes = &.{}, .authority = &.{}, .tests = &.{}, .fails = null, .hole = false, .examples = 0, .waiver = null };

/// A declaration of `kind` with the given interface block, docstring and facts.
fn declare(kind: []const u8, signature: []const u8, doc: []const u8, details: Details) Declaration {
    return .{ .name = "ports::serve_on", .kind = kind, .signature = signature, .doc = doc, .details = details, .decisions = &.{} };
}

/// A public function with the given capability parameters and failure type.
fn function(signature: []const u8, doc: []const u8, authority: []const types.Parameter, fails: ?[]const u8) Declaration {
    var facts = no_function;
    facts.authority = authority;
    facts.fails = fails;
    return declare("function", signature, doc, .{ .function = facts });
}

/// A public function with no capability parameter, no failure and no docstring.
fn plain(signature: []const u8) Declaration {
    return function(signature, "", &.{}, null);
}

fn record(signature: []const u8, doc: []const u8, fields: []const Field) Declaration {
    return declare("type", signature, doc, .{ .fields = fields });
}

fn enumeration(signature: []const u8, doc: []const u8, cases: []const Case) Declaration {
    return declare("type", signature, doc, .{ .cases = cases });
}

fn constant(signature: []const u8) Declaration {
    return declare("constant", signature, "", .{});
}

fn field(name: []const u8, ty: []const u8, default: ?[]const u8) Field {
    return .{ .name = name, .type = ty, .default = default };
}

fn variant(name: []const u8, fields: []const Field) Case {
    return .{ .name = name, .fields = fields };
}

/// Checks that `got` holds exactly the one sentence `expected`.
fn expectOnly(expected: []const u8, got: []const []const u8) !void {
    try t.expectEqual(@as(usize, 1), got.len);
    try t.expectEqualStrings(expected, got[0]);
}

/// Checks that `got` holds exactly the sentences `expected`, in order.
fn expectAll(expected: []const []const u8, got: []const []const u8) !void {
    try t.expectEqual(expected.len, got.len);
    for (expected, got) |want, have| try t.expectEqualStrings(want, have);
}

test "review sentence new function with a docstring" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const decl = function("public func status(kind: RefusalKind) -> int", "The HTTP status a refusal of `kind` is answered with.\n\nMore detail.", &.{}, null);
    const got = try sentences.added(arena.allocator(), decl);
    try expectOnly("New function `status(kind: RefusalKind) -> int`. The HTTP status a refusal of `kind` is answered with.", got);
}

test "review sentence new function without a docstring" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.added(arena.allocator(), plain("public func default_idle_ms() -> int"));
    try expectOnly("New function `default_idle_ms() -> int`.", got);
}

test "review sentence new function drops the contract lines above it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.added(arena.allocator(), plain("@ensures(result >= 0)\npublic func value(named extra: int = 0) -> int"));
    try expectOnly("New function `value(named extra: int = 0) -> int`.", got);
}

test "review sentence new record with fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const fields = [_]Field{
        field("id", "int", null),
        field("input", "bytes", null),
        field("output", "bytes", null),
        field("sent", "int", null),
        field("close", "bool", null),
        field("eof", "bool", null),
        field("done", "bool", null),
        field("interest", "int", null),
    };
    const got = try sentences.added(arena.allocator(), record("public record Conn:", "", &fields));
    try expectOnly("New record `Conn` with fields `id: int`, `input: bytes`, `output: bytes`, `sent: int`, `close: bool`, `eof: bool`, `done: bool`, `interest: int`.", got);
}

test "review sentence new record without fields" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.added(arena.allocator(), record("public record Marker:", "", &.{}));
    try expectOnly("New record `Marker`.", got);
}

test "review sentence new enum with cases and a docstring" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const cases = [_]Case{ variant("bad_request", &.{}), variant("too_large", &.{}) };
    const got = try sentences.added(arena.allocator(), enumeration("public enum RefusalKind:", "Why a request was refused.", &cases));
    try expectOnly("New enum `RefusalKind` with cases `bad_request`, `too_large`. Why a request was refused.", got);
}

test "review sentence new constant" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.added(arena.allocator(), constant("public const SLOTS: int = 1024"));
    try expectOnly("New `const SLOTS: int = 1024`.", got);
}

test "review sentence removed function and removed record" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const function_row = try sentences.removed(arena.allocator(), plain("public func serve(port: int) -> int"));
    try expectOnly("Removed `func serve(port: int) -> int`.", function_row);
    const record_row = try sentences.removed(arena.allocator(), record("public record Conn:\n    id: int", "", &.{}));
    try expectOnly("Removed `record Conn:`.", record_row);
}

test "review sentence made public" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.nowPublic(arena.allocator(), plain("public func serve(port: int) -> int"));
    try expectOnly("Now public: New function `serve(port: int) -> int`.", got);
}

test "review sentence made private" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const got = try sentences.noLongerPublic(arena.allocator(), plain("public func serve(port: int) -> int"));
    try expectOnly("No longer public: `func serve(port: int) -> int`.", got);
}

test "review sentence parameter added with a default" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old = plain("public func serve(port: int) -> int");
    const new = plain("public func serve(port: int, log: bool = false) -> int");
    const got = try sentences.changed(arena.allocator(), old, new);
    try expectOnly("now takes `log: bool` (defaults to `false`)", got);
}

test "review sentence parameter removed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old = plain("public func serve(port: int, log: bool) -> int");
    const new = plain("public func serve(port: int) -> int");
    const got = try sentences.changed(arena.allocator(), old, new);
    try expectOnly("no longer takes `log`", got);
}

test "review sentence parameter type changed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old = plain("public func serve(port: int) -> int");
    const new = plain("public func serve(port: u16) -> int");
    const got = try sentences.changed(arena.allocator(), old, new);
    try expectOnly("takes `port` as `u16` instead of `int`", got);
}

test "review sentence mut added and removed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const plain_state = plain("public func apply(state: Conn) -> Unit");
    const mut_state = plain("public func apply(mut state: Conn) -> Unit");
    const added_mut = try sentences.changed(arena.allocator(), plain_state, mut_state);
    try expectOnly("now changes the caller's `state`", added_mut);
    const removed_mut = try sentences.changed(arena.allocator(), mut_state, plain_state);
    try expectOnly("no longer changes the caller's `state`", removed_mut);
}

test "review sentence return type changed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const size_old = plain("public func size(x: int) -> int");
    const size_new = plain("public func size(x: int) -> bool");
    const size_got = try sentences.changed(arena.allocator(), size_old, size_new);
    try expectOnly("returns `bool` instead of `int`", size_got);
    const tick_old = plain("public func tick(x: int)");
    const tick_new = plain("public func tick(x: int) -> int");
    const tick_got = try sentences.changed(arena.allocator(), tick_old, tick_new);
    try expectOnly("returns `int` instead of `Unit`", tick_got);
}

test "review sentence failure gained, lost and changed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const infallible = function("public func load(path: str) -> str", "", &.{}, null);
    const io_failing = function("public func load(path: str) -> str fails IoError", "", &.{}, "IoError");
    const parse_failing = function("public func load(path: str) -> str fails ParseError", "", &.{}, "ParseError");
    const gained = try sentences.changed(arena.allocator(), infallible, io_failing);
    try expectOnly("can now fail with `IoError`", gained);
    const lost = try sentences.changed(arena.allocator(), io_failing, infallible);
    try expectOnly("can no longer fail", lost);
    const retyped = try sentences.changed(arena.allocator(), io_failing, parse_failing);
    try expectOnly("fails with `ParseError` instead of `IoError`", retyped);
}

test "review sentence capability gained and lost, sorted by type" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const filesystem = [_]types.Parameter{.{ .name = "fs", .type = "Filesystem" }};
    const three = [_]types.Parameter{
        .{ .name = "fs", .type = "Filesystem" },
        .{ .name = "scoped", .type = "Network" },
        .{ .name = "clock", .type = "Clock" },
    };
    const signature = "public func run(fs: Filesystem) -> int";
    const grown = try sentences.changed(arena.allocator(), function(signature, "", &filesystem, null), function(signature, "", &three, null));
    try expectAll(&.{ "now needs `Clock`", "now needs `Network`" }, grown);
    const shrunk = try sentences.changed(arena.allocator(), function(signature, "", &three, null), function(signature, "", &filesystem, null));
    try expectAll(&.{ "no longer needs `Clock`", "no longer needs `Network`" }, shrunk);
}

test "review sentence contract and invariant gained and lost" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const bare = plain("public func size(x: int) -> int");
    var ensured = bare;
    ensured.details.contracts = &.{"@ensures(result >= 0)"};
    const gained = try sentences.changed(arena.allocator(), bare, ensured);
    try expectOnly("gained contract `@ensures(result >= 0)`", gained);
    const lost = try sentences.changed(arena.allocator(), ensured, bare);
    try expectOnly("lost contract `@ensures(result >= 0)`", lost);
    const counted = declare("type", "public record Box:", "", .{});
    var bounded = counted;
    bounded.details.contracts = &.{"@invariant(count >= 0)"};
    const invariant = try sentences.changed(arena.allocator(), counted, bounded);
    try expectOnly("gained invariant `@invariant(count >= 0)`", invariant);
}

test "review sentence record field gained, lost, retyped and defaulted" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const id_only = [_]Field{field("id", "int", null)};
    const with_cap = [_]Field{ field("id", "int", null), field("cap", "int", "4") };
    const with_name = [_]Field{ field("id", "int", null), field("name", "str", null) };
    const id_u64 = [_]Field{field("id", "u64", null)};
    const cap_eight = [_]Field{field("cap", "int", "8")};
    const cap_four = [_]Field{field("cap", "int", "4")};
    const gained = try sentences.changed(arena.allocator(), record("public record Box:", "", &id_only), record("public record Box:", "", &with_cap));
    try expectOnly("gained field `cap: int = 4`", gained);
    const lost = try sentences.changed(arena.allocator(), record("public record Box:", "", &with_name), record("public record Box:", "", &id_only));
    try expectOnly("lost field `name`", lost);
    const retyped = try sentences.changed(arena.allocator(), record("public record Box:", "", &id_only), record("public record Box:", "", &id_u64));
    try expectOnly("field `id` is `u64` instead of `int`", retyped);
    const defaulted = try sentences.changed(arena.allocator(), record("public record Box:", "", &cap_four), record("public record Box:", "", &cap_eight));
    try expectOnly("field `cap` defaults to `8` instead of `4`", defaulted);
}

test "review sentence enum case gained and lost" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const busy_fields = [_]Field{field("n", "int", null)};
    const before = [_]Case{ variant("Idle", &.{}), variant("Busy", &busy_fields) };
    const after = [_]Case{ variant("Idle", &.{}), variant("Busy", &busy_fields), variant("Done", &.{}) };
    const gained = try sentences.changed(arena.allocator(), enumeration("public enum State:", "", &before), enumeration("public enum State:", "", &after));
    try expectOnly("gained case `Done`", gained);
    const lost = try sentences.changed(arena.allocator(), enumeration("public enum State:", "", &after), enumeration("public enum State:", "", &before));
    try expectOnly("lost case `Done`", lost);
}

test "review sentence real case: refusal kind replaces status" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old_reject = [_]Field{ field("status", "int", null), field("text", "str", null) };
    const new_reject = [_]Field{ field("kind", "RefusalKind", null), field("text", "str", null) };
    const ready = [_]Field{ field("request", "http.Request", null), field("consumed", "int", null) };
    const old_cases = [_]Case{ variant("NeedMore", &.{}), variant("Reject", &old_reject), variant("Ready", &ready) };
    const new_cases = [_]Case{ variant("NeedMore", &.{}), variant("Reject", &new_reject), variant("Ready", &ready) };
    const got = try sentences.changed(arena.allocator(), enumeration("public enum Head:", "", &old_cases), enumeration("public enum Head:", "", &new_cases));
    try expectOnly("case `Reject` carries `kind: RefusalKind` instead of `status: int`", got);
}

test "review sentence real case: serve gains blocking and idle_ms" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old_serve = [_]Field{ field("root", "str", null), field("port", "int", null), field("log", "bool", null) };
    const new_serve = [_]Field{ field("root", "str", null), field("port", "int", null), field("log", "bool", null), field("blocking", "bool", null), field("idle_ms", "int", null) };
    const old_cases = [_]Case{variant("Serve", &old_serve)};
    const new_cases = [_]Case{variant("Serve", &new_serve)};
    const got = try sentences.changed(arena.allocator(), enumeration("public enum Command:", "", &old_cases), enumeration("public enum Command:", "", &new_cases));
    try expectOnly("case `Serve` gained `blocking: bool`, `idle_ms: int`", got);
}

test "review sentence real case: serve_on takes a launch mode" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const authority = [_]types.Parameter{.{ .name = "net", .type = "Network" }};
    const old = function("public func serve_on(net: Network, err: Stream) -> int", "", &authority, null);
    const new = function("public func serve_on(net: Network, err: Stream, mode: launch.Mode) -> int", "", &authority, null);
    const got = try sentences.changed(arena.allocator(), old, new);
    try expectOnly("now takes `mode: launch.Mode`", got);
}

test "review sentence enum case field retyped" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old_fields = [_]Field{field("consumed", "int", null)};
    const new_fields = [_]Field{field("consumed", "u64", null)};
    const old_cases = [_]Case{variant("Ready", &old_fields)};
    const new_cases = [_]Case{variant("Ready", &new_fields)};
    const got = try sentences.changed(arena.allocator(), enumeration("public enum Head:", "", &old_cases), enumeration("public enum Head:", "", &new_cases));
    try expectOnly("case `Ready` field `consumed` is `u64` instead of `int`", got);
}

test "review sentence constant value and type" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const three = constant("public const LIMIT: int = 3");
    const five = constant("public const LIMIT: int = 5");
    const value_got = try sentences.changed(arena.allocator(), three, five);
    try expectOnly("`LIMIT` is now `5` (was `3`)", value_got);
    const wide = constant("public const LIMIT: u64 = 5");
    const type_got = try sentences.changed(arena.allocator(), five, wide);
    try expectOnly("`LIMIT` is now typed `u64` (was `int`)", type_got);
}

test "review sentence docstring shows its first sentence only when it counts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const old = function("public func f(a: int) -> int", "Adds one.", &.{}, null);
    const with_param = function("public func f(a: int, b: int) -> int", "Adds two numbers.", &.{}, null);
    const with_param_only = try sentences.changed(arena.allocator(), old, function("public func f(a: int, b: int) -> int", "Adds one.", &.{}, null));
    try expectOnly("now takes `b: int`", with_param_only);
    const with_both = try sentences.changed(arena.allocator(), old, with_param);
    try expectAll(&.{ "now takes `b: int`", "docstring now says: Adds two numbers." }, with_both);
    const later_paragraph = function("public func f(a: int) -> int", "Adds one.\n\nNow with a note.", &.{}, null);
    const quiet = try sentences.changed(arena.allocator(), old, later_paragraph);
    try t.expectEqual(@as(usize, 0), quiet.len);
    const reworded = function("public func f(a: int) -> int", "Adds two.", &.{}, null);
    const alone = try sentences.changed(arena.allocator(), old, reworded);
    try expectOnly("docstring now says: Adds two.", alone);
}

test "review sentence an unchanged declaration has no sentences" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const decl = function("public func serve(port: int) -> int", "Serves.", &.{}, null);
    const got = try sentences.changed(arena.allocator(), decl, decl);
    try t.expectEqual(@as(usize, 0), got.len);
}

test "review sentence fallback is the declaration changed sentence" {
    try t.expectEqualStrings("declaration changed", sentences.fallback);
}
