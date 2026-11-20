//! Named-constraint review repros kept as executable regressions.
//! Sources come from docs/audits/named-constraints-review-2026-09-15-probes.json.
const std = @import("std");

/// One embedded source file of a review probe.
pub const File = struct { name: []const u8, body: []const u8 };
/// One checking probe and the outcome a fixed compiler must produce.
pub const Probe = struct {
    name: []const u8,
    command: []const u8,
    expect_success: bool,
    /// Diagnostic code substring required when the probe must reject.
    diagnostic: []const u8 = "",
    /// Retired-language oracle retained when removal diagnostics take precedence.
    historical_diagnostic: []const u8 = "",
    /// Additional exact semantic detail for current nominal callback rejection.
    diagnostic_detail: []const u8 = "",
    files: []const File,
};
/// The 18 historical review probes, seven acceptance cases, and four nominal capture counterparts.
pub const probes = original_probes ++ modern_acceptance_probes ++ modern_capture_probes;
const original_probes = [_]Probe{
    .{
        .name = "nominal_distinct_coalesce",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{
                .name = "a.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record ID:
                \\    value: int
                \\public constraint Has[T] = copy + field(value: ID)
                \\
            },
            .{
                .name = "b.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record ID:
                \\    value: int
                \\public constraint Has[T] = copy + field(value: ID)
                \\
            },
            .{ .name = "main.selka", .body =
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\func accept[T: a.Has + b.Has](row: T) -> int:
            \\    return 0
            \\func main() -> int:
            \\    return accept(Row(value=a.ID(value=7)))
            \\
            },
        },
    },
    .{
        .name = "nominal_distinct_reverse",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{
                .name = "a.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record ID:
                \\    value: int
                \\public constraint Has[T] = copy + field(value: ID)
                \\
            },
            .{
                .name = "b.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record ID:
                \\    value: int
                \\public constraint Has[T] = copy + field(value: ID)
                \\
            },
            .{ .name = "main.selka", .body =
            \\import a
            \\import b
            \\record Row:
            \\    value: a.ID
            \\func accept[T: b.Has + a.Has](row: T) -> int:
            \\    return 0
            \\func main() -> int:
            \\    return accept(Row(value=a.ID(value=7)))
            \\
            },
        },
    },
    .{
        .name = "capture_imported_nominal",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_GENERIC_TYPE",
        .files = &.{
            .{
                .name = "contracts.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record Token:
                \\    value: int
                \\public constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
                \\
            },
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\import contracts
                \\domain Provider: int:
                \\    func make() -> Provider:
                \\        return wrap[Provider](0)
                \\    func use(s: Provider, token: int) -> int effects():
                \\        return token
                \\func call[Token, P: contracts.Use](p: P, token: Token) -> int effects():
                \\    return P.use(p, token)
                \\func main() -> int:
                \\    return call(Provider.make(), 0)
                \\
            },
        },
    },
    .{
        .name = "capture_control_renamed",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_GENERIC_TYPE",
        .files = &.{
            .{
                .name = "contracts.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\public record Token:
                \\    value: int
                \\public constraint Use[S] = copy + op(use(s: S, token: Token) -> int effects())
                \\
            },
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\import contracts
                \\domain Provider: int:
                \\    func make() -> Provider:
                \\        return wrap[Provider](0)
                \\    func use(s: Provider, token: int) -> int effects():
                \\        return token
                \\func call[U, P: contracts.Use](p: P, token: U) -> int effects():
                \\    return P.use(p, token)
                \\func main() -> int:
                \\    return call(Provider.make(), 0)
                \\
            },
        },
    },
    .{
        .name = "inline_subject_overlap",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint Id[P] = copy + op(identity(x: P) -> P effects())
                \\func forward[T: Id + op(identity(x: T) -> T effects())](x: T) -> T effects():
                \\    return T.identity(x)
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "composite_subject_overlap",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint A[P] = copy + op(identity(x: P[]) -> int effects())
                \\constraint B[Q] = copy + op(identity(x: Q[]) -> int effects())
                \\func use[T: A + B](x: T) -> int:
                \\    return 0
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "implied_copy_single",
        .command = "check",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\func value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "implied_copy_module",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\func value[T: equality + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "named_copy_plus_field",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint C[T] = copy
                \\func value[T: C + field(value: int)](x: T) -> int:
                \\    return x.value
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "export_wrong_module_index",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "contracts.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\record One:
                \\    a: int
                \\record Two:
                \\    a: int
                \\record Three:
                \\    a: int
                \\public constraint C[T] = copy
                \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: contracts.C](x: T) -> T effects():
            \\    return x
            \\func main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "export_false_private",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_EFFECTS_REMOVED",
        .historical_diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "contracts.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\record One:
                \\    a: int
                \\public constraint C[T] = copy
                \\
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: contracts.C](x: T) -> T effects():
            \\    return x
            \\func main() -> int:
            \\    return 0
            \\
            },
        },
    },
    .{
        .name = "single_duplicate",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint C[T] = copy
                \\constraint C[T] = equality
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "single_name_collision",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\record C:
                \\    value: int
                \\constraint C[T] = copy
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "overlap_limit_single",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
                \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
                \\func f[T: A + B](x: T) -> int:
                \\    return 0
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "overlap_limit_module",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_DOMAIN_REMOVED",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint A[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
                \\constraint B[T] = copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)
                \\func f[T: A + B](x: T) -> int:
                \\    return 0
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "unused_result_field",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint Bad[T] = copy + field(value: Result[int, int])
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "used_result_field",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_GENERIC_REQUIREMENT",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint Bad[T] = copy + field(value: Result[int, int])
                \\func bad[T: Bad](x: T) -> int:
                \\    return 0
                \\func main() -> int:
                \\    return 0
                \\
            },
        },
    },
    .{
        .name = "single_duplicate_used",
        .command = "check",
        .expect_success = false,
        .diagnostic = "E_DUPLICATE_SYMBOL",
        .files = &.{
            .{
                .name = "main.selka",
                .body =
                // migrate-embedded: skip intentional scalar-domain retirement/repair fixture
                \\constraint C[T] = copy
                \\constraint C[T] = integer
                \\func identity[T: C](x: T) -> T:
                \\    return x
                \\func main() -> int:
                \\    assert identity(True)
                \\    return 0
                \\
            },
        },
    },
};

