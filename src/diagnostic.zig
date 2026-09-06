//! Stable diagnostics are data; only the CLI chooses an output destination.
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
const std = @import("std");
const source = @import("source.zig");

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
        if (self.related) |related| {
            const at = src.locate(related.span.start);
            output.writer.print("  note: {s}:{d}:{d}: {s}\n", .{ at.path, at.line, at.column, related.message }) catch return error.OutOfMemory;
        }
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

    /// Append a source error and return SourceError, preserving allocator failure.
    pub fn fail(self: *Sink, code: []const u8, span: source.Span, message: []const u8) Error {
        self.items.append(self.allocator, .{ .code = code, .span = span, .message = message }) catch return error.OutOfMemory;
        return error.SourceError;
    }
};
