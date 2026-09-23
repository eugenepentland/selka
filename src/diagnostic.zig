//! Stable diagnostics are data; only the CLI chooses an output destination.
/// Shared code for attempts to discard a must-handle result value.
pub const result_discard = "E_RESULT_DISCARD";
pub const tuple_arity = "E_TUPLE_ARITY";
/// Shared code for forbidden source binding/type-variable shadowing.
pub const shadowing = "E_SHADOWING";
/// Shared code for aggregate operations that would erase result obligations.
pub const result_operation = "E_RESULT_OPERATION";
/// Shared code for inconsistent obligations across continuing control-flow paths.
pub const result_path = "E_RESULT_PATH";
/// Shared code for result obligations changed by a loop continuation.
pub const result_loop = "E_RESULT_LOOP";
/// Shared code for using an owned value after transfer.
pub const owned_consumed = "E_OWNED_CONSUMED";
/// Shared code for mutation without a mutable binding.
pub const immutable = "E_IMMUTABLE";
/// Shared code for a malformed resource acquisition result.
pub const resource_result = "E_RESOURCE_RESULT";
/// Shared diagnostic code for bounded generic parsing, checking and specialization.
pub const generic_limit = "E_GENERIC_LIMIT";
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const value_declared_here = "value declared here";

/// Distinguishes rejecting errors from advisory diagnostics.
pub const Severity = enum { err, warning };
/// What a note does for the reader. `alternative` names the accepted spelling
/// of a rejected Python form, `signature` renders the accepted callee itself;
/// the other three are evidence slots, and every note that declares no role
/// keeps its slot's role, so `diagnostic-v1` output for an existing diagnostic
/// is unchanged.
pub const Role = enum { related, origin, requirement, alternative, signature };
/// Additional source span and explanatory message attached to a diagnostic.
pub const Related = struct { span: source.Span, message: []const u8, role: Role = .related };
/// Guest function and source span recorded in a bounded runtime stack trace.
pub const Trace = struct { function: []const u8, span: source.Span };
/// Structured source diagnostic with optional related evidence and a bounded guest trace.
pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity = .err,
    span: source.Span,
    message: []const u8,
    related: ?Related = null,
    provenance: struct { origin: ?Related = null, requirement: ?Related = null, obligation: ?*const Obligation = null } = .{},
    // Bounded by-value guest trace needs no separate cleanup on trap paths.
    stack: struct { frames: [16]Trace = undefined, len: usize = 0, omitted: usize = 0 } = .{},

    /// Allocate a human-readable diagnostic mapped back to original source paths.
    pub fn render(self: Diagnostic, allocator: std.mem.Allocator, src: source.Source) std.mem.Allocator.Error![]u8 {
        const loc = src.locate(self.span.start);
        const padding = try allocator.alloc(u8, loc.column - 1);
        defer allocator.free(padding);
        @memset(padding, ' ');
        // Preserve tabs so the caret tracks the source in terminal displays.
        for (loc.text[0..@min(padding.len, loc.text.len)], 0..) |ch, i| {
            if (ch == '\t') padding[i] = '\t';
        }
        const primary = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: {s}[{s}]: {s}\n  {s}\n  {s}^\n", .{
            loc.path,  loc.line,     loc.column, if (self.severity == .err) "error" else "warning",
            self.code, self.message, loc.text,   padding,
        });
        defer allocator.free(primary);
        var output: std.Io.Writer.Allocating = .init(allocator);
        errdefer output.deinit();
        output.writer.writeAll(primary) catch return error.OutOfMemory;
        for ([_]?Related{ self.related, self.provenance.origin, self.provenance.requirement }) |note| if (note) |related| {
            if (related.role == .alternative) {
                // An alternative that repeats the primary sentence adds nothing
                // to the text; it is carried for structured consumers, which read
                // its role rather than the wording.
                if (std.mem.eql(u8, related.message, self.message)) continue;
                output.writer.print("  alternative: {s}\n", .{related.message}) catch return error.OutOfMemory;
                continue;
            }
            // A rendered callee signature is about the call, not about another
            // source site, so it prints without a location.
            if (related.role == .signature) {
                output.writer.print("  signature: {s}\n", .{related.message}) catch return error.OutOfMemory;
                continue;
            }
            const at = src.locate(related.span.start);
            output.writer.print("  note: {s}:{d}:{d}: {s}\n", .{ at.path, at.line, at.column, related.message }) catch return error.OutOfMemory;
        };
        for (self.stack.frames[0..self.stack.len]) |entry| {
            const at = src.locate(entry.span.start);
            output.writer.print("  in {s} at {s}:{d}:{d}\n", .{ entry.function, at.path, at.line, at.column }) catch return error.OutOfMemory;
        }
        if (self.stack.omitted != 0) output.writer.print("  ... {d} older frames omitted\n", .{self.stack.omitted}) catch return error.OutOfMemory;
        return output.toOwnedSlice();
    }
};

