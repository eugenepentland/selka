//! The `native-invocation-v1` contract: what one call of an exported function
//! accepts, what it returns, and how a parent process tells a returned language
//! `Result.Err` apart from a trap, a timeout, an invalid request and a host
//! failure.
//!
//! The wire subset starts from the copied-value matrix the native test runner
//! already validates; a type outside it is refused before any guest code runs.
//! Eligibility is a property of the checked schema alone, so `--describe` can
//! answer it without a native toolchain and without executing anything.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const wire = @import("native_test_wire.zig");
const Value = std.json.Value;

/// Version tag written on every `mylang invoke` response object.
pub const envelope_version = "native-invocation-v1";

/// Exit status for a call that completed, including one returning `Result.Err`.
pub const exit_completed: u8 = 0;

/// Exit status for a source rejection or a runtime trap inside the call.
pub const exit_source_or_runtime: u8 = 1;

/// Exit status for a malformed request or a host/setup failure.
pub const exit_request_or_setup: u8 = 2;

/// How one `mylang invoke` request ended, as spelled in the response.
pub const Status = enum {
    /// `--describe` answered without running guest code.
    described,
    /// The call returned a value, including a returned language `Err`.
    completed,
    /// The guest trapped; `failure.diagnostics` carries the located code.
    trap,
    /// The wall-clock bound ended the child before it answered.
    timeout,
    /// The project did not check, or the compiler rejected the source.
    @"source-error",
    /// The request named something that cannot be called as written.
    @"invalid-request",
    /// The checked signature is outside the copied-value wire subset.
    unsupported,
    /// A missing tool, a refused build, or a malformed child response.
    @"setup-failure",
};

/// The response spelling of one status; it is also its exit-status key.
pub fn statusText(status: Status) []const u8 {
    return @tagName(status);
}

/// Whether a status must exit 0; every other status has a failure exit code.
pub fn completed(status: Status) bool {
    return status == .described or status == .completed;
}

/// The process exit status for one response status.
pub fn exitStatus(status: Status) u8 {
    return switch (status) {
        .described, .completed => exit_completed,
        .@"source-error", .trap, .timeout => exit_source_or_runtime,
        .@"invalid-request", .unsupported, .@"setup-failure" => exit_request_or_setup,
    };
}

/// The process exit status for one response's status spelling. A spelling this
/// contract does not define is a request failure, never a crash.
pub fn exitStatusText(text: []const u8) u8 {
    return exitStatus(std.meta.stringToEnum(Status, text) orelse return exit_request_or_setup);
}

/// The execution quotas the response reports and the child enforces.
pub const Limits = struct {
    /// Guest steps one call may execute before `R_STEP_BUDGET`.
    max_steps: u64 = 0,
    /// Guest frames one call may open before the frame bound traps.
    max_frames: u64 = 0,
    /// Domain-codec calls one call may make before `CodecCallLimit`.
    max_calls: u64 = 0,
    /// Wall-clock bound on the child process, in milliseconds.
    timeout_ms: u32 = 0,
    /// Resolved byte ceiling the child runs under.
    max_memory: u64 = 0,
};

/// Source, compiler, schema and ABI identities one response is about.
pub const Identities = struct {
    /// Content identity of the captured source inventory.
    source: []const u8 = "",
    /// Build identity of the running compiler binary.
    compiler: []const u8 = "",
    /// SHA-256 of the checked `language-schema-v1` document.
    schema: []const u8 = "",
    /// Native ABI tag the checked graph was built for.
    abi: []const u8 = "",
};

/// The selected entry point and qualified function name.
pub const Target = struct {
    /// Qualified `module::name` the request named.
    function: []const u8 = "",
    /// Entry source path as the user spelled it.
    entry: []const u8 = "",
};

/// Quotas and identities every `native-invocation-v1` response carries.
pub const Context = struct {
    /// Effective execution quotas for this call.
    limits: Limits = .{},
    /// Effective source, compiler, schema and ABI identities.
    identities: Identities = .{},
};

/// Why a request was refused, and the first path that caused it.
pub const Failure = struct {
    /// Short machine-readable category, e.g. `unknown-function`.
    kind: []const u8,
    /// The first unsupported type path, when the refusal is about a type.
    path: []const u8 = "",
    /// One sentence a caller can act on.
    reason: []const u8 = "",
    /// Located compiler or trap text, when one exists.
    diagnostics: []const u8 = "",
};

