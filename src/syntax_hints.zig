//! Idiom rewrites: eight shapes of compiler-shaped code that a shorter spelling already covers.
//!
//! Each one is a checker warning with the certain `fix` that rewrites it, and `selka lint` reads it as an
//! `L_*` finding the way it reads `W_NEEDLESS_COPY`:
//!
//! - `W_BYTE_SET`: `c == 43 or c == 45 or c == 47` on an integer is `c in b"+-/"`;
//! - `W_RANGE_CHAIN`: `x >= a and x <= b` is `a <= x <= b`;
//! - `W_LITERAL_MATCH`: an `if x == A ... elif x == B ...` chain on one integer, `str` or `bytes` is a literal `match`;
//! - `W_PATTERN_SHORTHAND`: `case text(value=value)` is `case text(value)`;
//! - `W_OPTION_TRY`: an Option `match` whose `None` arm only returns `None`, in a function that returns an
//!   Option, is `const x = try ...`;
//! - `W_ELSE_IS_TRY`: `const x = f() else Err(e): fail e` (or `else: return None` in a function that returns an
//!   Option) only passes the failure on, which `const x = try f()` does;
//! - `W_MATCH_ELSE`: a two-arm `match` over an Option or a Result whose failure arm leaves is `const x = f() else:` with
//!   that arm's block, and the success arm's statements after it (FR20);
//! - `W_MATCH_IS`: a two-arm `match` over an Option or a Result one of whose arms does nothing is `if f() is Some(x):`
//!   (or `is None`, `is Ok(x)`, `is Err(e)`) with the other arm's statements (FR20).
//!
//! The pass reads the syntax tree, so a shape is exact: the value compared is a plain name, field or index
//! whose evaluation has no effect, the bytes are integer literals, and a statement rewrite copies lines
//! only where it can re-indent them without changing what a token spells. The one question the syntax cannot
//! answer, whether the compared value has a type the rewrite accepts (an integer for a byte set; an integer, a
//! `str` or `bytes` name for a literal `match`), is asked of the checked body (`Checked`). Where any condition
//! fails the pass says nothing; a false positive would be a defect, a miss only a missed hint. A reasoned
//! `# lint: allow RULE reason="..."` comment on the line above silences the warning, as for the other lints.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const checked_types = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const bind_or_else = @import("bind_or_else.zig");

/// `c == 43 or c == 45 or c == 47` where `c in b"+-/"` tests the same set.
pub const byte_set_code = "W_BYTE_SET";
/// `x >= a and x <= b` where `a <= x <= b` is one comparison chain.
pub const range_chain_code = "W_RANGE_CHAIN";
/// An `if`/`elif` chain of `x == literal` tests that is a literal `match`.
pub const literal_match_code = "W_LITERAL_MATCH";
/// A pattern field `name=name` that the bare `name` binds as well.
pub const pattern_shorthand_code = "W_PATTERN_SHORTHAND";
/// An Option `match` whose `None` arm only returns `None`, where `try` unwraps it.
pub const option_try_code = "W_OPTION_TRY";

/// A bind-or-else whose `else` block only passes the failure on, where `try` does the same.
pub const else_is_try_code = "W_ELSE_IS_TRY";
/// A two-arm Option or Result `match` whose failure arm leaves, where `const x = f() else:` unwraps the value.
pub const match_else_code = "W_MATCH_ELSE";
/// A two-arm Option or Result `match` one of whose arms does nothing, where `if f() is Some(x):` tests the value.
pub const match_is_code = "W_MATCH_IS";

/// The rule names a site waiver writes for each warning, in the order of the codes above.
pub const rules = [_][]const u8{ "byte-set", "range-chain", "literal-match", "pattern-shorthand", "option-try", "else-is-try", "match-else", "match-is" };

/// The rules whose file-wide waivers decide whether a stored repair of a function still holds (`Guards`): the idiom
/// rules above. W13's refusals no waiver excuses (`retiring_forms.zig`); their sites key a function by its whole file.
const guarded_rules = rules;

/// The fewest equality tests in an or-chain that `byte_set_code` reports.
const min_set_tests = 3;
/// The fewest `x == literal` tests in a chain that `literal_match_code` reports.
const min_match_tests = 3;
/// The deepest expression the pass reads, so a pathological source cannot exhaust the stack.
const depth_limit = 64;
/// The most operands of one `and` or `or` chain the pass reads.
const chain_limit = 512;

const Span = source.Span;
const Error = std.mem.Allocator.Error;

/// One `# lint: allow-file RULE reason="..."` comment: the rule it silences, in the file it stands in.
const FileWaiver = struct { rule: []const u8, path: []const u8 };

/// What the pass knows of the program's waivers: the file-wide ones, read from the source when the first warning needs them,
/// and the sites a waiver silenced.
const Waivers = struct { files: ?[]const FileWaiver = null, silenced: std.ArrayList(Span) = .empty };

/// What decides, for the functions of a program, whether an idiom warning is reported at a site: the file-wide waivers of its file,
/// and the comment on the line above the site. A warning stored with a function is valid while this digest of its region is the one it
/// was stored under (a comment inside the region is part of the region's own bytes).
pub const Guards = struct {
    /// Digest of the `allow-file` waivers found in each file read so far, by file path (a file with none has no entry).
    files: std.StringHashMapUnmanaged([32]u8) = .empty,
    /// The files already read, by their index in the merged source (`unplaced` for a source with no origins).
    scanned: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// The digest of each file's whole bytes, by its index in the merged source, for `wide`.
    whole: std.AutoHashMapUnmanaged(usize, [32]u8) = .empty,
    memory: std.mem.Allocator,
    src: source.Source,

    const unplaced = std.math.maxInt(usize);

    /// A reader of the file-wide waivers of the files of `src`. A file is read when the first function of it asks (`of`): most programs
    /// hold a stored repair or a silenced site in few files, and the rest of a large project's bytes are never scanned.
    pub fn read(memory: std.mem.Allocator, src: source.Source) Error!Guards {
        return .{ .memory = memory, .src = src };
    }

    fn scan(self: *Guards, input: usize) Error!void {
        const seen = try self.scanned.getOrPut(self.memory, input);
        if (seen.found_existing) return;
        const bytes: []const u8, const path: []const u8 = if (input == unplaced)
            .{ self.src.bytes, self.src.path }
        else
            .{ self.src.bytes[self.src.origins[input].start..][0..self.src.origins[input].original.bytes.len], self.src.origins[input].original.path };
        var hash = std.crypto.hash.Blake3.init(.{});
        var found = false;
        const marker = "# lint:";
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, bytes, cursor, marker)) |at| {
            const end = std.mem.indexOfScalarPos(u8, bytes, at, '\n') orelse bytes.len;
            cursor = end;
            for (guarded_rules) |rule| {
                if (!Pass.waives(bytes[at..end], "allow-file", rule)) continue;
                found = true;
                hash.update(rule);
                hash.update("\x1f");
            }
        }
        if (!found) return;
        var out: [32]u8 = undefined;
        hash.final(&out);
        try self.files.put(self.memory, path, out);
    }

    /// The digest for the function whose declaration region starts at `region_start`: its file's waivers and the line above the region.
    pub fn of(self: *Guards, region_start: usize) Error![32]u8 {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update("idiom-guard-v1");
        const located = self.src.originalSpan(.{ .start = region_start, .end = region_start }) catch null;
        try self.scan(if (located) |found| found.input else unplaced);
        const path = self.src.locate(region_start).path;
        if (self.files.get(path)) |digest| hash.update(&digest);
        const start = @min(region_start, self.src.bytes.len);
        if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..start], '\n')) |line_break| {
            const above = if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..line_break], '\n')) |previous| previous + 1 else 0;
            const line = self.src.bytes[above..line_break];
            if (std.mem.indexOf(u8, line, "# lint:") != null) hash.update(line);
        }
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// The guard of a function holding a site whose warning was decided by reading its file beyond the function (a W13
    /// warning: `Sink.file_reads`): `of`, and the digest of the whole file the region is in, so any edit of the file checks
    /// the function again (FX13). Its own domain, so it never equals a digest `of` gives.
    pub fn wide(self: *Guards, region_start: usize) Error![32]u8 {
        const narrow = try self.of(region_start);
        const located = self.src.originalSpan(.{ .start = region_start, .end = region_start }) catch null;
        const input = if (located) |found| found.input else unplaced;
        const entry = try self.whole.getOrPut(self.memory, input);
        if (!entry.found_existing) {
            const bytes = if (input == unplaced) self.src.bytes else self.src.bytes[self.src.origins[input].start..][0..self.src.origins[input].original.bytes.len];
            std.crypto.hash.Blake3.hash(bytes, entry.value_ptr, .{});
        }
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update("file-read-guard-v1");
        hash.update(&narrow);
        hash.update(entry.value_ptr);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }
};

/// The checked program a warning asks about the type of a value, and the checked function of each syntax function (none for
/// a generic function, whose body is checked per instance).
pub const Checked = struct { program: checked_types.Program, ordinary_ids: []const ?checked_types.FunctionId };

/// The sink the warnings go to, and where this pass's own warnings begin in it, so a site read twice reports once.
const Output = struct { sink: *diagnostic.Sink, first: usize };

