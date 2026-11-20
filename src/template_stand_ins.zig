//! The stand-in count of W3, step 1: a developer measure of what judging a generic body at its declaration would refuse. Today
//! `check` gives a template nothing instantiates one representative instance, every type parameter `int`
//! (`sema_specialize.probeTemplates`, D-G-3). With the count switched on (`diagnostic.Probes.every`, set only by the developer
//! command `selka template-stand-ins`), sema instead tries every template, the standard library's and the instantiated ones
//! included, with one stand-in type per kind of argument the ownership checker treats differently, and records here what each
//! choice became: an instance for the ownership pass, a body its own check refused, or a skip with its reason. The command then
//! judges the instances and prints one line per template and choice. Nothing is refused: the switch is off for every other command.
const std = @import("std");
const source = @import("source.zig");

/// The kinds of type argument a template is tried with: a scalar, a text, a plain record with a managed field, a list, and a
/// move-only type (a resource record) where the bound allows one.
pub const Kind = enum {
    int,
    text,
    record,
    list,
    move_only,

    /// The word the report prints for this kind.
    pub fn word(self: Kind) []const u8 {
        return switch (self) {
            .int => "int",
            .text => "str",
            .record => "record",
            .list => "list",
            .move_only => "move-only",
        };
    }
};

/// How a refusal at a declaration names a kind: "this body is refused when `T` is a text".
pub fn phrase(kind: Kind) []const u8 {
    return switch (kind) {
        .int => "a scalar (or a record of scalars)",
        .text => "a text",
        .record => "a record with a managed field",
        .list => "a list",
        .move_only => "a resource",
    };
}

/// The kinds `check` judges a template's body with at its declaration: no type parameter admits a resource (each carries an
/// implicit `copy` requirement), so the move-only kind is never tried.
pub const declaration_kinds = [_]Kind{ .text, .record, .list };

/// The choice of kinds `index` names for `check`'s judgment of a template of `count` type parameters (W3 step 2), written into
/// `out`, or null past the last: every parameter `int` first, then each parameter alone given each managed kind of
/// `declaration_kinds` with the others `int`, then, for two or more parameters, every parameter the same managed kind. Mixed
/// managed kinds (`str` with `int[]`) are not tried; a real instance still judges them.
pub fn declarationChoice(count: usize, index: usize, out: []Kind) ?[]const Kind {
    std.debug.assert(out.len == count);
    std.debug.assert(count != 0);
    @memset(out, .int);
    if (index == 0) return out;
    const varied = index - 1;
    const single = count * declaration_kinds.len;
    if (varied < single) {
        out[varied / declaration_kinds.len] = declaration_kinds[varied % declaration_kinds.len];
        return out;
    }
    if (count < 2 or varied - single >= declaration_kinds.len) return null;
    @memset(out, declaration_kinds[varied - single]);
    return out;
}

/// One way a template's body is refused at its declaration: the type parameters that held a managed kind (a bit per parameter,
/// all of them for the `int` instance) and the kinds that refused (a bit per `Kind`).
pub const Condition = struct { parameters: u16, kinds: u8 };

/// Add `kind` for the parameters `parameters` to `conditions`, merging it into a condition of the same parameters.
pub fn addCondition(allocator: std.mem.Allocator, conditions: *std.ArrayList(Condition), parameters: u16, kind: Kind) error{OutOfMemory}!void {
    const bit: u8 = @as(u8, 1) << @backingInt(kind);
    for (conditions.items) |*condition| if (condition.parameters == parameters) {
        condition.kinds |= bit;
        return;
    };
    try conditions.append(allocator, .{ .parameters = parameters, .kinds = bit });
}

