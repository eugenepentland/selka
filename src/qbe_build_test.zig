//! Focused native build-driver and adapter tests, independent of interpreter suites.
test {
    _ = @import("qbe_build.zig");
    _ = @import("qbe_build_cache.zig");
    _ = @import("qbe_build_io.zig");
    _ = @import("qbe_build_options.zig");
    _ = @import("qbe_build_outputs.zig");
    _ = @import("qbe_build_host.zig");
    _ = @import("qbe_build_embed.zig");
    _ = @import("qbe_build_shapes.zig");
}
