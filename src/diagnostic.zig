//! Stable diagnostics are data; only the CLI chooses an output destination.
/// Shared code for an assignment that lacks an explicit binding declaration.
pub const binding_declaration = "E_BINDING_DECLARATION";
/// Shared code for a pattern inconsistent with its declared enum payload.
pub const pattern_payload = "E_PATTERN_PAYLOAD";
/// Shared code for incorrect nominal or callable type argument counts.
pub const generic_arity = "E_GENERIC_ARITY";
/// Shared code for attempts to discard a must-handle result value.
pub const result_discard = "E_RESULT_DISCARD";
pub const tuple_arity = "E_TUPLE_ARITY";
/// Shared code for forbidden source binding/type-variable shadowing.
pub const shadowing = "E_SHADOWING";
/// A generator expression outside a call that consumes it, or asked for its length.
pub const generator = "E_GENERATOR";
/// Shared code for aggregate operations that would erase result obligations.
pub const result_operation = "E_RESULT_OPERATION";
pub const result_return_removed = "E_RESULT_RETURN_REMOVED";
/// Shared code for inconsistent obligations across continuing control-flow paths.
pub const result_path = "E_RESULT_PATH";
/// Shared code for result obligations changed by a loop continuation.
pub const result_loop = "E_RESULT_LOOP";
/// Shared code for mutation without a mutable binding.
pub const immutable = "E_IMMUTABLE";
/// Shared code for a malformed resource acquisition result.
pub const resource_result = "E_RESOURCE_RESULT";
/// Shared code for a value that is not an owned resource binding.
pub const resource_type = "E_RESOURCE_TYPE";
/// Shared diagnostic code for bounded generic parsing, checking and specialization.
pub const generic_limit = "E_GENERIC_LIMIT";
/// A type whose by-value layout cannot be built: a cycle with no finite value,
/// or a recursive value type holding what a shared box cannot (RECURSIVE-VALUES-1).
pub const recursive_record = "E_RECURSIVE_RECORD";
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const ownership_rules = @import("ownership_rules.zig");
const value_declared_here = "value declared here";

/// Closed ownership rule identifiers carried by source diagnostics.
pub const Rule = ownership_rules.Rule;
/// A diagnostic code paired with its explicitly selected ownership rule.
pub const Refusal = ownership_rules.Refusal;

