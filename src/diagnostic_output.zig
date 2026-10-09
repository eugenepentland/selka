//! Versioned diagnostic records resolve source coordinates before JSON serialization.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const project = @import("project.zig");
/// Default terminal text or one versioned JSON object per line.
pub const Format = enum { text, json };
const version = "diagnostic-v1";
const diagnostic_kind = "diagnostic";
const Position = struct { line: usize, column: usize };
const Location = struct { path: []const u8, start: Position, end: ?Position, bytes: ?source.Span };
const Note = struct { role: diagnostic.Role, message: []const u8, location: Location };
const Frame = struct { function: []const u8, location: Location };
const Payload = struct {
    code: []const u8,
    severity: []const u8,
    message: []const u8,
    location: Location,
    notes: []const Note,
    stack: struct { frames: []const Frame, omitted: usize },
};
const EditRecord = struct { path: []const u8, bytes: source.Span, text: []const u8 };
const FixRecord = struct { edits: []const EditRecord };
const FixedPayload = struct {
    code: []const u8,
    severity: []const u8,
    message: []const u8,
    location: Location,
    notes: []const Note,
    stack: @FieldType(Payload, "stack"),
    fix: FixRecord,
};
const FactRecord = struct { text: []const u8, location: Location };
const BindingRecord = struct { name: []const u8, type: []const u8, mutable: bool, location: Location };
const RequirementRecord = struct { subject: []const u8, requirement: []const u8, location: Location };
const ObligationIdentity = struct { snapshot: []const u8, function: ?FactRecord, site: Location, omitted: usize };
const ObligationTerms = struct { effects: ?FactRecord, mutation: ?FactRecord, transitive_effects: ?FactRecord, unusable_bindings: usize };
const ObligationRecord = struct {
    kind: []const u8,
    version: u32,
    identity: ObligationIdentity,
    declared: FactRecord,
    expected_type: ?FactRecord,
    bindings: []const BindingRecord,
    requirements: []const RequirementRecord,
    contract: ObligationTerms,
    unavailable: []const []const u8,
};
fn location(src: source.Source, span: source.Span) Location {
    const start = src.locate(span.start);
    var result: Location = .{ .path = start.path, .start = .{ .line = start.line, .column = start.column }, .end = null, .bytes = null };
    var original = src;
    var range = span;
    if (src.origins.len != 0) {
        const mapped = src.originalSpan(span) catch return result;
        original = src.origins[mapped.input].original;
        range = mapped.span;
    }
    if (range.start > range.end or range.end > original.bytes.len) return result;
    const end = original.locate(range.end);
    result.end = .{ .line = end.line, .column = end.column };
    result.bytes = range;
    return result;
}
fn encode(allocator: std.mem.Allocator, value: anytype) std.mem.Allocator.Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    std.json.Stringify.value(value, .{}, &out.writer) catch return error.OutOfMemory;
    out.writer.writeByte('\n') catch return error.OutOfMemory;
    return out.toOwnedSlice();
}
fn payload(diag: diagnostic.Diagnostic, src: source.Source) Payload {
    return .{
        .code = diag.code,
        .severity = if (diag.severity == .err) "error" else "warning",
        .message = diag.message,
        .location = location(src, diag.span),
        .notes = &.{},
        .stack = .{ .frames = &.{}, .omitted = diag.stack.omitted },
    };
}
/// Allocate one source diagnostic, preserving notes and bounded guest frames.
pub fn render(allocator: std.mem.Allocator, diag: diagnostic.Diagnostic, src: source.Source, format: Format) std.mem.Allocator.Error![]u8 {
    if (format == .text) return diag.render(allocator, src);
    var notes: [3]Note = undefined;
    var count: usize = 0;
    for ([_]?diagnostic.Related{ diag.related, diag.provenance.origin, diag.provenance.requirement }, [_]@FieldType(Note, "role"){ .related, .origin, .requirement }) |entry, role| if (entry) |note| {
        // A note that declares its own role keeps it; the slot name is the
        // fallback, so a note written before roles existed still reports the
        // evidence slot it occupies.
        notes[count] = .{ .role = if (note.role == .related) role else note.role, .message = note.message, .location = location(src, note.span) };
        count += 1;
    };
    var frames: [16]Frame = undefined;
    for (diag.stack.frames[0..diag.stack.len], 0..) |frame, index| frames[index] = .{ .function = frame.function, .location = location(src, frame.span) };
    var data = payload(diag, src);
    data.notes = notes[0..count];
    data.stack.frames = frames[0..diag.stack.len];
    if (diag.provenance.obligation) |obligation| return renderHole(allocator, data, obligation, src);
    if (diag.provenance.fix) |fix| return renderFixed(allocator, data, fix, src);
    return encode(allocator, .{ .version = version, .kind = diagnostic_kind, .diagnostic = data });
}
fn editRecord(src: source.Source, edit: diagnostic.Edit) ?EditRecord {
    if (edit.span.start > edit.span.end or edit.span.end > src.bytes.len) return null;
    if (src.origins.len == 0) return .{ .path = src.path, .bytes = edit.span, .text = edit.text };
    const mapped = src.originalSpan(edit.span) catch return null;
    const original = src.origins[mapped.input].original;
    if (mapped.span.end > original.bytes.len) return null;
    return .{ .path = original.path, .bytes = mapped.span, .text = edit.text };
}
fn renderFixed(allocator: std.mem.Allocator, data: Payload, fix: diagnostic.Fix, src: source.Source) std.mem.Allocator.Error![]u8 {
    const edits = try allocator.alloc(EditRecord, fix.count());
    defer allocator.free(edits);
    for (edits, 0..) |*record, index| record.* = editRecord(src, fix.at(index)) orelse
        return encode(allocator, .{ .version = version, .kind = diagnostic_kind, .diagnostic = data });
    const fixed: FixedPayload = .{
        .code = data.code,
        .severity = data.severity,
        .message = data.message,
        .location = data.location,
        .notes = data.notes,
        .stack = data.stack,
        .fix = .{ .edits = edits },
    };
    return encode(allocator, .{ .version = version, .kind = diagnostic_kind, .diagnostic = fixed });
}
/// Serialize one diagnostic beside its structured typed-hole obligation. Only a
/// diagnostic that actually carries an obligation takes this shape, so every
/// other diagnostic keeps its exact `diagnostic-v1` bytes.
fn renderHole(allocator: std.mem.Allocator, data: Payload, obligation: *const diagnostic.Obligation, src: source.Source) std.mem.Allocator.Error![]u8 {
    const bindings = try allocator.alloc(BindingRecord, obligation.bindings.len);
    defer allocator.free(bindings);
    for (obligation.bindings, bindings) |input, *output| output.* = .{
        .name = input.name,
        .type = input.ty,
        .mutable = input.mutable,
        .location = location(src, input.declaration),
    };
    const requirements = try allocator.alloc(RequirementRecord, obligation.requirements.len);
    defer allocator.free(requirements);
    for (obligation.requirements, requirements) |input, *output| output.* = .{
        .subject = input.subject,
        .requirement = input.requirement,
        .location = location(src, input.span),
    };
    const snapshot = try snapshotText(allocator, obligation.header.snapshot);
    defer allocator.free(snapshot);
    var unavailable: [4][]const u8 = undefined;
    var missing: usize = 0;
    if (obligation.expected == null) {
        unavailable[missing] = "expected_type";
        missing += 1;
    }
    if (obligation.contract.effects == null) {
        unavailable[missing] = "declared_effect_ceiling";
        missing += 1;
    }
    if (obligation.contract.mutation == null) {
        unavailable[missing] = "permitted_mutation_footprint";
        missing += 1;
    }
    // A transitive effect summary needs the whole program checked, which a hole
    // prevents by construction, so the obligation never claims one.
    if (obligation.contract.transitive_effects == null) {
        unavailable[missing] = "transitive_effects";
        missing += 1;
    }
    const record = ObligationRecord{
        .kind = "typed-hole-obligation",
        .version = obligation.header.version,
        .identity = .{
            .snapshot = snapshot,
            .function = if (obligation.header.function) |function| factRecord(src, function) else null,
            .site = location(src, obligation.header.site),
            .omitted = obligation.header.omitted,
        },
        .declared = factRecord(src, obligation.declared),
        .expected_type = if (obligation.expected) |expected| factRecord(src, expected) else null,
        .bindings = bindings,
        .requirements = requirements,
        .contract = .{
            .effects = if (obligation.contract.effects) |effects| factRecord(src, effects) else null,
            .mutation = if (obligation.contract.mutation) |mutation| factRecord(src, mutation) else null,
            .transitive_effects = if (obligation.contract.transitive_effects) |value| factRecord(src, value) else null,
            .unusable_bindings = obligation.contract.unusable_bindings,
        },
        .unavailable = unavailable[0..missing],
    };
    return encode(allocator, .{ .version = version, .kind = diagnostic_kind, .diagnostic = data, .obligation = record });
}
/// One source-spelled fact and the location it was declared at.
fn factRecord(src: source.Source, fact: diagnostic.Fact) FactRecord {
    return .{ .text = fact.text, .location = location(src, fact.span) };
}
/// Render a snapshot digest as fixed-width lowercase hex.
fn snapshotText(allocator: std.mem.Allocator, snapshot: u64) std.mem.Allocator.Error![]const u8 {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, snapshot, .little);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return allocator.dupe(u8, &hex);
}
/// Render module discovery/interface errors without losing cross-module related sites.
pub fn renderProject(allocator: std.mem.Allocator, loaded: *project.Project, format: Format) project.RenderProblemError![]u8 {
    if (format == .text) return loaded.renderProblem(allocator);
    const problem = loaded.problem orelse return error.NoProblem;
    const src = loaded.modules.items[problem.site.module].src;
    var data = payload(.{ .code = problem.code, .message = problem.message, .span = problem.site.span }, src);
    var notes: [1]Note = undefined;
    if (problem.related) |related| {
        notes[0] = .{ .role = .related, .message = "related module/import declaration", .location = location(loaded.modules.items[related.module].src, related.span) };
        data.notes = &notes;
    }
    if (problem.fix) |edit| return renderFixed(allocator, data, .{ .edit = edit, .more = problem.fix_more }, src);
    return encode(allocator, .{ .version = version, .kind = diagnostic_kind, .diagnostic = data });
}
/// Preserve auxiliary CLI messages as distinct records rather than mixing raw text into JSON.
pub fn message(allocator: std.mem.Allocator, text: []const u8, format: Format) std.mem.Allocator.Error![]u8 {
    if (format == .text) return allocator.dupe(u8, text);
    return encode(allocator, .{ .version = version, .kind = "message", .message = text });
}