/// One frame of a source-mapped trap trace.
pub const Frame = struct {
    /// Qualified guest function name the frame is executing.
    function: []const u8,
    /// Source path the frame's location is in.
    path: []const u8,
    /// One-based source line.
    line: u64,
    /// One-based source column.
    column: u64,
};

/// The runtime trap a call ended in, if it trapped.
pub const Trap = struct {
    /// Runtime trap code, e.g. `R_DIVISION_BY_ZERO`.
    code: []const u8 = "",
    /// The operation that trapped, when the runtime recorded one.
    operation: []const u8 = "",
    /// Source-mapped frames, innermost first.
    frames: []const Frame = &.{},
};

/// What one executed call produced: a typed value or a returned `Err`.
pub const Invocation = struct {
    /// `value` for a returned value, `returned-error` for a language `Err`.
    kind: []const u8,
    /// The decoded result or error payload as typed JSON.
    value: ?Value = null,
    /// Guest steps the call executed.
    steps: u64 = 0,
    /// Guest stdout the child captured, kept off the protocol channel.
    output: []const u8 = "",
    /// Located failure text for a trap, timeout or host failure.
    diagnostics: []const u8 = "",
    /// The runtime trap, when the call trapped.
    trap: ?Trap = null,
};

/// One argument position of the checked signature and its wire form.
pub const Argument = struct {
    /// Declared parameter name.
    name: []const u8,
    /// Checked language type of the position.
    type: []const u8,
    /// Wire kind the invocation boundary carries it as.
    wire: []const u8,
    /// Whether the runtime injects it instead of a JSON value.
    injected: bool = false,
};

/// The checked result position and its wire form.
pub const ResultType = struct {
    /// Checked language type of the result.
    type: []const u8,
    /// Wire kind the invocation boundary carries it as.
    wire: []const u8,
};

/// The selected function's checked argument and result contract.
pub const Contract = struct {
    /// Argument positions in declaration order.
    arguments: []const Argument,
    /// The checked result position.
    result: ResultType,
    /// Declared effect ceiling of the export.
    effects: []const []const u8,
    /// Declared mutation footprint positions.
    mutates: []const u64,
    /// Declared return origin: `fresh`, `params` or `unknown`.
    return_origin: []const u8,
};

/// What one invocation needs from the host beyond a fresh child process.
pub const Authority = struct {
    /// Capability types other than the injected `Stream` the signature needs.
    capabilities: []const []const u8,
    /// Declared effects the host must grant.
    effects: []const []const u8,
};

/// A JSON Schema for one request or result position of the wire subset.
pub const WireSchema = struct {
    /// JSON Schema of the named-argument object a request supplies.
    request: Value = .null,
    /// JSON Schema of the value a completed call returns.
    result: Value = .null,
};

/// The `--describe` answer: contract, authority and eligibility.
pub const Description = struct {
    /// Whether `--input` can execute this target.
    eligible: bool,
    /// Whether the checked signature is inside the copied-value wire subset at
    /// all, which is what `wire_schema` and the request spelling describe.
    wire_supported: bool,
    /// The checked contract the target advertises.
    contract: Contract,
    /// Host authority the signature and effects require.
    authority: Authority,
    /// Generated JSON Schema for the supported wire subset.
    wire_schema: ?WireSchema = null,
    /// Why the target is not eligible; absent when it is.
    unsupported: ?Failure = null,
};

/// One `native-invocation-v1` response object, rendered once on stdout.
pub const Response = struct {
    /// Envelope version tag.
    version: []const u8 = envelope_version,
    /// How the request ended.
    status: []const u8,
    /// The selected entry and function.
    target: Target = .{},
    /// The `--describe` payload, when the request described.
    description: ?Description = null,
    /// The executed call, when the request invoked.
    invocation: ?Invocation = null,
    /// Why the request failed, on every non-completed status.
    failure: ?Failure = null,
    /// Effective quotas and identities of this answer.
    context: Context = .{},
};

/// Checked-schema reading and eligibility failures.
pub const Error = error{ OutOfMemory, InvalidSchema };

/// The checked schema entry for one qualified name, or null when the checked
/// graph does not expose that name as an invokable export.
pub fn select(schema: Value, qualified: []const u8) ?Value {
    for (v.array(v.get(schema, "functions"))) |function| {
        if (std.mem.eql(u8, v.text(v.get(function, "name")), qualified)) return function;
    }
    return null;
}

