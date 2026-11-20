//! Ownership emission coverage: source construction is guarded, and real
//! diagnostics pin the rule selected by shared-code predicates.
const std = @import("std");
const t = std.testing;
const guard = @import("ownership_rule_site_guard.zig");
const rules = @import("ownership_rules.zig");
const options = @import("test_paths");
const print = std.debug.print;

// These exact expressions reject wrong receiver/context types. They do not
// enforce containment or linearity. A changed expression needs a fresh audit;
// an additional identical expression exceeds its pinned occurrence count.
const ordinary = [_]guard.Exception{
    .{ .path = "sema_builtins.zig", .expression = "self.sink.fail(\"E_DICT_TYPE\", node.span, \"dict() builds a dictionary, but this position expects another type\")" },
    .{ .path = "sema_builtins.zig", .expression = "self.sink.failRelated(\"E_DICT_TYPE\", node.span, dict_argument_message, .{ .span = node.span, .message = dict_argument_alternative, .role = .alternative })" },
    .{ .path = "sema_operators.zig", .expression = "self.sink.fail(\"E_DICT_TYPE\", node.span, \"dictionary literal requires dict key/value types\")" },
    .{ .path = "sema_operators.zig", .expression = "self.sink.fail(\"E_DICT_TYPE\", node.span, \"`{}` is an empty dict; write `set()` for an empty set, as Python does\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, span, \"operation requires a managed list, string, or dictionary\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(\"E_DICT_TYPE\", node.span, \"dictionary literal requires a dictionary type\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(\"E_DICT_TYPE\", node.span, \"`{}` is an empty dict; write `set()` for an empty set\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, operation.span, \"search and trim require str or bytes\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, span, \"operation requires a managed collection\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, operation.span, \"numeric byte parsing requires a bytes receiver\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, operation.span, \"split and join require str\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, operation.span, \"mapping operation requires a dictionary\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, range.span, \"numeric byte parsing requires a bytes receiver\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, sort.span, \"sort requires a list receiver\")" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, operation.owner, \"operation requires a managed collection value binding\")", .count = 2 },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(eListType, statement_value.span, \"iteration requires a collection, fixed array or dictionary view\")" },
    .{ .path = "sema_collections.zig", .expression = "self.sink.fail(eListType, span, needs_list)", .count = 3 },
    .{ .path = "sema_collections.zig", .expression = "self.sink.fail(eListType, operation.owner, needs_list)" },
    // An unconstrained generic value might become a Result, but refusing a
    // standalone scalar or unknown T only requires an explicit discard marker.
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(code, statement_value.span, message)" },
    .{ .path = "generic_bodies.zig", .expression = "self.sink.failFix(code, statement_value.span, message, .{ .span = .{ .start = at, .end = at }, .text = \"_ = \" })" },
    // This cycle is an infinite by-value layout, independently of ownership.
    .{ .path = "record_layouts.zig", .expression = "sink.fail(diagnostic.recursive_record, field.declaration, \"record fields must form a finite by-value layout; this field closes a cycle\")" },
    .{ .path = "nominal_layouts.zig", .expression = "self.sink.failRelated(diagnostic.recursive_record, edge.span, no_finite_value, .{ .span = child.site, .message = \"this type contains itself\" })" },
    .{ .path = "hashable_keys.zig", .expression = "sink.fail(if (set) set_code else dictionary_code, span, try message(allocator, records, key, found, set))" },
    // Both pipeline renderers first construct the checked diagnostic and print
    // its rule separately. The builder boundary also serves ordinary failures.
    .{ .path = "core/pipeline.zig", .expression = "report.print(allocator, \"{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: {s}\\n\", .{ at.path, at.line, at.column, message })", .count = 2 },
    .{ .path = "core/pipeline.zig", .expression = "report.print(allocator, \"error[E_CORE_UNSUPPORTED]: {s}\\n\", .{message})" },
    .{ .path = "core/test_runner_report.zig", .expression = "out.print(allocator, \"unsupported {f}: E_CORE_UNSUPPORTED ({s})\", .{ Shown{ .name = verdict.name }, verdict.reason })" },
    // A retired configuration and an LLVM emission failure do not enforce an
    // ownership predicate. The matching source expressions are pinned separately.
    .{ .path = "core/project_entry.zig", .expression = "report.print(allocator, \"{s}: error[E_CORE_UNSUPPORTED]: the new core requires value_semantics\\n\", .{configured.path})" },
    .{ .path = "core/pipeline.zig", .expression = "report.print(allocator, \"error[E_CORE_UNSUPPORTED]: LLVM emission failed: {s}\\n\", .{@errorName(err)})" },
    // Literal-arm shape, type and name failures precede the separate L1 check
    // that refuses copying a scrutinee with a pending Result obligation.
    .{ .path = "generic_bodies.zig", .expression = "self.sink.fail(\"E_LITERAL_ARM\", arm.name, \"a literal arm is not checked in a generic function yet; move the match into a function with concrete types\")" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, arm.name, \"a literal or constant arm has no payload\")" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, arm.name, \"a constant arm names a constant of this module alone, as `case LIMIT:`; \" ++" ++
        "\"an imported constant is not an arm yet, so compare with `if value == settings.ANSWER:`\")" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, span, message)" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, name, message)", .count = 2 },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, first.name, message)" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, node.span, \"an arm takes `ord` of a one-byte literal or a literal indexed by an integer literal, as `case ord(\\\"+\\\"):`\")" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.fail(eLiteralArm, node.span, \"the byte does not fit the matched integer type\")" },
    .{ .path = "sema_statements.zig", .expression = "self.sink.failFix(\"E_EXPLICIT_DISCARD_REQUIRED\", stmt.span, message, .{ .span = .{ .start = stmt.span.start, .end = stmt.span.start }, .text = \"_ = \" })" },
};

