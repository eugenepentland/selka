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

CASES['list_filter'] = dict(
    group='collections', bench='list_filter', gen_exe='list_filter', sizes=(64, 4096), iters=(300000, 8000),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13),
            (33, 40, 5), (5000, 6, 999999)],
    versions=V('list_filter', [
        (1, "today: heap lists, header traffic, plain_ready call, checked fold"),
        (2, "+ immutable locals: headers in regs, sticky checks (L2)"),
        (3, "+ typed append (no plain_ready call)"),
        (4, "+ bounded result capacity (one alloc, no growth)"),
        (5, "+ allocation hoisted out of the batch loop"),
        (12, "+ sign fact only: unsigned mod, i64 storage"),
        (6, "+ range x<1009: u32 storage"),
        (7, "+ fuse generator into filter (no input list)"),
        (8, "+ fuse fold (no lists), branchy"),
        (9, "+ branchless select"),
        (10, "+ strength-reduced remainder (induction)"),
        (11, "hand AVX2 u16, fused, rank by in-register scan"),
    ]) + [('v30 holdout: file data, fused scalar, branchy, sticky checks', 'list_filter', 30, 'file'),
          ('v31 holdout: file data, guard + hoisted r_j + AVX2', 'list_filter', 31, 'file'),
          ('v20 holdout reference: today reading file', 'list_filter', 20, 'file'),
          ('v8 baseline x86-64', 'list_filter_base', 8),
          ('v9 baseline x86-64', 'list_filter_base', 9),
          ('v10 baseline x86-64', 'list_filter_base', 10)],
)

CASES['dict_lookup'] = dict(
    group='collections', bench='dict_lookup', gen_exe='dict_lookup', sizes=(64, 4096), iters=(40000, 1500),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13),
            (33, 40, 5), (5000, 6, 999999)],
    versions=V('dict_lookup', [
        (1, "today: generic read call, hint record, out-param"),
        (2, "+ immutable dict: no hint record, hoisted fields"),
        (3, "+ typed int/int, probe inlined"),
    ]) + [('v4: + inline {key,value} slots, load<=1/2, 1-mul hash', 'dict_lookup', 4),
          ('v10: v4 layout with mylang hash (fold_multiply)', 'dict_lookup', 10),
          ('v5: + query-key induction (no div, no flags)', 'dict_lookup', 5),
          ('v6: dense-key direct addressing (runtime flag)', 'dict_lookup', 6),
          ('v7: hand AVX2 gather over dense, i64 values', 'dict_lookup', 7),
          ('v7n: hand AVX2 gather, u32 values', 'dict_lookup', 9),
          ('v8: hand AVX2 4-slot buckets (general keys)', 'dict_lookup', 8),
          ('v20 holdout ref: today, identity keys from file', 'dict_lookup', 20, 'file'),
          ('v21 holdout: + immutable dict, identity keys from file', 'dict_lookup', 21, 'file'),
          ('v30 holdout: best scalar table, keys from file', 'dict_lookup', 30, 'file'),
          ('v31 holdout: AVX2 buckets, keys from file', 'dict_lookup', 31, 'file'),
          ('v5 baseline x86-64', 'dict_lookup_base', 5)],
)

# Same kernel, but the dictionary keys are 40-bit pseudo-random ids from a file. There is no
# benchmark checksum for these, so there are no B0 arms; v20 (today's model) is the reference.
CASES['dict_lookup_sparse'] = dict(
    group='collections', bench='dict_lookup', gen_exe='dict_lookup', gen_mode='gensparse', b0=[],
    sizes=(64, 4096), iters=(40000, 1500), unit_div='size',
    verify=[(3, 7, 42), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13)],
    versions=[('v20 today model, sparse keys from file', 'dict_lookup', 20, 'file'),
              ('v21 + immutable dict (no hint), sparse', 'dict_lookup', 21, 'file'),
              ('v22 + typed, probe inlined, sparse', 'dict_lookup', 22, 'file'),
              ('v30 inline slots + Fibonacci hash, sparse', 'dict_lookup', 30, 'file'),
              ('v31 AVX2 4-slot buckets, sparse', 'dict_lookup', 31, 'file')],
)

CASES['tagged_stack'] = dict(
    group='legacy', bench='tagged_stack', gen_exe='tagged_stack', sizes=(64, 4096), iters=(4000000, 4000000),
    unit_div=1,
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 1000, 42), (4096, 20000, 42), (4100, 5001, 7),
            (1000, 3333, 13), (33, 4000, 5), (5000, 60000, 999999), (2, 3000000, 1000000)],
    versions=V('tagged_stack', [
        (1, "today: heap list, RC checks, ready calls, floor mods, idiv cursor"),
        (2, "+ value semantics: local list, header in regs"),
        (8, "+ tagged values built in place (no store-forward stall)"),
        (3, "+ stack scalar-replaced (balanced push/pop)"),
        (4, "+ range facts: unsigned, no overflow checks"),
        (5, "+ % M as cond-subtract, cursor compare-reset"),
        (6, "+ residue tracking (r = base mod 97)"),
        (7, "+ table lookup for r % k"),
    ]) + [('v30 holdout: opcodes from file, no range facts', 'tagged_stack', 30, 'file'),
          ('v31 holdout: file + runtime guard + v7', 'tagged_stack', 31, 'file'),
          ('v20 holdout reference: today, file', 'tagged_stack', 20, 'file'),
          ('v5 baseline x86-64', 'tagged_stack_base', 5),
          ('v7 baseline x86-64', 'tagged_stack_base', 7)],
)

