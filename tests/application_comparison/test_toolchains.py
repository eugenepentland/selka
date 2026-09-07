"""Actual interpreter/compiler execution inside the measured isolation boundary."""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from experiments.application_comparison.isolation import Limits, run

ROOT = Path(__file__).resolve().parents[2]


class ToolchainTests(unittest.TestCase):
    def test_three_languages_multifile_stdout_agree(self):
        tools = {'mylang': ROOT / 'zig-out/bin/mylang',
                 'zig': Path(shutil.which('zig')).resolve().parent}
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / 'main.my').write_text('module main;import value;fn main()->i64{return value::number();}')
            (work / 'value.my').write_text('module value;export number;fn number()->i64{return 42;}')
            (work / 'main.py').write_text('from value import number\nprint(number())\n')
            (work / 'value.py').write_text('def number():\n    return 42\n')
            (work / 'value.zig').write_text('pub fn number() i64 { return 42; }\n')
            (work / 'main.zig').write_text('''const std = @import("std");
pub fn main(init: std.process.Init) !void {
    var bytes: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&bytes, "{d}\\n", .{@import("value.zig").number()});
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
''')
            limits = Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=4 * 1024**3)
            compiled = run(work, ['/tools/zig/zig', 'build-exe', 'main.zig', '-OReleaseSafe',
                                  '-femit-bin=/work/app'], tools=tools, limits=limits)
            self.assertTrue(compiled['isolated'], compiled['stderr'])
            self.assertEqual(compiled['returncode'], 0, compiled['stderr'])
            commands = [['/tools/mylang', 'run-project', 'main.my'],
                        ['/usr/bin/python3', '-S', '-B', 'main.py'], ['/work/app']]
            for command in commands:
                with self.subTest(command=command):
                    result = run(work, command, tools=tools, limits=limits)
                    self.assertEqual(result['returncode'], 0, result['stderr'])
                    self.assertEqual(result['stdout'], b'42\n')


if __name__ == '__main__':
    unittest.main()