/// What the function being read says: whether it returns an Option and declares no failure, and its checked function (none for a
/// generic function, whose body is checked per instance); and the statements after the one being read in its block.
const Reading = struct { option_return: bool = false, current: ?checked_types.FunctionId = null, following: []const ast.StatementId = &.{} };

/// One checked program's syntax and the sink the warnings go to.
const Pass = struct {
    memory: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    checked: Checked,
    output: Output,
    /// What the function being read says.
    reading: Reading = .{},
    /// The waivers this pass met.
    waivers: Waivers = .{},

    fn node(self: *const Pass, id: ast.NodeId) ast.Node {
        return self.syntax.nodes.items[@backingInt(id)];
    }

    fn statementOf(self: *const Pass, id: ast.StatementId) ast.Statement {
        return self.syntax.statements.items[@backingInt(id)];
    }

    fn text(self: *const Pass, span: Span) []const u8 {
        return self.src.text(span);
    }

    // ---- shapes of expressions ------------------------------------------------------------------------

    /// Whether two expressions are the same plain expression, spelled with the same names.
    fn same(self: *const Pass, a: ast.NodeId, b: ast.NodeId, depth: usize) bool {
        if (depth > depth_limit) return false;
        const x = self.node(a);
        const y = self.node(b);
        if (std.meta.activeTag(x.data) != std.meta.activeTag(y.data)) return false;
        return switch (x.data) {
            .name => |name| std.mem.eql(u8, self.text(name), self.text(y.data.name)),
            .integer => |digits| std.mem.eql(u8, self.text(digits), self.text(y.data.integer)),
            .field => |field| std.mem.eql(u8, self.text(field.name), self.text(y.data.field.name)) and self.same(field.base, y.data.field.base, depth + 1),
            .index => |index| self.same(index.base, y.data.index.base, depth + 1) and self.same(index.index, y.data.index.index, depth + 1),
            .length => |operand| self.same(operand, y.data.length, depth + 1),
            .unary => |unary| unary.op == y.data.unary.op and self.same(unary.operand, y.data.unary.operand, depth + 1),
            .binary => |binary| binary.op == y.data.binary.op and !binary.chained and !y.data.binary.chained and
                self.same(binary.left, y.data.binary.left, depth + 1) and self.same(binary.right, y.data.binary.right, depth + 1),
            else => false,
        };
    }

    /// Whether evaluating an expression twice, or once instead of twice, is the same: a name, a literal, a
    /// field, an index or a length of such, or arithmetic over them. A call is never plain.
    fn plain(self: *const Pass, id: ast.NodeId, depth: usize) bool {
        if (depth > depth_limit) return false;
        return switch (self.node(id).data) {
            .name, .integer => true,
            .field => |field| self.plain(field.base, depth + 1),
            .index => |index| self.plain(index.base, depth + 1) and self.plain(index.index, depth + 1),
            .length => |operand| self.plain(operand, depth + 1),
            .unary => |unary| (unary.op == .neg) and self.plain(unary.operand, depth + 1),
            .binary => |binary| switch (binary.op) {
                .add, .sub, .mul, .floor_div, .floor_rem => !binary.chained and self.plain(binary.left, depth + 1) and self.plain(binary.right, depth + 1),
                else => false,
            },
            else => false,
        };
    }

    /// The value of an integer literal node, when it is one.
    fn literal(self: *const Pass, id: ast.NodeId) ?u64 {
        const data = self.node(id).data;
        if (data != .integer) return null;
        var digits: [64]u8 = undefined;
        var count: usize = 0;
        for (self.text(data.integer)) |byte| {
            if (byte == '_') continue;
            if (count == digits.len) return null;
            digits[count] = byte;
            count += 1;
        }
        return std.fmt.parseInt(u64, digits[0..count], 0) catch null;
    }

    /// Append the operands of a chain of `op` nodes, left to right. False when the chain is too long.
    fn flatten(self: *const Pass, id: ast.NodeId, op: ast.BinaryOp, out: *std.ArrayList(ast.NodeId), depth: usize) Error!bool {
        if (depth > depth_limit * 4) return false;
        const data = self.node(id).data;
        if (data == .binary and data.binary.op == op and !data.binary.chained) {
            if (!try self.flatten(data.binary.left, op, out, depth + 1)) return false;
            return self.flatten(data.binary.right, op, out, depth + 1);
        }
        if (out.items.len == chain_limit) return false;
        try out.append(self.memory, id);
        return true;
    }

    /// Whether the only thing between two operands is the keyword that joins them.
    fn joined(self: *const Pass, before: ast.NodeId, after: ast.NodeId, keyword: []const u8) bool {
        const first = self.node(before).span.end;
        const second = self.node(after).span.start;
        if (first > second) return false;
        return std.mem.eql(u8, std.mem.trim(u8, self.src.bytes[first..second], " \t"), keyword);
    }

    // ---- the warning --------------------------------------------------------------------------------

    /// Whether a reasoned `# lint: allow RULE reason="..."` comment on the line above `at`, or a
    /// `# lint: allow-file RULE reason="..."` comment anywhere in the same file, silences the rule.
    fn waived(self: *Pass, at: usize, rule: []const u8) Error!bool {
        const marker = "# lint:";
        const start = @min(at, self.src.bytes.len);
        if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..start], '\n')) |line_break| {
            const above = if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..line_break], '\n')) |previous| previous + 1 else 0;
            if (std.mem.indexOf(u8, self.src.bytes[above..line_break], marker)) |offset| {
                if (waives(self.src.bytes[above + offset .. line_break], "allow", rule)) return true;
            }
        }
        const waivers = try self.fileWaiversOfProgram();
        if (waivers.len == 0) return false;
        const path = self.src.locate(start).path;
        for (waivers) |waiver| {
            if (std.mem.eql(u8, waiver.rule, rule) and std.mem.eql(u8, waiver.path, path)) return true;
        }
        return false;
    }

    /// Every file-wide waiver of the program, found by reading the source once. A warning used to read the
    /// whole source for its own check, so the pass cost the warnings it reported times the program's size.
    fn fileWaiversOfProgram(self: *Pass) Error![]const FileWaiver {
        if (self.waivers.files) |known| return known;
        const marker = "# lint:";
        var found: std.ArrayList(FileWaiver) = .empty;
        var cursor: usize = 0;
        while (std.mem.indexOfPos(u8, self.src.bytes, cursor, marker)) |at| {
            const end = std.mem.indexOfScalarPos(u8, self.src.bytes, at, '\n') orelse self.src.bytes.len;
            cursor = end;
            for (rules) |rule| {
                if (!waives(self.src.bytes[at..end], "allow-file", rule)) continue;
                try found.append(self.memory, .{ .rule = rule, .path = self.src.locate(at).path });
            }
        }
        self.waivers.files = found.items;
        return found.items;
    }

    /// Whether one `# lint:` comment is a `directive` (`allow` or `allow-file`) naming `rule` with a reason.
    pub fn waives(comment: []const u8, directive: []const u8, rule: []const u8) bool {
        const after = std.mem.trim(u8, comment["# lint:".len..], " \t");
        if (!std.mem.startsWith(u8, after, directive)) return false;
        const rest = std.mem.trim(u8, after[directive.len..], " \t");
        const space = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
        if (!std.mem.eql(u8, rest[0..space], rule)) return false;
        const at_reason = std.mem.indexOf(u8, comment, "reason=") orelse return false;
        return std.mem.trim(u8, comment[at_reason + "reason=".len ..], " \t\"'").len != 0;
    }

    /// Report `code` at `span` with the edits that rewrite it, or note the site as silenced when a waiver covers it.
    fn report(self: *Pass, code: []const u8, rule: []const u8, span: Span, message: []const u8, edits: []const diagnostic.Edit) Error!void {
        if (try self.waived(span.start, rule)) return self.waivers.silenced.append(self.memory, span);
        std.debug.assert(edits.len != 0);
        // The arms of a `case a(x) | b(x):` list each read a copy of one body, so a site of it is met once per arm.
        for (self.output.sink.items.items[self.output.first..]) |earlier| {
            if (earlier.span.start == span.start and earlier.span.end == span.end and std.mem.eql(u8, earlier.code, code)) return;
        }
        try self.output.sink.items.append(self.memory, .{
            .severity = .warning,
            .code = code,
            .span = span,
            .message = message,
            .provenance = .{ .fix = .{ .edit = edits[0], .more = if (edits.len > 1) edits[1..] else &.{} } },
        });
    }

    // ---- W_BYTE_SET -----------------------------------------------------------------------------------

    /// One `subject == literal` test of a byte.
    const ByteTest = struct { subject: ast.NodeId, value: u8 };

    fn byteTest(self: *const Pass, id: ast.NodeId) ?ByteTest {
        const data = self.node(id).data;
        if (data != .binary or data.binary.op != .eq or data.binary.chained) return null;
        const compare = data.binary;
        const left = self.literal(compare.left);
        const right = self.literal(compare.right);
        if ((left == null) == (right == null)) return null;
        const value = left orelse right.?;
        const subject = if (left == null) compare.left else compare.right;
        if (value > 255 or !self.plain(subject, 0)) return null;
        return .{ .subject = subject, .value = @intCast(value) };
    }

    /// The byte-literal spelling of a set of octets, in first-seen order. A set holding a double quote and no
    /// single quote is spelled with single quotes, the form `selka fmt` writes.
    fn byteLiteral(self: *Pass, values: []const u8) Error![]const u8 {
        const single = std.mem.indexOfScalar(u8, values, '"') != null and std.mem.indexOfScalar(u8, values, '\'') == null;
        const quote: u8 = if (single) '\'' else '"';
        var out: std.ArrayList(u8) = .empty;
        try out.append(self.memory, 'b');
        try out.append(self.memory, quote);
        for (values) |value| switch (value) {
            '\n' => try out.appendSlice(self.memory, "\\n"),
            '\r' => try out.appendSlice(self.memory, "\\r"),
            '\t' => try out.appendSlice(self.memory, "\\t"),
            0x20...0x7e => {
                if (value == quote or value == '\\') try out.append(self.memory, '\\');
                try out.append(self.memory, value);
            },
            else => try out.print(self.memory, "\\x{x:0>2}", .{value}),
        };
        try out.append(self.memory, quote);
        return out.toOwnedSlice(self.memory);
    }

    /// Report each run of byte equalities on one value in an or-chain.
    fn orChain(self: *Pass, id: ast.NodeId) Error!void {
        var operands: std.ArrayList(ast.NodeId) = .empty;
        defer operands.deinit(self.memory);
        if (!try self.flatten(id, .logical_or, &operands, 0)) return;
        var first: usize = 0;
        while (first < operands.items.len) {
            const start = self.byteTest(operands.items[first]) orelse {
                first += 1;
                continue;
            };
            var last = first + 1;
            while (last < operands.items.len) : (last += 1) {
                const next = self.byteTest(operands.items[last]) orelse break;
                if (!self.same(start.subject, next.subject, 0) or !self.joined(operands.items[last - 1], operands.items[last], "or")) break;
            }
            if (last - first >= min_set_tests) try self.reportByteSet(operands.items[first..last], start.subject);
            first = last;
        }
    }

    fn reportByteSet(self: *Pass, run: []const ast.NodeId, subject: ast.NodeId) Error!void {
        if (!try self.subjectTyped(subject, .integer)) return;
        var values: std.ArrayList(u8) = .empty;
        defer values.deinit(self.memory);
        for (run) |id| {
            const value = self.byteTest(id).?.value;
            if (std.mem.indexOfScalar(u8, values.items, value) == null) try values.append(self.memory, value);
        }
        const span: Span = .{ .start = self.node(run[0]).span.start, .end = self.node(run[run.len - 1]).span.end };
        const name = self.text(self.node(subject).span);
        const set = try self.byteLiteral(values.items);
        const replacement = try std.fmt.allocPrint(self.memory, "{s} in {s}", .{ name, set });
        const message = try std.fmt.allocPrint(self.memory, "{d} equality tests of `{s}` against bytes: `{s}` tests the same set", .{ run.len, name, replacement });
        try self.report(byte_set_code, rules[0], span, message, &.{.{ .span = span, .text = replacement }});
    }

    // ---- W_RANGE_CHAIN --------------------------------------------------------------------------------

    /// One comparison of a value with a bound, normalized so the value is on the left.
    const Bound = struct { bound: ast.NodeId, lower: bool, strict: bool };

    /// The bound that comparison `id` puts on `subject`, when it compares `subject` with something plain.
    fn boundOn(self: *const Pass, id: ast.NodeId, subject: ast.NodeId) ?Bound {
        const data = self.node(id).data;
        if (data != .binary or data.binary.chained) return null;
        const compare = data.binary;
        const subject_left = self.same(compare.left, subject, 0);
        const subject_right = self.same(compare.right, subject, 0);
        if (subject_left == subject_right) return null;
        const bound = if (subject_left) compare.right else compare.left;
        if (!self.plain(bound, 0)) return null;
        // `S op bound`, or `bound op S` read from the other side.
        const lower = switch (compare.op) {
            .ge, .gt => subject_left,
            .le, .lt => !subject_left,
            else => return null,
        };
        return .{ .bound = bound, .lower = lower, .strict = compare.op == .gt or compare.op == .lt };
    }

    /// Whether a bound is an integer literal, or arithmetic with one in it.
    fn scalarBound(self: *const Pass, id: ast.NodeId, depth: usize) bool {
        if (depth > depth_limit) return false;
        return switch (self.node(id).data) {
            .integer => true,
            .unary => |unary| unary.op == .neg and self.scalarBound(unary.operand, depth + 1),
            .binary => |binary| self.scalarBound(binary.left, depth + 1) or self.scalarBound(binary.right, depth + 1),
            else => false,
        };
    }

    /// Report each adjacent pair of bounds on one value in an and-chain.
    fn andChain(self: *Pass, id: ast.NodeId) Error!void {
        var operands: std.ArrayList(ast.NodeId) = .empty;
        defer operands.deinit(self.memory);
        if (!try self.flatten(id, .logical_and, &operands, 0)) return;
        var at: usize = 0;
        while (at + 1 < operands.items.len) {
            if (try self.reportRange(operands.items[at], operands.items[at + 1])) {
                at += 2;
            } else at += 1;
        }
    }

    fn reportRange(self: *Pass, first: ast.NodeId, second: ast.NodeId) Error!bool {
        if (!self.joined(first, second, "and")) return false;
        const data = self.node(first).data;
        if (data != .binary or data.binary.chained) return false;
        // The value is whichever operand of the first comparison the second compares as well.
        for ([_]ast.NodeId{ data.binary.left, data.binary.right }) |subject| {
            if (!self.plain(subject, 0) or self.node(subject).data == .integer) continue;
            const a = self.boundOn(first, subject) orelse continue;
            const b = self.boundOn(second, subject) orelse continue;
            if (a.lower == b.lower) continue;
            const low = if (a.lower) a else b;
            const high = if (a.lower) b else a;
            // A Simd comparison chain is lane-wise `and`, not a chain; an integer literal beside the value
            // is the evidence the operands are scalars (a Simd operator needs a Simd on both sides).
            if (!self.scalarBound(low.bound, 0) and !self.scalarBound(high.bound, 0)) continue;
            const span: Span = .{ .start = self.node(first).span.start, .end = self.node(second).span.end };
            const replacement = try std.fmt.allocPrint(self.memory, "{s} {s} {s} {s} {s}", .{
                self.text(self.node(low.bound).span),
                if (low.strict) "<" else "<=",
                self.text(self.node(subject).span),
                if (high.strict) "<" else "<=",
                self.text(self.node(high.bound).span),
            });
            const message = try std.fmt.allocPrint(self.memory, "two comparisons bound `{s}` from both sides: `{s}` is one chain", .{ self.text(self.node(subject).span), replacement });
            try self.report(range_chain_code, rules[1], span, message, &.{.{ .span = span, .text = replacement }});
            return true;
        }
        return false;
    }

    // ---- expressions --------------------------------------------------------------------------------

    /// Read an expression and every expression inside it.
    fn expression(self: *Pass, id: ast.NodeId, depth: usize) Error!void {
        if (depth > depth_limit) return;
        const data = self.node(id).data;
        switch (data) {
            .binary => |binary| {
                if (binary.op == .logical_or and !binary.chained) {
                    try self.orChain(id);
                    return self.descend(id, .logical_or, depth);
                }
                if (binary.op == .logical_and and !binary.chained) {
                    try self.andChain(id);
                    return self.descend(id, .logical_and, depth);
                }
                try self.expression(binary.left, depth + 1);
                try self.expression(binary.right, depth + 1);
            },
            .unary => |unary| try self.expression(unary.operand, depth + 1),
            .membership => |member| {
                try self.expression(member.needle, depth + 1);
                try self.expression(member.container, depth + 1);
            },
            .call => |call| for (call.arguments) |argument| try self.expression(argument, depth + 1),
            .method_call => |call| {
                try self.expression(call.base, depth + 1);
                for (call.arguments) |argument| try self.expression(argument, depth + 1);
            },
            .field => |field| try self.expression(field.base, depth + 1),
            .index => |index| {
                try self.expression(index.base, depth + 1);
                try self.expression(index.index, depth + 1);
            },
            .length, .propagate, .unwrap, .mut_argument, .own_argument => |operand| try self.expression(operand, depth + 1),
            .list_literal => |items| for (items) |item| try self.expression(item, depth + 1),
            .format => |parts| for (parts) |part| try self.expression(part, depth + 1),
            .format_field => |field| try self.expression(field.value, depth + 1),
            .variant => |variant| {
                if (variant.value) |value| try self.expression(value, depth + 1);
                for (variant.values) |value| try self.expression(value, depth + 1);
            },
            .record => |record| for (record.fields) |field| try self.expression(field.value, depth + 1),
            .field_assignment => |assign| try self.expression(assign.value, depth + 1),
            .index_assignment => |assign| try self.expression(assign.value, depth + 1),
            .cast, .wrap => |typed| try self.expression(typed.value, depth + 1),
            else => {},
        }
    }

    /// Read the operands of a chain once its own warnings are reported, so no sub-chain is judged twice.
    fn descend(self: *Pass, id: ast.NodeId, op: ast.BinaryOp, depth: usize) Error!void {
        const data = self.node(id).data;
        if (data == .binary and data.binary.op == op and !data.binary.chained) {
            try self.descend(data.binary.left, op, depth + 1);
            return self.descend(data.binary.right, op, depth + 1);
        }
        try self.expression(id, depth + 1);
    }

    // ---- statements ---------------------------------------------------------------------------------

    /// Read a function: its statements and, from them, every expression.
    fn function(self: *Pass, item: ast.Function) Error!void {
        const returns = std.mem.trim(u8, self.text(item.signature.return_type), " \t");
        self.reading.option_return = item.signature.failure_type == null and returns.len > 1 and returns[returns.len - 1] == '?';
        try self.statement(item.body, false, 0);
    }

    /// Read a statement; `last` says it ends its block, `elif` that it continues a chain already read.
    fn statement(self: *Pass, id: ast.StatementId, last: bool, depth: usize) Error!void {
        return self.statementIn(id, last, false, depth);
    }

    fn statementIn(self: *Pass, id: ast.StatementId, last: bool, elif: bool, depth: usize) Error!void {
        if (depth > depth_limit) return;
        const item = self.statementOf(id);
        switch (item.data) {
            .block => |children| for (children, 0..) |child, index| {
                self.reading.following = children[index + 1 ..];
                try self.statement(child, index + 1 == children.len, depth + 1);
            },
            .ret, .fail, .discard => |value| try self.expression(value, 0),
            .binding => |binding| try self.expression(binding.value, 0),
            .assignment => |assignment| try self.expression(assignment.value, 0),
            .assertion => |assertion| try self.expression(assertion.condition, 0),
            .branch => |branch| {
                if (!elif) try self.literalChain(id);
                try self.expression(branch.condition, 0);
                try self.statement(branch.then_body, false, depth + 1);
                if (branch.else_body) |other| {
                    const continues = self.statementOf(other).data == .branch;
                    try self.statementIn(other, false, continues, depth + 1);
                }
            },
            .loop => |loop| {
                try self.expression(loop.condition, 0);
                try self.statement(loop.body, false, depth + 1);
            },
            .for_each => |each| {
                try self.expression(each.iterable, 0);
                try self.statement(each.body, false, depth + 1);
            },
            .for_range => |range| try self.statement(range.body, false, depth + 1),
            .with_scope => |scope| try self.statement(scope.body, false, depth + 1),
            .match => |match| {
                const rest = self.reading.following;
                try self.expression(match.value, 0);
                for (match.arms) |arm| {
                    try self.shorthand(arm);
                    try self.statement(arm.body, false, depth + 1);
                }
                const tried = last and try self.optionMatch(id);
                try self.elseIsTry(id);
                if (!tried) try self.unwrapMatch(id, rest);
            },
            else => {},
        }
    }

    // ---- W_PATTERN_SHORTHAND ------------------------------------------------------------------------

    /// Report an arm whose pattern binds a field under the field's own name with its label spelled out. Only the
    /// fields of the arm's own case count: the checker takes the bare form at the top of an arm and refuses it in a
    /// nested pattern (`E_NAMED_PATTERN`, `case Some(item(value, note))`), so a nested field keeps its label.
    fn shorthand(self: *Pass, arm: ast.MatchArm) Error!void {
        var edits: std.ArrayList(diagnostic.Edit) = .empty;
        defer edits.deinit(self.memory);
        try self.labels(arm.payload_patterns, &edits);
        if (edits.items.len == 0) return;
        const names = if (edits.items.len == 1) "a field" else "fields";
        const message = try std.fmt.allocPrint(self.memory, "{s} bound under {s} own name: drop the `name=` label and write the bare name", .{ names, if (edits.items.len == 1) "its" else "their" });
        try self.report(pattern_shorthand_code, rules[3], arm.name, message, try self.memory.dupe(diagnostic.Edit, edits.items));
    }

    fn labels(self: *Pass, fields: []const ast.PatternField, edits: *std.ArrayList(diagnostic.Edit)) Error!void {
        for (fields) |field| switch (field.pattern.data) {
            .binding => |binding| {
                const label = field.name orelse continue;
                const name = binding orelse continue;
                if (!std.mem.eql(u8, self.text(label), self.text(name))) continue;
                if (name.start < label.end) continue;
                if (!std.mem.eql(u8, std.mem.trim(u8, self.src.bytes[label.end..name.start], " \t"), "=")) continue;
                try edits.append(self.memory, .{ .span = .{ .start = label.start, .end = name.start }, .text = "" });
            },
            .variant => {},
        };
    }

    // ---- W_LITERAL_MATCH ------------------------------------------------------------------------------

    /// One literal an `if` chain compares a value with.
    const Literal = struct { kind: enum { integer, text, bytes }, id: ast.NodeId };

    fn matchLiteral(self: *const Pass, id: ast.NodeId) ?Literal {
        return switch (self.node(id).data) {
            .integer => if (self.literal(id) != null) .{ .kind = .integer, .id = id } else null,
            .text => .{ .kind = .text, .id = id },
            .bytes => .{ .kind = .bytes, .id = id },
            else => null,
        };
    }

    /// Whether two literals of one kind hold the same value.
    fn sameLiteral(self: *const Pass, a: Literal, b: Literal) bool {
        return switch (a.kind) {
            .integer => self.literal(a.id).? == self.literal(b.id).?,
            .text => std.mem.eql(u8, self.node(a.id).data.text, self.node(b.id).data.text),
            .bytes => std.mem.eql(u8, self.node(a.id).data.bytes, self.node(b.id).data.bytes),
        };
    }

    /// `subject == literal` as a test of a chain's value, in either order.
    const Test = struct { subject: ast.NodeId, literal: Literal };

    fn literalTest(self: *const Pass, id: ast.NodeId) ?Test {
        const data = self.node(id).data;
        if (data != .binary or data.binary.op != .eq or data.binary.chained) return null;
        const left = self.matchLiteral(data.binary.left);
        const right = self.matchLiteral(data.binary.right);
        if ((left == null) == (right == null)) return null;
        const subject = if (left == null) data.binary.left else data.binary.right;
        if (!self.plain(subject, 0) or self.node(subject).data == .integer) return null;
        return .{ .subject = subject, .literal = left orelse right.? };
    }

    /// The offset of the first byte of the line holding `at`.
    fn lineStart(self: *const Pass, at: usize) usize {
        return if (std.mem.lastIndexOfScalar(u8, self.src.bytes[0..at], '\n')) |previous| previous + 1 else 0;
    }

    /// The offset of the end of the line holding `at`, before its line break.
    fn lineEnd(self: *const Pass, at: usize) usize {
        return std.mem.indexOfScalarPos(u8, self.src.bytes, at, '\n') orelse self.src.bytes.len;
    }

    /// The leading whitespace of the line holding `at`.
    fn indentOf(self: *const Pass, at: usize) []const u8 {
        const start = self.lineStart(at);
        var end = start;
        while (end < self.src.bytes.len and (self.src.bytes[end] == ' ' or self.src.bytes[end] == '\t')) end += 1;
        return self.src.bytes[start..end];
    }

    /// Whether the text from `from` to the end of its line is the colon that ends a header, with at most a
    /// comment after it.
    fn headerRest(self: *const Pass, from: usize) ?[]const u8 {
        const end = self.lineEnd(from);
        const rest = self.src.bytes[from..end];
        const trimmed = std.mem.trimStart(u8, rest, " \t");
        if (trimmed.len == 0 or trimmed[0] != ':') return null;
        return rest;
    }

    /// The body lines of a block: from the line after its header through the end of the line its last token
    /// ends (a comment after that token travels with it), or null when the text cannot move whole (a
    /// multi-line string, a tab, a line out of the block's indentation).
    fn bodyLines(self: *const Pass, header_end: usize, body: ast.StatementId, indent: usize) ?[]const u8 {
        const block = self.statementOf(body).span;
        const start = self.lineEnd(header_end) + 1;
        const last = self.lineEnd(block.end);
        if (start > last or last > self.src.bytes.len) return null;
        const lines = self.src.bytes[start..last];
        if (std.mem.indexOf(u8, lines, "\"\"\"") != null or std.mem.indexOfScalar(u8, lines, '\t') != null) return null;
        var rest = lines;
        while (rest.len != 0) {
            const stop = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..stop];
            if (std.mem.trim(u8, line, " ").len != 0) {
                var spaces: usize = 0;
                while (spaces < line.len and line[spaces] == ' ') spaces += 1;
                if (spaces <= indent) return null;
            }
            rest = if (stop == rest.len) rest[stop..] else rest[stop + 1 ..];
        }
        return lines;
    }

    /// What the checked type of a compared value must be for a rewrite to check.
    const Wanted = enum {
        /// A value a literal `match` takes: an integer, a `bool`, or a `str` or `bytes` that a plain name holds.
        match_value,
        /// An integer, which `value in b"..."` tests.
        integer,
        /// An Option or a Result, which a bind-or-else unwraps and an `is` test names a case of.
        unwrappable,
    };

    /// Whether the checked body gives `subject` a type the rewrite needs, so a rewrite never writes what the checker refuses. The
    /// syntax cannot say: `bytes?` (named cases) takes no literal arm and no `in b"..."`, Core refuses a literal match on a `str` or
    /// `bytes` field or element (it would copy the value), and a generic body checks no literal arm. Every checked node spelled exactly as
    /// the subject must have the type, and a function with no checked body (a generic one), or no node at the span, gets no warning.
    fn subjectTyped(self: *const Pass, subject: ast.NodeId, wanted: Wanted) Error!bool {
        const id = self.reading.current orelse return false;
        const span = self.node(subject).span;
        const named = self.node(subject).data == .name;
        const program = self.checked.program;
        var body = try typed_walk.Walker.init(self.memory, program, program.functions[@backingInt(id)].scope.body);
        defer body.deinit();
        var found = false;
        while (try body.next()) |item| {
            const visited = switch (item) {
                .expression => |value| value,
                .statement => continue,
            };
            const checked_node = program.nodes[@backingInt(visited)];
            if (checked_node.span.start != span.start or checked_node.span.end != span.end) continue;
            const fits = switch (wanted) {
                .match_value => literalType(program.records, checked_node.ty, named),
                .integer => checked_node.ty.isInteger(),
                .unwrappable => bind_or_else.unwrappable(checked_node.ty, program.records),
            };
            if (!fits) return false;
            found = true;
        }
        return found;
    }

    /// Whether a value of type `ty` takes literal arms: an integer or a `bool`, or a `str` or `bytes` that a plain name holds.
    fn literalType(records: []const checked_types.Record, ty: checked_types.Type, named: bool) bool {
        if (ty.isInteger() or ty == .bool) return true;
        if (!named or !ty.isAggregate()) return false;
        if (ty.recordIndex() >= records.len) return false;
        const kind = records[ty.recordIndex()].collection.kind;
        return kind == .string or kind == .bytes;
    }

    /// Report an `if`/`elif` chain of `x == literal` tests as a literal `match`.
    fn literalChain(self: *Pass, root: ast.StatementId) Error!void {
        var tests: std.ArrayList(Test) = .empty;
        defer tests.deinit(self.memory);
        var bodies: std.ArrayList(ast.StatementId) = .empty;
        defer bodies.deinit(self.memory);
        var conditions: std.ArrayList(ast.NodeId) = .empty;
        defer conditions.deinit(self.memory);
        var else_body: ?ast.StatementId = null;
        var current = root;
        while (true) {
            const branch = self.statementOf(current).data.branch;
            const found = self.literalTest(branch.condition) orelse return;
            if (tests.items.len != 0) {
                const first = tests.items[0];
                if (!self.same(first.subject, found.subject, 0) or first.literal.kind != found.literal.kind) return;
                for (tests.items) |earlier| if (self.sameLiteral(earlier.literal, found.literal)) return;
            }
            try tests.append(self.memory, found);
            try bodies.append(self.memory, branch.then_body);
            try conditions.append(self.memory, branch.condition);
            const other = branch.else_body orelse break;
            if (self.statementOf(other).data == .branch) {
                current = other;
                continue;
            }
            else_body = other;
            break;
        }
        if (tests.items.len < min_match_tests) return;
        if (!try self.subjectTyped(tests.items[0].subject, .match_value)) return;
        const start = self.statementOf(root).span.start;
        const lead = self.indentOf(start);
        if (self.lineStart(start) + lead.len != start) return;
        const step = try self.stepOf(start, bodies.items[0]) orelse return;
        var out: std.ArrayList(u8) = .empty;
        const subject = self.text(self.node(tests.items[0].subject).span);
        try out.print(self.memory, "match {s}:\n", .{subject});
        var end: usize = 0;
        for (tests.items, 0..) |item, index| {
            const condition_end = self.node(conditions.items[index]).span.end;
            const rest = self.headerRest(condition_end) orelse return;
            const lines = self.bodyLines(condition_end, bodies.items[index], lead.len) orelse return;
            try out.print(self.memory, "{s}{s}case {s}{s}\n", .{ lead, step, self.text(self.node(item.literal.id).span), rest });
            try self.shifted(&out, lines, step);
            end = self.lineEnd(self.statementOf(bodies.items[index]).span.end);
            // The next header follows with nothing but blank lines between, so no comment is dropped.
            const next = self.nextLine(end);
            if (index + 1 < tests.items.len) {
                if (!self.opensAt(next, lead, "elif")) return;
            } else if (else_body != null) {
                if (self.elseRest(next, lead) == null) return;
            }
        }
        if (else_body) |other| {
            const header = self.nextLine(end);
            const rest = self.elseRest(header, lead) orelse return;
            const lines = self.bodyLines(header + rest.len, other, lead.len) orelse return;
            try out.print(self.memory, "{s}{s}case _{s}\n", .{ lead, step, rest });
            try self.shifted(&out, lines, step);
            end = self.lineEnd(self.statementOf(other).span.end);
        } else {
            try out.print(self.memory, "{s}{s}case _:\n{s}{s}{s}pass", .{ lead, step, lead, step, step });
        }
        if (out.items[out.items.len - 1] == '\n') _ = out.pop();
        const span: Span = .{ .start = start, .end = end };
        const message = try std.fmt.allocPrint(self.memory, "{d} tests of `{s}` against literals: a literal `match` compares it once", .{ tests.items.len, subject });
        try self.report(literal_match_code, rules[2], .{ .start = start, .end = self.node(conditions.items[0]).span.end }, message, &.{.{ .span = span, .text = try out.toOwnedSlice(self.memory) }});
    }

    /// The text of the rest of a line `else:` opens, when the line at `at` is exactly an `else` header.
    fn elseRest(self: *const Pass, at: usize, lead: []const u8) ?[]const u8 {
        if (at > self.src.bytes.len) return null;
        const end = self.lineEnd(at);
        const line = self.src.bytes[at..end];
        if (!std.mem.startsWith(u8, line, lead)) return null;
        const after = line[lead.len..];
        if (!std.mem.startsWith(u8, after, "else")) return null;
        const rest = after["else".len..];
        const trimmed = std.mem.trimStart(u8, rest, " \t");
        if (trimmed.len == 0 or trimmed[0] != ':') return null;
        return rest;
    }

    /// The start of the first line after the one holding `at` that is not blank, or the end of the source.
    fn nextLine(self: *const Pass, at: usize) usize {
        var line = self.lineEnd(at) + 1;
        while (line < self.src.bytes.len) {
            const stop = self.lineEnd(line);
            if (std.mem.trim(u8, self.src.bytes[line..stop], " \t\r").len != 0) return line;
            line = stop + 1;
        }
        return self.src.bytes.len;
    }

    /// Whether the line starting at `line` is `lead` and then `keyword` and a space.
    fn opensAt(self: *const Pass, line: usize, lead: []const u8, keyword: []const u8) bool {
        const rest = self.src.bytes[@min(line, self.src.bytes.len)..];
        if (!std.mem.startsWith(u8, rest, lead)) return false;
        const after = rest[lead.len..];
        return std.mem.startsWith(u8, after, keyword) and after.len > keyword.len and after[keyword.len] == ' ';
    }

    /// The whitespace one level of indentation adds: the first body line's indent past the header's.
    fn stepOf(self: *const Pass, header: usize, body: ast.StatementId) Error!?[]const u8 {
        const block = self.statementOf(body).span;
        const lead = self.indentOf(header);
        var at = self.lineEnd(header) + 1;
        while (at < block.end) {
            const line_end = self.lineEnd(at);
            if (std.mem.trim(u8, self.src.bytes[at..line_end], " ").len != 0) {
                const indent = self.indentOf(at);
                if (indent.len <= lead.len) return null;
                const step = try self.memory.dupe(u8, indent[lead.len..]);
                return step;
            }
            at = line_end + 1;
        }
        return null;
    }

    /// Append `lines` with `step` added to every non-blank line.
    fn shifted(self: *const Pass, out: *std.ArrayList(u8), lines: []const u8, step: []const u8) Error!void {
        var rest = lines;
        while (rest.len != 0) {
            const stop = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..stop];
            if (std.mem.trim(u8, line, " \r").len != 0) try out.appendSlice(self.memory, step);
            try out.appendSlice(self.memory, line);
            try out.append(self.memory, '\n');
            rest = if (stop == rest.len) rest[stop..] else rest[stop + 1 ..];
        }
    }

    // ---- W_OPTION_TRY ---------------------------------------------------------------------------------

    /// Report a match that ends its block, in a function that returns an Option, whose `None` arm only
    /// returns `None`: `const x = try call()` binds the payload and returns `None` itself. True when it reported, or when a
    /// waiver silenced the report, so `W_MATCH_ELSE` leaves the statement to it.
    fn optionMatch(self: *Pass, id: ast.StatementId) Error!bool {
        if (!self.reading.option_return) return false;
        const item = self.statementOf(id);
        const match = item.data.match;
        if (match.exclusive or match.arms.len != 2) return false;
        const call = self.node(match.value).data;
        if (call != .call and call != .method_call) return false;
        var some: ?ast.MatchArm = null;
        var none: ?ast.MatchArm = null;
        for (match.arms) |arm| {
            const name = self.text(arm.name);
            if (std.mem.eql(u8, name, "Some") and arm.payload_patterns.len == 1 and arm.payload_patterns[0].name == null) some = arm;
            if (std.mem.eql(u8, name, "None") and arm.payload_patterns.len == 0) none = arm;
        }
        const taking = some orelse return false;
        const absent = none orelse return false;
        const payload = taking.payload_patterns[0].pattern.data;
        if (payload != .binding or payload.binding == null) return false;
        if (!self.returnsNone(absent.body)) return false;
        const name = self.text(payload.binding.?);
        const start = item.span.start;
        const lead = self.indentOf(start);
        if (self.lineStart(start) + lead.len != start) return false;
        if (self.headerRest(self.afterPattern(taking)) == null) return false;
        const step = try self.stepOf(start, taking.body) orelse return false;
        const body = self.statementOf(taking.body).span;
        const lines = self.bodyLines(self.afterPattern(taking), taking.body, lead.len + step.len) orelse return false;
        const arms_end = self.lineEnd(@max(body.end, self.statementOf(absent.body).span.end));
        // Everything but the Some body is rewritten away, so a comment there would be lost.
        const body_start = self.lineEnd(taking.name.start) + 1;
        const body_end = self.lineEnd(body.end);
        if (std.mem.indexOfScalar(u8, self.src.bytes[start..body_start], '#') != null) return false;
        if (body_end < arms_end and std.mem.indexOfScalar(u8, self.src.bytes[body_end..arms_end], '#') != null) return false;
        var out: std.ArrayList(u8) = .empty;
        try out.print(self.memory, "const {s} = try {s}\n", .{ name, self.text(self.node(match.value).span) });
        try self.dedented(&out, lines, 2 * step.len);
        if (out.items[out.items.len - 1] == '\n') _ = out.pop();
        const span: Span = .{ .start = start, .end = arms_end };
        const message = try std.fmt.allocPrint(self.memory, "the `None` arm only returns `None`: `const {s} = try {s}` unwraps the Option and returns `None` itself", .{ name, self.text(self.node(match.value).span) });
        try self.report(option_try_code, rules[4], .{ .start = start, .end = self.node(match.value).span.end }, message, &.{.{ .span = span, .text = try out.toOwnedSlice(self.memory) }});
        return true;
    }

    // ---- W_ELSE_IS_TRY --------------------------------------------------------------------------------

    /// Report a bind-or-else (`const x = call() else Err(e):`) whose `else` block is only `fail e`, or only
    /// `return None` in a function that returns an Option: `const x = try call()` does the same and says less.
    /// The rewrite inserts `try ` before the call and deletes the `else` tail; it is refused when a comment
    /// would be lost.
    fn elseIsTry(self: *Pass, id: ast.StatementId) Error!void {
        const item = self.statementOf(id);
        const match = item.data.match;
        if (match.arms.len != 2) return;
        var failure: ?ast.MatchArm = null;
        for (match.arms) |arm| {
            if (arm.alternatives.role == .failure) failure = arm;
        }
        const arm = failure orelse return;
        const only = self.onlyStatement(arm.body) orelse return;
        if (!self.passesOn(arm, only)) return;
        const call = self.node(match.value);
        // `try` takes the payload: over a borrowed place it is refused, and the copy that repairs it is one the program did
        // not make (FR20). A call's payload is the declaration's to own either way.
        if (call.data != .call and call.data != .method_call) return;
        const at = call.span.end;
        const block_end = self.lineEnd(self.statementOf(arm.body).span.end);
        if (block_end <= at or !std.mem.startsWith(u8, std.mem.trimStart(u8, self.src.bytes[at..block_end], " \t"), "else")) return;
        if (std.mem.indexOfScalar(u8, self.src.bytes[at..block_end], '#') != null) return;
        const message = try std.fmt.allocPrint(self.memory, "the `else` block only passes the failure on: `try {s}` unwraps the value and does the same", .{self.text(call.span)});
        const edits = [_]diagnostic.Edit{
            .{ .span = .{ .start = call.span.start, .end = call.span.start }, .text = "try " },
            .{ .span = .{ .start = at, .end = block_end }, .text = "" },
        };
        try self.report(else_is_try_code, rules[5], .{ .start = item.span.start, .end = at }, message, try self.memory.dupe(diagnostic.Edit, &edits));
    }

    /// The one statement of a block, or null when it has none or several.
    fn onlyStatement(self: *const Pass, body: ast.StatementId) ?ast.Statement {
        const data = self.statementOf(body).data;
        if (data != .block or data.block.len != 1) return null;
        return self.statementOf(data.block[0]);
    }

    /// Whether the single statement of a failure arm passes the failure on unchanged: `fail e` for the name the
    /// arm binds, or `return None` for an Option's absence in a function that returns an Option.
    fn passesOn(self: *const Pass, arm: ast.MatchArm, only: ast.Statement) bool {
        if (arm.bindings.len == 1) {
            const bound = arm.bindings[0] orelse return false;
            if (only.data != .fail) return false;
            const value = self.node(only.data.fail);
            return value.data == .name and std.mem.eql(u8, self.text(value.data.name), self.text(bound));
        }
        if (arm.bindings.len != 0 or !self.reading.option_return or only.data != .ret) return false;
        return std.mem.eql(u8, self.text(self.node(only.data.ret).span), "None");
    }

    /// The offset just after an arm's pattern, where its colon stands.
    fn afterPattern(self: *const Pass, arm: ast.MatchArm) usize {
        var end = arm.name.end;
        if (arm.payload_patterns.len != 0) {
            const close = std.mem.indexOfScalarPos(u8, self.src.bytes, arm.name.end, ')') orelse return end;
            end = close + 1;
        }
        return end;
    }

    /// Whether a block is exactly `return None`.
    fn returnsNone(self: *const Pass, body: ast.StatementId) bool {
        const data = self.statementOf(body).data;
        if (data != .block or data.block.len != 1) return false;
        const only = self.statementOf(data.block[0]).data;
        if (only != .ret) return false;
        return std.mem.eql(u8, self.text(self.node(only.ret).span), "None");
    }

    // ---- W_MATCH_ELSE and W_MATCH_IS ---------------------------------------------------------------------

    /// The two arms of a `match` written in the source over an Option or a Result: `case Some(P)` or `case Ok(P)`, and
    /// `case None` or `case Err(Q)`, each unqualified, alone on its `case` line, and binding at most one name.
    const Unwrapping = struct { success: ast.MatchArm, failure: ast.MatchArm, result: bool };

    /// One arm of an unwrapping `match` as the rewrite reads its text: the line its `case` stands on, its header comment,
    /// and its body's lines.
    const ArmText = struct { line: usize, comment: []const u8, lines: []const u8, end: usize };

    /// The rewrite of one unwrapping `match`: what it reads, where it stands, and the indentation of one level.
    const Rewrite = struct { id: ast.StatementId, shape: Unwrapping, lead: []const u8, step: []const u8, subject: []const u8, comment: []const u8 };

    /// The arms of an unwrapping `match`, or null for any other `match` (one the parser built for a bind-or-else or an
    /// `is` test, `match mut`, a third arm, a guard-like literal arm, a `|` list, a nested or labelled pattern).
    fn unwrapping(self: *const Pass, match: @FieldType(@FieldType(ast.Statement, "data"), "match")) ?Unwrapping {
        if (match.exclusive or match.arms.len != 2) return null;
        var success: ?ast.MatchArm = null;
        var failure: ?ast.MatchArm = null;
        var options: usize = 0;
        for (match.arms) |arm| {
            if (arm.alternatives.role != .named or arm.internal.wildcard or arm.alternatives.group != null or arm.alternatives.rest) return null;
            if (arm.alternatives.name_bodies.len != 0 or arm.literals.len != 0 or arm.ty.start != arm.ty.end) return null;
            const name = self.text(arm.name);
            const payload = arm.payload_patterns.len == 1 and arm.payload_patterns[0].name == null and arm.payload_patterns[0].pattern.data == .binding and arm.bindings.len == 1;
            const bare = arm.payload_patterns.len == 0 and arm.bindings.len == 0;
            if ((std.mem.eql(u8, name, "Some") or std.mem.eql(u8, name, "Ok")) and payload and success == null) {
                success = arm;
                if (name[0] == 'S') options += 1;
            } else if (std.mem.eql(u8, name, "None") and bare and failure == null) {
                failure = arm;
                options += 1;
            } else if (std.mem.eql(u8, name, "Err") and payload and failure == null) {
                failure = arm;
            } else return null;
        }
        if (options == 1) return null;
        return .{ .success = success orelse return null, .failure = failure orelse return null, .result = options == 0 };
    }

    /// Whether every path through a block ends in `return`, `fail`, `break` or `continue`: the block's last statement does,
    /// or is an `if` with an `else` or a `match` each of whose bodies does. The checker accepts each such block as one that
    /// does not fall through (`E_ELSE_FALLTHROUGH`); a block it accepts for another reason is not read as leaving.
    fn leaves(self: *const Pass, id: ast.StatementId, depth: usize) bool {
        if (depth > depth_limit) return false;
        return switch (self.statementOf(id).data) {
            .block => |children| children.len != 0 and self.leaves(children[children.len - 1], depth + 1),
            .ret, .fail, .loop_exit => true,
            .branch => |branch| if (branch.else_body) |other| self.leaves(branch.then_body, depth + 1) and self.leaves(other, depth + 1) else false,
            .match => |match| all: {
                if (match.arms.len == 0) break :all false;
                for (match.arms) |arm| if (!self.leaves(arm.body, depth + 1)) break :all false;
                break :all true;
            },
            else => false,
        };
    }

    /// Whether an arm's body does nothing: `pass`, or `_ = ` an integer literal.
    fn doesNothing(self: *const Pass, body: ast.StatementId) bool {
        const data = self.statementOf(body).data;
        if (data != .block) return false;
        if (data.block.len == 0) return true;
        if (data.block.len != 1) return false;
        const only = self.statementOf(data.block[0]);
        return switch (only.data) {
            .block => |inner| inner.len == 0,
            .discard => |value| !only.implicit_discard and self.node(value).data == .integer,
            else => false,
        };
    }

    /// Append to `out` every name `body` declares at its own level: its bindings, and the names a bind-or-else among them
    /// binds together with the ones declared after it, which the parser nests in its success arm.
    fn ownLevelNames(self: *const Pass, body: ast.StatementId, out: *std.ArrayList([]const u8), depth: usize) Error!bool {
        if (depth > depth_limit) return false;
        const data = self.statementOf(body).data;
        if (data != .block) return true;
        for (data.block) |child| switch (self.statementOf(child).data) {
            .binding => |binding| try out.append(self.memory, self.text(binding.name)),
            .match => |match| if (bind_or_else.isBindOrElse(match.arms)) for (match.arms) |arm| {
                if (arm.alternatives.role != .success) continue;
                for (arm.bindings) |bound| if (bound) |name| try out.append(self.memory, self.text(name));
                if (!try self.ownLevelNames(arm.body, out, depth + 1)) return false;
            },
            else => {},
        };
        return true;
    }

    /// Whether any statement of `statements`, at any depth, declares one of `names` (a binding, a loop name, a `with` name,
    /// a pattern binding, a bind-or-else); a declaration too deep to read counts as one.
    fn declaresAny(self: *const Pass, statements: []const ast.StatementId, names: []const []const u8, depth: usize) bool {
        if (depth > depth_limit) return true;
        for (statements) |id| {
            const item = self.statementOf(id);
            switch (item.data) {
                .binding => |binding| if (listed(self.text(binding.name), names)) return true,
                .for_each => |each| {
                    if (listed(self.text(each.name), names)) return true;
                    if (each.index_name) |index| if (listed(self.text(index), names)) return true;
                },
                .for_range => |range| if (listed(self.text(range.name), names)) return true,
                .with_scope => |scope| if (scope.name) |name| if (listed(self.text(name), names)) return true,
                .match => |match| for (match.arms) |arm| {
                    for (arm.bindings) |bound| if (bound) |name| if (listed(self.text(name), names)) return true;
                    if (self.patternDeclares(arm.payload_patterns, names, depth + 1)) return true;
                },
                else => {},
            }
            var nested: std.ArrayList(ast.StatementId) = .empty;
            defer nested.deinit(self.memory);
            ast.appendNested(self.memory, &nested, item) catch return true;
            if (self.declaresAny(nested.items, names, depth + 1)) return true;
        }
        return false;
    }

    fn patternDeclares(self: *const Pass, fields: []const ast.PatternField, names: []const []const u8, depth: usize) bool {
        if (depth > depth_limit) return true;
        for (fields) |field| switch (field.pattern.data) {
            .binding => |bound| if (bound) |name| if (listed(self.text(name), names)) return true,
            .variant => |nested| if (self.patternDeclares(nested.fields, names, depth + 1)) return true,
        };
        return false;
    }

    fn listed(name: []const u8, names: []const []const u8) bool {
        if (std.mem.eql(u8, name, "_")) return false;
        for (names) |known| if (std.mem.eql(u8, known, name)) return true;
        return false;
    }

    /// Whether the statements of `arm` can move out of it into the enclosing block: no name they declare at their own level,
    /// nor `bound`, is declared by the statements after the `match`.
    fn movable(self: *const Pass, arm: ast.MatchArm, bound: ?Span, rest: []const ast.StatementId) Error!bool {
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.memory);
        if (bound) |name| try names.append(self.memory, self.text(name));
        if (!try self.ownLevelNames(arm.body, &names, 0)) return false;
        if (names.items.len == 0) return true;
        return !self.declaresAny(rest, names.items, 0);
    }

    /// The comment after a header's colon (`rest` starts before the colon), or empty.
    fn headerComment(rest: []const u8) ?[]const u8 {
        const trimmed = std.mem.trimStart(u8, rest, " \t");
        const after = std.mem.trim(u8, trimmed[1..], " \t\r");
        if (after.len == 0) return "";
        if (after[0] != '#') return null;
        return after;
    }

    /// Read the text of one arm: its `case` line must begin with `lead` and `step` and hold only the pattern and a comment,
    /// and its body must be one level deeper than its `case`, every line of it at least that deep.
    fn armText(self: *Pass, arm: ast.MatchArm, lead: []const u8, step: []const u8) ?ArmText {
        const line = self.lineStart(arm.name.start);
        const prefix = self.src.bytes[line..arm.name.start];
        if (prefix.len != lead.len + step.len + "case ".len or !std.mem.endsWith(u8, prefix, "case ")) return null;
        if (!std.mem.startsWith(u8, prefix, lead) or !std.mem.eql(u8, prefix[lead.len .. lead.len + step.len], step)) return null;
        const after = self.afterPattern(arm);
        const rest = self.headerRest(after) orelse return null;
        const comment = headerComment(rest) orelse return null;
        const depth = lead.len + 2 * step.len;
        const lines = self.bodyLines(after, arm.body, depth - 1) orelse return null;
        if (!self.indentedAtLeast(lines, depth)) return null;
        var first = lines;
        while (first.len != 0 and (first[0] == '\n' or first[0] == ' ' or first[0] == '\r')) first = first[1..];
        const body_line = self.lineStart(@intFromPtr(first.ptr) - @intFromPtr(self.src.bytes.ptr));
        if (self.indentOf(body_line).len != depth) return null;
        return .{ .line = line, .comment = comment, .lines = lines, .end = self.lineEnd(self.statementOf(arm.body).span.end) };
    }

    /// Whether every non-blank line of `lines` starts with at least `width` spaces.
    fn indentedAtLeast(self: *const Pass, lines: []const u8, width: usize) bool {
        _ = self;
        var rest = lines;
        while (rest.len != 0) {
            const stop = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..stop];
            if (std.mem.trim(u8, line, " \r").len != 0) {
                if (line.len < width) return false;
                for (line[0..width]) |byte| if (byte != ' ') return false;
            }
            rest = if (stop == rest.len) rest[stop..] else rest[stop + 1 ..];
        }
        return true;
    }

    /// Whether only blank lines stand between offset `from` (a line end) and the start of line `to`.
    fn blankBetween(self: *const Pass, from: usize, to: usize) bool {
        if (from > to) return false;
        return std.mem.trim(u8, self.src.bytes[from..to], " \t\r\n").len == 0;
    }

    /// The comment lines of a body that does nothing, each without its indentation and followed by a line break and `lead`.
    fn commentLines(self: *Pass, out: *std.ArrayList(u8), lines: []const u8, lead: []const u8) Error!void {
        var rest = lines;
        while (rest.len != 0) {
            const stop = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = std.mem.trim(u8, rest[0..stop], " \r");
            if (line.len != 0 and line[0] == '#') try out.print(self.memory, "{s}\n{s}", .{ line, lead });
            rest = if (stop == rest.len) rest[stop..] else rest[stop + 1 ..];
        }
    }

    /// Report an unwrapping `match` whose rewrite is certain: `W_MATCH_IS` where an arm does nothing (or the success arm
    /// leaves and the failure arm binds nothing), else `W_MATCH_ELSE` where the failure arm leaves. `rest` is the
    /// statements after the `match` in its block.
    fn unwrapMatch(self: *Pass, id: ast.StatementId, rest: []const ast.StatementId) Error!void {
        const item = self.statementOf(id);
        const match = item.data.match;
        const shape = self.unwrapping(match) orelse return;
        if (self.node(match.value).data == .mut_argument) return;
        const start = item.span.start;
        const lead = self.indentOf(start);
        if (self.lineStart(start) + lead.len != start or !std.mem.startsWith(u8, self.src.bytes[start..], "match ")) return;
        const value_end = self.node(match.value).span.end;
        const header = self.headerRest(value_end) orelse return;
        const comment = headerComment(header) orelse return;
        const subject = std.mem.trim(u8, self.src.bytes[start + "match".len .. value_end], " ");
        const first_arm = if (shape.success.name.start < shape.failure.name.start) shape.success else shape.failure;
        const arm_line = self.lineStart(first_arm.name.start);
        const arm_indent = self.indentOf(arm_line);
        if (arm_indent.len <= lead.len) return;
        const one = arm_indent[lead.len..];
        for (one) |byte| if (byte != ' ') return;
        if (!try self.subjectTyped(self.unwrappedSubject(match.value), .unwrappable)) return;
        const rewrite: Rewrite = .{ .id = id, .shape = shape, .lead = lead, .step = one, .subject = subject, .comment = comment };
        const success = self.armText(shape.success, lead, one) orelse return;
        const failure = self.armText(shape.failure, lead, one) orelse return;
        const earlier = if (success.line < failure.line) success else failure;
        const later_arm = if (success.line < failure.line) failure else success;
        if (!self.blankBetween(self.lineEnd(value_end), earlier.line) or !self.blankBetween(earlier.end, later_arm.line)) return;
        // A comment after the last arm, deeper than the `match`, would be left behind at the old depth.
        const after = self.nextLine(later_arm.end);
        if (after < self.src.bytes.len and self.indentOf(after).len > lead.len) return;
        const end = later_arm.end;
        const own_subject = self.node(match.value).data == .own_argument;
        const failure_idle = self.doesNothing(shape.failure.body);
        const success_idle = self.doesNothing(shape.success.body);
        if (failure_idle and success_idle) return;
        if (failure_idle or success_idle) {
            if (own_subject) return;
            return self.reportIs(rewrite, success, failure, end, if (failure_idle) .test_success else .test_failure);
        }
        const bound = shape.success.payload_patterns[0].pattern.data.binding;
        if (self.leaves(shape.failure.body, 0)) {
            if (!try self.movable(shape.success, bound, rest)) return;
            return self.reportElse(rewrite, success, failure, end);
        }
        const failure_binds = shape.failure.bindings.len != 0 and shape.failure.bindings[0] != null;
        if (own_subject or failure_binds or !self.leaves(shape.success.body, 0)) return;
        if (!try self.movable(shape.failure, null, rest)) return;
        return self.reportIs(rewrite, success, failure, end, .success_leaves);
    }

    /// The node whose checked type is the matched value's: the operand of `own x`, or the value itself.
    fn unwrappedSubject(self: *const Pass, value: ast.NodeId) ast.NodeId {
        return switch (self.node(value).data) {
            .own_argument => |operand| operand,
            else => value,
        };
    }

    /// The source text of an arm's pattern, `Some(h)` or `Err(_)`, or its bare case name when it binds nothing.
    fn patternText(self: *const Pass, arm: ast.MatchArm) []const u8 {
        if (arm.bindings.len == 1 and arm.bindings[0] == null) return self.text(arm.name);
        return self.src.bytes[arm.name.start..self.afterPattern(arm)];
    }

    /// Write `comment` after a header, or, when the header already has one, on its own line at `indent` after it.
    fn headerWith(self: *Pass, out: *std.ArrayList(u8), first: []const u8, second: []const u8, indent: []const u8) Error!void {
        if (first.len != 0) try out.print(self.memory, " {s}", .{first});
        try out.append(self.memory, '\n');
        if (first.len != 0 and second.len != 0) {
            try out.print(self.memory, "{s}{s}\n", .{ indent, second });
        } else if (second.len != 0) {
            out.items.len -= 1;
            try out.print(self.memory, " {s}\n", .{second});
        }
    }

    /// `W_MATCH_ELSE`: `const P = V else FAILURE:` with the failure arm's block, then the success arm's statements.
    fn reportElse(self: *Pass, r: Rewrite, success: ArmText, failure: ArmText, end: usize) Error!void {
        const bound = r.shape.success.payload_patterns[0].pattern.data.binding;
        var out: std.ArrayList(u8) = .empty;
        if (bound) |name| try out.print(self.memory, "const {s} = ", .{self.text(name)}) else try out.appendSlice(self.memory, "_ = ");
        try out.print(self.memory, "{s} else", .{r.subject});
        if (r.shape.result) try out.print(self.memory, " {s}", .{self.src.bytes[r.shape.failure.name.start..self.afterPattern(r.shape.failure)]});
        try out.append(self.memory, ':');
        const block_indent = try std.mem.concat(self.memory, u8, &.{ r.lead, r.step });
        try self.headerWith(&out, r.comment, failure.comment, block_indent);
        try self.dedented(&out, failure.lines, r.step.len);
        if (success.comment.len != 0) try out.print(self.memory, "{s}{s}\n", .{ r.lead, success.comment });
        try self.dedented(&out, success.lines, 2 * r.step.len);
        if (out.items[out.items.len - 1] == '\n') _ = out.pop();
        const flat = if (bound) |name| try std.fmt.allocPrint(self.memory, "const {s} = {s} else", .{ self.text(name), r.subject }) else try std.fmt.allocPrint(self.memory, "_ = {s} else", .{r.subject});
        const case = if (r.shape.result) "`Err` arm" else "`None` arm";
        const tail = if (r.shape.result) try std.fmt.allocPrint(self.memory, " {s}", .{self.src.bytes[r.shape.failure.name.start..self.afterPattern(r.shape.failure)]}) else "";
        const message = try std.fmt.allocPrint(self.memory, "this `match` only unwraps `{s}` and its {s} leaves: `{s}{s}:` with that block, " ++
            "then the other arm's statements, says the same without the `match`", .{ r.subject, case, flat, tail });
        try self.reportUnwrap(match_else_code, r, message, end, try out.toOwnedSlice(self.memory));
    }

    /// Which `if` an unwrapping `match` becomes: the success case, the failure case, or the success case when its arm
    /// leaves and the failure arm's statements follow the `if`.
    const IsShape = enum { test_success, test_failure, success_leaves };

    /// `W_MATCH_IS`: `if V is CASE:` with the other arm's statements; a deleted arm's comments go above it.
    fn reportIs(self: *Pass, r: Rewrite, success: ArmText, failure: ArmText, end: usize, shape: IsShape) Error!void {
        const kept = if (shape == .test_failure) failure else success;
        const dropped = if (shape == .test_failure) success else failure;
        const kept_arm = if (shape == .test_failure) r.shape.failure else r.shape.success;
        var out: std.ArrayList(u8) = .empty;
        if (shape != .success_leaves) {
            if (dropped.comment.len != 0) try out.print(self.memory, "{s}\n{s}", .{ dropped.comment, r.lead });
            try self.commentLines(&out, dropped.lines, r.lead);
        }
        const pattern = self.patternText(kept_arm);
        try out.print(self.memory, "if {s} is {s}:", .{ r.subject, pattern });
        const block_indent = try std.mem.concat(self.memory, u8, &.{ r.lead, r.step });
        try self.headerWith(&out, r.comment, kept.comment, block_indent);
        try self.dedented(&out, kept.lines, r.step.len);
        if (shape == .success_leaves) {
            if (dropped.comment.len != 0) try out.print(self.memory, "{s}{s}\n", .{ r.lead, dropped.comment });
            try self.dedented(&out, dropped.lines, 2 * r.step.len);
        }
        if (out.items[out.items.len - 1] == '\n') _ = out.pop();
        const message = switch (shape) {
            .test_success, .test_failure => try std.fmt.allocPrint(self.memory, "this `match` only unwraps `{s}` and its other arm does nothing: " ++
                "`if {s} is {s}:` says the same without the `match`", .{ r.subject, r.subject, pattern }),
            .success_leaves => try std.fmt.allocPrint(self.memory, "this `match` only unwraps `{s}` and its `{s}` arm leaves: `if {s} is {s}:` " ++
                "with that block, then the other arm's statements, says the same without the `match`", .{ r.subject, self.text(kept_arm.name), r.subject, pattern }),
        };
        try self.reportUnwrap(match_is_code, r, message, end, try out.toOwnedSlice(self.memory));
    }

    /// Report `code` (`W_MATCH_ELSE` or `W_MATCH_IS`) at the `match` header, with the edit that replaces the whole statement.
    fn reportUnwrap(self: *Pass, code: []const u8, r: Rewrite, message: []const u8, end: usize, replacement: []const u8) Error!void {
        const rule = if (std.mem.eql(u8, code, match_else_code)) rules[6] else rules[7];
        const start = self.statementOf(r.id).span.start;
        const value = self.statementOf(r.id).data.match.value;
        try self.report(code, rule, .{ .start = start, .end = self.node(value).span.end }, message, &.{.{ .span = .{ .start = start, .end = end }, .text = replacement }});
    }

    /// Append `lines` with `width` leading blanks removed from every non-blank line.
    fn dedented(self: *const Pass, out: *std.ArrayList(u8), lines: []const u8, width: usize) Error!void {
        var rest = lines;
        while (rest.len != 0) {
            const stop = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = rest[0..stop];
            if (std.mem.trim(u8, line, " \r").len != 0) try out.appendSlice(self.memory, line[@min(width, line.len)..]) else try out.appendSlice(self.memory, line);
            try out.append(self.memory, '\n');
            rest = if (stop == rest.len) rest[stop..] else rest[stop + 1 ..];
        }
    }
};

