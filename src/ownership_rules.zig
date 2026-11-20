//! Closed ownership rules and the diagnostic codes which may enforce each one.
const std = @import("std");

/// Stable rule identifiers named by ownership diagnostics and the living reference.
pub const Rule = enum {
    T1,
    T2,
    T3,
    T4,
    B1,
    B2,
    B3,
    B4,
    B5,
    B6,
    B7,
    B8,
    B9,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    M1,
    M2,
    M3,
    M4,
    M5,
    M6,
    W1,
    W2,
    W3,
    W4,
    V1,
    V2,
    V3,
    V4,
    V5,
    V6,
    V7,
    X1,
    X2,
    P1,
    P2,
    P3,
    P4,
    P5,
    K1,
    K2,
    K3,
    L1,
    C1,
    C2,
    C3,
    Z1,
    Z2,
    Z3,
};

/// One ownership refusal selects its actual rule explicitly, even for a shared code.
pub const Refusal = struct { code: []const u8, rule: Rule };

/// The layer deciding a rule's predicates; split rules name distinct predicates.
pub const Layer = enum { frontend, core, both };

/// D1's final assignment, including source-mode spelling beside Core W2 transfers. P4 is both: Core refuses a local or a return that
/// stores an open file, and the front end refuses the record, list, variant or callback type where it is declared (`record_layouts.zig`).
pub fn layer(rule: Rule) Layer {
    return switch (rule) {
        .T1, .T2, .T3, .T4, .B1, .M2, .M3, .W3, .V6, .K2, .K3, .L1, .C2 => .frontend,
        .M4, .R7, .W2, .X2, .K1, .P4 => .both,
        else => .core,
    };
}

/// Canonical layer text used by the living rules reference.
pub fn layerText(rule: Rule) []const u8 {
    return switch (layer(rule)) {
        .frontend => "Frontend",
        .core => "Core",
        .both => "Frontend and Core",
    };
}

/// The heading of the living reference that files a rule: one of the model's three rules, the limits of today's checker, the
/// applications to resources, task groups and pending Results, or the appendix of accepted behaviour.
pub const Family = enum { escape, exclusion, gone, limit, application, appendix };

/// The reference's headings in document order, as their text (`## Rule 1: Escape` is `Escape`).
pub const family_names = [_][]const u8{ "Escape", "Exclusion", "Gone", "Current limits", "Applications", "Appendix" };

/// Which heading of `docs/ownership-rules.md` files `rule`; a test holds it equal to the document's own filing.
pub fn family(rule: Rule) Family {
    return switch (rule) {
        .B2, .B7, .B9, .R1, .R3, .R4, .R6, .M1, .W2, .W4, .V2, .V4, .V5, .V6, .C1 => .escape,
        .T3, .B1, .R2, .R7, .M2, .M3, .M4, .M5, .M6, .V3, .X1, .X2 => .exclusion,
        .B3, .B6, .C3 => .gone,
        .B8, .R5, .Z3 => .limit,
        .T2, .T4, .W3, .P1, .P2, .P3, .P4, .K1, .K2, .K3, .L1 => .application,
        .T1, .B4, .B5, .W1, .V1, .V7, .P5, .C2, .Z1, .Z2 => .appendix,
    };
}

/// The rules of one diagnostic code that one heading of the reference files.
pub const FamilyRules = struct { family: []const u8, rules: []const Rule };

/// Backing storage for `grouped`: up to sixteen rules under each of the six headings.
pub const Grouped = struct {
    groups: [family_names.len]FamilyRules = undefined,
    buffer: [family_names.len][16]Rule = undefined,
};

/// Group a code's rules by the heading that files them, in the reference's order, dropping empty headings. The groups point
/// into `storage`.
pub fn grouped(rules: []const Rule, storage: *Grouped) []const FamilyRules {
    var used: usize = 0;
    for (family_names, 0..) |name, index| {
        var count: usize = 0;
        for (rules) |rule| {
            if (@backingInt(family(rule)) != index or count == storage.buffer[used].len) continue;
            storage.buffer[used][count] = rule;
            count += 1;
        }
        if (count == 0) continue;
        storage.groups[used] = .{ .family = name, .rules = storage.buffer[used][0..count] };
        used += 1;
    }
    return storage.groups[0..used];
}

/// A rule's short description, shared with reference-contract checks.
pub const Definition = struct { rule: Rule, description: []const u8 };