fn findings(bytes: []const u8) ![]u8 {
    return findingsAt("sample.zig", bytes);
}

fn findingsAt(path: []const u8, bytes: []const u8) ![]u8 {
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(t.allocator);
    try guard.inspect(t.allocator, path, bytes, &.{}, &.{}, &report);
    return report.toOwnedSlice(t.allocator);
}

fn expectFinding(bytes: []const u8, fragment: []const u8) !void {
    const found = try findings(bytes);
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, fragment) != null);
}

fn expectClean(bytes: []const u8) !void {
    return expectCleanAt("sample.zig", bytes);
}

fn expectCleanAt(path: []const u8, bytes: []const u8) !void {
    const found = try findingsAt(path, bytes);
    defer t.allocator.free(found);
    try t.expectEqualStrings("", found);
}

fn expectLayerFinding(path: []const u8, bytes: []const u8) !void {
    const found = try findingsAt(path, bytes);
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "ownership rule") != null);
    try t.expect(std.mem.indexOf(u8, found, "belongs to") != null);
}

test "ownership rule site guard rejects unlabelled literal and aliased emitters" {
    try expectFinding("fn f(s: anytype, at: anytype) void { s.fail(\"E_IMMUTABLE\", at, \"write\"); }", "ownership emission");
    try expectFinding("const code = \"E_IMMUTABLE\"; fn f(s: anytype, at: anytype) void { const emit = s.fail; emit(code, at, \"write\"); }", "ownership emission");
    try expectFinding("const d = @import(\"diagnostic.zig\"); fn f(s: anytype, at: anytype) void { const code = d.immutable; s.failFix(code, at, \"write\", .{}); }", "ownership emission");
    try expectFinding("const c = @import(\"collection_lower.zig\"); fn f(s: anytype, at: anytype) void { s.fail(c.list_type_error, at, \"containment\"); }", "ownership emission");
}