CASES['string_split'] = dict(
    group='text', bench='string_split', gen_exe='string_split', sizes=(64, 4096), iters=(20000, 600),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13),
            (33, 40, 5), (5000, 6, 999999), (130, 9, 3)],
    versions=V('string_split', [
        (1, "today: owned pieces, encode copies, RC drain"),
        (2, "+ no RC/malloc: region allocation (L3)"),
        (3, "+ borrowed encode (no copy)"),
        (4, "+ pieces as views (no copy, no per-piece alloc)"),
        (5, "+ fuse split into score (no parts list)"),
        (9, "+ byte-level fusion, per-part sums kept"),
        (6, "+ split-fold identity (no per-part work), scalar"),
        (7, "hand AVX2 scan (psadbw + cmpeq/popcnt)"),
        (8, "WORK ELIM: memoize the two documents"),
    ]) + [('v30 holdout: documents from file, v5', 'string_split', 30, 'file'),
          ('v31 holdout: documents from file, hand AVX2', 'string_split', 31, 'file'),
          ('v20 holdout reference: today, file', 'string_split', 20, 'file'),
          ('v5 baseline x86-64', 'string_split_base', 5),
          ('v9 baseline x86-64', 'string_split_base', 9),
          ('v6 baseline x86-64', 'string_split_base', 6)],
)

CASES['branch_mixed'] = dict(
    group='compute', bench='branch_mixed', gen_exe='branch_mixed', sizes=(64, 4096), iters=(300000, 8000),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (64, 100, 42), (4096, 20, 42), (4100, 5, 7), (1000, 3, 13),
            (33, 40, 5), (5000, 6, 999999)],
    versions=V('branch_mixed', [
        (1, "today: bounds checks, branch on flags, checked arms"),
        (2, "+ immutable lists, hoisted bounds, sticky checks (L2)"),
        (3, "+ range facts: no arm checks (branch written as if)"),
        (4, "+ if-conversion written as select"),
        (5, "+ narrow arithmetic (i32), plain C"),
        (6, "+ u16 storage, plain C"),
        (8, "+ chunked u32 accumulation, plain C"),
        (7, "hand AVX2 u16 blend"),
    ]) + [('v2 holdout: file data, L2 form, branchy (no range facts)', 'branch_mixed', 2, 'file'),
          ('v30 holdout: file data, no range facts, branch-free sticky', 'branch_mixed', 30, 'file'),
          ('v31 holdout: file data, runtime guard + AVX2 i32', 'branch_mixed', 31, 'file'),
          ('v20 holdout reference: today, file', 'branch_mixed', 20, 'file'),
          ('v4 baseline x86-64', 'branch_mixed_base', 4),
          ('v6 baseline x86-64', 'branch_mixed_base', 6),
          ('v8 baseline x86-64', 'branch_mixed_base', 8)],
)

# json_transform: the ladder varies only the PARSE component (json.loads plus releasing its tree); the
# transform/serialize/score back end is shared. ns/iter of the ladder rows is the parse component only;
# rows labelled "(whole job)" use version+1000 and time the complete job and compare with the B0 arms.
CASES['json_parse'] = dict(
    group='text', bench='json_transform', gen_exe='json_parse', sizes=(16, 256), iters=(4000, 400),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (16, 50, 42), (256, 20, 42), (260, 5, 7), (100, 3, 13)],
    versions=V('json_parse', [
        (1, "today model: memory scanner, Results in memory, RC tree, per-string buffers"),
        (2, "+ register scanner, unboxed Results (same tree, same allocations)"),
        (3, "+ bump region, no RC/drain"),
        (4, "+ borrowed document, string views, in-place literals"),
        (5, "+ single-pass integers"),
        (6, "+ flat objects (no hash dictionaries)"),
        (7, "+ schema-directed: rows straight from the bytes"),
        (8, "+ demand-driven string decoding"),
        (9, "+ AVX2 string scan, SWAR integers"),
    ]) + [('v1 (whole job)', 'json_parse', 1001),
          ('v7 (whole job)', 'json_parse', 1007),
          ('v9 (whole job)', 'json_parse', 1009),
          ('v30 holdout: pretty/reordered/escaped doc, typed parser', 'json_parse', 30, 'file'),
          ('v31 holdout: pretty/reordered/escaped doc, AVX2 parser', 'json_parse', 31, 'file'),
          ('v20 holdout reference: today model on that doc', 'json_parse', 20, 'file'),
          ('v8 baseline x86-64', 'json_parse_base', 8)],
)

CASES['lox_eval'] = dict(
    group='collections', bench='lox_eval', gen_exe='lox_eval', sizes=(16, 256), iters=(100000, 3000),
    unit_div='size',
    verify=[(2, 1, 1), (3, 7, 42), (17, 31, 999983), (16, 100, 42), (256, 20, 42), (260, 5, 7), (100, 3, 13), (2, 9, 1000000)],
    versions=V('lox_eval', [
        (1, "today: RC lists, ready calls, vector-copy stalls, if/elif chain"),
        (2, "+ value semantics: local lists, headers in regs (stalls remain)"),
        (3, "+ tagged values in place (no store-forward stall)"),
        (4, "+ list storage hoisted out of the batch loop"),
        (5, "+ threaded dispatch (computed goto), pointer pc"),
        (6, "+ stack top cached in registers"),
        (8, "BOUND: assumes a load-time verifier (no tags/checks)"),
        (9, "BOUND + 32-bit division bypass for %"),
        (7, "WORK ELIM: partial evaluation of the fixed program"),
    ]) + [('v30 holdout: program from file, threaded', 'lox_eval', 30, 'file'),
          ('v31 holdout: program from file, + stack cache', 'lox_eval', 31, 'file'),
          ('v20 holdout reference: today, program from file', 'lox_eval', 20, 'file'),
          ('v3 baseline x86-64', 'lox_eval_base', 3),
          ('v6 baseline x86-64', 'lox_eval_base', 6)],
)
