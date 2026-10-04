"""Case definitions for ladder.py. versions: (label, executable in build/, version argument)."""
V = lambda exe, rows: [(f'v{n}: {text}', exe, n) for n, text in rows]

CASES = {}

CASES['float_math'] = dict(
    group='compute', bench='float_math', gen_exe='float_math', sizes=(64, 4096), iters=(400000, 6000), unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13)],
    versions=V('float_math', [
        (0, "today incl. in-loop kind dispatch"),
        (1, "dispatch unswitched: bounds check, runtime-call int(float), checked add"),
        (2, "+ inline checked int(float)"),
        (3, "+ immutable list, one bounds check, sticky checks (L2)"),
        (4, "+ element range: no checks (f64, i64)"),
        (13, "v4 + result range assume (types stay i64)"),
        (5, "+ i32 conversions (plain C)"),
        (6, "+ u16 storage (plain C)"),
        (7, "hand AVX2 f64, i64 storage"),
        (8, "hand AVX2 f64, u16 storage"),
        (9, "+ FMA contraction"),
        (10, "f32 lanes (precision narrowing)"),
        (11, "WORK ELIM: integer identity"),
        (12, "WORK ELIM: closed form"),
    ]) + [('v30 holdout: data from file, v3 (no range)', 'float_math', 30, 'file'),
          ('v31 holdout: data from file, runtime range guard + AVX2', 'float_math', 31, 'file'),
          ] + [('v3 baseline x86-64 (no AVX2)', 'float_math_base', 3), ('v4 baseline x86-64', 'float_math_base', 4),
          ('v5 baseline x86-64', 'float_math_base', 5), ('v6 baseline x86-64', 'float_math_base', 6)],
)