test "ownership rule site guard rejects conditional codes direct construction and raw printing" {
    try expectFinding("fn f(s: anytype, at: anytype, moved: bool) void { const code = if (moved) \"E_SINGLE_OWNER_MOVED\" else \"E_RESULT_CONSUMED\"; s.fail(code, at, \"used\"); }", "ownership emission");
    try expectFinding("const item = .{ .code = \"E_IMMUTABLE\", .span = .{}, .message = \"write\" };", "ownership construction");
    try expectFinding("const item = .{ .code = \"E_IMMUTABLE\", .span = .{}, .message = \"write\", .provenance = .{ .rule = null } };", "ownership construction");
    try expectFinding("const missing = null; const item = .{ .code = \"E_IMMUTABLE\", .span = .{}, .message = \"write\", .provenance = .{ .rule = missing } };", "ownership construction");
    try expectFinding("fn f(s: anytype, at: anytype) void { var code = \"E_TYPE_MISMATCH\"; code = \"E_IMMUTABLE\"; s.fail(code, at, \"write\"); }", "ownership emission");
    try expectFinding("fn f() void { std.debug.print(\"error[E_SINGLE_OWNER_BORROW]: refusal\\n\", .{}); }", "ownership emission");
}

test "ownership rule site guard validates literal descriptor pairs and permits ordinary diagnostics" {
    try expectFinding("const refusal = .{ .code = \"E_IMMUTABLE\", .rule = .M3 };", "rule is not registered");
    try expectClean("fn f(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_IMMUTABLE\", .rule = .B1 }, at, \"write\"); }");
    try expectCleanAt("core/check.zig", "const item = .{ .code = \"E_SINGLE_OWNER_BORROW\", .span = .{}, .message = \"borrow\", .provenance = .{ .rule = .R1 } };");
    try expectClean("fn f(s: anytype, at: anytype) void { s.fail(\"E_TYPE_MISMATCH\", at, \"type\"); } // E_IMMUTABLE is not emitted\n");
    try expectClean("fn f(s: anytype, at: anytype) void { s.fail(\"E_TYPE_MISMATCH\", at, message(\"E_IMMUTABLE\")); }");
}

test "ownership rule site guard follows only the result arms of code selections" {
    try expectFinding("fn f(s: anytype, at: anytype, flag: bool) void { const code = switch (flag) { true => \"E_IMMUTABLE\", false => \"E_TYPE_MISMATCH\" }; s.fail(code, at, \"type\"); }", "ownership emission");
    try expectClean("fn f(s: anytype, at: anytype, flag: bool) void { s.failOwnership(if (flag) .{ .code = \"E_IMMUTABLE\", .rule = .B1 } else .{ .code = \"E_MUTATION_MARKER\", .rule = .M3 }, at, \"write\"); }");
}

test "ownership layer guard refuses move borrow and overlap checks in the frontend" {
    try expectLayerFinding("sema.zig", "const item = .{ .code = \"E_SINGLE_OWNER_MOVED\", .rule = .B3 };");
    try expectLayerFinding("sema_calls.zig", "fn f(s: anytype, at: anytype) void { const code = \"E_SINGLE_OWNER_OVERLAP\"; const selected = .M5; " ++
        "const refusal = .{ .code = code, .rule = selected }; const emit = s.failOwnership; emit(refusal, at, \"overlap\"); }");
    try expectLayerFinding("generic_bodies.zig", "fn f(s: anytype, at: anytype, flag: bool) void { s.failOwnership(.{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = if (flag) .R1 else .M4 }, at, \"borrow\"); }");
    try expectLayerFinding("core/frontend.zig", "const item = .{ .code = \"E_SINGLE_OWNER_OVERLAP\", .rule = .M5 };");
    try expectLayerFinding("frontend_storage_rules.zig", "const item = .{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = .R1 };");
}