/// The message of a refusal at a declaration: "the body of `name` is refused when `T` is a text, a record with a managed field
/// or a list", one clause per condition, joined by "; or when". `names` are the template's type parameter names.
pub fn describe(allocator: std.mem.Allocator, name: []const u8, names: []const []const u8, conditions: []const Condition) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(allocator, "the body of `{s}` is refused when ", .{name});
    var written: usize = 0;
    for (conditions) |given| {
        // A kind a narrower condition already names (every parameter a text, when one of them a text refuses) is left out.
        var condition = given;
        for (conditions) |other| {
            if (other.parameters != given.parameters and other.parameters & given.parameters == other.parameters) condition.kinds &= ~other.kinds;
        }
        if (condition.kinds == 0) continue;
        if (written != 0) try out.appendSlice(allocator, "; or when ");
        written += 1;
        var named: usize = 0;
        for (names, 0..) |parameter, position| if (position < 16 and condition.parameters & (@as(u16, 1) << @intCast(position)) != 0) {
            if (named != 0) try out.appendSlice(allocator, " and ");
            try out.print(allocator, "`{s}`", .{parameter});
            named += 1;
        };
        if (named == 0) try out.appendSlice(allocator, "its type parameters");
        const every_kind: u8 = 0b1111;
        if (condition.kinds & every_kind == every_kind) {
            try out.appendSlice(allocator, if (named > 1) " are each any kind of type, a scalar included" else " is any kind of type, a scalar included");
            continue;
        }
        try out.appendSlice(allocator, if (named > 1) " are each " else " is ");
        var listed: usize = 0;
        var total: usize = 0;
        for (kinds) |kind| if (condition.kinds & (@as(u8, 1) << @backingInt(kind)) != 0) {
            total += 1;
        };
        for (kinds) |kind| if (condition.kinds & (@as(u8, 1) << @backingInt(kind)) != 0) {
            if (listed != 0) try out.appendSlice(allocator, if (listed + 1 == total) " or " else ", ");
            try out.appendSlice(allocator, phrase(kind));
            listed += 1;
        };
    }
    try out.appendSlice(allocator, "; a generic body is judged at its declaration for every kind of type argument its bounds admit");
    return out.toOwnedSlice(allocator);
}

/// The type parameter names of the declaration whose name ends at `name_end` in `bytes`: the identifiers of the bracketed list
/// after the name (`[T, U: copy, const N: u64]` gives `T`, `U`, `N`), allocated in `allocator`; empty when there is none.
pub fn parameterNames(allocator: std.mem.Allocator, bytes: []const u8, name_end: usize) error{OutOfMemory}![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    if (name_end >= bytes.len or bytes[name_end] != '[') return names.toOwnedSlice(allocator);
    var at = name_end + 1;
    var depth: usize = 0;
    var start = at;
    while (at < bytes.len) : (at += 1) {
        const byte = bytes[at];
        if (byte == '[' or byte == '(') depth += 1;
        if ((byte == ']' or byte == ')') and depth > 0) {
            depth -= 1;
            continue;
        }
        if (depth == 0 and (byte == ',' or byte == ']')) {
            try names.append(allocator, identifier(bytes[start..at]));
            start = at + 1;
            if (byte == ']') break;
        }
    }
    return names.toOwnedSlice(allocator);
}

/// Whether every type parameter of the declaration whose name ends at `name_end` admits `copy(...)` of its values: one with no
/// bound (a parameter defaults to `copy`), or a bound that names `copy`, `equality` or `integer` (each implies `copy`). A
/// `copy(...)` repair of a generic body is certain only then: `T: storable` alone refuses `copy(value)`.
pub fn parametersCopy(bytes: []const u8, name_end: usize) bool {
    if (name_end >= bytes.len or bytes[name_end] != '[') return true;
    var at = name_end + 1;
    var depth: usize = 0;
    var start = at;
    while (at < bytes.len) : (at += 1) {
        const byte = bytes[at];
        if (byte == '[' or byte == '(') depth += 1;
        if ((byte == ']' or byte == ')') and depth > 0) {
            depth -= 1;
            continue;
        }
        if (depth == 0 and (byte == ',' or byte == ']')) {
            const item = bytes[start..at];
            if (std.mem.indexOfScalar(u8, item, ':')) |colon| {
                const bound = item[colon + 1 ..];
                const constant = std.mem.startsWith(u8, std.mem.trim(u8, item, " "), "const ");
                const copies = std.mem.indexOf(u8, bound, "copy") != null or std.mem.indexOf(u8, bound, "equality") != null or
                    std.mem.indexOf(u8, bound, "integer") != null;
                if (!constant and !copies) return false;
            }
            start = at + 1;
            if (byte == ']') break;
        }
    }
    return true;
}