/// The checked type definitions the schema publishes for reachable exports.
pub fn types(schema: Value) []const Value {
    return v.array(v.get(schema, "types"));
}

/// The checked declaration of one type name, or null when the schema has none.
pub fn definition(definitions: []const Value, name: []const u8) ?Value {
    for (definitions) |item| {
        if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
    }
    return null;
}

/// The wire kind one checked type name crosses the invocation boundary as.
pub fn wireKind(definitions: []const Value, name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, stream_cap_name)) return "injected-stream";
    const item = definition(definitions, name) orelse return "unknown";
    const kind = v.text(v.get(item, "kind"));
    if (std.mem.eql(u8, kind, "domain")) {
        const codec = v.get(item, "codec");
        const encoded = v.text(v.get(codec, "wire"));
        return if (encoded.len == 0) "domain" else "domain";
    }
    return kind;
}

/// The declared result-origin spelling of one checked function.
pub fn returnOrigin(function: Value) []const u8 {
    const origin = v.text(v.get(function, "return_origin"));
    return if (origin.len == 0) "unknown" else origin;
}

/// Effects an invoked call may have without a host grant: allocation, printing
/// to the injected stream, and mutating its own copied arguments.
const grantable_effects = [_][]const u8{ "managed_allocation", "output", "mutation" };

/// A reason a selected export cannot be invoked as written.
pub const Refusal = struct {
    /// Short machine-readable category.
    kind: []const u8,
    /// The first unsupported type path, when the refusal is about one.
    path: []const u8 = "",
    /// One sentence naming what is unsupported and what would work instead.
    reason: []const u8,
};

/// The eligibility verdict for one checked signature.
pub const Verdict = struct {
    /// Whether `--input` can execute the target today.
    eligible: bool,
    /// Whether the signature is inside the copied-value wire subset at all.
    wire_supported: bool,
    /// Why the target is not eligible, when it is not.
    refusal: ?Refusal = null,
    /// Capability types the signature needs beyond the injected stream.
    capabilities: []const []const u8 = &.{},
    /// Declared effects the call would perform.
    effects: []const []const u8 = &.{},
};

/// One copied-value tree walk that reports the first unsupported type path.
const Walk = struct {
    allocator: std.mem.Allocator,
    definitions: []const Value,

    fn child(self: Walk, name: []const u8, path: []const u8, suffix: []const u8) Error!?Refusal {
        const joined = if (suffix.len == 0) path else try std.fmt.allocPrint(self.allocator, "{s} -> {s}", .{ path, suffix });
        return self.check(name, joined, false);
    }

    /// Walk one checked type at one path; null means the boundary can carry it.
    fn check(self: Walk, name: []const u8, path: []const u8, is_argument: bool) Error!?Refusal {
        const item = definition(self.definitions, name) orelse return .{
            .kind = unsupported_type_kind,
            .path = path,
            .reason = "the checked schema publishes no definition for this type, so it has no wire representation",
        };
        const kind = v.text(v.get(item, "kind"));
        if (std.mem.eql(u8, kind, "integer")) return integerRefusal(item, path);
        if (std.mem.eql(u8, kind, "boolean")) return null;
        if (v.boolean(v.get(item, "move_only"))) return .{
            .kind = unsupported_type_kind,
            .path = path,
            .reason = "a move-only value has one owner and cannot be copied across the invocation boundary",
        };
        if (is_argument) {
            // The injected standard stream is the one capability the runtime
            // supplies itself; it is not a value the request carries.
            if (std.mem.eql(u8, name, stream_cap_name)) return null;
            if (try argumentRefusal(name, kind, path)) |refusal| return refusal;
        }
        if (std.mem.eql(u8, kind, "domain")) return domainRefusal(self, item, path);
        if (std.mem.eql(u8, kind, "record")) return self.fields(item, path);
        if (std.mem.eql(u8, kind, "table")) return self.table(item, path);
        if (std.mem.eql(u8, kind, "array")) return self.child(v.text(v.get(item, "element")), path, "element");
        if (isVariant(kind)) return self.cases(item, path);
        return .{
            .kind = unsupported_type_kind,
            .path = path,
            .reason = try std.fmt.allocPrint(self.allocator, "kind '{s}' is outside the copied-value wire subset", .{kind}),
        };
    }

    fn fields(self: Walk, item: Value, path: []const u8) Error!?Refusal {
        for (v.array(v.get(item, "fields"))) |field| {
            const suffix = try std.fmt.allocPrint(self.allocator, "field '{s}'", .{v.text(v.get(field, "name"))});
            if (try self.child(v.text(v.get(field, "type")), path, suffix)) |refusal| return refusal;
        }
        return null;
    }

    fn table(self: Walk, item: Value, path: []const u8) Error!?Refusal {
        const key = definition(self.definitions, v.text(v.get(item, "key"))) orelse return .{
            .kind = unsupported_type_kind,
            .path = path,
            .reason = "the table's key enumeration has no checked definition",
        };
        for (v.array(v.get(key, "cases"))) |case| {
            const suffix = try std.fmt.allocPrint(self.allocator, "key '{s}'", .{v.text(v.get(case, "name"))});
            if (try self.child(v.text(v.get(item, "element")), path, suffix)) |refusal| return refusal;
        }
        return null;
    }

    fn cases(self: Walk, item: Value, path: []const u8) Error!?Refusal {
        for (v.array(v.get(item, "cases"))) |case| {
            const payload = v.get(case, "payload");
            if (payload != .string) continue;
            const suffix = try std.fmt.allocPrint(self.allocator, "case '{s}' payload", .{v.text(v.get(case, "name"))});
            if (try self.child(v.text(payload), path, suffix)) |refusal| return refusal;
        }
        return null;
    }

    fn domainRefusal(self: Walk, item: Value, path: []const u8) Error!?Refusal {
        const encoded = v.get(v.get(item, "codec"), "wire");
        if (encoded != .string) return .{
            .kind = unsupported_type_kind,
            .path = path,
            .reason = "this domain declares no codec, so it has no wire representation",
        };
        return self.child(encoded.string, path, "");
    }
};

