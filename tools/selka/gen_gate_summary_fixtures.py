#!/usr/bin/env python3
"""Generate tools/selka/gate_summary_fixtures.selka from scripts/gate_summary.py.

The Selka port must print what the Python original prints. This script builds a corpus of gate logs (the original's own test
logs, hand-written edge cases for every matcher, and seeded random logs made of the lines each regular expression looks
for), runs the original on each, and writes the logs and the expected outputs as Selka string literals.

Usage: python3 tools/selka/gen_gate_summary_fixtures.py > tools/selka/gate_summary_fixtures.selka
       selka fmt tools/selka/gate_summary_fixtures.selka --write
"""
import importlib.util
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("GATE_SUMMARY_ROOT", os.path.join(HERE, "..", ".."))
spec = importlib.util.spec_from_file_location("gate_summary", os.path.join(ROOT, "scripts", "gate_summary.py"))
original = importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)


def literal(text):
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif code < 32 or code == 127:
            out.append("\\x%02x" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


GREEN_LOG = '''Build Summary: 3/3 steps succeeded
test
+- verification action core member 0 success 12s
   +- compile exe selka debug native (reused)
+- verification action cli member 0 success 3s
'''


def red_log(lines, action='cli'):
    return ('test\n'
            '+- verification action %s member 0 1 pass, 1 fail (2 total)\n' % action
            + '\n'.join(lines) + '\n'
            + 'failed command: python3 scripts/verification_native_telemetry.py --action-id %s '
              '--member 0 --root-id test/integration.zig -- ./test --listen=-\n' % action
            + '\n'
            'Build Summary: 2/4 steps succeeded (1 failed); 1/2 tests passed (1 failed)\n')


REAL_ZIG_FAILURE = """build-slot: build slot 1, FIFO ticket 10704 after 0s
test-memory-budget
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
test: FAIL — 1 failed of 8
test: RESULT {"passed":7,"failed":1,"skipped":0}
error: 'memory_budget.test.review probe: a failing assertion must show its message' failed:
       test: 8 test(s) selected
       expected 1, found 2
       /home/u/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/testing.zig:111:17: 0x12905e4 in expectEqualInner__anon_44754 (std.zig)
                       return error.TestExpectedEqual;
                       ^
       /home/u/zig-toolchains/0.17.0-dev.1683+5ceec001b/lib/std/testing.zig:75:5: 0x1290654 in expectEqual (memory_budget.zig)
           return expectEqualInner(T, expected, actual);
           ^
       /home/u/ai/canopy/mylang-review-gate-probe/src/memory_budget.zig:368:5: 0x129069b in test.review probe: a failing assertion must show its message (memory_budget.zig)
           try std.testing.expectEqual(@as(u32, 1), @as(u32, 2));
           ^
failed command: python3 scripts/verification_native_telemetry.py --action-id memory_budget --member 0 --root-id src/memory_budget.zig -- sh -c "..."

Build Summary: 16/18 steps succeeded (1 failed); 7/8 tests passed (1 failed)
test-memory-budget transitive failure
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
"""

REAL_SILENT_FAILURE = """test-memory-budget
+- verification action memory_budget member 0 7 pass, 1 fail (8 total)
error: 'memory_budget.test.review probe: a failing assertion must show its message' failed without output
failed command: python3 scripts/verification_native_telemetry.py --action-id memory_budget --member 0 --root-id src/memory_budget.zig -- sh -c "..."

Build Summary: 16/18 steps succeeded (1 failed); 7/8 tests passed (1 failed)
"""

CASES = []  # (name, text, log_directory or None)


def add(name, text, directory=None):
    CASES.append((name, text, directory))


add("green", GREEN_LOG)
add("green with a directory", GREEN_LOG, "/logs/gate")
add("seeded failure", red_log(['test_network_endpoint (test/integration.zig) ... FAIL', 'error: expected true',
                                'test deadline: test/integration.zig::NETWORK-ENDPOINT-1 ran 301.0 s (limit 300.0 s); killed',
                                'at test/integration.zig:6618']), "/logs/gate")
add("one failure", red_log(['error: first failure at src/root_test.zig:10']))
add("thirty failures", ''.join(red_log(['error: failure at src/root_test.zig:' + str(index)], action='cli%d' % index) for index in range(30)))
add("twelve failures", ''.join(red_log(['error: broke at src/root_test.zig:%d' % index], action='a%d' % index) for index in range(12)))
add("real zig failure", REAL_ZIG_FAILURE)
add("real silent failure", REAL_SILENT_FAILURE)
add("python driver failure", red_log(['FAIL: test_budget (verify_cache_test.Tests.test_budget)', 'Traceback (most recent call last):',
                                       '  File "/usr/lib/python3.12/unittest/case.py", line 58, in testPartExecutor',
                                       '  File "/home/u/ai/canopy/tree/scripts/verify_cache_test.py", line 812, in test_budget',
                                       'AssertionError: 3 != 4', 'error: process exited with code 1'], action='verification_cache'))
add("red without a block", 'Build Summary: 3/4 steps succeeded (1 failed)\n')
add("empty", '')
add("unknown verdict", 'nothing to see here\n')
add("verification verdicts", 'verification: PARTIAL; 3 reused\n')
add("verification pass word boundary", 'verification: PASSED\n')
add("directory with a trailing slash", GREEN_LOG, "logs//gate/")
add("directory with dots", GREEN_LOG, "./a/./b/../c/")
add("empty directory name", GREEN_LOG, ".")
add("zero summary", 'Build Summary: 03/3 steps succeeded\n')
add("ties in slowest", '''Build Summary: 5/5 steps succeeded
+- verification action a member 0 success 5s
+- verification action b member 0 success 5s
+- verification action c member 0 success 5s
+- verification action d member 0 success 5s
+- verification action a member 1 success 500ms
+- verification action e member 0 success 1.25s
+- verification action f member 0 success 0.05s
''')
add("milliseconds", 'Build Summary: 2/2 steps succeeded\n+- verification action x member 0 success 250ms\n+- verification action y member 3 success 1ms\n')
add("zig frames with echo", red_log(['error: boom', '/home/u/src/a.zig:10:5: 0x1f in f (a.zig)', '    var x = 1;', '    ^', 'error: after the frame',
                                      'src/b.zig:7:1: 0xabc in g (b.zig)', 'echo one', 'echo two', 'expected 5, found 6']))
add("test failed variants", red_log(["error: 'a.test.x' failed:", "error: 'b.test.y' timed out", "error: 'c.test.z' leaked", "error: 'd.test.w' logged an error",
                                      "error: 'a.test.x' failed again", "error: '' failed", "error: 'q failed", "error: 'e.test.v' hung"]))
add("many tests", red_log(["error: 'suite.test.%d' failed" % index for index in range(8)]))
add("deadline shapes", red_log(['test deadline: a ran 1.5 s (limit 2.0 s); killed', 'x test deadline: b::c ran 301 s (limit 300 s); killed extra',
                                 'test deadline:  ran 1 s (limit 1 s); killed', 'test deadline: a ran s (limit 1 s); killed',
                                 'test deadline: a ran 1 s (limit 1 s) killed']))
add("failure words", red_log(['AssertionError', 'ParseError: x', 'myError', 'Errors', 'error:x', 'xerror: y', 'panic: z', 'xpanic: z', 'FAILED', 'FAILEDX', 'XFAIL',
                               'FAIL', 'assertion', 'assertions', 'expected', 'unexpected', '_expected', 'expected_', 'é error: unicode', 'café FAIL']))
add("duplicate lines", red_log(['error: same', 'error: same', 'error: other', 'error: same', 'FAIL: again', 'FAIL: again']))
add("file line shapes", red_log(['error: see src/a.zig:12', 'error: see /abs/path/to/src/b.py:7:3', 'error: /file.zig:3', 'error: a.zig:1 and tests/c.selka:22',
                                  'error: x.txt:5', 'error: dir/sub/d.sh:9', 'error: e.zon:100', 'error: f.zig: 5', 'error: g.zig:', 'error: ./h.zig:8',
                                  'error: ../i.zig:9', 'error: a/b.c.zig:4', 'error: -x.selka:5']))
add("toolchain frames first", red_log(['error: /home/u/zig-toolchains/0.17/lib/std/testing.zig:111:17', 'at /usr/lib/python3.12/lib/std/x.py:3',
                                        'in /opt/lib/python3.11/site.py:9', 'repo /home/u/ai/selka/src/real.zig:42', 'FAIL']))
add("python frames", red_log(['Traceback', '  File "/usr/lib/python3.12/unittest/case.py", line 58, in x', '  File "/w/tests/t.py", line 9, in y',
                               '  File "relative/z.py", line 2, in z', 'File "", line 3', 'error: e']))
add("repository roots", red_log(['  File "/a/b/src/x.py", line 1', ], 'r1') + red_log(['  File "/a/test/y.py", line 2'], 'r2') + red_log(['  File "/a/tests/z.py", line 3'], 'r3')
    + red_log(['  File "/a/b/docs/w.py", line 4'], 'r4') + red_log(['  File "/a/b/other/v.py", line 5'], 'r5') + red_log(['  File "/src/u.py", line 6'], 'r6')
    + red_log(['  File "/a/experiments/src/q.py", line 7'], 'r7'))
add("action fallbacks", 'test\n+- verification action named_step member 0 1 fail\nerror: lost the command\nfailed command: zig build\nBuild Summary: 0/1 steps succeeded (1 failed)\n')
add("no action at all", 'error: nothing names an action\nfailed command: zig build test\nBuild Summary: 0/1 steps succeeded (1 failed)\n')
add("action id characters", 'x\nerror: bad\nfailed command: tool --action-id a.b-c_9 --member 0\n--action-id  skip --action-id real_one\nBuild Summary: 0/1 steps succeeded\n')
add("action id second occurrence", 'error: q\nfailed command: --action-id  --action-id second1 x\nBuild Summary: 0/1 steps succeeded\n')
add("blocks split by build summary", 'error: lost one\nBuild Summary: 1/2 steps succeeded\nerror: kept\nfailed command: t --action-id k\nBuild Summary: 1/3 steps succeeded\n')
add("long lines", red_log(['error: ' + 'x' * 600, 'error: ' + 'é' * 500, "error: 'n" + 'y' * 450 + "' failed"]))
add("long block", red_log(['noise %d' % i for i in range(450)] + ['error: tail']))
add("crlf", 'test\r\n+- verification action w member 0 1 fail\r\nerror: crlf\r\nfailed command: t --action-id w\r\nBuild Summary: 1/2 steps succeeded\r\n')
add("odd line breaks", 'error: a\x0bb\x0cc\x1cd\x1de\x1ef\u0085g h i\rj\nfailed command: t --action-id odd\nBuild Summary: 1/2 steps succeeded\n')
add("strip characters", red_log(['  \terror: padded  ', ' error: nbsp ', '　error: ideographic　', '\x1f\x1e error: separators \x1d']))
add("unicode text", red_log(['error: café — 日本語 at src/é.zig:5', 'FAIL ✓']))
add("verdict from verification line", 'verification: FAIL\nerror: x\nfailed command: t --action-id v\n')
add("pass with failures present", 'error: seen\nfailed command: t --action-id p\nBuild Summary: 2/2 steps succeeded\n')
add("pass in a later summary", 'Build Summary: 1/2 steps succeeded\nBuild Summary: 2/2 steps succeeded\n')


def random_log(rng, index):
    actions = ['core', 'cli', 'units', 'lang', 'doctest', 'fmt', 'guardian', 'x.y', 'a-b']
    pieces = []
    failing = rng.random() < 0.8
    for _ in range(rng.randrange(0, 4)):
        action = rng.choice(actions)
        for _ in range(rng.randrange(0, 12)):
            kind = rng.randrange(14)
            if kind == 0:
                pieces.append("error: 'suite.test.%d' %s" % (rng.randrange(20), rng.choice(['failed', 'timed out', 'leaked', 'logged', 'failed:', 'died'])))
            elif kind == 1:
                pieces.append(rng.choice(['  ', '', '       ']) + rng.choice(['expected 1, found 2', 'error: boom', 'panic: oops', 'FAIL: x', 'FAILED', 'AssertionError: 3 != 4', 'noise line', 'Error']))
            elif kind == 2:
                pieces.append(rng.choice(['/home/u/ai/w/src/a.zig', 'src/b.zig', '/x/zig-toolchains/0.17/lib/std/t.zig', 'tests/c.py', '/p/lib/python3.12/u.py',
                                           'scripts/d.sh', 'file.selka', 'x/y/z.zon', 'a.txt']) + ':%d' % rng.randrange(1, 900) + rng.choice(['', ':5', ':5: 0x12ab in f (a.zig)', ' note']))
            elif kind == 3:
                pieces.append('      ' + rng.choice(['return error.X;', '^', 'try foo();']))
            elif kind == 4:
                pieces.append('test deadline: %s::T-%d ran %.1f s (limit %.1f s); killed' % (rng.choice(['a.zig', 'b.zig']), rng.randrange(9), rng.random() * 400, 300.0))
            elif kind == 5:
                pieces.append('  File "%s", line %d, in f' % (rng.choice(['/usr/lib/python3.12/x.py', '/w/scripts/g.py', 'tests/h.py']), rng.randrange(1, 99)))
            elif kind == 6:
                pieces.append('+- verification action %s member %d success %s' % (rng.choice(actions), rng.randrange(3), rng.choice(['3s', '120ms', '0.5s', '12.25s', '7s'])))
            elif kind == 7:
                pieces.append('test: ' + rng.choice(['FAIL — 1 failed of 8', 'RESULT {"passed":7}', 'test wall 1.2s']))
            elif kind == 8:
                pieces.append(rng.choice(['', ' ', '\t']))
            elif kind == 9:
                pieces.append('error: ' + ''.join(rng.choice('abc xyz:/.0123') for _ in range(rng.randrange(1, 40))))
            elif kind == 10:
                pieces.append('+- verification action %s member 0 1 pass, 1 fail (2 total)' % action)
            elif kind == 11:
                pieces.append(''.join(rng.choice('abcdefg :/.-_0123456789é') for _ in range(rng.randrange(0, 50))))
            elif kind == 12:
                pieces.append('/home/u/zig/lib/x.zig:%d:%d: 0x%x in fn (x.zig)' % (rng.randrange(1, 99), rng.randrange(1, 99), rng.randrange(1 << 20)))
                pieces.append('   some source')
                pieces.append('   ^')
            else:
                pieces.append('error: expected %d, found %d' % (rng.randrange(9), rng.randrange(9)))
        if failing:
            pieces.append('failed command: python3 t.py%s --member 0 -- ./test' % rng.choice([' --action-id %s' % action, '', ' --action-id', ' --action-id %s extra' % rng.choice(actions)]))
        if rng.random() < 0.3:
            pieces.append('Build Summary: %d/%d steps succeeded (1 failed)' % (rng.randrange(1, 9), rng.randrange(1, 9)))
    if rng.random() < 0.6:
        pieces.append(rng.choice(['Build Summary: 5/5 steps succeeded', 'Build Summary: 4/5 steps succeeded (1 failed)', 'verification: PASS', 'verification: FAIL', 'verification: PARTIAL; x']))
    rng.shuffle(pieces) if rng.random() < 0.15 else None
    return '\n'.join(pieces) + ('\n' if rng.random() < 0.8 else '')


rng = random.Random(20261030)
for index in range(60):
    add("random %d" % index, random_log(rng, index), "/logs/r%d" % index if rng.random() < 0.3 else None)


def expected(text, directory):
    return "\n".join(original.summarize(log_directory=None if directory is None else _Dir(directory), text=text))


class _Dir(str):
    """A log directory as the original prints it: str(Path(...))."""
    def __new__(cls, name):
        from pathlib import Path
        return str.__new__(cls, str(Path(name)))


def cli_cases():
    """Command lines run against a small tree of files: (argv, {path: text})."""
    red = ''.join(red_log(['error: broke at src/root_test.zig:%d' % index], action='a%d' % index) for index in range(12))
    tree = {
        "logs/gate/stderr.log": REAL_ZIG_FAILURE,
        "logs/gate/stdout.log": "gate stdout line\n",
        "logs/inventory/stdout.log": "inventory: 48 actions\n",
        "logs/preparation/stderr.log": "prep\n",
        "logs/other.txt": "not a log\n",
        "logs/sub/deeper/z.log": "z log\n",
        "logs/a.log": "a log\n",
        "logs/Z.log": "capital\n",
    }
    cases = [
        (["gate.log"], {"gate.log": GREEN_LOG}),
        (["gate.log"], {"gate.log": red}),
        (["--max-lines", "3", "gate.log"], {"gate.log": red}),
        (["gate.log", "--max-lines=5"], {"gate.log": red}),
        (["--max-lines", "0", "gate.log"], {"gate.log": red}),
        (["--max-lines", "-2", "gate.log"], {"gate.log": red}),
        (["--max-lines", "100", "gate.log"], {"gate.log": GREEN_LOG}),
        (["gate.log"], {"gate.log": "crlf\r\nBuild Summary: 1/2 steps succeeded\r\n"}),
        (["gate.log"], {"gate.log": ""}),
        (["logs"], tree),
        (["--max-lines", "4", "logs"], tree),
        (["run/gate"], {"run/gate/stderr.log": REAL_SILENT_FAILURE, "run/gate/b.log": "b\n", "run/gate/a.log": "a\n"}),
        (["logs"], {"logs/x.txt": "nothing\n"}),
        (["logs/gate/stdout.log"], {"logs/gate/stdout.log": "no verdict here\n", "logs/gate/stderr.log": "Build Summary: 9/9 steps succeeded\n"}),
        (["logs/gate/stderr.log"], {"logs/gate/stdout.log": "no verdict here\n", "logs/gate/stderr.log": "Build Summary: 9/9 steps succeeded\n"}),
        (["logs/gate/stdout.log"], {"logs/gate/stdout.log": "gate stdout line\n", "logs/gate/stderr.log": REAL_ZIG_FAILURE}),
        (["--max-lines", "2", "logs/gate/stdout.log"], {"logs/gate/stdout.log": "gate stdout line\n", "logs/gate/stderr.log": REAL_ZIG_FAILURE}),
        (["stdout.log"], {"stdout.log": "no verdict here\n"}),
        (["stderr.log"], {"stderr.log": GREEN_LOG}),
        (["logs"], {"logs/gate/stdout.log": GREEN_LOG, "logs/gate/stderr.log": "Build Summary: 9/9 steps succeeded\n"}),
        ([], {}),
        (["-h"], {}),
        (["--help"], {}),
        (["absent.log"], {}),
        (["--max-lines", "x", "gate.log"], {"gate.log": GREEN_LOG}),
        (["--max-lines"], {}),
        (["--nope", "gate.log"], {"gate.log": GREEN_LOG}),
        (["gate.log", "other.log"], {"gate.log": GREEN_LOG}),
        (["--max-lines", "2", "--max-lines", "3", "gate.log"], {"gate.log": red}),
    ]
    return cases


def run_cli(argv, tree):
    import subprocess
    import tempfile
    with tempfile.TemporaryDirectory() as directory:
        for path, text in tree.items():
            full = os.path.join(directory, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
        done = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "gate_summary.py")] + argv, cwd=directory, capture_output=True, text=True)
        return done.stdout, done.stderr, done.returncode


