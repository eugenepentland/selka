//! Select scalar instruction forms for the resolved native backend.
const std = @import("std");

/// Both policies preserve checked arithmetic; LLVM keeps division visible to
/// its own signed constant-division optimizer instead of receiving a recipe.
pub const Policy = enum {
    qbe,
    llvm,

    /// A foreign frontend receives no new internal argument.
    pub fn forBackend(llvm: bool, foreign: bool) Policy {
        return if (llvm and !foreign) .llvm else .qbe;
    }
    /// Stable fragment and replay key for backend-native scalar operations.
    pub fn identity(self: Policy) []const u8 {
        return switch (self) {
            .qbe => "",
            .llvm => "scalar-llvm-v1",
        };
    }
    /// Configuration spelling carried by module interface facts.
    pub fn suffix(self: Policy) []const u8 {
        return switch (self) {
            .qbe => "",
            .llvm => " scalar=llvm-v1",
        };
    }
    /// Internal frontend switch, absent for the standalone QBE API default.
    pub fn flag(self: Policy) ?[]const u8 {
        return switch (self) {
            .qbe => null,
            .llvm => "--native-scalars=llvm-v1",
        };
    }
    /// Refuse unknown or unchecked policies.
    pub fn parse(text: []const u8) ?Policy {
        if (std.mem.eql(u8, text, "qbe")) return .qbe;
        if (std.mem.eql(u8, text, "llvm-v1")) return .llvm;
        return null;
    }
};
