"""Installed raw-byte VM host acceptance inside participant command isolation."""
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.isolation import Limits, run

ROOT = Path(__file__).resolve().parents[2]
IO = ('module io\n\n\n\n\n\n'
      'host def length() -> i64 effects(host)\n\n\n'
      'host def byte(index: i64) -> u8 effects(host)\n\n\n'
      'host def put(value: u8) -> i64 effects(host)\n')


class ByteIoHostTests(unittest.TestCase):
    def test_output_temporaries_are_reclaimed_under_memory_limit(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / 'io.my').write_text(IO)
            (work / 'main.my').write_text('module main\nimport io\n\n\ndef main() -> i64:\n    i = 0\n'
                                          '    while i < 8388608:\n        discard io.put(65u8)\n'
                                          '        i += 1\n    return 0\n')
            result = run(work, ['/tools/byte_io', '--project', '/work'],
                         tools={'byte_io': ROOT / 'zig-out/bin/mylang-io'},
                         limits=Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=256 * 1024**2, output_bytes=16 * 1024**2))
            self.assertEqual(result['returncode'], 0, result['stderr'])
            self.assertEqual(result['stdout'], b'A' * 8388608)

    def test_native_boundary_rejects_extra_callbacks_and_wrong_signatures(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            io = IO
            cases = [
                (io, 'module main\nimport io\n\n\nhost def route() -> i64 effects(host)\n\n\n'
                     'def main() -> i64:\n    discard io.put(65u8)\n    discard route()\n    return 0\n',
                 b'HostMissingRegistration'),
                (io.replace('byte(index: i64) -> u8', 'byte(index: i64) -> i64'),
                 'module main\nimport io\n\n\ndef main() -> i64:\n    discard io.byte(0)\n    return 0\n',
                 b'HostSignatureMismatch'),
                (io, 'module main\nimport io\n\n\ndef main() -> i64:\n    discard io.put(65u8)\n    return 1\n',
                 b'GuestExit'),
                (io, 'module main;import io;fn main()->i64{discard io::put(65u8);discard io::byte(-1);return 0;}', b'GuestTrap'),
            ]
            for declarations, source, diagnostic in cases:
                with self.subTest(diagnostic=diagnostic):
                    (work / 'io.my').write_text(declarations)
                    (work / 'main.my').write_text(source)
                    result = run(work, ['/tools/byte_io', '--project', '/work'],
                                 tools={'byte_io': ROOT / 'zig-out/bin/mylang-io'}, input_bytes=b'x')
                    self.assertTrue(result['isolated'], result['stderr'])
                    self.assertNotEqual(result['returncode'], 0)
                    self.assertEqual(result['stdout'], b'')
                    self.assertIn(diagnostic, result['stderr'])

    def test_guest_raw_io_and_source_reload_without_tool_rebuild(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary)
            (work / 'io.my').write_text('module io;;;;host fn length()->i64 effects(host);host fn byte(index:i64)->u8 effects(host);host fn put(value:u8)->i64 effects(host);')
            (work / 'main.my').write_text('module main;import io;fn main()->i64{let mut i=0;while i<io::length(){discard io::put(io::byte(i));i+=1;}return 0;}')
            tools = {'byte_io': ROOT / 'zig-out/bin/mylang-io'}
            command = ['/tools/byte_io', '--project', '/work']
            raw = b'\xff\x00{not-json}'
            result = run(work, command, tools=tools, input_bytes=raw)
            self.assertTrue(result['isolated'], result['stderr'])
            self.assertEqual(result['returncode'], 0, result['stderr'])
            self.assertEqual(result['stdout'], raw)
            (work / 'main.my').write_text('module main;import io;fn main()->i64{discard io::put(65u8);return 0;}')
            result = run(work, command, tools=tools)
            self.assertEqual(result['returncode'], 0, result['stderr'])
            self.assertEqual(result['stdout'], b'A')


if __name__ == '__main__':
    unittest.main()