test "ownership layer guard keeps B1 in every frontend body and refuses it in Core" {
    try expectLayerFinding("core/single_owner.zig", "const item = .{ .code = \"E_IMMUTABLE\", .rule = .B1 };");
    try expectLayerFinding("core/check.zig", "const item = .{ .code = \"E_SLICE_ESCAPES\", .rule = .K3 };");
    try expectLayerFinding("core/check.zig", "const item = .{ .code = \"E_LIST_ELEMENT\", .rule = .T4 };");
    try expectCleanAt("generic_bodies.zig", "const item = .{ .code = \"E_IMMUTABLE\", .rule = .B1 };");
    try expectLayerFinding("generic_bodies.zig", "const item = .{ .code = \"E_SINGLE_OWNER_MOVED\", .rule = .B3 };");
    try expectCleanAt("frontend_storage_rules.zig", "const item = .{ .code = \"E_SLICE_ESCAPES\", .rule = .K3 };");
    try expectCleanAt("core/view_function_value.zig", "const item = .{ .code = \"E_VIEW_FUNCTION_VALUE\", .rule = .V4 };");
}

test "ownership layer guard distinguishes binding shape and writable-owner predicates" {
    try expectClean("const item = .{ .code = \"E_VALUE_BINDING_WRITE\", .rule = .R7 }; const temporary = .{ .code = \"E_VALUE_TEMPORARY_WRITE\", .rule = .M4 }; const shape = .{ .code = \"E_MATCH_MUT\", .rule = .X2 };");
    try expectCleanAt("core/check.zig", "const item = .{ .code = \"E_SINGLE_OWNER_OVERLAP\", .rule = .R7 }; " ++
        "const writable = .{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = .M4 }; const matched = .{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = .X2 };");
    try expectLayerFinding("sema_statements.zig", "const item = .{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = .X2 };");
    try expectLayerFinding("core/check.zig", "const item = .{ .code = \"E_MATCH_MUT\", .rule = .X2 };");
    try expectLayerFinding("core/check.zig", "const item = .{ .code = \"E_VALUE_BINDING_WRITE\", .rule = .R7 };");
}

fn markerFunction(name: []const u8, refusal: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        t.allocator,
        "fn {s}(sink: anytype, at: anytype, rule: anytype) void {{ sink.failOwnership({s}, at, \"marker\"); }}",
        .{ name, refusal },
    );
}

fn expectMarkerFunction(path: []const u8, name: []const u8, allowed: bool) !void {
    const bytes = try markerFunction(name, ".{ .code = \"E_OWN_MARKER\", .rule = .W2 }");
    defer t.allocator.free(bytes);
    if (allowed) return expectCleanAt(path, bytes);
    return expectLayerFinding(path, bytes);
}

test "ownership layer guard confines frontend W2 to audited mode spelling functions" {
    try expectMarkerFunction("sema_calls.zig", "checkMutationMarkers", true);
    try expectMarkerFunction("sema_calls.zig", "checkTakingModeMarkers", true);
    try expectMarkerFunction("sema_collections.zig", "checkWriterFunction", true);
    // The shared receiver marker check compares the written modes of a writing call's first operand.
    try expectMarkerFunction("sema_receiver_marker.zig", "require", true);
    try expectMarkerFunction("sema_receiver_marker.zig", "checkTransfer", false);
    try expectMarkerFunction("core/check.zig", "checkTransfer", true);
    try expectMarkerFunction("sema_calls.zig", "checkTransfer", false);
    try expectMarkerFunction("sema_collections.zig", "checkTransfer", false);
    try expectMarkerFunction("sema.zig", "checkMutationMarkers", false);
    try expectMarkerFunction("sema_calls.zig", "checkWriterFunction", false);
    try expectMarkerFunction("sema_collections.zig", "checkTakingModeMarkers", false);
    try expectLayerFinding("sema_calls.zig", "const item = .{ .code = \"E_OWN_MARKER\", .rule = .W2 };");
}

test "ownership layer guard spelling functions cannot enforce Core marker rules" {
    const bytes = try markerFunction("checkMutationMarkers", ".{ .code = \"E_OWN_MARKER\", .rule = if (flag) .W2 else .B2 }");
    defer t.allocator.free(bytes);
    try expectLayerFinding("sema_calls.zig", bytes);
    const borrowed = try markerFunction("checkTakingModeMarkers", ".{ .code = \"E_OWN_MARKER\", .rule = .B9 }");
    defer t.allocator.free(borrowed);
    try expectLayerFinding("sema_calls.zig", borrowed);
}