pub const Error = std.mem.Allocator.Error || error{ SourceError, InternalError };
/// Allocator-backed collector used by lexical, syntax, and semantic validation.
pub const Sink = struct {
    items: std.ArrayList(Diagnostic) = .empty,
    allocator: std.mem.Allocator,
    /// Retained typed-hole snapshots, created on the first observed hole.
    holes: ?Holes = null,

    /// Append an error with a related location and return SourceError, preserving allocator failure.
    /// Release the collected diagnostics and every retained hole snapshot;
    /// diagnostic text and obligation records must not be read afterwards.
    pub fn deinit(self: *Sink) void {
        self.items.deinit(self.allocator);
        self.items = .empty;
        if (self.holes) |*store| store.deinit();
        self.holes = null;
    }

    /// Reject an explicit typed implementation obligation, retaining the bounded
    /// context snapshot the checker copied out of its state before failed-function
    /// recovery cleared it. `src` supplies both the declared type spelling and the
    /// content identity a later query must present.
    pub fn recordHole(self: *Sink, src: source.Source, at: source.Span, target: source.Span, findings: Findings) Error {
        const declared: Fact = .{ .text = src.text(target), .span = target };
        const obligation = self.holeStore().record(at, snapshotId(src.path, src.bytes, at), declared, findings) catch null;
        self.items.append(self.allocator, .{
            .code = typed_hole_code,
            .span = at,
            .message = typed_hole_message,
            .related = .{ .span = target, .message = typed_hole_target },
            .provenance = .{ .obligation = obligation },
        }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// The sink's retained-snapshot store, created on first use.
    fn holeStore(self: *Sink) *Holes {
        if (self.holes == null) self.holes = .{ .allocator = self.allocator, .arena = std.heap.ArenaAllocator.init(self.allocator) };
        return if (self.holes) |*store| store else unreachable;
    }

    /// Append a primary diagnostic together with a related source location.
    pub fn failRelated(self: *Sink, code: []const u8, span: source.Span, message: []const u8, related: Related) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message, .related = related }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Keep the immediate cause and the value declaration as separate source evidence.
    pub fn failProvenance(self: *Sink, code: []const u8, span: source.Span, message: []const u8, cause: Related, declaration: source.Span) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message, .related = cause, .provenance = .{ .origin = .{ .span = declaration, .message = value_declared_here } } }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Diagnose reuse of a transferred value, retaining a witness from the checked path.
    pub fn failTransfer(self: *Sink, code: []const u8, span: source.Span, declaration: source.Span, transfer: ?source.Span) Error {
        const message = "value has already been transferred or handled";
        if (transfer) |at| return self.failProvenance(code, span, message, .{ .span = at, .message = "earlier transfer or handling on this path" }, declaration);
        return self.failRelated(code, span, message, .{ .span = declaration, .message = value_declared_here });
    }

    /// Append a source error and return SourceError, preserving allocator failure.
    pub fn fail(self: *Sink, code: []const u8, span: source.Span, message: []const u8) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Reject a call site with both halves of the contract: the accepted
    /// spelling as an `alternative` note when the language has one, and the
    /// accepted callee rendered as a `signature` note, beside a primary message
    /// that stays the caller's own.
    pub fn failCallSite(self: *Sink, code: []const u8, span: source.Span, message: []const u8, alternative: ?Related, signature: []const u8) Error {
        self.items.append(self.allocator, .{
            .code = code,
            .span = span,
            .message = message,
            .related = alternative,
            .provenance = .{ .requirement = .{ .span = span, .message = signature, .role = .signature } },
        }) catch return error.OutOfMemory;
        return error.SourceError;
    }
};

/// Stable code for malformed or undeclared generic capability contracts.
pub const generic_requirement = "E_GENERIC_REQUIREMENT";
/// Stable code for a concrete or forwarded generic contract mismatch.
pub const generic_argument = "E_GENERIC_ARGUMENT";

/// Constant generic length syntax, kind or specialization-bound failure.
pub const generic_length = "E_GENERIC_LENGTH";

