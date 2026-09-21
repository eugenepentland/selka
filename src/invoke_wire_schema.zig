//! Generated JSON Schema for the `native-invocation-v1` wire subset.
//!
//! This describes *only* what one invocation request and response carry: an
//! object of named arguments whose scalar and aggregate spellings the
//! copied-value codec reconstructs, and the value a completed call returns.
//! It is deliberately not the language-contract graph — no effects, mutation
//! footprint, ownership or origin appear here, and the checked contract itself
//! stays the `language-schema-v1` document the compiler publishes.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const invoke = @import("invoke.zig");
const wire = @import("native_test_wire.zig");
const Value = std.json.Value;

/// JSON Schema dialect name every generated document declares without a URL.
pub const dialect = "2020-12";

/// Generated-schema failures: a malformed checked type graph, or allocation.
pub const Error = error{ InvalidSchema, OutOfMemory };
/// JSON Schema object key holding one value's members.
const properties_key = "properties";
/// JSON Schema keyword refusing unknown members.
const additional_key = "additionalProperties";
/// JSON Schema keyword listing the members a value must carry.
const required_key = "required";
/// Extension key tying a wire subschema back to its checked language type.
const type_key = "x-mylang-type";

/// Annotation key carrying the human-readable meaning of one wire subschema.
const description_key = "description";

/// Pattern a signed `iN` argument must match: a canonical decimal string.
pub const signed_pattern = "^-?(0|[1-9][0-9]*)$";

/// Pattern an unsigned `uN` argument must match: a canonical decimal string.
pub const unsigned_pattern = "^(0|[1-9][0-9]*)$";

/// The nesting bound the copied-value codec enforces on one value tree.
const depth_limit = 64;
/// The checked schema kind of a user list. Text carries the same kind, so the
/// earlier nominal `str` branch is what keeps text out of this one.
const list_kind = "list";

const Pair = struct { key: []const u8, value: Value };

fn object(allocator: std.mem.Allocator, pairs: []const Pair) Error!Value {
    var map: std.json.ObjectMap = .empty;
    for (pairs) |entry| try map.put(allocator, entry.key, entry.value);
    return .{ .object = map };
}

fn string(value: []const u8) Value {
    return .{ .string = value };
}

fn boolean(value: bool) Value {
    return .{ .bool = value };
}

fn integer(value: u64) Value {
    return .{ .integer = @intCast(value) };
}

fn array(allocator: std.mem.Allocator, items: []const Value) Error!Value {
    var list: std.json.Array = .init(allocator);
    for (items) |item| try list.append(item);
    return .{ .array = list };
}

fn names(allocator: std.mem.Allocator, items: []const []const u8) Error!Value {
    var list: std.json.Array = .init(allocator);
    for (items) |item| try list.append(string(item));
    return .{ .array = list };
}

/// One generated JSON Schema document for the named-argument object a request
/// supplies to the selected function.
pub fn request(allocator: std.mem.Allocator, definitions: []const Value, function: Value) Error!Value {
    var properties: std.json.ObjectMap = .empty;
    var required: std.json.Array = .init(allocator);
    for (v.array(v.get(function, "parameters"))) |parameter| {
        const type_name = v.text(v.get(parameter, "type"));
        if (std.mem.eql(u8, type_name, "stream_cap")) continue;
        const name = v.text(v.get(parameter, "name"));
        try properties.put(allocator, name, try typeSchema(allocator, definitions, type_name, 0));
        try required.append(string(name));
    }
    return object(allocator, &.{
        .{ .key = "$id", .value = string("native-invocation-v1/request") },
        .{ .key = "x-mylang-dialect", .value = string(dialect) },
        .{ .key = "title", .value = string(try std.fmt.allocPrint(allocator, "mylang invoke request for {s}", .{v.text(v.get(function, "name"))})) },
        .{ .key = "$comment", .value = string("native-invocation-v1 wire subset: named arguments only, integers as decimal strings. This is not the language-contract graph.") },
        .{ .key = "type", .value = string("object") },
        .{ .key = properties_key, .value = .{ .object = properties } },
        .{ .key = required_key, .value = .{ .array = required } },
        .{ .key = additional_key, .value = boolean(false) },
    });
}