fn identifier(item: []const u8) []const u8 {
    var text = std.mem.trim(u8, item, " \t\r\n");
    if (std.mem.startsWith(u8, text, "const ")) text = std.mem.trimStart(u8, text["const ".len..], " ");
    var end: usize = 0;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
    return text[0..end];
}

/// The dependency digest a template's judgment at its declaration is proven under (W3 step 2): the template's own dependency
/// context (what its body and signature name, and the front end's contracts, the compiler's identity among them) folded with
/// the judgment's rule: the stand-in kinds and how choices are made. A proof of the judgment is held under the template's
/// stable key, this digest and its region digest (`ownership_proof_facts.receiptDigest`), so a change to any of them, or to
/// this rule (bump `judgment_rule`), judges the template again.
pub fn judgmentContext(context: [32]u8) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(judgment_rule);
    state.update("\x00");
    for (declaration_kinds) |kind| {
        state.update(kind.word());
        state.update("\x00");
    }
    state.update(&context);
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

/// The version of the judgment's rule that `judgmentContext` folds: the stand-in types, the choices of `declarationChoice` and
/// what a refusal of one means.
pub const judgment_rule = "selka-template-judgment-v1: int; each parameter alone str, tuple[str, int], int[]; uniform for two or more";

/// The kinds every template is tried with, in report order.
pub const kinds = [_]Kind{ .int, .text, .record, .list, .move_only };

/// A template with at most this many type parameters is tried with every combination of kinds; one with more is tried with
/// every parameter the same kind and with each parameter alone given each other kind, the rest `int`.
pub const full_product_limit = 2;

/// The choice of kinds `index` names for a template of `count` type parameters, written into `out` (length `count`), or null past
/// the last choice. The first `kinds.len` choices give every parameter the same kind; a template with more parameters than
/// `full_product_limit` then varies one parameter at a time, and a smaller one walks the rest of the full product.
pub fn choice(count: usize, index: usize, out: []Kind) ?[]const Kind {
    std.debug.assert(out.len == count);
    std.debug.assert(count != 0);
    if (index < kinds.len) {
        @memset(out, kinds[index]);
        return out;
    }
    if (count <= full_product_limit) {
        // The full product in base `kinds.len`, skipping the uniform choices the first `kinds.len` indices gave.
        var total: usize = 1;
        for (0..count) |_| total *= kinds.len;
        var seen: usize = kinds.len;
        var code: usize = 0;
        while (code < total) : (code += 1) {
            var rest = code;
            for (out) |*slot| {
                slot.* = kinds[rest % kinds.len];
                rest /= kinds.len;
            }
            if (uniform(out)) continue;
            if (seen == index) return out;
            seen += 1;
        }
        return null;
    }
    const varied = index - kinds.len;
    const others = kinds.len - 1;
    if (varied >= count * others) return null;
    @memset(out, .int);
    out[varied / others] = kinds[1 + varied % others];
    return out;
}

fn uniform(chosen: []const Kind) bool {
    for (chosen) |kind| if (kind != chosen[0]) return false;
    return true;
}

/// What one template and one choice of kinds became.
pub const Outcome = union(enum) {
    /// An instance the ownership pass judges: its index in the checked program's functions.
    instance: usize,
    /// The choice was not tried, and why: a bound the stand-in does not meet, a structural requirement, no move-only type in
    /// the program, or the instance budget.
    skipped: []const u8,
};

/// The first error of an instance whose own body check refused it.
pub const Refusal = struct { code: []const u8, span: source.Span };

/// One template and one choice of kinds per type parameter.
pub const Row = struct {
    /// The template's name, as the report prints it, and the place of its declaration.
    name: []const u8,
    at: source.Span,
    chosen: []const Kind,
    outcome: Outcome,
};