/// Modern acceptance counterparts retain the type/module regressions after named-constraint retirement.
const modern_acceptance_probes = [_]Probe{
    .{
        .name = "modern_inline_subject_overlap",
        .command = "check",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\func identity(x: int) -> int:
            \\    return x
            \\func forward[T: copy](x: T, callback: func(T) -> T) -> T:
            \\    return callback(x)
            \\func main() -> int:
            \\    assert forward(7, identity) == 7
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_composite_subject_overlap",
        .command = "check",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\func count(values: int[]) -> int:
            \\    return len(values)
            \\func use[T: copy](x: T, identity: func(T[]) -> int) -> int:
            \\    return identity([x])
            \\func main() -> int:
            \\    assert use(7, count) == 1
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_named_copy_plus_field",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\record Row:
            \\    value: int
            \\func value[T: copy + field(value: int)](x: T) -> int:
            \\    return x.value
            \\func main() -> int:
            \\    assert value(Row(value=7)) == 7
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_export_wrong_module_index",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\record One:
            \\    a: int
            \\record Two:
            \\    a: int
            \\record Three:
            \\    a: int
            \\public record C:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: copy](x: T, marker: contracts.C) -> T from x:
            \\    _ = marker
            \\    return x
            \\public func g[T: copy](x: T, marker: contracts.C) -> T from x:
            \\    return f(x, marker)
            \\func main() -> int:
            \\    assert f(7, contracts.C(value=1)) == 7
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_export_false_private",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\record One:
            \\    a: int
            \\public record C:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\public func f[T: copy](x: T, marker: contracts.C) -> T from x:
            \\    _ = marker
            \\    return x
            \\func main() -> int:
            \\    assert f(7, contracts.C(value=1)) == 7
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_overlap_limit_single",
        .command = "check",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\record Row:
            \\    f0: int
            \\    f1: int
            \\    f2: int
            \\    f3: int
            \\    f4: int
            \\    f5: int
            \\    f6: int
            \\    f7: int
            \\func f[T: copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)](x: T) -> int:
            \\    return x.f0 + x.f7
            \\func main() -> int:
            \\    assert f(Row(f0=0, f1=1, f2=2, f3=3, f4=4, f5=5, f6=6, f7=7)) == 7
            \\    return 0
            },
        },
    },
    .{
        .name = "modern_overlap_limit_module",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "main.selka", .body =
            \\record Row:
            \\    f0: int
            \\    f1: int
            \\    f2: int
            \\    f3: int
            \\    f4: int
            \\    f5: int
            \\    f6: int
            \\    f7: int
            \\func f[T: copy + field(f0: int) + field(f1: int) + field(f2: int) + field(f3: int) + field(f4: int) + field(f5: int) + field(f6: int) + field(f7: int)](x: T) -> int:
            \\    return x.f0 + x.f7
            \\func main() -> int:
            \\    assert f(Row(f0=0, f1=1, f2=2, f3=3, f4=4, f5=5, f6=6, f7=7)) == 7
            \\    return 0
            },
        },
    },
};