fn isVariant(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "enumeration") or std.mem.eql(u8, kind, "tagged_union") or std.mem.eql(u8, kind, "result");
}

/// Failure kind for a request whose shape cannot be executed as written.
pub const invalid_request_kind = "invalid-request";
/// Failure kind for a checked type outside the copied-value wire subset.
const unsupported_type_kind = "unsupported-type";
/// The name the checked schema gives the injected standard output stream.
const stream_cap_name = "stream_cap";

/// The exact-integer names the copied-value codec accepts; a user alias of an
/// integer is a distinct nominal spelling and is not reconstructed.
fn integerRefusal(item: Value, path: []const u8) ?Refusal {
    const name = v.text(v.get(item, "name"));
    if (name.len < 2 or (name[0] != 'i' and name[0] != 'u')) return integerNameRefusal(path);
    const width = std.fmt.parseInt(u8, name[1..], 10) catch return integerNameRefusal(path);
    if (width != 8 and width != 16 and width != 32 and width != 64) return integerNameRefusal(path);
    if (v.number(v.get(item, "bits")) != width) return integerNameRefusal(path);
    return null;
}

fn integerNameRefusal(path: []const u8) Refusal {
    return .{
        .kind = unsupported_type_kind,
        .path = path,
        .reason = "integers cross as decimal strings only under their canonical i8/i16/i32/i64/u8/u16/u32/u64 name",
    };
}

/// An argument position crosses the native ABI, which carries a copyable
/// aggregate as the address of its storage and a scalar as one word. The
/// generated adapter reads that crossing from the compiler's manifest and
/// passes the argument buffer pointer, so every type the copied-value codec can
/// reconstruct is executable; only a capability still needs a host grant, and
/// the checked wire subset of an aggregate is walked so an unsupported nested
/// type keeps naming its own path.
fn argumentRefusal(name: []const u8, kind: []const u8, path: []const u8) Error!?Refusal {
    if (std.mem.eql(u8, name, stream_cap_name)) return null;
    if (std.mem.eql(u8, kind, "capability")) return .{
        .kind = "authority",
        .path = path,
        .reason = "a capability argument needs a host grant; `mylang invoke` supplies only the standard streams",
    };
    if (isFixedAggregate(kind)) return null;
    return .{
        .kind = unsupported_type_kind,
        .path = path,
        .reason = "this argument type is outside the copied-value wire subset",
    };
}

