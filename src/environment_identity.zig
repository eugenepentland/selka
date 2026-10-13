//! The environment identity contract (ENV-IDENTITY-1, ENV-IDENTITY-2) in Zig.
//! `environment_identity.zon` lists which variables are keyed for every
//! identity, keyed for host tools only, only placement, or dropped; this file classifies a name against that
//! list and computes the environment digest. It allocates nothing, performs no
//! I/O and imports only `std`, so the compiler, the test receipts and a build
//! host tool can all compile it. `scripts/verification_environment.py` reads the
//! same contract and must produce the same classes and digests; the fixture
//! under `test/fixtures/environment-identity` pins both.
const std = @import("std");

/// How one environment variable takes part in identities and child environments.
pub const Class = enum {
    /// `NAME=VALUE` enters every identity, guest and host, and children receive it.
    keyed,
    /// `NAME=VALUE` enters host-tool identities only, never a guest test
    /// receipt, and children receive the variable.
    host,
    /// Children receive the variable, but no identity contains it.
    placement,
    /// Children never receive the variable, and no identity contains it.
    dropped,
};

/// Which identity a digest is for: a guest test receipt keys only the keyed
/// class; host tooling (build-graph verdicts, Python drivers, the coordinator)
/// keys the keyed and host classes.
pub const Scope = enum { guest, host };

/// The domain string that starts every environment digest.
pub const domain = "environment-identity-v1";

/// One environment variable handed to `digest`.
pub const Variable = struct { name: []const u8, value: []const u8 };

/// One tool handed to `digest`: its name and the lowercase hex SHA-256 of its bytes.
pub const Tool = struct { name: []const u8, digest: []const u8 };

const Contract = struct { keyed: []const []const u8, host: []const []const u8, placement: []const []const u8, dropped: []const []const u8 };
const contract: Contract = @import("environment_identity.zon");
const Rule = struct { pattern: []const u8, class: Class };
const rule_count = contract.keyed.len + contract.host.len + contract.placement.len + contract.dropped.len;
const rules: [rule_count]Rule = validated();

/// Every contract entry tagged with its class, rejected at compile time when an
/// entry is empty, has a `*` anywhere but at its end, or is spelled twice.
fn validated() [rule_count]Rule {
    comptime {
        @setEvalBranchQuota(200_000);
        var all: [rule_count]Rule = undefined;
        var next: usize = 0;
        for ([_]Class{ .keyed, .host, .placement, .dropped }) |class| {
            for (@field(contract, @tagName(class))) |pattern| {
                if (pattern.len == 0 or std.mem.eql(u8, pattern, "*")) @compileError("environment_identity.zon: empty entry");
                if (std.mem.indexOfScalar(u8, pattern[0 .. pattern.len - 1], '*') != null) @compileError("environment_identity.zon: '*' only ends a prefix: " ++ pattern);
                for (all[0..next]) |earlier| if (std.mem.eql(u8, earlier.pattern, pattern)) @compileError("environment_identity.zon: duplicate entry " ++ pattern);
                all[next] = .{ .pattern = pattern, .class = class };
                next += 1;
            }
        }
        return all;
    }
}

/// The class of the variable `name`: an exact entry wins, then the longest
/// matching prefix entry, and a name nothing matches is dropped.
pub fn classify(name: []const u8) Class {
    var best: Class = .dropped;
    var best_length: usize = 0;
    for (rules) |rule| {
        if (rule.pattern[rule.pattern.len - 1] != '*') {
            if (std.mem.eql(u8, name, rule.pattern)) return rule.class;
            continue;
        }
        const prefix = rule.pattern[0 .. rule.pattern.len - 1];
        if (prefix.len > best_length and std.mem.startsWith(u8, name, prefix)) {
            best = rule.class;
            best_length = prefix.len;
        }
    }
    return best;
}

/// Whether `NAME=VALUE` of this variable enters every identity, guest test
/// receipts included (the keyed class only).
pub fn keyed(name: []const u8) bool {
    return classify(name) == .keyed;
}

/// Whether `NAME=VALUE` of this variable enters host-tool identities (the
/// keyed and host classes).
pub fn hostKeyed(name: []const u8) bool {
    const class = classify(name);
    return class == .keyed or class == .host;
}

/// Whether a child process receives this variable (keyed, host or placement).
pub fn passedThrough(name: []const u8) bool {
    return classify(name) != .dropped;
}

/// The environment digest for `scope`, lowercase hex SHA-256 over `domain`,
/// then the name and value of every variable the scope keys (`keyed` for
/// `.guest`, `hostKeyed` for `.host`) in bytewise name order, then
/// `"tool:" ++ name` and the hex digest of every tool in name order, each as a
/// u64 little-endian length followed by the bytes. Other variables are ignored.
/// Both slices are sorted in place, so a caller passes its own buffers and
/// nothing is allocated; names must be unique within each slice.
pub fn digest(scope: Scope, variables: []Variable, tools: []Tool) [64]u8 {
    std.mem.sort(Variable, variables, {}, variableBefore);
    std.mem.sort(Tool, tools, {}, toolBefore);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    field(&hash, "", domain);
    for (variables) |variable| {
        const included = switch (scope) {
            .guest => keyed(variable.name),
            .host => hostKeyed(variable.name),
        };
        if (!included) continue;
        field(&hash, "", variable.name);
        field(&hash, "", variable.value);
    }
    for (tools) |tool| {
        field(&hash, "tool:", tool.name);
        field(&hash, "", tool.digest);
    }
    var bytes: [32]u8 = undefined;
    hash.final(&bytes);
    return std.fmt.bytesToHex(bytes, .lower);
}

/// One length-prefixed field whose bytes are `head` followed by `tail`.
fn field(hash: *std.crypto.hash.sha2.Sha256, head: []const u8, tail: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, head.len + tail.len, .little);
    hash.update(&length);
    hash.update(head);
    hash.update(tail);
}

fn variableBefore(_: void, lhs: Variable, rhs: Variable) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn toolBefore(_: void, lhs: Tool, rhs: Tool) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}
