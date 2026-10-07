//! Reviewed default native execution platform used exclusively by Core.
//! An unfamiliar runtime or loader cache remains executable without reuse.
// Bounded reviewed native execution platform. Retained readelf/ldd receipts
// prove this loader/libc/libm closure has no RPATH/RUNPATH and these exact cache
// bytes select the captured libc/libm paths. Unknown platform content bypasses
// reuse; this is not a generic ELF or ld.so.cache dependency parser.
pub const runtime_files = [_]struct { path: []const u8, resolved: []const u8, sha256: []const u8 }{
    .{
        .path = "/lib64/ld-linux-x86-64.so.2",
        .resolved = "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
        .sha256 = "bda779ea9e9ad234f60315477d7cfd0bdde861cd8ddd9df8cdaf62f18c4cec14",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libc.so.6",
        .resolved = "/usr/lib/x86_64-linux-gnu/libc.so.6",
        .sha256 = "85e64f97e348786a8fb4d9f3d52fec289e2fb86bba20f0731dfe61990525e0f7",
    },
    .{
        .path = "/lib/x86_64-linux-gnu/libm.so.6",
        .resolved = "/usr/lib/x86_64-linux-gnu/libm.so.6",
        .sha256 = "1c488db6f4fe8cecb72456bc018de000b7a9b539c2994864b0416b5e8371b3d8",
    },
    .{
        .path = "/etc/ld.so.cache",
        .resolved = "/etc/ld.so.cache",
        .sha256 = "fe063c1bee92cacf27776b62c04e35a2c71e7ed111ec3eaa542ba339410fcde3",
    },
};
pub const preload_path = "/etc/ld.so.preload";