test "ownership layer guard confines frontend task loan codes to argument admission" {
    try expectCleanAt("sema_tasks.zig", "fn submit(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_TASK_LOAN\", .rule = .K1 }, at, \"bind the list element\"); }");
    try expectCleanAt("core/single_owner.zig", "fn checkLoans(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_TASK_LOAN\", .rule = .K1 }, at, \"lent until the join\"); }");
    try expectLayerFinding("sema_tasks.zig", "fn refuseLoaned(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_TASK_LOAN\", .rule = .K1 }, at, \"duplicate conflict\"); }");
    try expectLayerFinding("sema_places.zig", "fn submit(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_TASK_LOAN\", .rule = .K1 }, at, \"duplicate conflict\"); }");
    try expectLayerFinding("core/single_owner.zig", "fn checkTasks(s: anytype, at: anytype) void { s.failOwnership(.{ .code = \"E_TASK_MUT\", .rule = .K1 }, at, \"argument kind\"); }");
}

test "ownership layer guard confines the front end's P4 to the declaration of a type that stores an open file" {
    const refusal = ".{ .code = \"E_WITH_RESOURCE\", .rule = .P4 }";
    const declared = try markerFunction("refuseFile", refusal);
    defer t.allocator.free(declared);
    try expectCleanAt("record_layouts.zig", declared);
    try expectCleanAt("core/single_owner.zig", declared);
    const elsewhere = try markerFunction("refuseLocal", refusal);
    defer t.allocator.free(elsewhere);
    try expectLayerFinding("record_layouts.zig", elsewhere);
    try expectLayerFinding("sema_calls.zig", declared);
}

test "ownership layer guard own marker helpers require complete decision descriptors" {
    const forwarded = try markerFunction("rejectMarker", ".{ .code = \"E_OWN_MARKER\", .rule = rule }");
    defer t.allocator.free(forwarded);
    const found = try findingsAt("core/check.zig", forwarded);
    defer t.allocator.free(found);
    try t.expect(std.mem.indexOf(u8, found, "mixed-layer code requires an explicit rule descriptor") != null);
    const spelling = try markerFunction("checkTakingModeMarkers", ".{ .code = \"E_OWN_MARKER\", .rule = rule }");
    defer t.allocator.free(spelling);
    const frontend = try findingsAt("sema_calls.zig", spelling);
    defer t.allocator.free(frontend);
    try t.expect(std.mem.indexOf(u8, frontend, "mixed-layer code requires an explicit rule descriptor") != null);
    try expectCleanAt("core/check.zig", "fn rejectMarker(refusal: anytype, at: anytype) void { sink.failOwnership(refusal, at, \"marker\"); } " ++
        "fn check(at: anytype) void { rejectMarker(.{ .code = \"E_OWN_MARKER\", .rule = .W2 }, at); }");
}

test "ownership layer guard validates conditional rule arms without mixing exclusive selections" {
    try expectFinding("const item = .{ .code = \"E_IMMUTABLE\", .rule = if (flag) .M5 else .B1 };", "rule is not registered");
    try expectClean("fn f(flag: bool) void { const code = if (flag) \"E_RESULT_OPERATION\" else \"E_IMMUTABLE\"; const selected = if (flag) .L1 else .B1; const item = .{ .code = code, .rule = selected }; }");
    try expectClean("fn f(flag: bool) void { const code = switch (flag) { true => \"E_RESULT_OPERATION\", false => \"E_IMMUTABLE\" }; " ++
        "const selected = switch (flag) { false => .B1, true => .L1 }; const item = .{ .code = code, .rule = selected }; }");
    try expectLayerFinding("sema.zig", "const item = .{ .code = \"E_SINGLE_OWNER_OVERLAP\", .rule = switch (flag) { true => .R2, false => .M5 } };");
    try expectClean("fn f(s: anytype, at: anytype) void { s.fail(\"E_TYPE_MISMATCH\", at, message(.{ .code = \"ordinary\", .rule = .M5 })); }");
}