def main():
    out = ["# Generated by gen_gate_summary_fixtures.py from scripts/gate_summary.py; do not edit by hand.\n"]
    out.append("# Gate logs: the original's own test logs, edge cases for each matcher and seeded random logs.\npublic func texts() -> str[]:\n    return [\n")
    for _, text, _ in CASES:
        out.append("        %s,\n" % literal(text))
    out.append("    ]\n\n")
    out.append("# The log directory each log is summarized with, or \"\" for none (as `gate_summary.py LOG-FILE` has none).\npublic func directories() -> str[]:\n    return [\n")
    for _, _, directory in CASES:
        out.append("        %s,\n" % literal("" if directory is None else directory))
    out.append("    ]\n\n")
    out.append("# What the original prints for each log (the summary lines joined by newlines).\npublic func expected() -> str[]:\n    return [\n")
    for _, text, directory in CASES:
        out.append("        %s,\n" % literal(expected(text, directory)))
    out.append("    ]\n\n")
    out.append("# The name of each log, for a failure message.\npublic func names() -> str[]:\n    return [\n")
    for name, _, _ in CASES:
        out.append("        %s,\n" % literal(name))
    out.append("    ]\n\n")
    # unit tables: location of line groups, repository_path, step_seconds, inferred_verdict
    paths = ["", "src/a.zig", "/home/u/ai/w/src/a.zig", "/x/test/y.zig", "/x/tests/y.zig", "/a/docs/z.md", "/a/other/q.zig", "/src/u.py", "/a/experiments/src/q.py",
             "/a/b/velocity/v.py", "relative/scripts/s.py", "/a/benchmarks/b.selka", "/a/bench/b.selka", "/a/examples/e.selka", "/a/selfhost/s.selka", "//src/x"]
    cases = cli_cases()
    out.append("# Command lines of the tool: each argument list.\npublic func cli_argvs() -> str[][]:\n    return [\n")
    for argv, _ in cases:
        out.append("        [%s],\n" % ", ".join(literal(word) for word in argv))
    out.append("    ]\n\n")
    out.append("# The files each command line runs against, flat: a path, then its text.\npublic func cli_trees() -> str[][]:\n    return [\n")
    for _, tree in cases:
        flat = []
        for path, text in tree.items():
            flat += [literal(path), literal(text)]
        out.append("        [%s],\n" % ", ".join(flat))
    out.append("    ]\n\n")
    results = [run_cli(argv, tree) for argv, tree in cases]
    out.append("# What the original printed on standard output, on standard error, and its exit status.\npublic func cli_stdout() -> str[]:\n    return [\n")
    for stdout, _, _ in results:
        out.append("        %s,\n" % literal(stdout))
    out.append("    ]\n\npublic func cli_stderr() -> str[]:\n    return [\n")
    for _, stderr, _ in results:
        out.append("        %s,\n" % literal(stderr))
    out.append("    ]\n\npublic func cli_status() -> int[]:\n    return [%s]\n\n" % ", ".join(str(code) for _, _, code in results))
    import binascii
    samples = [b"", b"plain", b"caf\xc3\xa9", b"\xff", b"\xc3", b"a\xc3", b"\xe2\x82", b"\xe2\x82\xac", b"\xe2\x82\xe2\x82\xac", b"\xed\xa0\x80", b"\xf0\x9f\x98", b"\xf0\x9f\x98\x80",
               b"\xf0\x9f\x98\x80\xf0\x9f\x98", b"\xc0\x80", b"\xc1\xbf", b"\xf5\x80\x80\x80", b"\xf4\x90\x80\x80", b"\xf4\x8f\xbf\xbf", b"\xe0\x9f\xbf", b"\xe0\xa0\x80",
               b"\x80\x80\x80", b"ok \xe2\x80\x94 \xe2 ok", b"\xef\xbf\xbd", b"\xf8\x88\x80\x80\x80", b"\xe2\x28\xa1", b"\xc2\xc2\xa9", b"\xf0\x28\x8c\xbc", b"\xf0\x90\x28\xbc", b"\xf0\x28\x8c\x28"]
    rng2 = random.Random(7)
    for _ in range(80):
        samples.append(bytes(rng2.choice([0x41, 0x7f, 0x80, 0xbf, 0xc2, 0xdf, 0xe0, 0xe2, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff, 0x82, 0xac, 0x9f, 0xa0, 0x90, 0x8f]) for _ in range(rng2.randrange(1, 9))))
    out.append("# `bytes.decode('utf-8', 'replace')`: the bytes as hexadecimal, then the UTF-8 of what the original decoded to, as hexadecimal.\npublic func decode_cases() -> str[]:\n    return [\n")
    for sample in samples:
        out.append("        %s,\n        %s,\n" % (literal(binascii.hexlify(sample).decode()), literal(binascii.hexlify(sample.decode("utf-8", "replace").encode("utf-8")).decode())))
    out.append("    ]\n\n")
    lines_samples = ["", "a", "a\n", "a\nb", "a\r\nb\rc\nd", "\n\n", "a\x0bb\x0cc\x1cd\x1de\x1ef", "x\u0085y\u2028z\u2029w", "\r\n\r\n", "end\r", "caf\u00e9\nna\u00efve"]
    out.append("# `str.splitlines()`: the text, then its lines joined by a vertical bar and counted.\npublic func splitlines_cases() -> str[]:\n    return [\n")
    for sample in lines_samples:
        out.append("        %s,\n        %s,\n" % (literal(sample), literal("%d:%s" % (len(sample.splitlines()), "|".join(sample.splitlines())))))
    out.append("    ]\n\n")
    strip_samples = ["", " ", "  a b  ", "\t\n a \r", "\u00a0x\u00a0", "\u3000y\u3000", "\x1f\x1ez\x1d", "\u2003w\u2009", "\u200bk\u200b", "\u0085q\u0085", "\u180ev\u180e", "caf\u00e9 ", "\u2028a\u2029"]
    out.append("# `str.strip()`: the text, then the stripped text between vertical bars.\npublic func strip_cases() -> str[]:\n    return [\n")
    for sample in strip_samples:
        out.append("        %s,\n        %s,\n" % (literal(sample), literal("|" + sample.strip() + "|")))
    out.append("    ]\n\n")
    out.append("# `repository_path` on absolute and relative paths: path, then what the original returned.\npublic func repository_path_cases() -> str[]:\n    return [\n")
    for path in paths:
        out.append("        %s,\n        %s,\n" % (literal(path), literal(original.repository_path(path))))
    out.append("    ]\n\n")
    groups = [["no location here"], ["error at src/a.zig:12"], ["/x/zig-toolchains/0.17/lib/std/t.zig:1:2", "then src/real.zig:7"], ['File "/usr/lib/python3.12/u.py", line 5', 'File "/w/scripts/g.py", line 9'],
              ["a.zig:1 b.zig:2"], ["x.txt:5", "y.sh:6"], ["/file.zig:3"], ["//a/b.zig:3"], ["dir//f.zig:4"], ["./h.zig:8"], ["a.b.c.zig:4:5"], ["f.zig:abc", "g.zig:7"],
              ["/lib/std/q.zig:1 /lib/compiler/r.zig:2 s.zig:3"], ["/lib/python3/z.py:3", "/lib/python3.12.1/y.py:4", "/lib/pythonx/w.py:5"]]
    raws = ["", ".", "./", "a", "a/", "a//b", "./a/./b", "a/../b", "/", "//", "///", "//a", "///a//b/", "/a/b/", "a/b/.", "./.", "..", "../..", "/..", "a/b/../..", "x y/z", "é/日本"]
    out.append("# `str(Path(raw))` for paths as given: raw, then what pathlib printed.\npublic func path_cases() -> str[]:\n    return [\n")
    from pathlib import Path
    for raw in raws:
        out.append("        %s,\n        %s,\n" % (literal(raw), literal(str(Path(raw)))))
    out.append("    ]\n\n")
    out.append("# `location` on groups of lines (joined with a vertical bar here): what the original returned, or \"-\" for None.\npublic func location_cases() -> str[]:\n    return [\n")
    for group in groups:
        found = original.location(group)
        out.append("        %s,\n        %s,\n" % (literal("|".join(group)), literal(found if found is not None else "-")))
    out.append("    ]\n")
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