/// One generated JSON Schema document for the value a completed call returns.
pub fn result(allocator: std.mem.Allocator, definitions: []const Value, function: Value) Error!Value {
    var schema = try typeSchema(allocator, definitions, v.text(v.get(function, "result")), 0);
    if (schema != .object) return schema;
    try schema.object.put(allocator, "x-mylang-dialect", string(dialect));
    try schema.object.put(allocator, "$id", string("native-invocation-v1/result"));
    try schema.object.put(allocator, "$comment", string("native-invocation-v1 wire subset. This is not the language-contract graph."));
    return schema;
}

/// One JSON Schema for one checked type name, following the same nominal shape
/// the copied-value codec reconstructs.
pub fn typeSchema(allocator: std.mem.Allocator, definitions: []const Value, name: []const u8, depth: usize) Error!Value {
    if (depth > depth_limit) return error.InvalidSchema;
    if (std.mem.eql(u8, name, "stream_cap")) return object(allocator, &.{
        .{ .key = type_key, .value = string(name) },
        .{ .key = description_key, .value = string("injected by the runtime: a standard output stream the call may print to; it takes no request value") },
    });
    const item = invoke.definition(definitions, name) orelse return error.InvalidSchema;
    const kind = v.text(v.get(item, "kind"));
    // Immutable Unicode text crosses as a JSON string, in both positions. The
    // rule is the checked name `str`, so a user `List<u32>` — which the checked
    // schema spells identically — keeps its own refusal instead of being
    // described as text.
    if (wire.isText(name)) return object(allocator, &.{
        .{ .key = "type", .value = string("string") },
        .{ .key = type_key, .value = string(name) },
        .{ .key = description_key, .value = string("immutable Unicode text; it crosses as a JSON string and the boundary carries one wire node per Unicode scalar, so an embedded NUL is a scalar and not a terminator") },
    });
    // A user list crosses as one wire node per element, so the schema is a JSON
    // array whose items are the element's own schema. Neither end is bounded:
    // a list has no declared length, unlike a fixed-size array.
    if (std.mem.eql(u8, kind, list_kind)) return object(allocator, &.{
        .{ .key = "type", .value = string("array") },
        .{ .key = "items", .value = try typeSchema(allocator, definitions, v.text(v.get(item, "element")), depth + 1) },
        .{ .key = type_key, .value = string(name) },
    });
    if (std.mem.eql(u8, kind, "integer")) return integerSchema(allocator, item, name);
    if (std.mem.eql(u8, kind, "boolean")) return object(allocator, &.{
        .{ .key = "type", .value = string("boolean") },
        .{ .key = type_key, .value = string(name) },
    });
    if (std.mem.eql(u8, kind, "domain")) {
        const encoded = v.text(v.get(v.get(item, "codec"), "wire"));
        if (encoded.len == 0) return error.InvalidSchema;
        var schema = try typeSchema(allocator, definitions, encoded, depth + 1);
        if (schema != .object) return schema;
        try schema.object.put(allocator, "x-mylang-domain", string(name));
        return schema;
    }
    if (std.mem.eql(u8, kind, "record")) return fieldsSchema(allocator, definitions, item, name, depth);
    if (std.mem.eql(u8, kind, "table")) return tableSchema(allocator, definitions, item, name, depth);
    if (std.mem.eql(u8, kind, "array")) return object(allocator, &.{
        .{ .key = "type", .value = string("array") },
        .{ .key = "items", .value = try typeSchema(allocator, definitions, v.text(v.get(item, "element")), depth + 1) },
        .{ .key = "minItems", .value = integer(v.number(v.get(item, "length"))) },
        .{ .key = "maxItems", .value = integer(v.number(v.get(item, "length"))) },
        .{ .key = type_key, .value = string(name) },
    });
    if (std.mem.eql(u8, kind, "enumeration")) return enumerationSchema(allocator, item, name);
    if (std.mem.eql(u8, kind, "tagged_union") or std.mem.eql(u8, kind, "result")) return variantSchema(allocator, definitions, item, name, depth);
    return error.InvalidSchema;
}