test "ownership layer guard keeps declared borrow rules in Core" {
    try expectCleanAt("core/borrow_contract.zig", "const item = .{ .code = \"E_BORROW_SOURCE\", .rule = .R4 };");
    try expectCleanAt("core/single_owner.zig", "const item = .{ .code = \"E_BORROW_UNDECLARED\", .rule = .R4 };");
    try expectLayerFinding("sema.zig", "const item = .{ .code = \"E_BORROW_SOURCE\", .rule = .R4 };");
    try expectLayerFinding("generic_bodies.zig", "const item = .{ .code = \"E_BORROW_UNDECLARED\", .rule = .R4 };");
}

test "ownership layer guard requires decision descriptors for helpers sharing a mixed-layer code" {
    const forwarded = try findingsAt("core/check.zig", "fn reject(rule: anytype) void { const item = .{ .code = \"E_SLICE_ESCAPES\", .rule = rule }; }");
    defer t.allocator.free(forwarded);
    try t.expect(std.mem.indexOf(u8, forwarded, "mixed-layer code requires an explicit rule descriptor") != null);
    try expectCleanAt("core/check.zig", "fn reject(refusal: anytype, at: anytype) void { sink.failOwnership(refusal, at, \"slice\"); } " ++
        "fn check(at: anytype) void { const code = \"E_SLICE_ESCAPES\"; reject(.{ .code = code, .rule = .V3 }, at); }");
    try expectLayerFinding("core/check.zig", "fn reject(refusal: anytype, at: anytype) void { sink.failOwnership(refusal, at, \"slice\"); } " ++
        "fn check(at: anytype) void { reject(.{ .code = \"E_SLICE_ESCAPES\", .rule = .K3 }, at); }");
    try expectCleanAt("core/check.zig", "fn reject(rule: anytype) void { const item = .{ .code = \"E_SINGLE_OWNER_BORROW\", .rule = rule }; }");
}

fn exceptionFindings(duplicated: bool) ![]u8 {
    const emission = "s.fail(\"E_LIST_TYPE\", at, \"wrong receiver\")";
    const one = "fn f(s: anytype, at: anytype) void { " ++ emission ++ "; }";
    const two = "fn f(s: anytype, at: anytype) void { " ++ emission ++ "; " ++ emission ++ "; }";
    const exception = [_]guard.Exception{.{ .path = "sample.zig", .expression = emission }};
    var seen = [_]usize{0};
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(t.allocator);
    try guard.inspect(t.allocator, "sample.zig", if (duplicated) two else one, &exception, &seen, &report);
    return report.toOwnedSlice(t.allocator);
}

test "ownership rule site guard ordinary exceptions cannot hide an additional identical site" {
    const one = try exceptionFindings(false);
    defer t.allocator.free(one);
    const two = try exceptionFindings(true);
    defer t.allocator.free(two);
    try t.expectEqualStrings("", one);
    try t.expect(std.mem.indexOf(u8, two, "ownership emission") != null);
}

fn checkoutFindings() ![]u8 {
    var directory = try std.Io.Dir.cwd().openDir(t.io, "src", .{ .iterate = true });
    defer directory.close(t.io);
    var walker = try directory.walk(t.allocator);
    defer walker.deinit();
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(t.allocator);
    var seen: [ordinary.len]usize = undefined;
    @memset(&seen, 0);
    while (try walker.next(t.io)) |file| {
        if (file.kind != .file or !std.mem.endsWith(u8, file.basename, ".zig") or std.mem.endsWith(u8, file.basename, "_test.zig")) continue;
        const bytes = try file.dir.readFileAlloc(t.io, file.basename, t.allocator, .limited(16 * 1024 * 1024));
        defer t.allocator.free(bytes);
        try guard.inspect(t.allocator, file.path, bytes, &ordinary, &seen, &report);
    }
    for (ordinary, seen) |exception, count| {
        if (count == exception.count) continue;
        try report.print(t.allocator, "{s}: ordinary exception expected {d} occurrences, saw {d}: {s}\n", .{ exception.path, exception.count, count, exception.expression });
    }
    return report.toOwnedSlice(t.allocator);
}