/// Whether one kind is a copied-value aggregate the codec can reconstruct.
fn isFixedAggregate(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "record") or std.mem.eql(u8, kind, "array") or std.mem.eql(u8, kind, "table") or
        std.mem.eql(u8, kind, "domain") or isVariant(kind);
}

/// Whether a declared effect needs authority the invocation does not grant.
fn effectRefusal(effect: []const u8) ?Refusal {
    for (grantable_effects) |allowed| if (std.mem.eql(u8, allowed, effect)) return null;
    return .{
        .kind = "authority",
        .reason = "the call declares an external effect; `mylang invoke` grants no filesystem, network, clock, entropy, environment or host authority",
    };
}

/// Decide whether one checked signature can be invoked, naming the first
/// unsupported type path or the missing authority instead of running it. Every
/// type the checked wire subset carries is executable, because the generated
/// adapter passes a copyable aggregate as the address of the emitter's own
/// crossing, so `wire_supported` and `eligible` disagree only on authority.
pub fn eligibility(allocator: std.mem.Allocator, schema: Value, function: Value) Error!Verdict {
    const definitions = types(schema);
    const walk: Walk = .{ .allocator = allocator, .definitions = definitions };
    var verdict: Verdict = .{ .eligible = true, .wire_supported = true };
    const effects = try effectNames(allocator, function);
    verdict.effects = effects;
    for (v.array(v.get(function, v.parameters_key))) |parameter| {
        const name = v.text(v.get(parameter, "name"));
        const type_name = v.text(v.get(parameter, "type"));
        const path = try std.fmt.allocPrint(allocator, "argument '{s}'", .{name});
        const item = definition(definitions, type_name);
        if (item != null and std.mem.eql(u8, v.text(v.get(item.?, "kind")), "capability") and !std.mem.eql(u8, type_name, stream_cap_name)) {
            verdict.capabilities = try append(allocator, verdict.capabilities, type_name);
        }
        const refusal = try walk.check(type_name, path, true);
        if (refusal != null) verdict.wire_supported = false;
        if (refusal) |item_refusal| return .{
            .eligible = false,
            .wire_supported = verdict.wire_supported,
            .refusal = item_refusal,
            .capabilities = verdict.capabilities,
            .effects = effects,
        };
    }
    for (effects) |effect| {
        if (effectRefusal(effect)) |refusal| return .{
            .eligible = false,
            .wire_supported = verdict.wire_supported,
            .refusal = refusal,
            .capabilities = verdict.capabilities,
            .effects = effects,
        };
    }
    const result = try std.fmt.allocPrint(allocator, "result of '{s}'", .{v.text(v.get(function, "name"))});
    const refusal = try walk.check(v.text(v.get(function, "result")), result, false);
    if (refusal != null) verdict.wire_supported = false;
    if (refusal) |item_refusal| return .{
        .eligible = false,
        .wire_supported = verdict.wire_supported,
        .refusal = item_refusal,
        .capabilities = verdict.capabilities,
        .effects = effects,
    };
    return verdict;
}

/// The declared effect ceiling of one checked function, in declaration order.
pub fn effectNames(allocator: std.mem.Allocator, function: Value) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (v.array(v.get(function, "effects"))) |effect| try names.append(allocator, v.text(effect));
    return names.items;
}

/// The declared mutation footprint positions of one checked function.
pub fn mutates(allocator: std.mem.Allocator, function: Value) Error![]const u64 {
    var positions: std.ArrayList(u64) = .empty;
    for (v.array(v.get(function, "mutates"))) |position| try positions.append(allocator, v.number(position));
    return positions.items;
}

fn append(allocator: std.mem.Allocator, values: []const []const u8, item: []const u8) Error![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    try list.appendSlice(allocator, values);
    try list.append(allocator, item);
    return list.items;
}

/// Whether a message names a returned language error rather than a value.
pub fn returnedError(actual: Value) bool {
    if (actual != .object) return false;
    const selected = v.get(actual, "case");
    return selected == .string and std.mem.eql(u8, selected.string, "err");
}