/// The count's record, written by sema and read by the command. Its slices live in `allocator`.
pub const Log = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList(Row) = .empty,
    /// The functions of the checked program from this index on were made by the count, not by the program's own calls.
    first_stand_in: usize = 0,
    /// The type each kind stood for in this program, as the report's header prints it; empty for a kind with none.
    types: [kinds.len][]const u8 = @splat(""),
    /// The instances whose own body check refused them, by function index, with the first error: each stands in with an empty
    /// body, so the ownership pass does not judge it.
    refused: std.array_hash_map.Auto(usize, Refusal) = .empty,

    /// Release the rows, their chosen kinds, the type names and the refusal table; the template names belong to the checker.
    pub fn deinit(self: *Log) void {
        for (self.types) |name| if (name.len != 0) self.allocator.free(name);
        for (self.rows.items) |row| self.allocator.free(row.chosen);
        self.rows.deinit(self.allocator);
        self.refused.deinit(self.allocator);
    }
};

/// How many choices `declarationChoice` gives a template of `count` type parameters.
fn declarationChoices(comptime count: usize) usize {
    var out: [count]Kind = undefined;
    var total: usize = 0;
    while (declarationChoice(count, total, &out) != null) total += 1;
    return total;
}

/// How many choices `choice` gives a template of `count` type parameters.
fn choices(comptime count: usize) usize {
    var out: [count]Kind = undefined;
    var total: usize = 0;
    while (choice(count, total, &out) != null) total += 1;
    return total;
}

test "W3 declaration choices: int first, each parameter alone, then uniform for two or more parameters" {
    try std.testing.expectEqual(@as(usize, 4), declarationChoices(1));
    try std.testing.expectEqual(@as(usize, 1 + 2 * 3 + 3), declarationChoices(2));
    var two: [2]Kind = undefined;
    try std.testing.expectEqualSlices(Kind, &.{ .int, .int }, declarationChoice(2, 0, &two).?);
    try std.testing.expectEqualSlices(Kind, &.{ .int, .list }, declarationChoice(2, 6, &two).?);
    try std.testing.expectEqualSlices(Kind, &.{ .record, .record }, declarationChoice(2, 8, &two).?);
    try std.testing.expect(declarationChoice(2, 10, &two) == null);
}

test "W3 a refusal at a declaration names the parameters and the kinds" {
    var conditions: std.ArrayList(Condition) = .empty;
    defer conditions.deinit(std.testing.allocator);
    try addCondition(std.testing.allocator, &conditions, 0b10, .text);
    try addCondition(std.testing.allocator, &conditions, 0b10, .list);
    try addCondition(std.testing.allocator, &conditions, 0b11, .record);
    const names = try parameterNames(std.testing.allocator, "second[A, const B: u64](a: A)", "second".len);
    defer std.testing.allocator.free(names);
    try std.testing.expectEqualStrings("B", names[1]);
    try std.testing.expect(parametersCopy("f[T, U: copy + storable, const N: u64](x: T)", 1));
    try std.testing.expect(!parametersCopy("f[T: storable](x: T)", 1));
    const text = try describe(std.testing.allocator, "second", names, conditions.items);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "the body of `second` is refused when `B` is a text or a list; or when `A` and `B` are each a record with a managed field;"));
    try addCondition(std.testing.allocator, &conditions, 0b11, .text);
    const narrowed = try describe(std.testing.allocator, "second", names, conditions.items);
    defer std.testing.allocator.free(narrowed);
    try std.testing.expect(std.mem.indexOf(u8, narrowed, "each a text") == null);
}

test "W3 stand-in choices: uniform first, the full product for two parameters, one varied at a time for three" {
    var one: [1]Kind = undefined;
    try std.testing.expectEqual(Kind.int, choice(1, 0, &one).?[0]);
    try std.testing.expectEqual(Kind.move_only, choice(1, 4, &one).?[0]);
    try std.testing.expect(choice(1, 5, &one) == null);
    try std.testing.expectEqual(@as(usize, 25), choices(2));
    try std.testing.expectEqual(@as(usize, 5 + 3 * 4), choices(3));
    var three: [3]Kind = undefined;
    try std.testing.expectEqualSlices(Kind, &.{ .text, .text, .text }, choice(3, 1, &three).?);
    try std.testing.expectEqualSlices(Kind, &.{ .text, .int, .int }, choice(3, 5, &three).?);
    try std.testing.expectEqualSlices(Kind, &.{ .int, .int, .move_only }, choice(3, 5 + 11, &three).?);
    try std.testing.expect(choice(3, 5 + 12, &three) == null);
}