/// Every rule, including rules implemented by accepted behavior rather than a refusal.
pub const definitions = [_]Definition{
    .{ .rule = .T1, .description = "Managed types" },
    .{ .rule = .T2, .description = "Move-only types" },
    .{ .rule = .T3, .description = "No shared mutable identity" },
    .{ .rule = .T4, .description = "Containment" },
    .{ .rule = .B1, .description = "Writability" },
    .{ .rule = .B2, .description = "Moves" },
    .{ .rule = .B3, .description = "Use after move" },
    .{ .rule = .B4, .description = "Reinitialization" },
    .{ .rule = .B5, .description = "Joins" },
    .{ .rule = .B6, .description = "Loops" },
    .{ .rule = .B7, .description = "No moving out of a container" },
    .{ .rule = .B8, .description = "No partial record moves" },
    .{ .rule = .B9, .description = "Const place bindings borrow" },
    .{ .rule = .R1, .description = "Plain parameters borrow" },
    .{ .rule = .R2, .description = "Loans block changes" },
    .{ .rule = .R3, .description = "Borrowed call results" },
    .{ .rule = .R4, .description = "Borrowed returns" },
    .{ .rule = .R5, .description = "One kind of return" },
    .{ .rule = .R6, .description = "Borrowed selections" },
    .{ .rule = .R7, .description = "Iteration" },
    .{ .rule = .M1, .description = "Mut parameters" },
    .{ .rule = .M2, .description = "Declared mutation" },
    .{ .rule = .M3, .description = "Call markers" },
    .{ .rule = .M4, .description = "Writable targets" },
    .{ .rule = .M5, .description = "Disjoint arguments" },
    .{ .rule = .M6, .description = "No self-source" },
    .{ .rule = .W1, .description = "Taking parameters" },
    .{ .rule = .W2, .description = "Own argument markers" },
    .{ .rule = .W3, .description = "Function types" },
    .{ .rule = .W4, .description = "No slice to own" },
    .{ .rule = .V1, .description = "Slices are views" },
    .{ .rule = .V2, .description = "Views are never stored" },
    .{ .rule = .V3, .description = "View sources stay put" },
    .{ .rule = .V4, .description = "Returned views" },
    .{ .rule = .V5, .description = "Joins of views" },
    .{ .rule = .V6, .description = "Dictionary views" },
    .{ .rule = .V7, .description = "View operations" },
    .{ .rule = .X1, .description = "Matching a name borrows" },
    .{ .rule = .X2, .description = "Mutable matches" },
    .{ .rule = .P1, .description = "Resource origin" },
    .{ .rule = .P2, .description = "Resource lifetime" },
    .{ .rule = .P3, .description = "Returned resources" },
    .{ .rule = .P4, .description = "Scoped handles" },
    .{ .rule = .P5, .description = "Retired provider contexts" },
    .{ .rule = .K1, .description = "Lent task arguments" },
    .{ .rule = .K2, .description = "Scoped groups and handles" },
    .{ .rule = .K3, .description = "Parallel map" },
    .{ .rule = .L1, .description = "Linear Results" },
    .{ .rule = .C1, .description = "Written copies" },
    .{ .rule = .C2, .description = "Old captures" },
    .{ .rule = .C3, .description = "Destruction" },
    .{ .rule = .Z1, .description = "Evaluation temporaries" },
    .{ .rule = .Z2, .description = "Retired analysis budget" },
    .{ .rule = .Z3, .description = "Build-time ownership limits" },
};

/// The union of actual ownership rules a diagnostic code may enforce.
pub const CodeRules = struct { code: []const u8, rules: []const Rule };