/// Parse the located trap text one failed child response carries into its trap
/// code, operation and source-mapped frames. Text that does not match the
/// runtime's own rendering leaves the structured fields empty; the raw
/// diagnostics stay authoritative either way.
pub fn trapDetail(allocator: std.mem.Allocator, diagnostics: []const u8) Error!Trap {
    var lines = std.mem.splitScalar(u8, diagnostics, '\n');
    const header = lines.next() orelse return .{};
    var trap: Trap = .{ .code = trapCode(header), .operation = trapOperation(header) };
    var frames: std.ArrayList(Frame) = .empty;
    while (lines.next()) |line| {
        if (try trapFrame(line)) |parsed| try frames.append(allocator, parsed);
    }
    trap.frames = frames.items;
    return trap;
}

/// The runtime trap code at the head of one located trap line. Only the
/// runtime's own `R_`-prefixed codes are structured; host failure text keeps
/// its raw spelling in `diagnostics` alone.
fn trapCode(header: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, header, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "R_")) return "";
    if (std.mem.indexOfScalar(u8, trimmed, ' ')) |at| return trimmed[0..at];
    return trimmed;
}

/// The bounded operation name inside the detail parentheses, when present.
fn trapOperation(header: []const u8) []const u8 {
    const open = std.mem.indexOfScalar(u8, header, '(') orelse return "";
    const rest = header[open + 1 ..];
    const close = std.mem.indexOfScalar(u8, rest, ')') orelse return "";
    const detail = rest[0..close];
    if (std.mem.indexOfScalar(u8, detail, ':')) |at| return detail[0..at];
    return detail;
}

/// One `  in function at path:line:column` trace line, or null for any other.
fn trapFrame(line: []const u8) Error!?Frame {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "in ")) return null;
    const rest = trimmed["in ".len..];
    const at = std.mem.indexOf(u8, rest, " at ") orelse return null;
    const where = rest[at + " at ".len ..];
    const column_at = std.mem.lastIndexOfScalar(u8, where, ':') orelse return null;
    const line_at = std.mem.lastIndexOfScalar(u8, where[0..column_at], ':') orelse return null;
    return .{
        .function = rest[0..at],
        .path = where[0..line_at],
        .line = std.fmt.parseInt(u64, where[line_at + 1 .. column_at], 10) catch return null,
        .column = std.fmt.parseInt(u64, where[column_at + 1 ..], 10) catch return null,
    };
}

/// The declared argument names a request must supply, excluding injected ones.
pub fn argumentNames(allocator: std.mem.Allocator, function: Value) Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (v.array(v.get(function, v.parameters_key))) |parameter| {
        if (std.mem.eql(u8, v.text(v.get(parameter, "type")), stream_cap_name)) continue;
        try names.append(allocator, v.text(v.get(parameter, "name")));
    }
    return names.items;
}

/// The first declared name missing from `values`, or the first extra key.
/// Duplicates are rejected earlier, from the raw request text, because a JSON
/// parser keeps only the last spelling of a repeated key.
pub fn nameRefusal(allocator: std.mem.Allocator, function: Value, values: Value) Error!?Failure {
    if (values != .object) return .{ .kind = invalid_request_kind, .reason = "the request must be a JSON object of named arguments" };
    const names = try argumentNames(allocator, function);
    for (names) |name| {
        if (!values.object.contains(name)) return .{
            .kind = invalid_request_kind,
            .reason = try std.fmt.allocPrint(allocator, "argument '{s}' is missing", .{name}),
        };
    }
    var iterator = values.object.iterator();
    while (iterator.next()) |entry| {
        const known = for (names) |name| {
            if (std.mem.eql(u8, name, entry.key_ptr.*)) break true;
        } else false;
        if (!known) return .{
            .kind = invalid_request_kind,
            .reason = try std.fmt.allocPrint(allocator, "argument '{s}' is not a parameter of the selected function", .{entry.key_ptr.*}),
        };
    }
    return null;
}

/// The first argument whose JSON value the copied-value codec rejects. Only the
/// failing path reaches this probe, so a valid request never re-encodes.
pub fn valueRefusal(allocator: std.mem.Allocator, codec: *wire.Codec, function: Value, values: Value) Error!?Failure {
    for (v.array(v.get(function, v.parameters_key))) |parameter| {
        const name = v.text(v.get(parameter, "name"));
        if (std.mem.eql(u8, v.text(v.get(parameter, "type")), stream_cap_name)) continue;
        const supplied = values.object.get(name) orelse continue;
        var probe: wire.Codec = .{ .allocator = allocator, .types = codec.types };
        defer probe.deinit();
        probe.encode(v.text(v.get(parameter, "type")), supplied, 0) catch |err| return .{
            .kind = invalid_request_kind,
            .path = try std.fmt.allocPrint(allocator, "argument '{s}'", .{name}),
            .reason = try std.fmt.allocPrint(allocator, "argument '{s}' is not a valid {s}: {s}", .{ name, v.text(v.get(parameter, "type")), valueReason(err) }),
        };
    }
    return null;
}

