//! Declarations the semantic checker's modules share: diagnostic codes and
//! messages, and the small value types that cross module boundaries.
const std = @import("std");
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const source = @import("source.zig");
const typed = @import("typed.zig");
const ast = @import("ast.zig");
const option_flow = @import("option_flow.zig");
pub const call_argument_code = "E_CALL_ARGUMENT";
pub const eCollectionMethod = "E_COLLECTION_METHOD";
pub const eFileArgument = "E_FILE_ARGUMENT";
/// The refusal of `net.host(value)` with a value that is not a literal, naming the operations that take one (FR5a).
pub const network_host_literal_message = "host requires a string literal endpoint; for an address the program has at run time, " ++
    "use `network.connect_to`, `connect_within_to`, `listen_at`, `open_poller_at` or `dial_to`, which the launch's grants check";
/// The refusal of `fs.dir(value)` with a value that is not a literal, naming the call that takes a folder known at run time.
pub const filesystem_dir_literal_message = "dir requires a string literal path; for a folder the program learns at run time, " ++
    "use `filesystem.dir_at(fs, path)`, which reads the path as `fs` reads one and returns the same narrowed Filesystem";
/// Whether `fs.dir(...)` with one computed argument is written in one of the compiler's own standard-library sources (or
/// one granted their trust), the one place a computed narrowing is checked (`filesystem.dir_at`); its argument is then
/// queued before the call. `src` is the checker's source and `nodes` its syntax nodes.
pub fn computedDirSite(src: anytype, nodes: []const ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
    if (input.arguments.len != 1 or input.type_arguments.len != 0 or input.argument_names.len != 0) return false;
    const argument = nodes[@backingInt(input.arguments[0])];
    if (argument.data == .text or argument.data == .bytes) return false;
    const library = @import("standard_library.zig");
    if (src.trusted_intrinsics or library.trusted(src.path, src.bytes, false)) return true;
    const original = src.originalSpan(input.name) catch return false;
    const unit = src.origins[original.input].original;
    return library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
}
/// The refusal of `acquire_resource` on a Network outside the standard library (FR5a), naming what to use instead.
pub const raw_network_message = "`acquire_resource` on a Network is reserved for the standard library's `network` module, whose requests are its own encoding; " ++
    "use `network.connect`, `connect_within`, `listen`, `open_poller` or `dial` on a `net.host(\"IP:PORT\")` narrowing, or " ++
    "`network.connect_to`, `connect_within_to`, `listen_at`, `open_poller_at` or `dial_to` with an address the program has at run time";
/// The ownership-transfer state of one local at a control-flow checkpoint.
pub const Pending = struct { available: bool, transfer_span: ?source.Span };
/// One pending node on the expression work queue, with the context it is checked in.
/// One queued expression check. `hint_from` names an operand checked earlier whose
/// type becomes this expression's expected type just before it is checked.
pub const Work = struct {
    default_value: bool = false,
    id: ast.NodeId,
    /// `emit_borrowed` emits a field read whose value is borrowed (the operand of `own`, of `mut`, or the base of a further
    /// field read), so a `@linear` field it reads is not a second owner (`linear_rules.checkProjection`).
    mode: enum { check, emit, borrow_result_list, emit_borrowed } = .check,
    checkpoint: ?option_flow.Guard = null,
    sorted_key: bool = false,
    verify: ?struct { pending: []const Pending, facts: []const usize } = null,
    hint_from: ?Peer = null,
};
/// An operand checked before a queued expression, whose type the expression expects. `literal` marks an unsuffixed
/// literal beside it, which takes that type only by `literal_peer.adopted`'s rule.
pub const Peer = struct { id: ast.NodeId, literal: ?@import("literal_peer.zig").Site = null };
/// The `lambda_types` entry of a sort-key lambda whose key type could not be
/// inferred (LAMBDA-KEY-INFER-1). No callback type is `unit`, so the marker
/// never collides with a real slot; its `E_SORT_KEY` already names the lambda.
pub const uninferred_lambda: typed.Type = .unit;
/// Whether a callee declares a `mut` footprint at this parameter position.
pub fn markerPositionDeclared(positions: []const u16, position: u16) bool {
    for (positions) |candidate| if (candidate == position) return true;
    return false;
}
/// Whether a managed byte-kind schema is the mutable octet buffer rather than an
/// immutable byte string.
pub fn isMutableBytes(schema: typed.Record) bool {
    return schema.collection.kind == .bytes and std.mem.eql(u8, schema.name, byte_buffer_name);
}
pub const eCellEquality = "E_CELL_EQUALITY";
/// One diagnostic for every rejected `Option` operation, so the intrinsic
/// methods and the `is None` test report the same code.
pub const eOptionTest = "E_OPTION_TEST";
pub const bufferOperation = "buffer_operation";
pub const eEnvironmentName = "E_ENVIRONMENT_NAME";
pub const eWithResource = "E_WITH_RESOURCE";
pub const lambda_context_code = "E_LAMBDA_CONTEXT";
pub const variantDeclaredHere = "variant declared here";
/// One name a lambda body reads from its enclosing function.
pub const LambdaCapture = struct { name: []const u8 };
/// How a checked statement leaves control flow: whether it terminates or loops forever.
pub const StatementFlow = struct {
    terminates: bool = false,
    /// A loop the checker proved never exits ends control flow without making a
    /// following statement a mistake, because its exit is inferred, not written.
    looping: bool = false,
};