fn integerSchema(allocator: std.mem.Allocator, item: Value, name: []const u8) Error!Value {
    const signed = v.boolean(v.get(item, "signed"));
    const minimum = v.text(v.get(item, "minimum"));
    const maximum = v.text(v.get(item, "maximum"));
    return object(allocator, &.{
        .{ .key = "type", .value = string("string") },
        .{ .key = "pattern", .value = string(if (signed) signed_pattern else unsigned_pattern) },
        .{ .key = type_key, .value = string(name) },
        .{ .key = "x-mylang-minimum", .value = string(minimum) },
        .{ .key = "x-mylang-maximum", .value = string(maximum) },
        .{ .key = description_key, .value = string(try std.fmt.allocPrint(allocator, "exact {d}-bit {s} integer written as a decimal string in [{s}, {s}]", .{
            v.number(v.get(item, "bits")),
            if (signed) "signed" else "unsigned",
            minimum,
            maximum,
        })) },
    });
}

fn fieldsSchema(allocator: std.mem.Allocator, definitions: []const Value, item: Value, name: []const u8, depth: usize) Error!Value {
    var properties: std.json.ObjectMap = .empty;
    var required: std.json.Array = .init(allocator);
    for (v.array(v.get(item, "fields"))) |field| {
        const field_name = v.text(v.get(field, "name"));
        try properties.put(allocator, field_name, try typeSchema(allocator, definitions, v.text(v.get(field, "type")), depth + 1));
        try required.append(string(field_name));
    }
    return object(allocator, &.{
        .{ .key = "type", .value = string("object") },
        .{ .key = properties_key, .value = .{ .object = properties } },
        .{ .key = required_key, .value = .{ .array = required } },
        .{ .key = additional_key, .value = boolean(false) },
        .{ .key = type_key, .value = string(name) },
    });
}

fn tableSchema(allocator: std.mem.Allocator, definitions: []const Value, item: Value, name: []const u8, depth: usize) Error!Value {
    const key = invoke.definition(definitions, v.text(v.get(item, "key"))) orelse return error.InvalidSchema;
    const element = try typeSchema(allocator, definitions, v.text(v.get(item, "element")), depth + 1);
    var properties: std.json.ObjectMap = .empty;
    var required: std.json.Array = .init(allocator);
    for (v.array(v.get(key, "cases"))) |case| {
        const case_name = v.text(v.get(case, "name"));
        try properties.put(allocator, case_name, element);
        try required.append(string(case_name));
    }
    return object(allocator, &.{
        .{ .key = "type", .value = string("object") },
        .{ .key = properties_key, .value = .{ .object = properties } },
        .{ .key = required_key, .value = .{ .array = required } },
        .{ .key = additional_key, .value = boolean(false) },
        .{ .key = type_key, .value = string(name) },
    });
}

fn enumerationSchema(allocator: std.mem.Allocator, item: Value, name: []const u8) Error!Value {
    var values: std.json.Array = .init(allocator);
    for (v.array(v.get(item, "cases"))) |case| try values.append(string(v.text(v.get(case, "name"))));
    return object(allocator, &.{
        .{ .key = "type", .value = string("string") },
        .{ .key = "enum", .value = .{ .array = values } },
        .{ .key = type_key, .value = string(name) },
    });
}

fn variantSchema(allocator: std.mem.Allocator, definitions: []const Value, item: Value, name: []const u8, depth: usize) Error!Value {
    var alternatives: std.json.Array = .init(allocator);
    for (v.array(v.get(item, "cases"))) |case| {
        const case_name = v.text(v.get(case, "name"));
        const payload = v.get(case, "payload");
        var properties: std.json.ObjectMap = .empty;
        try properties.put(allocator, "case", .{ .object = try constObject(allocator, case_name) });
        var required: std.json.Array = .init(allocator);
        try required.append(string("case"));
        if (payload == .string) {
            try properties.put(allocator, "value", try typeSchema(allocator, definitions, payload.string, depth + 1));
            try required.append(string("value"));
        }
        try alternatives.append(try object(allocator, &.{
            .{ .key = "type", .value = string("object") },
            .{ .key = properties_key, .value = .{ .object = properties } },
            .{ .key = required_key, .value = .{ .array = required } },
            .{ .key = additional_key, .value = boolean(false) },
        }));
    }
    return object(allocator, &.{
        .{ .key = "oneOf", .value = .{ .array = alternatives } },
        .{ .key = type_key, .value = string(name) },
        .{ .key = "x-mylang-result-error-case", .value = string("err") },
    });
}

fn constObject(allocator: std.mem.Allocator, value: []const u8) Error!std.json.ObjectMap {
    var map: std.json.ObjectMap = .empty;
    try map.put(allocator, "const", string(value));
    return map;
}
