import copy
import json
from pathlib import Path
import tempfile
import unittest
from experiments.application_comparison import parity_readiness as parity
from experiments.application_comparison.storage import digest


def matrix():
    return dict(version='stdlib-parity-matrix-v1', applications=['eda'],
                status='ready', policy='stdlib-parity-before-application-timing-v1',
                comparator_versions=dict(python='fixture-python', zig='fixture-zig'),
                review=dict(reviewer='fixture reviewer', completed_at='fixture timestamp'),
                capabilities=[dict(id='json', applications=['eda'], status='ready',
                    required_behavior='ordinary JSON', my_api='std_json', notes='fixture only',
                    comparators=dict(python='json', zig='std.json'), evidence=['acceptance'])])


def inputs(path, **extra):
    return dict({name: path for name in parity.required_inputs(matrix())}, **extra)


class ParityReadinessTests(unittest.TestCase):
    def test_matrix_state_policy_and_versions_must_match_declared_readiness(self):
        for key, value in [('status', 'in-progress'), ('policy', None),
                           ('comparator_versions', {}), ('comparator_versions', {'python': '3'})]:
            draft = matrix()
            draft[key] = value
            with self.assertRaises(ValueError):
                parity.validate_matrix(draft)

    def test_unresolved_unreviewed_and_missing_evidence_reject(self):
        original = matrix()
        for replacement in ('gap', 'validation-pending', None):
            draft = copy.deepcopy(original)
            draft['capabilities'][0]['status'] = replacement
            with self.assertRaisesRegex(ValueError, 'unresolved'):
                parity.validate_matrix(draft)
        original['review']['reviewer'] = None
        with self.assertRaisesRegex(ValueError, 'named readiness review'):
            parity.validate_matrix(original)
        original = matrix()
        original['capabilities'][0]['evidence'] = []
        with self.assertRaisesRegex(ValueError, 'acceptance evidence'):
            parity.validate_matrix(original)

    def test_changed_tool_source_or_evidence_invalidates_readiness(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            m = root / 'matrix.json'
            m.write_text(json.dumps(matrix()))
            library = root / 'library'
            library.mkdir()
            (library / 'std_json.my').write_text('original')
            evidence = root / 'acceptance.json'
            evidence.write_text('{"passed":1}')
            tool = root / 'compiler'
            tool.write_text('compiler-v1')
            receipt = parity.capture(m, inputs=inputs(tool, stdlib=library, acceptance=evidence), output=root / 'receipt.json')
            self.assertEqual(parity.verify(receipt)['status'], 'verified')
            self.assertFalse(receipt['scored_launch_authorized'])
            with self.assertRaises(FileExistsError):
                parity.capture(m, inputs=dict(acceptance=evidence), output=root / 'receipt.json')
            for path in (tool, evidence, library / 'std_json.my'):
                old = path.read_bytes()
                path.write_bytes(old + b'changed')
                with self.assertRaisesRegex(ValueError, 'input changed'):
                    parity.verify(receipt)
                path.write_bytes(old)
            (library / 'new.my').write_text('new dependency')
            with self.assertRaisesRegex(ValueError, 'input changed'):
                parity.verify(receipt)

    def test_runtime_symlinks_are_recorded_and_changed_targets_reject(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / 'runtime'
            runtime.mkdir()
            (runtime / 'real.py').write_text('one')
            (runtime / 'alias.py').symlink_to('real.py')
            m = root / 'matrix.json'
            m.write_text(json.dumps(matrix()))
            receipt = parity.capture(m, inputs=inputs(m, python_stdlib=runtime, acceptance=m), output=root / 'receipt.json')
            self.assertEqual(parity.verify(receipt)['status'], 'verified')
            (runtime / 'real.py').write_text('two')
            with self.assertRaisesRegex(ValueError, 'input changed'):
                parity.verify(receipt)

    def test_rehashed_receipt_cannot_drop_declared_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            m = root / 'matrix.json'
            m.write_text(json.dumps(matrix()))
            e = root / 'evidence'
            e.write_text('fixture')
            with self.assertRaisesRegex(ValueError, 'named inputs'):
                parity.capture(m, inputs=dict(unrelated=e), output=root / 'missing.json')
            receipt = parity.capture(m, inputs=inputs(e, acceptance=e), output=root / 'receipt.json')
            del receipt['inputs']['acceptance']
            receipt['sha256'] = digest({k:v for k,v in receipt.items() if k != 'sha256'})
            with self.assertRaisesRegex(ValueError, 'inventory incomplete'):
                parity.verify(receipt)


if __name__ == '__main__':
    unittest.main()