test "ownership rule site guard every compiler emission selects its rule in its assigned layer" {
    const found = try checkoutFindings();
    defer t.allocator.free(found);
    try t.expectEqualStrings("", found);
}

test "ownership rule site guard rejects invalid pairs supplied through runtime data" {
    const parsed = try std.json.parseFromSlice(struct { code: []const u8, rule: rules.Rule }, t.allocator, "{\"code\":\"E_IMMUTABLE\",\"rule\":\"M3\"}", .{});
    defer parsed.deinit();
    try t.expect(!rules.valid(.{ .code = parsed.value.code, .rule = parsed.value.rule }));
    try t.expect(rules.valid(.{ .code = parsed.value.code, .rule = .B1 }));
}

const Case = struct { name: []const u8, source: []const u8, code: []const u8, rule: ?rules.Rule };

fn firstError(bytes: []const u8) !std.json.Parsed(std.json.Value) {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
        const item = parsed.value.object.get("diagnostic") orelse {
            parsed.deinit();
            continue;
        };
        const severity = item.object.get("severity") orelse {
            parsed.deinit();
            continue;
        };
        if (std.mem.eql(u8, severity.string, "error")) return parsed;
        parsed.deinit();
    }
    return error.TestUnexpectedResult;
}

fn checkCase(case: Case) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "rules.selka", .data = case.source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "rules.selka" });
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", path, "--no-cache", "--diagnostics=json" } });
    errdefer print("ownership rule case {s}:\n{s}\n", .{ case.name, result.stderr });
    try t.expect(result.term == .exited and result.term.exited == 1);
    var parsed = try firstError(result.stderr);
    defer parsed.deinit();
    const item = parsed.value.object.get("diagnostic").?;
    const code = item.object.get("code").?.string;
    try t.expectEqualStrings(case.code, code);
    const selected = item.object.get("rule");
    if (case.rule) |expected| {
        try t.expect(selected != null);
        try t.expectEqualStrings(@tagName(expected), selected.?.string);
        try t.expect(rules.valid(.{ .code = code, .rule = expected }));
    } else try t.expect(selected == null);
}

const entry = "\n\nfunc main() -> int:\n    return 0\n";

test "ownership rule site matrix shared frontend codes choose the actual predicate" {
    try checkCase(.{
        .name = "plain move-only parameter",
        .source =
        \\import network
        \\func keep(listener: network.Listener) -> int:
        \\    return 0
        \\
        ++ entry,
        .code = "E_OWN_PARAMETER",
        .rule = .T2,
    });
    try checkCase(.{
        .name = "plain move-only function position",
        .source =
        \\import network
        \\func apply(f: func(network.Listener) -> int) -> int:
        \\    return 0
        \\
        ++ entry,
        .code = "E_OWN_PARAMETER",
        .rule = .W3,
    });
    try checkCase(.{
        .name = "mut declaration on affine record",
        .source =
        \\import network
        \\record Holder:
        \\    listener: network.Listener
        \\func change(mut holder: Holder) -> int:
        \\    return 0
        \\
        ++ entry,
        .code = "E_MUTATION_MARKER",
        .rule = .M2,
    });
    try checkCase(.{
        .name = "missing mut call marker",
        .source =
        \\func fill(mut xs: int[]) -> int:
        \\    append(mut xs, 1)
        \\    return len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return fill(xs)
        \\
        ,
        .code = "E_MUTATION_MARKER",
        .rule = .M3,
    });
    try checkCase(.{
        .name = "task mut argument",
        .source =
        \\import parallel
        \\func work(mut xs: int[]) -> int:
        \\    return len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    with parallel.group() as g:
        \\        const t = g.submit(work, mut xs)
        \\        return t.result()
        \\
        ,
        .code = "E_TASK_MUT",
        .rule = .K1,
    });
    try checkCase(.{
        .name = "parallel map mut argument",
        .source =
        \\import parallel
        \\func work(item: int, xs: int[]) -> int:
        \\    return item + len(xs)
        \\func main() -> int:
        \\    mut xs = [1]
        \\    return parallel.map([1], work, mut xs)[0]
        \\
        ,
        .code = "E_TASK_MUT",
        .rule = .K3,
    });
}