/// Stable code carried by every unresolved typed implementation obligation.
pub const typed_hole_code = "E_TYPED_HOLE";
const typed_hole_message = "unresolved implementation obligation; fill this hole before checking or execution";
const typed_hole_target = "required result type declared here";
/// Record version of the structured typed-hole obligation.
pub const obligation_version: u32 = 1;
/// Most bindings one typed-hole snapshot retains; the rest are counted as omitted.
pub const max_obligation_bindings: usize = 32;
/// Most generic requirements one typed-hole snapshot retains; the rest are counted as omitted.
pub const max_obligation_requirements: usize = 32;

/// One source-spelled type or contract fact retained in a hole snapshot.
pub const Fact = struct { text: []const u8, span: source.Span };
/// One binding a filling may read: in scope, initialized, and unconsumed.
pub const Binding = struct { name: []const u8, ty: []const u8, declaration: source.Span, mutable: bool };
/// One generic requirement in force at a typed hole.
pub const Requirement = struct { subject: []const u8, requirement: []const u8, span: source.Span };
/// Declared effect ceiling, permitted mutation footprint, and the facts a hole
/// cannot promise: a transitive effect summary needs whole-program checking,
/// which an unresolved hole never reaches.
pub const ObligationContract = struct {
    effects: ?Fact = null,
    mutation: ?Fact = null,
    transitive_effects: ?Fact = null,
    unusable_bindings: usize = 0,
};
/// One binding a checker offers at a typed hole, with its own usability verdict.
pub const Candidate = struct { name: []const u8, ty: []const u8, declaration: source.Span, mutable: bool, usable: bool };
/// Local facts a checker copied out of its own state for one typed hole, before
/// the sink moves them into retained storage. Every slice here is borrowed from
/// checker state and is invalid once that state is reset, so the sink copies
/// each fact before the failed-function recovery that follows the diagnostic.
pub const Findings = struct {
    function: ?Fact = null,
    expected: ?Fact = null,
    candidates: []const Candidate = &.{},
    requirements: []const Requirement = &.{},
    contract: ObligationContract = .{},
};
/// Bounded-snapshot header: record version, content identity, enclosing
/// callable, hole range, and how many facts the caps dropped.
pub const ObligationHeader = struct {
    version: u32 = obligation_version,
    snapshot: u64,
    function: ?Fact,
    site: source.Span,
    omitted: usize,
};
/// Bounded context snapshot retained beside one `E_TYPED_HOLE` diagnostic.
pub const Obligation = struct {
    header: ObligationHeader,
    declared: Fact,
    expected: ?Fact,
    bindings: []const Binding,
    requirements: []const Requirement,
    contract: ObligationContract,
};
/// What a caller must present to retrieve one recorded obligation.
pub const Query = struct { snapshot: u64, site: source.Span };

/// Content identity of a checked snapshot: the same path, text and hole range
/// keep the same identity, and an edit anywhere gives a different one, so old
/// offsets alone can never identify a hole after an edit.
pub fn snapshotId(path: []const u8, bytes: []const u8, site: source.Span) u64 {
    var hasher = std.hash.Wyhash.init(0x6d796c616e67);
    hasher.update(path);
    hasher.update(&[_]u8{0});
    hasher.update(bytes);
    hasher.update(std.mem.asBytes(&site.start));
    hasher.update(std.mem.asBytes(&site.end));
    return hasher.final();
}

/// Find the obligation a query identifies among collected diagnostics. A query
/// whose snapshot identity or exact hole range no longer matches is stale and
/// answers null rather than a different hole's snapshot.
pub fn findObligation(items: []const Diagnostic, query: Query) ?*const Obligation {
    for (items) |item| {
        const obligation = item.provenance.obligation orelse continue;
        if (obligation.header.snapshot != query.snapshot) continue;
        if (obligation.header.site.start != query.site.start) continue;
        if (obligation.header.site.end != query.site.end) continue;
        return obligation;
    }
    return null;
}

/// Copy one borrowed fact into retained storage.
fn copyFact(allocator: std.mem.Allocator, fact: Fact) std.mem.Allocator.Error!Fact {
    return .{ .text = try allocator.dupe(u8, fact.text), .span = fact.span };
}

