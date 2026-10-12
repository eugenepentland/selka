import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
loader = importlib.util.spec_from_file_location('observe', HERE / 'observe_cell.py')
observe = importlib.util.module_from_spec(loader)
loader.loader.exec_module(observe)


class SnapshotContract(unittest.TestCase):
    def test_names_only_process_inspection(self):
        with patch.object(observe.subprocess, 'check_output', return_value='PID COMM\n1 python\n') as command:
            value = observe.snapshot(8)
        self.assertEqual(command.call_args.args[0], ['ps', '-eo', 'pid,ppid,psr,pcpu,comm', '--sort=-pcpu'])
        self.assertEqual(value['cpu'], 8)
        self.assertEqual(value['schema'], 'text-gap-host-before-v1')

    def test_snapshot_pinned_and_measurement_arguments_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            spec, output = root / 'spec.json', root / 'result.json'
            before = output.with_suffix('.host-before.json')
            spec.write_text(json.dumps({'files': [str(before)]}))
            args = ['observe_cell.py', str(spec), str(output), '--cpu', '8']
            with patch.object(sys, 'argv', args), patch.object(observe, 'snapshot', return_value={'cpu': 8}), patch.object(observe.subprocess, 'run') as run:
                observe.main()
                self.assertEqual(run.call_args.args[0], [sys.executable, '-B', str(HERE / 'measure.py'), *args[1:]])
                self.assertEqual(json.loads(before.read_text()), {'cpu': 8})
                with self.assertRaises(FileExistsError):
                    observe.main()
                self.assertEqual(run.call_count, 1)

    def test_unpinned_snapshot_rejected_before_measurement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            spec, output = root / 'spec.json', root / 'result.json'
            spec.write_text(json.dumps({'files': []}))
            with patch.object(sys, 'argv', ['observe_cell.py', str(spec), str(output), '--cpu', '8']), patch.object(observe.subprocess, 'run') as run:
                with self.assertRaises(AssertionError):
                    observe.main()
                run.assert_not_called()
                self.assertFalse(output.with_suffix('.host-before.json').exists())


if __name__ == '__main__':
    unittest.main()
