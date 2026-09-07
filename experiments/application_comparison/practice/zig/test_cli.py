"""Coordinator-only construction checks; never part of the participant starter."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
ZIG = Path('/home/epentland/.local/bin/zig')


class PracticeCli(unittest.TestCase):
    def test_solution_and_three_starter_defects(self):
        with tempfile.TemporaryDirectory(prefix='practice-zig-') as temporary:
            work = Path(temporary)
            executable = work / 'practice'

            def compile_project(source):
                return subprocess.run(
                    [str(ZIG), 'build-exe', str(source / 'main.zig'),
                     f'-femit-bin={executable}', '--cache-dir', str(work / 'cache'),
                     '--global-cache-dir', str(work / 'global-cache')],
                    capture_output=True, timeout=60,
                )

            def run_case(data, expected):
                completed = subprocess.run([str(executable)], input=data,
                                           capture_output=True, timeout=5)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertEqual(completed.stderr, b'')
                self.assertEqual(completed.stdout, f'{expected}\n'.encode())

            compiled = compile_project(ROOT / 'solution')
            self.assertEqual(compiled.returncode, 0, compiled.stderr.decode())
            cases = [(b'm', 42), (b'd', 9)]
            cases += [(b'f' + bytes([digit]), digit - ord('0'))
                      for digit in range(ord('0'), ord('9') + 1)]
            cases += [(data, -1) for data in (
                b'', b'fx', b'f', b'f12', b'f\xff', b'f\xc3\xa9',
                b' m', b'm\n', b'd\x00', b'f0\n', b'\xff',
                b'x' * 255, b'x' * 256, b'x' * 257, b'x' * 1024,
                b'f' + b'0' * 255, b'f' + b'0' * 256,
            )]
            for data, expected in cases:
                with self.subTest(input=data[:20], size=len(data)):
                    run_case(data, expected)

            compiled = compile_project(ROOT / 'starter')
            self.assertNotEqual(compiled.returncode, 0)
            self.assertIn(b"undeclared identifier 'missing_nine'", compiled.stderr)

            repaired = work / 'name-repaired'
            shutil.copytree(ROOT / 'starter', repaired)
            main = repaired / 'main.zig'
            main.write_text(main.read_text().replace('return missing_nine;', 'return nine;'))
            compiled = compile_project(repaired)
            self.assertEqual(compiled.returncode, 0, compiled.stderr.decode())
            run_case(b'd', 9)
            run_case(b'm', 36)
            run_case(b'fx', 0)
            run_case(b'f', 0)
            run_case(b'f\xff', 0)
            main.write_text(main.read_text().replace('helper.multiply(6)', 'helper.multiply(7)')
                            .replace('catch 0', 'catch -1'))
            self.assertEqual(main.read_bytes(), (ROOT / 'solution/main.zig').read_bytes())
            self.assertEqual((repaired / 'helper.zig').read_bytes(),
                             (ROOT / 'solution/helper.zig').read_bytes())


if __name__ == '__main__':
    unittest.main()
