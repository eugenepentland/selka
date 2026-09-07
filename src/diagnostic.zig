//! Stable diagnostics are data; only the CLI chooses an output destination.
/// Shared code for attempts to discard a must-handle result value.
pub const result_discard = "E_RESULT_DISCARD";
/// Shared code for forbidden source binding/type-variable shadowing.
pub const shadowing = "E_SHADOWING";
/// Shared code for misuse of a reference-returning function or reference result.
pub const reference_result = "E_REFERENCE_RESULT";
/// Shared code for attempts to strengthen shared reference permissions.
pub const reference_read_only = "E_REFERENCE_READ_ONLY";
/// Shared code for mismatched or invalid declared reference provenance.
pub const return_lifetime = "E_RETURN_LIFETIME";
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
const source = @import("source.zig");
const value_declared_here = "value declared here";

/// Distinguishes rejecting errors from advisory diagnostics.
pub const Severity = enum { err, warning };
/// Additional source span and explanatory message attached to a diagnostic.
pub const Related = struct { span: source.Span, message: []const u8 };
/// Guest function and source span recorded in a bounded runtime stack trace.
pub const Trace = struct { function: []const u8, span: source.Span };
/// Structured source diagnostic with optional related evidence and a bounded guest trace.
pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity = .err,
    span: source.Span,
    message: []const u8,
    related: ?Related = null,
    provenance: struct { origin: ?Related = null, requirement: ?Related = null } = .{},
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

    /// Append an error with a related location and return SourceError, preserving allocator failure.
    /// Release the collected diagnostic array; diagnostic text continues to borrow source storage.
    pub fn deinit(self: *Sink) void {
        self.items.deinit(self.allocator);
        self.items = .empty;
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

    /// Explain the actual returned borrow, its owner and the input required by the signature.
    pub fn failReturnLifetime(self: *Sink, span: source.Span, loan: source.Span, owner: source.Span, input: source.Span) Error {
        self.items.append(self.allocator, .{
            .code = return_lifetime,
            .span = span,
            .message = "returned reference does not borrow from the declared input parameter",
            .related = .{ .span = loan, .message = "returned borrow declared here" },
            .provenance = .{
                .origin = .{ .span = owner, .message = value_declared_here },
                .requirement = .{ .span = input, .message = "result lifetime is tied to this input" },
            },
        }) catch return error.OutOfMemory;
        return error.SourceError;
    }

    /// Identify the earlier extraction when a moved field is accessed again.
    pub fn failMovedField(self: *Sink, span: source.Span, declaration: source.Span, transfer: source.Span) Error {
        return self.failProvenance("E_FIELD_MOVED", span, "field has already been transferred", .{ .span = transfer, .message = "earlier field transfer on this path" }, declaration);
    }

    /// Identify a missing field when the incomplete record is used as a whole.
    pub fn failPartialMove(self: *Sink, span: source.Span, declaration: source.Span, transfer: source.Span) Error {
        return self.failProvenance("E_PARTIAL_MOVE", span, "record has missing fields; access remaining fields individually or replace the binding", .{ .span = transfer, .message = "earlier field transfer on this path" }, declaration);
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
};

/// Owned/result references remain restricted to supported copyable buffer views.
pub const result_borrow = "E_RESULT_BORROW";

/// Stable code for malformed or undeclared generic capability contracts.
pub const generic_requirement = "E_GENERIC_REQUIREMENT";
/// Stable code for a concrete or forwarded generic contract mismatch.
pub const generic_argument = "E_GENERIC_ARGUMENT";

/// Invalid argument to a reference parameter.
pub const reference_argument = "E_REFERENCE_ARGUMENT";
