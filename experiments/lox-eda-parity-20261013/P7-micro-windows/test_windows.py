import argparse
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('windows', HERE / 'windows.py')
w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
TOOLS = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/experiments/text-gaps-20261012/bench/tools/measure.py')


class Windows(unittest.TestCase):
    def setUp(self):
        private = HERE.parents[2] / '.tmp/lox-eda-parity/P7-micro-windows'
        private.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=private)
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.guest = self.folder / 'guest.py'
        self.guest.write_text('''import os,json,sys
if os.environ.get('MYLANG_COUNTERS'):
 totals={k:0 for k in ['allocs','reallocs','alloc_bytes','realloc_added_bytes','peak_live_bytes','live_bytes_at_exit','runtime_retains','runtime_releases','share_marks']}
 kinds={k:{'count':0} for k in ['retain','release','unique_test','release_unique']}
 open(os.environ['MYLANG_COUNTERS'],'w').write(json.dumps({'version':'mylang-counters-v1','totals':totals,'kinds':kinds}))
print('bad' if 'bad' in sys.argv else 'done')
''')
        binary = str(Path(sys.executable).resolve())
        self.data = {'cell':'synthetic/7arms', 'protocol':'stdout', 'expected_stdout':'done\n', 'warmups':3, 'rounds':15, 'rss_rounds':3,
          'files':[str(self.guest)], 'arms':{str(n):{'status':'ok','binary':binary,'sha256':w.sha(binary),'args':[str(self.guest)]} for n in range(7)},
          'counted':{str(n):{'status':'ok','binary':binary,'sha256':w.sha(binary),'args':[str(self.guest)],'zero_rc':True} for n in range(3)}}
        self.path = self.folder / 'spec.json'; self.path.write_text(json.dumps(self.data))
        self.args = argparse.Namespace(spec=self.path,tools=TOOLS,output=self.folder/'out',cpu=min(os.sched_getaffinity(0)),timeout=2,window_seconds=.15)
        affinity = os.sched_getaffinity(0); self.addCleanup(os.sched_setaffinity,0,affinity)
        self.tools = w.load_tools(TOOLS)

    def run_window(self):
        with patch.dict(os.environ,{'MYLANG_ADMISSION_KIND':'timing','MYLANG_ADMISSION_DIR':'synthetic-test-only'}):
            with patch('builtins.print'):
                w.window(self.args)

    def test_resume_preserves_exact_protocol_order_counts_and_metric_schema(self):
        self.run_window()
        self.assertFalse((self.args.output/'cell.json').exists())
        for _ in range(200):
            if (self.args.output/'cell.json').exists():break
            self.run_window()
        result=json.loads((self.args.output/'cell.json').read_text())
        for phase,rounds in [('warmups',range(-3,0)),('samples',range(15)),('rss',range(3))]:
            for rnd in rounds:
                index=rnd+3 if rnd<0 else rnd
                got=[v['arm'] for v in result[phase] if v['round']==rnd]
                self.assertEqual(got,self.tools.balanced_order(list(self.data['arms']),index,self.data['cell']+'/'+phase))
        self.assertEqual(len(result['warmups']),21);self.assertEqual(len(result['samples']),105);self.assertEqual(len(result['rss']),21)
        self.assertEqual(len(result['counted']),3)
        self.assertTrue(all(v['complete'] for v in result['summary'].values()))
        self.assertTrue(all(v['metrics']['live_bytes_at_exit']==0 for v in result['counted'].values()))
        self.assertGreater(len(result['windows']),1)
        self.assertTrue(all(r['elapsed_seconds'] <= r['launch_window_seconds'] + r['guest_deadline_seconds'] + .5 for r in result['windows']))
        for i,r in enumerate(result['windows'][1:],1):self.assertEqual(r['previous_receipt_sha256'],w.sha(self.args.output/('window-%04d.json'%(i-1))))
        self.assertEqual(result['identities'],result['identities_after'])
        with self.assertRaises(AssertionError):self.run_window()

    def test_changed_input_and_interrupted_guest_refuse_resume(self):
        self.run_window();self.guest.write_text(self.guest.read_text()+'# changed\n')
        with self.assertRaises(AssertionError):self.run_window()
        self.guest.write_text(self.guest.read_text().removesuffix('# changed\n'))
        state=json.loads((self.args.output/'state.json').read_text());state['active']={'phase':'samples'};w.save(state,self.args.output,'start')
        with self.assertRaises(AssertionError):self.run_window()

    def test_failed_output_remains_status_and_counting_is_separate(self):
        self.data['arms']['0']['args'].append('bad');self.path.write_text(json.dumps(self.data));self.args.window_seconds=55
        self.run_window();r=json.loads((self.args.output/'cell.json').read_text())
        self.assertEqual(r['arm_status']['0']['status'],'output_mismatch')
        self.assertFalse(r['summary']['0']['complete']);self.assertIsNone(r['summary']['0']['process_wall_ns'])
        self.assertEqual(r['counted']['0']['status'],'ok')
        self.assertEqual(len([v for v in r['samples'] if v['arm']=='0']),0)

    def test_missing_foreign_snapshot_refused_without_write(self):
        foreign = self.folder / 'foreign.host-before.json'
        self.data['files'].append(str(foreign)); self.path.write_text(json.dumps(self.data))
        with self.assertRaises(AssertionError): self.run_window()
        self.assertFalse(foreign.exists())

    def test_post_window_identity_change_and_receipt_tampering_refuse(self):
        marker = self.folder / 'marker.txt'; marker.write_text('initial')
        self.data['files'].append(str(marker)); self.path.write_text(json.dumps(self.data))
        self.guest.write_text('open(' + repr(str(marker)) + ', \"w\").write(\"changed\")\n' + self.guest.read_text())
        with self.assertRaises(AssertionError): self.run_window()
        self.assertFalse((self.args.output / 'cell.json').exists())
        self.assertFalse((self.args.output / 'window-0000.json').exists())

    def test_outer_admission_required(self):
        with patch.dict(os.environ,{},clear=True):
            with self.assertRaises(AssertionError):w.window(self.args)
        self.assertFalse(self.args.output.exists())

    def test_kernel_pilot_matches_original_adjustment_boundaries(self):
        s={'document':{'spec':{'max_slowest_kernel_ms':100,'target_fastest_kernel_ms':10,'max_iterations':1000},'pilots':[]},'phase':'pilot','round':0,'position':7,'count':31,'pilot_results':[{'kernel_ns':200_000_000}]}
        w.advance_round(s,self.tools)
        self.assertEqual(s['count'],13);self.assertEqual(s['round'],1);self.assertEqual(s['phase'],'pilot')
        s['round']=9;s['pilot_results']=[{'kernel_ns':200_000_000}]
        self.tools.registry=type('R',(),{'checksum':staticmethod(lambda *a:123)})
        s['document']['spec'].update(protocol='kernel',case='synthetic',size=1,seed=42)
        w.advance_round(s,self.tools)
        self.assertEqual(s['phase'],'warmups');self.assertEqual(s['document']['calibration']['reason'],'slowest_arm_budget')
        self.assertEqual(s['document']['expected'],123)


if __name__=='__main__':unittest.main()