test "ownership rule site matrix slices distinguish owned arguments from parallel lending" {
    try checkCase(.{
        .name = "slice to own",
        .source =
        \\func my_take(own xs: int[]) -> int:
        \\    return len(xs)
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    return my_take(xs[0:1])
        \\
        ,
        .code = "E_SLICE_ESCAPES",
        .rule = .W4,
    });
    // FR59: `parallel.map` lends a slice as the view itself, so a slice there is accepted; what parallel lending still
    // refuses is an `own` argument, under K3.
    try checkCase(.{
        .name = "own argument to parallel map",
        .source =
        \\import parallel
        \\func add(x: int, extra: int) -> int:
        \\    return x + extra
        \\func main() -> int:
        \\    const xs = [1, 2]
        \\    const extra = 3
        \\    return len(parallel.map(xs[0:1], add, own extra))
        \\
        ,
        .code = "E_PARALLEL_MAP_ARGS",
        .rule = .K3,
    });
}

test "ownership rule site matrix result operations distinguish pending obligations from affine copies" {
    try checkCase(.{
        .name = "affine record field write",
        .source =
        \\import network
        \\record Holder:
        \\    listener: network.Listener
        \\    count: int
        \\func change(own holder: Holder) -> int:
        \\    holder.count = 1
        \\    return 0
        \\
        ++ entry,
        .code = "E_RESULT_OPERATION",
        .rule = .T2,
    });
    try checkCase(.{
        .name = "pending record field write",
        .source =
        \\record Holder:
        \\    value: Result[int, str]
        \\    count: int
        \\func change(own holder: Holder) -> int:
        \\    holder.count = 1
        \\    return 0
        \\
        ++ entry,
        .code = "E_RESULT_OPERATION",
        .rule = .L1,
    });
    try checkCase(.{
        .name = "generic pending discard",
        .source =
        \\enum Fault:
        \\    bad
        \\func make[T](x: T) -> T fails Fault:
        \\    return x
        \\func ignore[T](x: T) -> int:
        \\    make[T](x)
        \\    return 0
        \\
        ++ entry,
        .code = "E_EXPLICIT_DISCARD_REQUIRED",
        .rule = .L1,
    });
}

test "ownership rule site matrix ordinary collection typing stays without a rule" {
    try checkCase(.{
        .name = "list used as scalar",
        .source =
        \\func main() -> int:
        \\    const x: int = [1]
        \\    return x
        \\
        ,
        .code = "E_LIST_TYPE",
        .rule = null,
    });
    try checkCase(.{
        .name = "dict used as scalar",
        .source =
        \\func main() -> int:
        \\    const x: int = {1: 2}
        \\    return x
        \\
        ,
        .code = "E_DICT_TYPE",
        .rule = null,
    });
    try checkCase(.{
        .name = "ordinary generic iterable",
        .source =
        \\func bad[T](x: T) -> int:
        \\    for value in 42:
        \\        return value
        \\    return 0
        \\
        ++ entry,
        .code = "E_LIST_TYPE",
        .rule = null,
    });
    try checkCase(.{
        .name = "ordinary generic discard",
        .source =
        \\func bad[T](x: T) -> int:
        \\    x
        \\    return 0
        \\
        ++ entry,
        .code = "E_EXPLICIT_DISCARD_REQUIRED",
        .rule = null,
    });
}
