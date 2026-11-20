#!/usr/bin/env python3
"""Tests of `scripts/where.py --body` and `--around` (the finder is `scripts/where_body.py`) on a scratch repository.

The fixture is a git repository in a temporary folder with copies of the two scripts under `scripts/` (so that `ROOT` is the
fixture) and small Zig, C, Selka, Python and shell files, some of them untracked. Each test names the rule it pins.

    python3 scripts/where_test.py        # about 10 seconds; not run by the gate (like `where.py --selftest`)
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
import where_body as wb  # noqa: E402

ZIG = '''//! Fixture module.
const std = @import("std");

/// Adds one. The doc comment is part of the declaration.
pub fn plusOne(x: u32) u32 {
    const brace = "{ not a block";
    const close = '}';
    _ = brace;
    _ = close;
    return x + 1; // } in a comment
}

fn oneLiner() void {}

pub const fxAnswer = 42;

const raw_text =
    \\\\fn fakeInString() void {
    \\\\    {
;

pub fn longSignature(
    a: u32,
    b: u32,
) !u32 {
    return a + b;
}

pub const Thing = struct {
    value: u32,

    /// A method of Thing.
    pub fn method(self: Thing) u32 {
        return self.value;
    }

    fn helper() void {
        const fxLocal = 1;
        _ = fxLocal;
    }
};

test "does a thing" {
    try std.testing.expect(true);
}

test helperTest {
    try std.testing.expect(true);
}

var fxCounter: u32 = 0;
'''

C = '''#include <stdio.h>
#define SQUARE(x) \\
    ((x) * (x))
#define FX_LIMIT 10

typedef struct {
    int a;
    char *b;
} cfg_t;

struct node {
    int v;
};

static const int table[] = {
    1, 2, 3,
};

int proto(int x);

/* Doubles x. The comment is part of
   the declaration. */
int double_it(int x) {
    const char *s = "}";
    /* } */
    return x * 2;
}

static int
two_line(int x)
{
    return x;
}
'''

SELKA = '''import strings

# Adds one.
public func plus_one(x: int) -> int:
    const fxSum = x + 1
    return fxSum


# A point.
public record Point:
    x: int
    y: int


public enum Shape:
    Dot
    Line(length: int)

public const ITEMS = [
    "a",
    "b",
]

type Alias = int

func wide(
    a: int,
    b: int,
) -> int:
    return a + b
# A comment that belongs to the next declaration.
func after() -> int:
    return 1
public builtin func fx_builtin() -> int
extern func fx_extern() -> int
'''

PY = '''"""Module doc with a fake def below.

def fake():
    pass
