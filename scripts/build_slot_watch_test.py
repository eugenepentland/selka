"""Wrapper argv compatibility; do not execute Zig or allocate a second slot."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SLOT = Path(__file__).resolve().with_name('build-slot.sh')
MARKER = 'pub const admission_watch_identity = true;\n'
IMPORT = '    const identity = @import("build_identity.zig").module(b, target);\n'


class WatchCommand(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        # Capture the exact argv delivered to admission. No project file is
        # sourced, and this fake interpreter never executes the admission file.
        interpreter = self.bin / 'python3'
        interpreter.write_text('#!' + sys.executable + '\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n')
        interpreter.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.project()

    def project(self, marker=MARKER, imported=IMPORT):
        (self.root / 'build_identity.zig').write_text(marker)
        (self.root / 'build.zig').write_text(imported)

    def forwarded(self, arguments, cwd=None):
        result = subprocess.run(['bash', str(SLOT), *arguments], cwd=cwd or self.root,
                                env=self.env, check=True, text=True, capture_output=True)
        output = json.loads(result.stdout)
        self.assertEqual(output[:2], ['-B', str(SLOT.with_name('build_admission.py'))])
        return output[2:]

    def test_direct_watch_build_opts_in_with_exact_capability(self):
        for kind in ('build', 'gate', 'timing'):
            for zig in ('zig', '/tools/private bin/zig'):
                with self.subTest(kind=kind, zig=zig):
                    arguments = [kind, '--', zig, 'build', '--watch', '-fincremental', 'a b']
                    self.assertEqual(self.forwarded(arguments), arguments[:4] + ['-Dwatch-identity=true'] + arguments[4:])

    def test_explicit_identity_options_are_preserved(self):
        for option in ('-Dwatch-identity=false', '-Dwatch-identity=true', '-Dwatch-identity', '-Dwatch-identity=invalid'):
            with self.subTest(option=option):
                arguments = ['build', 'zig', 'build', '--watch', option]
                self.assertEqual(self.forwarded(arguments), arguments)

    def test_other_commands_and_build_file_overrides_are_unchanged(self):
        for arguments in (
            [], ['status'], ['build', 'zig', 'build'],
            ['build', 'env', 'zig', 'build', '--watch'],
            ['build', 'bash', '-c', 'zig build --watch'],
            ['build', 'zig', 'test', '--watch'],
            ['build', 'zig', 'build', '--', '--watch'],
            ['build', 'zig', 'build', '--watch', '--build-file', 'elsewhere.zig'],
            ['build', 'zig', 'build', '--watch', '--build-file=elsewhere.zig'],
        ):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.forwarded(arguments), arguments)

    def test_option_scanning_stops_at_program_argument_separator(self):
        arguments = ['build', 'zig', 'build', '--watch', '--', '-Dwatch-identity=false', 'a\nb', '$(exit 1)']
        self.assertEqual(self.forwarded(arguments), arguments[:3] + ['-Dwatch-identity=true'] + arguments[3:])

    def test_old_or_unrelated_projects_do_not_opt_in(self):
        arguments = ['build', 'zig', 'build', '--watch']
        for marker, imported in (
            ('', IMPORT), (MARKER, ''), ('// ' + MARKER, IMPORT),
            (' ' + MARKER, IMPORT), (MARKER, '// ' + IMPORT),
            (MARKER, 'const other = @import("build_identity.zig");\n'),
        ):
            with self.subTest(marker=marker, imported=imported):
                self.project(marker, imported)
                self.assertEqual(self.forwarded(arguments), arguments)
        self.project()
        subdirectory = self.root / 'nested'
        subdirectory.mkdir()
        self.assertEqual(self.forwarded(arguments, subdirectory), arguments)


if __name__ == '__main__':
    unittest.main()