/// One actionable sentence for a copied-value codec rejection.
fn valueReason(err: wire.Error) []const u8 {
    return switch (err) {
        error.InvalidTestValue => "the JSON value does not match the declared shape (an integer is a decimal string, a record is an object of its fields, an array has its exact length)",
        error.TestValueLimit => "the value nests deeper than 64 levels or exceeds the node budget",
        error.UnsupportedTestType => "the declared type is outside the copied-value wire subset",
        else => "the value could not be converted",
    };
}

/// Validate named arguments against the signature and flatten them into the
/// child's wire nodes, rejecting missing, extra, duplicate and malformed input.
pub fn arguments(codec: *wire.Codec, allocator: std.mem.Allocator, function: Value, values: Value) Error!?Failure {
    if (try nameRefusal(allocator, function, values)) |failure| return failure;
    codec.arguments(function, values) catch |err| {
        if (try valueRefusal(allocator, codec, function, values)) |failure| return failure;
        return .{ .kind = invalid_request_kind, .reason = @errorName(err) };
    };
    return null;
}

/// The first top-level object key that appears twice in `text`, or null. The
/// scan is byte-level because a parsed object has already lost the first
/// spelling; a key with escapes compares by its raw spelling.
pub fn duplicateKey(allocator: std.mem.Allocator, text: []const u8) Error!?[]const u8 {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    var cursor = skipSpace(text, 0);
    if (cursor >= text.len or text[cursor] != '{') return null;
    cursor = skipSpace(text, cursor + 1);
    if (cursor < text.len and text[cursor] == '}') return null;
    while (cursor < text.len) {
        const key = try string(text, cursor) orelse return null;
        if (seen.contains(key.value)) return key.value;
        try seen.put(allocator, key.value, {});
        const colon = skipSpace(text, key.end);
        if (colon >= text.len or text[colon] != ':') return null;
        cursor = skipSpace(text, try skipValue(text, skipSpace(text, colon + 1)));
        if (cursor < text.len and text[cursor] == ',') {
            cursor = skipSpace(text, cursor + 1);
            continue;
        }
        return null;
    }
    return null;
}

const Span = struct { value: []const u8, end: usize };

fn skipSpace(text: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < text.len and std.ascii.isWhitespace(text[cursor])) cursor += 1;
    return cursor;
}

/// One JSON string at `start`, with its raw inner bytes and the position after
/// the closing quote.
fn string(text: []const u8, start: usize) Error!?Span {
    if (start >= text.len or text[start] != '"') return null;
    var cursor = start + 1;
    while (cursor < text.len) {
        switch (text[cursor]) {
            '"' => return .{ .value = text[start + 1 .. cursor], .end = cursor + 1 },
            '\\' => cursor += 2,
            else => cursor += 1,
        }
    }
    return null;
}

/// The position after one JSON value at `start`, skipping strings and nesting.
fn skipValue(text: []const u8, start: usize) Error!usize {
    if (start >= text.len) return start;
    if (text[start] == '"') return if (try string(text, start)) |found| found.end else text.len;
    if (text[start] != '{' and text[start] != '[') return scalarEnd(text, start);
    var depth: usize = 0;
    var cursor = start;
    while (cursor < text.len) : (cursor += 1) {
        if (text[cursor] == '"') {
            cursor = if (try string(text, cursor)) |found| found.end - 1 else text.len;
            continue;
        }
        if (text[cursor] == '{' or text[cursor] == '[') depth += 1;
        if (text[cursor] != '}' and text[cursor] != ']') continue;
        depth -= 1;
        if (depth == 0) return cursor + 1;
    }
    return text.len;
}

/// The position after one scalar JSON token: a number, literal or bare word.
fn scalarEnd(text: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < text.len and text[cursor] != ',' and text[cursor] != '}' and text[cursor] != ']') cursor += 1;
    return cursor;
}