/// Distinguishes rejecting errors from advisory diagnostics.
pub const Severity = enum { err, warning };
/// What a note does for the reader. `alternative` names the accepted spelling
/// of a rejected Python form, `signature` renders the accepted callee itself;
/// the other three are evidence slots, and every note that declares no role
/// keeps its slot's role, so `diagnostic-v1` output for an existing diagnostic
/// is unchanged. `cause` is the statement that made an ownership refusal's
/// earlier line an error (W2): it is printed after the other notes.
pub const Role = enum { related, origin, requirement, alternative, signature, cause };
/// Additional source span and explanatory message attached to a diagnostic.
pub const Related = struct { span: source.Span, message: []const u8, role: Role = .related };
/// Guest function and source span recorded in a bounded runtime stack trace.
pub const Trace = struct { function: []const u8, span: source.Span };
/// An exact replacement in the diagnostic's source, mapped to an original
/// module by diagnostic-v1 before a migration tool applies it.
pub const Edit = struct { span: source.Span, text: []const u8 };
/// All edits of a repair are applied together; one-edit repairs allocate none.
pub const Fix = struct {
    edit: Edit,
    more: []const Edit = &.{},

    /// Count every edit in this repair.
    pub fn count(self: Fix) usize {
        return 1 + self.more.len;
    }

    /// Read one edit by its zero-based index.
    pub fn at(self: Fix, index: usize) Edit {
        return if (index == 0) self.edit else self.more[index - 1];
    }

    /// Whether `other` makes the same edits as this repair, in the same order: the same spans and the same text.
    pub fn same(self: Fix, other: Fix) bool {
        if (self.count() != other.count()) return false;
        for (0..self.count()) |index| {
            const mine = self.at(index);
            const theirs = other.at(index);
            if (mine.span.start != theirs.span.start or mine.span.end != theirs.span.end) return false;
            if (!std.mem.eql(u8, mine.text, theirs.text)) return false;
        }
        return true;
    }
};
/// A note that points at a declaration the program does not spell (a builtin type's case or field, whose span is the
/// placeholder 0..0) has nowhere to point and is left out, rather than printed at line 1 of the first file (F-60).
/// An `alternative` or a `signature` prints without a location and is always kept.
fn located(note: ?Related) ?Related {
    const value = note orelse return null;
    if (value.role == .alternative or value.role == .signature) return value;
    if (value.span.start == 0 and value.span.end == 0) return null;
    return value;
}
/// Structured source diagnostic with optional related evidence and a bounded guest trace.
pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity = .err,
    span: source.Span,
    message: []const u8,
    related: ?Related = null,
    provenance: struct { origin: ?Related = null, requirement: ?Related = null, obligation: ?*const Obligation = null, fix: ?Fix = null, rule: ?Rule = null, cause: ?Related = null } = .{},
    // Bounded by-value guest trace needs no separate cleanup on trap paths.
    stack: struct { frames: [16]Trace = undefined, len: usize = 0, omitted: usize = 0 } = .{},

    /// The located notes in their printed order: the related fact, the origin, the requirement and the cause.
    pub fn notes(self: Diagnostic) [4]?Related {
        return .{ located(self.related), located(self.provenance.origin), located(self.provenance.requirement), located(self.provenance.cause) };
    }

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
        if (self.provenance.rule) |rule| output.writer.print("  note: ownership rule {s}\n", .{@tagName(rule)}) catch return error.OutOfMemory;
        for (self.notes()) |note| if (note) |related| {
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

/// Construct an ownership diagnostic only from a registered code/rule pair.
pub fn ownership(refusal: Refusal, span: source.Span, message: []const u8) Diagnostic {
    std.debug.assert(ownership_rules.valid(refusal));
    return .{ .code = refusal.code, .span = span, .message = message, .provenance = .{ .rule = refusal.rule } };
}

pub const Error = std.mem.Allocator.Error || error{ SourceError, InternalError };
/// What a typed hole means to the checker. `refuse` reports E_TYPED_HOLE and publishes no program;
/// `trap` checks the hole as an expression of its declared type and reports nothing, so a program
/// with holes runs until it reaches one, and that evaluation traps `R_TYPED_HOLE`. `recover` traps holes too and stands in an
/// empty body for every ordinary function whose body fails to check, so a refused check can still validate the ownership of
/// the bodies that did check (F-RC-214); the program it returns is never lowered, run or stored.
pub const HoleMode = enum { refuse, trap, recover };
/// Whether `items` holds at least one error and every error is an `E_TYPED_HOLE`.
pub fn holesOnly(items: []const Diagnostic) bool {
    var found = false;
    for (items) |item| {
        if (item.severity != .err) continue;
        if (!std.mem.eql(u8, item.code, typed_hole_code)) return false;
        found = true;
    }
    return found;
}
/// Whether `items` already holds a diagnostic with the code and the place of `item`.
pub fn holds(items: []const Diagnostic, item: Diagnostic) bool {
    for (items) |held| if (held.span.start == item.span.start and held.span.end == item.span.end and std.mem.eql(u8, held.code, item.code)) return true;
    return false;
}
/// What a unit's checks are asked to do beyond the rules: how they treat a typed hole, and whether they also check the generic
/// functions nothing instantiates (`Sink.template_probes`).
pub const Checking = struct { holes: HoleMode = .refuse, template_probes: Probes = .off };
/// Which generic functions a check also checks through stand-in instances. `off` (builds): only the instances a program makes.
/// `declaration` (`check`, W3 step 2): every template, the standard library's and the instantiated ones included, is judged at
/// its declaration through one instance per kind of type argument its bounds admit (`template_stand_ins.declarationChoice`); a
/// refusal of one is reported once, at the declaration, naming the type parameter and the kinds. `every` (the developer count of
/// W3, `selka template-stand-ins` only): every template with each kind of stand-in type, recorded in the log
/// (`template_stand_ins.zig`), refusing nothing.
pub const Probes = union(enum) {
    off,
    declaration,
    every: *@import("template_stand_ins.zig").Log,

    /// Whether the check registers any stand-in instance.
    pub fn any(self: Probes) bool {
        return self != .off;
    }
};
/// Allocator-backed collector used by lexical, syntax, and semantic validation.
pub const Sink = struct {
    items: std.ArrayList(Diagnostic) = .empty,
    allocator: std.mem.Allocator,
    /// Retained typed-hole snapshots, created on the first observed hole.
    holes: ?Holes = null,
    /// How the checker treats a `todo[T]()` hole: refused (`check`, release builds) or a typed
    /// node that traps at run time (debug builds and `selka test`).
    hole_mode: HoleMode = .refuse,
    /// Holes this check kept as traps. A check that kept any publishes no cache entry: a strict check must
    /// never replay a body that was accepted only because its hole was allowed.
    trapped_holes: u32 = 0,
    /// `check` judges each generic function at its declaration through stand-in instances (`Probes`), so an ownership error
    /// that some admitted kind of type argument makes is reported at the declaration. Builds leave it off: they lower only the
    /// instances a program uses.
    template_probes: Probes = .off,
    /// Sites whose warning, or its absence, was decided by reading the file beyond the declaration the site is in (a file
    /// waiver, a name another function binds, the file's imports: `retiring_forms.reported`). A stored record of that
    /// declaration holds only while the file is as it was (FX13), so the check summaries guard it by the file's bytes and the
    /// checked-body store keeps no body that holds one.
    file_reads: std.ArrayList(source.Span) = .empty,

    /// Append an error with a related location and return SourceError, preserving allocator failure.
    /// Release the collected diagnostics and every retained hole snapshot;
    /// diagnostic text and obligation records must not be read afterwards.
    pub fn deinit(self: *Sink) void {
        self.items.deinit(self.allocator);
        self.items = .empty;
        self.file_reads.deinit(self.allocator);
        self.file_reads = .empty;
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

    /// Append a source error and return SourceError, preserving allocator failure.
    pub fn fail(self: *Sink, code: []const u8, span: source.Span, message: []const u8) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Append a source error carrying the one edit that repairs it, and return
    /// SourceError. The edit's replacement text must outlive the sink.
    pub fn failFix(self: *Sink, code: []const u8, span: source.Span, message: []const u8, edit: Edit) Error {
        try self.appendFix(.{ .code = code, .span = span, .message = message }, edit);
        return error.SourceError;
    }

    /// Append a source error carrying `fix`, a repair of one or more edits applied together, or no fix when it is null,
    /// and return SourceError.
    pub fn failRepaired(self: *Sink, code: []const u8, span: source.Span, message: []const u8, fix: ?Fix) Error {
        var item: Diagnostic = .{ .code = code, .span = span, .message = message };
        item.provenance.fix = fix;
        self.items.append(self.allocator, item) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Append one diagnostic with a single-edit fix without failing, for a
    /// finding the caller reports and then keeps checking past.
    pub fn appendFix(self: *Sink, item: Diagnostic, edit: Edit) std.mem.Allocator.Error!void {
        var fixed = item;
        fixed.provenance.fix = .{ .edit = edit };
        try self.items.append(self.allocator, fixed);
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

    /// Append an ownership refusal whose code and actual rule are explicit.
    pub fn failOwnership(self: *Sink, refusal: Refusal, span: source.Span, message: []const u8) Error {
        self.items.append(self.allocator, ownership(refusal, span, message)) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Preserve a refusal's rule beside a certain single-edit repair.
    pub fn failOwnershipFix(self: *Sink, refusal: Refusal, span: source.Span, message: []const u8, edit: Edit) Error {
        try self.appendFix(ownership(refusal, span, message), edit);
        return error.SourceError;
    }

    /// Preserve a refusal's rule beside a related source witness.
    pub fn failOwnershipRelated(self: *Sink, refusal: Refusal, span: source.Span, message: []const u8, related: Related) Error {
        var item = ownership(refusal, span, message);
        item.related = related;
        self.items.append(self.allocator, item) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// `E_RESULT_UNHANDLED` for the binding `name` declared at `binding`, still pending where a path leaves at `exit`. The
    /// refusal sits on the binding, which is the line to change; the exit that abandoned it is the note.
    pub fn failResultUnhandled(self: *Sink, name: []const u8, binding: source.Span, exit: source.Span) Error {
        const message = std.fmt.allocPrint(self.allocator, "`{s}` is a result still unhandled on a path out of its scope: match it, return it " ++
            "or write `_ = {s}` before that exit", .{ name, name }) catch return error.OutOfMemory;
        const note = std.fmt.allocPrint(self.allocator, "this exit leaves while `{s}` is still unhandled", .{name}) catch return error.OutOfMemory;
        return self.failOwnershipRelated(.{ .code = "E_RESULT_UNHANDLED", .rule = .L1 }, binding, message, .{ .span = exit, .message = note });
    }

    /// Keep a refusal's rule, its immediate cause and its declaration witness.
    pub fn failOwnershipProvenance(self: *Sink, refusal: Refusal, span: source.Span, message: []const u8, cause: Related, declaration: source.Span) Error {
        var item = ownership(refusal, span, message);
        item.related = cause;
        item.provenance.origin = .{ .span = declaration, .message = value_declared_here };
        self.items.append(self.allocator, item) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Diagnose a transfer while retaining the selected ownership or Result rule.
    pub fn failOwnershipTransfer(self: *Sink, refusal: Refusal, span: source.Span, declaration: source.Span, transfer: ?source.Span) Error {
        const message = "value has already been transferred or handled";
        if (transfer) |at| return self.failOwnershipProvenance(refusal, span, message, .{ .span = at, .message = "earlier transfer or handling on this path" }, declaration);
        return self.failOwnershipRelated(refusal, span, message, .{ .span = declaration, .message = value_declared_here });
    }

    /// Attach accepted call syntax and signature without dropping the refusal's rule.
    pub fn failOwnershipCallSite(self: *Sink, refusal: Refusal, span: source.Span, message: []const u8, alternative: ?Related, signature: []const u8) Error {
        var item = ownership(refusal, span, message);
        item.related = alternative;
        item.provenance.requirement = .{ .span = span, .message = signature, .role = .signature };
        self.items.append(self.allocator, item) catch return error.OutOfMemory;
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
    mutation: ?Fact = null,
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
                .mutation = if (findings.contract.mutation) |mutation| try copyFact(arena, mutation) else null,
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