"""
FX_PY_LIMIT = 5


@decorator
def decorated(a, b):
    """Doc."""
    return a + b


class Box:
    def open(self):
        return 1

    def shut(self):
        return 2
'''

SH = '''#!/bin/sh
FX_NAME=value
die() { echo "failed" >&2; exit 2; }

# Runs it.
run_it() {
    echo "{"
    if true; then
        echo hi
    fi
}
'''

FILES = {
    'src/zigmod.zig': ZIG,
    'src/core/runtime/rt.c': C,
    'src/stdlib/lib.selka': SELKA,
    'scripts/tool.py': PY,
    'scripts/run.sh': SH,
    'tests/lang/t.selka': 'public func test_x() -> bool:\n    return True\n',
    'src/dup_a.zig': 'pub fn shared() void {}\n',
    'src/dup_b.zig': 'pub fn shared() u32 {\n    return 1;\n}\n',
    'src/twice.zig': 'const A = struct {\n    fn again() void {}\n};\nconst B = struct {\n    fn again() u8 {\n'
                     '        return 1;\n    }\n};\n',
    'src/long.zig': 'pub fn long() void {\n' + ''.join(f'    _ = {n};\n' for n in range(1, 99)) + '}\n',
    'src/diagnostic_codes.zig': 'const errors = [_]Row{\n    .{ .name = "WIDGET_BROKEN", .meaning = "a widget is broken", '
                                '.guide = topic.widgets },\n};\n',
    'src/raiser.zig': 'fn raise(self: *Thing) !void {\n    return fail("E_WIDGET_BROKEN", "message");\n}\n\n'
                      'fn explain() []const u8 {\n    return "the widget is broken today";\n}\n',
}
UNTRACKED = ('src/long.zig', 'src/raiser.zig', 'scripts/run.sh')


def many(count):
    """`count` Zig functions of 100 lines each, named many0, many1, ..."""
    return ''.join(f'fn many{k}() void {{\n' + ''.join(f'    _ = {n};\n' for n in range(98)) + '}\n\n' for k in range(count))


class Fixture(unittest.TestCase):
    """One scratch repository for the whole class; `where` runs the copied script from another folder."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix='where-test-'))
        cls.repo = cls.tmp / 'repo'
        (cls.repo / 'scripts').mkdir(parents=True)
        for name in ('where.py', 'where_body.py'):
            shutil.copy(SCRIPTS / name, cls.repo / 'scripts' / name)
        files = dict(FILES, **{'src/many.zig': many(6)})
        for name, text in files.items():
            (cls.repo / name).parent.mkdir(parents=True, exist_ok=True)
            (cls.repo / name).write_text(text)
        env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')
        subprocess.run(['git', 'init', '-q'], cwd=cls.repo, check=True, env=env)
        tracked = [n for n in files if n not in UNTRACKED]
        subprocess.run(['git', 'add'] + tracked + ['scripts/where.py', 'scripts/where_body.py'], cwd=cls.repo, check=True, env=env)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def where(self, *args):
        """The output lines of `where.py ARGS` run from outside the repository."""
        out = subprocess.run([sys.executable, str(self.repo / 'scripts' / 'where.py'), *args], cwd=self.tmp,
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        return out.stdout.rstrip('\n').split('\n')

    def lines_of(self, path):
        return (self.repo / path).read_text().split('\n')


class Zig(Fixture):
    def test_a_function_runs_from_its_doc_comment_to_its_closing_brace(self):
        out = self.where('plusOne', '--body')
        self.assertEqual(out[0], 'src/zigmod.zig:4-11: fn plusOne')
        self.assertEqual(out[1], ' 4: /// Adds one. The doc comment is part of the declaration.')
        self.assertEqual(out[-1], '11: }')
        self.assertEqual(len(out), 1 + 8)

    def test_braces_in_strings_chars_and_comments_do_not_end_a_function_early(self):
        self.assertIn('11: }', self.where('plusOne', '--body'))
        self.assertEqual(len(self.where('plusOne', '--body')), 9)

    def test_a_multi_line_signature_is_one_declaration(self):
        out = self.where('longSignature', '--body')
        self.assertEqual(out[0], 'src/zigmod.zig:22-27: fn longSignature')
        self.assertEqual(out[-1], '27: }')

    def test_one_line_declarations_print_one_line(self):
        self.assertEqual(self.where('oneLiner', '--body'), ['src/zigmod.zig:13: fn oneLiner', '13: fn oneLiner() void {}'])
        self.assertEqual(self.where('fxAnswer', '--body')[0], 'src/zigmod.zig:15: const fxAnswer')

    def test_a_multi_line_string_constant_ends_at_its_semicolon_and_hides_the_code_inside_it(self):
        out = self.where('raw_text', '--body')
        self.assertEqual(out[0], 'src/zigmod.zig:17-20: const raw_text')
        self.assertEqual(self.where('fakeInString', '--body'),
                         ['fakeInString: no declaration found in src, test, scripts, tests/lang (`where.py fakeInString` shows its uses)'])

    def test_a_struct_is_a_type_and_its_method_is_found_by_the_qualified_name(self):
        out = self.where('Thing', '--body')
        self.assertEqual(out[0], 'src/zigmod.zig:29-41: struct Thing')
        method = self.where('Thing.method', '--body')
        self.assertEqual(method[0], 'src/zigmod.zig:32-35: fn method')
        self.assertEqual(method[1], '32:     /// A method of Thing.')

    def test_a_test_block_is_found_by_its_identifier_and_by_a_piece_of_its_name(self):
        self.assertEqual(self.where('helperTest', '--body')[0], 'src/zigmod.zig:47-49: test helperTest')
        by_text = self.where('does a thing', '--body')
        self.assertEqual(by_text[0], 'src/zigmod.zig:43-45: test does a thing')

    def test_a_local_const_is_offered_only_when_nothing_else_has_the_name(self):
        self.assertEqual(self.where('fxLocal', '--body')[0], 'src/zigmod.zig:38: const fxLocal')
        self.assertEqual(self.where('fxCounter', '--body')[0], 'src/zigmod.zig:51: var fxCounter')
        self.assertEqual(self.where('src/zigmod.zig:Thing.helper', '--body')[0], 'src/zigmod.zig:37-40: fn helper')


class Others(Fixture):
    def test_c_function_macro_typedef_tag_and_global_with_the_comment_above_and_the_type_line(self):
        self.assertEqual(self.where('double_it', '--body')[0], 'src/core/runtime/rt.c:21-27: fn double_it')
        self.assertEqual(self.where('double_it', '--body')[1], '21: /* Doubles x. The comment is part of')
        self.assertEqual(self.where('two_line', '--body')[0], 'src/core/runtime/rt.c:29-33: fn two_line')
        self.assertEqual(self.where('SQUARE', '--body')[0], 'src/core/runtime/rt.c:2-3: macro SQUARE')
        self.assertEqual(self.where('FX_LIMIT', '--body')[0], 'src/core/runtime/rt.c:4: macro FX_LIMIT')
        self.assertEqual(self.where('cfg_t', '--body')[0], 'src/core/runtime/rt.c:6-9: typedef cfg_t')
        self.assertEqual(self.where('node', '--body')[0], 'src/core/runtime/rt.c:11-13: struct node')
        self.assertEqual(self.where('table', '--body')[0], 'src/core/runtime/rt.c:15-17: var table')

    def test_a_c_prototype_is_not_a_declaration(self):
        self.assertIn('no declaration found', self.where('proto', '--body')[0])

    def test_selka_func_record_enum_const_type_and_a_multi_line_signature(self):
        self.assertEqual(self.where('plus_one', '--body')[0], 'src/stdlib/lib.selka:3-6: func plus_one')
        self.assertEqual(self.where('Point', '--body')[0], 'src/stdlib/lib.selka:9-12: record Point')
        self.assertEqual(self.where('Shape', '--body')[0], 'src/stdlib/lib.selka:15-17: enum Shape')
        self.assertEqual(self.where('ITEMS', '--body')[0], 'src/stdlib/lib.selka:19-22: const ITEMS')
        self.assertEqual(self.where('Alias', '--body')[0], 'src/stdlib/lib.selka:24: type Alias')
        self.assertEqual(self.where('wide', '--body')[0], 'src/stdlib/lib.selka:26-30: func wide')

    def test_a_selka_declaration_stops_before_the_comment_of_the_next_one(self):
        out = self.where('wide', '--body')
        self.assertEqual(out[-1], '30:     return a + b')
        self.assertEqual(self.where('after', '--body')[0], 'src/stdlib/lib.selka:31-33: func after')

    def test_selka_builtin_and_extern_functions_have_no_body_and_are_found(self):
        self.assertEqual(self.where('fx_builtin', '--body')[0], 'src/stdlib/lib.selka:34: func fx_builtin')
        self.assertEqual(self.where('fx_extern', '--body')[0], 'src/stdlib/lib.selka:35: func fx_extern')

    def test_selka_guest_tests_are_searched(self):
        self.assertEqual(self.where('test_x', '--body')[0], 'tests/lang/t.selka:1-2: func test_x')

    def test_python_decorator_class_method_and_a_def_inside_a_docstring(self):
        self.assertEqual(self.where('decorated', '--body')[0], 'scripts/tool.py:9-12: def decorated')
        self.assertEqual(self.where('decorated', '--body')[1], ' 9: @decorator')
        self.assertEqual(self.where('Box.shut', '--body')[0], 'scripts/tool.py:19-20: def shut')
        self.assertEqual(self.where('Box', '--body')[0], 'scripts/tool.py:15-20: class Box')
        self.assertEqual(self.where('FX_PY_LIMIT', '--body')[0], 'scripts/tool.py:6: const FX_PY_LIMIT')
        self.assertIn('no declaration found', self.where('fake', '--body')[0])

    def test_shell_functions_and_assignments_in_an_untracked_file(self):
        self.assertEqual(self.where('die', '--body')[0], 'scripts/run.sh:3: fn die')
        self.assertEqual(self.where('run_it', '--body')[0], 'scripts/run.sh:5-11: fn run_it')
        self.assertEqual(self.where('FX_NAME', '--body')[0], 'scripts/run.sh:2: const FX_NAME')


class Answers(Fixture):
    def test_a_name_declared_twice_lists_each_first_line_and_how_to_choose(self):
        out = self.where('shared', '--body')
        self.assertEqual(out[0], 'shared: 2 declarations; name the file to choose one')
        self.assertEqual(out[1:3], ['  src/dup_a.zig:1: pub fn shared() void {}', '  src/dup_b.zig:1: pub fn shared() u32 {'])
        self.assertEqual(out[3], '  choose: where.py src/dup_a.zig:shared --body  (PATH:NAME)')
        self.assertEqual(len(out), 4)

    def test_a_path_and_a_name_choose_one_and_a_path_suffix_will_do(self):
        self.assertEqual(self.where('src/dup_b.zig:shared', '--body')[0], 'src/dup_b.zig:1-3: fn shared')
        self.assertEqual(self.where('dup_a.zig:shared', '--body')[0], 'src/dup_a.zig:1: fn shared')
        self.assertEqual(self.where('dup_a.zig:nothing', '--body'),
                         ['dup_a.zig:nothing: no declaration found in src/dup_a.zig (`where.py nothing` shows its uses)'])

    def test_two_declarations_in_one_file_are_chosen_by_line(self):
        out = self.where('again', '--body')
        self.assertEqual(out[-1], '  choose: where.py src/twice.zig:2 --body  (PATH:LINE when one file declares it twice)')
        self.assertEqual(self.where('src/twice.zig:5', '--body')[0], 'src/twice.zig:5-7: fn again')
        self.assertEqual(self.where('src/twice.zig:2', '--body')[0], 'src/twice.zig:2: fn again')

    def test_several_names_are_answered_in_order_with_a_blank_line_between(self):
        out = self.where('oneLiner', 'nothingByThisName', 'Point', '--body')
        self.assertEqual([i for i, s in enumerate(out) if s == ''], [2, 4])
        self.assertEqual(out[0], 'src/zigmod.zig:13: fn oneLiner')
        self.assertTrue(out[3].startswith('nothingByThisName: no declaration found'))
        self.assertEqual(out[5], 'src/stdlib/lib.selka:9-12: record Point')

    def test_a_body_over_60_lines_is_cut_with_the_range_that_is_left(self):
        out = self.where('long', '--body')
        self.assertEqual(out[0], 'src/long.zig:1-100: fn long')
        self.assertEqual(out[60], '60:     _ = 59;')
        self.assertEqual(out[61], '  ... not shown: src/long.zig:61-100 (40 lines; Read it with offset and limit)')
        self.assertEqual(len(out), 62)

    def test_a_call_never_prints_more_than_150_lines_and_every_name_gets_its_share(self):
        names = [f'many{k}' for k in range(6)]
        out = self.where(*names, '--body')
        self.assertLessEqual(len(out), 150)
        for name in names:
            self.assertTrue(any(s.endswith(f': fn {name}') for s in out), name)
        self.assertEqual(sum(1 for s in out if 'not shown' in s), 6)

    def test_a_code_prints_its_table_row_and_the_function_that_raises_it(self):
        out = self.where('E_WIDGET_BROKEN', '--body')
        self.assertEqual(out[0], 'E_WIDGET_BROKEN: its table row, then 1 raising function')
        self.assertEqual(out[1], 'src/diagnostic_codes.zig:2: row E_WIDGET_BROKEN')
        self.assertEqual(out[3], 'src/raiser.zig:1-3: fn raise')

    def test_a_piece_of_a_message_prints_the_function_that_builds_it(self):
        out = self.where('the widget is broken today', '--body')
        self.assertEqual(out[0], 'src/raiser.zig:5-7: fn explain')

    def test_without_body_a_single_query_is_answered_as_before(self):
        out = self.where('plusOne')
        self.assertEqual(out[0], 'plusOne: a function; 1 definition, 0 callers')
        self.assertTrue(out[1].startswith('  def src/zigmod.zig:5: /// Adds one.'))
        self.assertEqual(self.where('E_WIDGET_BROKEN')[0][:44], 'E_WIDGET_BROKEN: a code; 1 raising line in 1')
        self.assertEqual(self.where('"the widget is broken today"')[0][:40], '"the widget is broken today": message te')

    def test_without_body_several_queries_are_answered_one_after_the_other(self):
        out = self.where('plusOne', 'oneLiner')
        self.assertEqual([s for s in out if s.endswith('a function; 1 definition, 0 callers')],
                         ['plusOne: a function; 1 definition, 0 callers', 'oneLiner: a function; 1 definition, 0 callers'])

    def test_a_missing_name_says_so_in_one_line(self):
        out = self.where('noSuchThing', '--body')
        self.assertEqual(len(out), 1)
        self.assertIn('noSuchThing: no declaration found', out[0])


class Around(Fixture):
    def test_the_declaration_that_holds_the_line_with_that_line_marked(self):
        out = self.where('--around', 'src/zigmod.zig:8')
        self.assertEqual(out[0], 'src/zigmod.zig:4-11: fn plusOne')
        self.assertEqual([s for s in out if '>' in s[:4]], [' 8>     _ = brace;'])

    def test_a_line_of_a_compiler_error_with_a_column_is_accepted(self):
        out = self.where('--around', 'src/zigmod.zig:34:9')
        self.assertEqual(out[0], 'src/zigmod.zig:32-35: fn method')
        self.assertIn('34>         return self.value;', out)

    def test_a_long_declaration_shows_a_window_of_60_lines_around_the_line(self):
        out = self.where('--around', 'src/long.zig:50')
        self.assertEqual(out[0], 'src/long.zig:1-100: fn long (100 lines; showing 20-79 around line 50)')
        self.assertEqual(len(out), 61)
        self.assertIn('50>     _ = 49;', out)

    def test_n_lines_around_the_line_when_a_count_is_given(self):
        out = self.where('--around', 'src/zigmod.zig:10', '6')
        self.assertEqual(out[0], 'src/zigmod.zig:7-12: 6 lines around line 10; in fn plusOne 4-11')
        self.assertEqual(len(out), 7)

    def test_a_line_outside_any_declaration_shows_21_lines(self):
        out = self.where('--around', 'src/zigmod.zig:3')
        self.assertEqual(out[0], 'src/zigmod.zig:1-21: 21 lines around line 3')
        self.assertEqual(len(out), 22)

    def test_a_line_past_the_end_and_a_missing_file_and_a_bad_spec_say_so(self):
        self.assertEqual(self.where('--around', 'src/zigmod.zig:999'), ['src/zigmod.zig:999: the file has 51 lines'])
        self.assertEqual(self.where('--around', 'src/nope.zig:3'), ['src/nope.zig: no such file'])
        self.assertIn('takes PATH:LINE', self.where('--around', 'src/zigmod.zig')[0])

    def test_path_and_line_with_body_is_the_same_lookup(self):
        self.assertEqual(self.where('src/zigmod.zig:8', '--body'), self.where('--around', 'src/zigmod.zig:8'))

    def test_a_selka_line_finds_its_function_not_its_local_constant(self):
        out = self.where('--around', 'src/stdlib/lib.selka:5')
        self.assertEqual(out[0], 'src/stdlib/lib.selka:3-6: func plus_one')

    def test_several_places_in_one_call(self):
        out = self.where('--around', 'src/zigmod.zig:8', '--around', 'src/stdlib/lib.selka:5')
        self.assertEqual([s for s in out if s.endswith(('fn plusOne', 'func plus_one'))],
                         ['src/zigmod.zig:4-11: fn plusOne', 'src/stdlib/lib.selka:3-6: func plus_one'])


class Units(unittest.TestCase):
    """The finder without the command line."""

    def test_masking_keeps_the_length_and_blanks_strings_comments_and_multi_line_strings(self):
        raw = ['const a = "x{y"; // {', '    \\\\{ line', "const c = '}';", 'int d; /* a', ' } b */ int e;', 's = """', '}', '"""']
        for lang, rows in (('zig', raw[:3]), ('c', raw[3:5]), ('py', raw[5:])):
            masked = wb.mask(rows, lang)
            self.assertEqual([len(s) for s in masked], [len(s) for s in rows])
            self.assertNotIn('}', ''.join(masked), lang)
        self.assertEqual(wb.mask(['a="b#c" # d', 'echo $#'], 'sh'), ['a="   "    ', 'echo $#'])

    def test_a_declaration_scan_finds_the_names_a_line_starts_with(self):
        raw = ['pub fn a() void {', '}', 'const T = struct {', '};', 'test "x y" {', '}']
        found = wb.scan_zig(raw, wb.mask(raw, 'zig'))
        self.assertEqual([(r.name, r.kind) for r in found], [('a', 'fn'), ('T', 'struct'), ('x y', 'test')])

    def test_five_names_of_the_real_repository_take_under_a_second(self):
        index = wb.Index(SCRIPTS.parent)
        start = time.time()
        for name in ('mask', 'brace_end', 'Index', 'answer_code', 'indent_end'):
            self.assertTrue(index.find(name), name)
        self.assertLess(time.time() - start, 1.0)


if __name__ == '__main__':
    unittest.main()