/// Imported nominal callback parameters remain independent of local generic binder names.
const modern_capture_probes = [_]Probe{
    .{
        .name = "modern_capture_Token_invalid",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_TYPE",
        .diagnostic_detail = "expected func(main.Provider, contracts.Token) -> int, found func(main.Provider, int) -> int",
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\record Provider:
            \\    value: int
            \\func use(s: Provider, token: int) -> int:
            \\    return token
            \\func call[Token, P: copy](p: P, token: Token, callback: func(P, contracts.Token) -> int) -> int:
            \\    _ = token
            \\    return callback(p, contracts.Token(value=7))
            \\func main() -> int:
            \\    return call(Provider(value=0), 0, use)
            },
        },
    },
    .{
        .name = "modern_capture_Token_valid",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\record Provider:
            \\    value: int
            \\func use(s: Provider, token: contracts.Token) -> int:
            \\    return token.value
            \\func call[Token, P: copy](p: P, token: Token, callback: func(P, contracts.Token) -> int) -> int:
            \\    _ = token
            \\    return callback(p, contracts.Token(value=7))
            \\func main() -> int:
            \\    return call(Provider(value=0), 0, use)
            },
        },
    },
    .{
        .name = "modern_capture_U_invalid",
        .command = "check-project",
        .expect_success = false,
        .diagnostic = "E_TYPE",
        .diagnostic_detail = "expected func(main.Provider, contracts.Token) -> int, found func(main.Provider, int) -> int",
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\record Provider:
            \\    value: int
            \\func use(s: Provider, token: int) -> int:
            \\    return token
            \\func call[U, P: copy](p: P, token: U, callback: func(P, contracts.Token) -> int) -> int:
            \\    _ = token
            \\    return callback(p, contracts.Token(value=7))
            \\func main() -> int:
            \\    return call(Provider(value=0), 0, use)
            },
        },
    },
    .{
        .name = "modern_capture_U_valid",
        .command = "check-project",
        .expect_success = true,
        .files = &.{
            .{ .name = "contracts.selka", .body =
            \\public record Token:
            \\    value: int
            },
            .{ .name = "main.selka", .body =
            \\import contracts
            \\record Provider:
            \\    value: int
            \\func use(s: Provider, token: contracts.Token) -> int:
            \\    return token.value
            \\func call[U, P: copy](p: P, token: U, callback: func(P, contracts.Token) -> int) -> int:
            \\    _ = token
            \\    return callback(p, contracts.Token(value=7))
            \\func main() -> int:
            \\    return call(Provider(value=0), 0, use)
            },
        },
    },
};