/// Sink-owned obligation storage: every retained record lives exactly as long
/// as its sink, and every string is copied here so a later checker reset cannot
/// invalidate it.
pub const Holes = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(*const Obligation) = .empty,

    /// Release every retained snapshot. A diagnostic that borrows one must not
    /// be rendered after this.
    pub fn deinit(self: *Holes) void {
        self.items.deinit(self.allocator);
        self.arena.deinit();
    }

    /// Copy one checker's findings into retained storage and return the stable
    /// record. Candidates the checker marked unusable are counted, never published.
    pub fn record(self: *Holes, site: source.Span, snapshot: u64, declared: Fact, findings: Findings) std.mem.Allocator.Error!*const Obligation {
        const arena = self.arena.allocator();
        var usable: std.ArrayList(Binding) = .empty;
        defer usable.deinit(self.allocator);
        var unusable: usize = findings.contract.unusable_bindings;
        for (findings.candidates) |candidate| {
            if (!candidate.usable) {
                unusable += 1;
                continue;
            }
            try usable.append(self.allocator, .{ .name = candidate.name, .ty = candidate.ty, .declaration = candidate.declaration, .mutable = candidate.mutable });
        }
        const kept_bindings = @min(usable.items.len, max_obligation_bindings);
        const kept_requirements = @min(findings.requirements.len, max_obligation_requirements);
        const bindings = try arena.alloc(Binding, kept_bindings);
        for (usable.items[0..kept_bindings], bindings) |input, *output| output.* = .{
            .name = try arena.dupe(u8, input.name),
            .ty = try arena.dupe(u8, input.ty),
            .declaration = input.declaration,
            .mutable = input.mutable,
        };
        const requirements = try arena.alloc(Requirement, kept_requirements);
        for (findings.requirements[0..kept_requirements], requirements) |input, *output| output.* = .{
            .subject = try arena.dupe(u8, input.subject),
            .requirement = try arena.dupe(u8, input.requirement),
            .span = input.span,
        };
        const obligation = try arena.create(Obligation);
        obligation.* = .{
            .header = .{
                .snapshot = snapshot,
                .function = if (findings.function) |function| try copyFact(arena, function) else null,
                .site = site,
                .omitted = (usable.items.len - kept_bindings) + (findings.requirements.len - kept_requirements),
            },
            .declared = try copyFact(arena, declared),
            .expected = if (findings.expected) |expected| try copyFact(arena, expected) else null,
            .bindings = bindings,
            .requirements = requirements,
            .contract = .{
                .effects = if (findings.contract.effects) |effects| try copyFact(arena, effects) else null,
                .mutation = if (findings.contract.mutation) |mutation| try copyFact(arena, mutation) else null,
                .transitive_effects = if (findings.contract.transitive_effects) |transitive| try copyFact(arena, transitive) else null,
                .unusable_bindings = unusable,
            },
        };
        try self.items.append(self.allocator, obligation);
        return obligation;
    }
};

/// Append the source-spelled requirements of every generic type parameter to a
/// hole snapshot, keeping each requirement's own declaration span.
pub fn appendRequirements(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.TypeParameter, out: *std.ArrayList(Requirement)) error{OutOfMemory}!void {
    for (parameters) |parameter| {
        const subject = src.text(parameter.name);
        for (parameter.requirements) |span| try out.append(allocator, .{ .subject = subject, .requirement = src.text(span), .span = span });
        for (parameter.named_requirements) |reference| try out.append(allocator, .{ .subject = subject, .requirement = src.text(reference.name), .span = reference.name });
        for (parameter.field_requirements) |field| try out.append(allocator, .{
            .subject = subject,
            .requirement = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ src.text(field.name), src.text(field.ty) }),
            .span = field.name,
        });
        for (parameter.operation_requirements) |operation| try out.append(allocator, .{
            .subject = subject,
            .requirement = try std.fmt.allocPrint(allocator, "{s}(...) -> {s}", .{ src.text(operation.name), src.text(operation.return_type) }),
            .span = operation.name,
        });
    }
}

/// Spell one declaration's mutation footprint from its own parameter names as
/// the `name: mut T` list a reader would write, or `none` when it declares no
/// written parameter.
pub fn mutationFact(allocator: std.mem.Allocator, src: source.Source, function: ast.Function) error{OutOfMemory}!Fact {
    if (function.signature.mut_positions.len == 0) return .{ .text = "none", .span = function.name };
    var out: std.Io.Writer.Allocating = .init(allocator);
    // The successful slice is transferred out and empties the writer, so this
    // releases only a partial buffer on an error return.
    defer out.deinit();
    out.writer.writeAll("mut(") catch return error.OutOfMemory;
    for (function.signature.mut_positions, 0..) |position, index| {
        if (index != 0) out.writer.writeAll(", ") catch return error.OutOfMemory;
        out.writer.writeAll(src.text(function.signature.parameters[position].name)) catch return error.OutOfMemory;
    }
    out.writer.writeAll(")") catch return error.OutOfMemory;
    return .{ .text = try out.toOwnedSlice(), .span = function.name };
}