/// Emit the idiom warnings of every function body `skip` does not name (indexed like `syntax.functions`). Returns the span
/// of every site a waiver silenced, ordered by start: a stored summary of a function that holds one cannot say what removing
/// the waiver would bring back, so the function must be read again each time.
pub fn warn(memory: std.mem.Allocator, src: source.Source, syntax: ast.Program, skip: []const bool, checked: Checked, sink: *diagnostic.Sink) Error![]const Span {
    var pass: Pass = .{ .memory = memory, .src = src, .syntax = syntax, .checked = checked, .output = .{ .sink = sink, .first = sink.items.items.len } };
    for (syntax.functions, 0..) |item, index| {
        if (index < skip.len and skip[index]) continue;
        if (item.policy.host != null) continue;
        // The standard library a program compiles with is not the program's to rewrite: its warnings would name a file
        // `selka fix` cannot edit.
        if (std.mem.startsWith(u8, src.locate(item.name.start).path, "@stdlib/")) continue;
        pass.reading.current = if (index < checked.ordinary_ids.len) checked.ordinary_ids[index] else null;
        try ast.ensureBody(syntax, item.body);
        try pass.function(item);
    }
    const silenced = pass.waivers.silenced.items;
    std.mem.sort(Span, silenced, {}, startsFirst);
    return silenced;
}

fn startsFirst(_: void, a: Span, b: Span) bool {
    return a.start < b.start;
}
