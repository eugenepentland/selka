from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison.guardian_runner import stage


class GuardianRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source, self.policy = self.root / 'source', self.root / 'policy'
        self.source.mkdir()
        self.policy.mkdir()
        for name, data in [('guardian.toml', '[baseline]\nenabled = false\n'),
                           ('main.zig', 'pub const main = @import("src/main.zig").main;\n')]:
            (self.source / name).write_text(data)
            (self.policy / name).write_text(data)
        (self.source / 'src').mkdir()
        (self.source / 'src/main.zig').write_text('pub fn main() void {}\n')

    def test_stage_preserves_source_and_discards_participant_cache(self):
        cache = self.source / '.guardian/cache'
        cache.mkdir(parents=True)
        (cache / 'forged-green-stamp').write_text('claimed success')
        destination = self.root / 'stage'
        stage(self.source, self.policy, destination)
        self.assertEqual((destination / 'src/main.zig').read_bytes(), (self.source / 'src/main.zig').read_bytes())
        self.assertFalse((destination / '.guardian').exists())
        self.assertTrue((cache / 'forged-green-stamp').exists())

    def test_policy_edits_snapshots_git_and_unscanned_code_reject(self):
        for name in ('guardian.toml', 'main.zig'):
            path = self.source / name
            original = path.read_bytes()
            path.write_bytes(original + b'// changed')
            with self.assertRaisesRegex(ValueError, 'protected Guardian'):
                stage(self.source, self.policy, self.root / 'stage')
            path.write_bytes(original)
        for name in ('.guardian/baseline.json', '.git/config', '.gitattributes', 'helper.zig'):
            path = self.source / name
            path.parent.mkdir(exist_ok=True)
            path.write_text('bypass')
            with self.assertRaises(ValueError):
                stage(self.source, self.policy, self.root / 'stage')
            path.unlink()
            if name == '.git/config':
                path.parent.rmdir()
        self.assertFalse((self.root / 'stage').exists())


if __name__ == '__main__':
    unittest.main()