/// Canonical code-to-rule relation; a diagnostic still selects its own single rule.
pub const entries = [_]CodeRules{
    .{ .code = "E_BORROW_MIXED", .rules = &.{.R5} },
    .{ .code = "E_BORROW_SOURCE", .rules = &.{.R4} },
    .{ .code = "E_BORROW_UNDECLARED", .rules = &.{.R4} },
    .{ .code = "E_CELL_ELEMENT", .rules = &.{.T3} },
    .{ .code = "E_CONTRACT_OLD_COPY", .rules = &.{.C2} },
    .{ .code = "E_CONTRACT_OLD_SHARED", .rules = &.{.C2} },
    .{ .code = "E_CORE_HIDDEN_COPY", .rules = &.{.C1} },
    .{ .code = "E_CORE_UNSUPPORTED", .rules = &.{.Z3} },
    .{ .code = "E_DICT_TYPE", .rules = &.{.T4} },
    .{ .code = "E_EXPLICIT_DISCARD_REQUIRED", .rules = &.{.L1} },
    .{ .code = "E_IMMUTABLE", .rules = &.{.B1} },
    .{ .code = "E_LIST_ELEMENT", .rules = &.{.T4} },
    .{ .code = "E_LIST_TYPE", .rules = &.{ .T2, .T4 } },
    .{ .code = "E_LITERAL_ARM", .rules = &.{.C1} },
    .{ .code = "E_LIVE_VIEW_CYCLE", .rules = &.{.V6} },
    .{ .code = "E_MATCH_MUT", .rules = &.{.X2} },
    .{ .code = "E_MUTATION_MARKER", .rules = &.{ .M2, .M3 } },
    .{ .code = "E_MUTATION_PERMISSION", .rules = &.{.M2} },
    .{ .code = "E_NOALLOC_ALLOCATES", .rules = &.{.C3} },
    .{ .code = "E_OWN_MARKER", .rules = &.{ .B2, .B9, .W2 } },
    .{ .code = "E_OWN_PARAMETER", .rules = &.{ .T2, .W3 } },
    .{ .code = "E_PARALLEL_MAP_ARGS", .rules = &.{.K3} },
    .{ .code = "E_RECURSIVE_RECORD", .rules = &.{.T4} },
    .{ .code = "E_RESOURCE_ESCAPE", .rules = &.{ .P2, .P3 } },
    .{ .code = "E_RESOURCE_ORIGIN", .rules = &.{ .P1, .P3 } },
    .{ .code = "E_RESULT_CONSUMED", .rules = &.{.L1} },
    .{ .code = "E_RESULT_DISCARD", .rules = &.{.L1} },
    .{ .code = "E_RESULT_LOOP", .rules = &.{.L1} },
    .{ .code = "E_RESULT_OPERATION", .rules = &.{ .T2, .L1 } },
    .{ .code = "E_RESULT_OVERWRITE", .rules = &.{.L1} },
    .{ .code = "E_RESULT_PATH", .rules = &.{.L1} },
    .{ .code = "E_RESULT_PROPAGATION", .rules = &.{.L1} },
    .{ .code = "E_RESULT_UNHANDLED", .rules = &.{.L1} },
    .{ .code = "E_SET_ELEMENT", .rules = &.{.T4} },
    .{ .code = "E_SINGLE_OWNER_BORROW", .rules = &.{ .B7, .B8, .B9, .R1, .R3, .R4, .R6, .M1, .M4, .X2, .P4 } },
    .{ .code = "E_SINGLE_OWNER_LOOP", .rules = &.{.B6} },
    .{ .code = "E_SINGLE_OWNER_MOVED", .rules = &.{.B3} },
    .{ .code = "E_SINGLE_OWNER_OVERLAP", .rules = &.{ .R2, .R7, .M5, .M6, .X1, .X2 } },
    .{ .code = "E_SLICE_ESCAPES", .rules = &.{ .V2, .V3, .V4, .V5, .W4, .K3 } },
    .{ .code = "E_TASK_CAPABILITY", .rules = &.{.K1} },
    .{ .code = "E_TASK_ESCAPE", .rules = &.{.K2} },
    .{ .code = "E_TASK_GROUP", .rules = &.{.K2} },
    .{ .code = "E_TASK_HANDLE", .rules = &.{.K2} },
    .{ .code = "E_TASK_HOST", .rules = &.{.K1} },
    .{ .code = "E_TASK_LOAN", .rules = &.{.K1} },
    .{ .code = "E_TASK_MUT", .rules = &.{ .K1, .K3 } },
    .{ .code = "E_TASK_RESOURCE", .rules = &.{.K1} },
    .{ .code = "E_TASK_RESULT_UNREAD", .rules = &.{.K2} },
    .{ .code = "E_TEXT_IMMUTABLE", .rules = &.{.T4} },
    .{ .code = "E_VALUE_BINDING_WRITE", .rules = &.{.R7} },
    .{ .code = "E_VALUE_CELL", .rules = &.{.T3} },
    .{ .code = "E_VALUE_CLASS", .rules = &.{.T3} },
    .{ .code = "E_VALUE_TEMPORARY_WRITE", .rules = &.{.M4} },
    .{ .code = "E_VIEW_FUNCTION_VALUE", .rules = &.{.V4} },
    .{ .code = "E_VIEW_STORED", .rules = &.{.V6} },
    .{ .code = "E_WITH_RESOURCE", .rules = &.{.P4} },
};

/// List all ownership rules a code can enforce; ordinary diagnostics have none.
pub fn rulesFor(code: []const u8) []const Rule {
    for (entries) |entry| if (std.mem.eql(u8, entry.code, code)) return entry.rules;
    return &.{};
}

/// Check that the selected instance rule belongs to its diagnostic code.
pub fn valid(refusal: Refusal) bool {
    for (rulesFor(refusal.code)) |rule| if (rule == refusal.rule) return true;
    return false;
}
