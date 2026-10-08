import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from runner import artifact_hashes, digest, invoke, runtime_environment, summarize, validate, verify_manifest
from oracle import checksum

class MeasurementTests(unittest.TestCase):
    def result(self, stdout='42 100\n', status=0, stderr=''):
        return subprocess.CompletedProcess([],status,stdout,stderr)

    def test_protocol_rejects_extra_or_invalid_measurements(self):
        for output in ('42 0\n','42 -1\n','42 100\nextra\n','42 100',' 42 100\n','42 1.5\n'):
            with self.subTest(output=output), self.assertRaises(RuntimeError): validate(self.result(output),42)

    def test_wrong_checksum_failed_guest_and_stderr(self):
        with self.assertRaises(RuntimeError): validate(self.result('43 100\n'),42)
        with self.assertRaises(RuntimeError): validate(self.result(status=3),42)
        with self.assertRaises(RuntimeError): validate(self.result(stderr='warning\n'),42)
        for stderr in ('RUNTIME_RSS_KIB=42\nnoise\n','RUNTIME_RSS_KIB=42\nRUNTIME_RSS_KIB=43\n',''):
            with self.assertRaises(RuntimeError): validate(self.result(stderr=stderr),42,rss=True)
        validate(self.result(stderr='RUNTIME_RSS_KIB=42\n'),42,rss=True)

    def test_skip_build_manifest_rejects_port_tool_object_and_binary_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            files = {name:work/name for name in ('port','compiler','guest','native_clock.o')}
            for path in files.values(): path.write_bytes(b'original')
            binaries = {'test-arm':files['guest']}
            def identity():
                return {'sources':{'port':digest(files['port'])},'tools':{'compiler':digest(files['compiler'])},'commands':['-O']}
            manifest = work/'manifest.json'
            manifest.write_text(json.dumps({'identity':identity(),'binary_hashes':artifact_hashes(binaries,work)}))
            verify_manifest(manifest,identity(),binaries,work)
            for name,path in files.items():
                path.write_bytes(b'changed')
                with self.subTest(name=name), self.assertRaises(RuntimeError): verify_manifest(manifest,identity(),binaries,work)
                path.write_bytes(b'original')
            changed = identity(); changed['commands']=['-O0']
            with self.assertRaises(RuntimeError): verify_manifest(manifest,changed,binaries,work)

    def test_timeout_propagates_without_measurement(self):
        with patch('runner.subprocess.run',side_effect=subprocess.TimeoutExpired('guest',120)):
            with self.assertRaises(subprocess.TimeoutExpired): invoke(Path('/guest'),'record_reads',2,1,1,2,1)

    def test_runtime_env_disables_inherited_tuning_and_enables_normal_gc(self):
        with patch.dict(os.environ,{'GOGC':'off','GOMEMLIMIT':'1KiB','MYLANG_OPTIONS':'--gc-stress','MYLANG_OTHER':'step','RUSTFLAGS':'-C target-cpu=native','GOFLAGS':'-gcflags=all=-N','GOAMD64':'v4','GODEBUG':'gctrace=1'}):
            env = runtime_environment()
        self.assertEqual(env['GOGC'],'100')
        self.assertEqual(env['GOMEMLIMIT'],'off')
        self.assertEqual(env['GOAMD64'],'v1')
        self.assertEqual(env['GOFLAGS'],'')
        for key in ('MYLANG_OPTIONS','MYLANG_OTHER','RUSTFLAGS','GODEBUG'): self.assertNotIn(key,env)

    def test_summary_pairs_rounds_instead_of_ratios_of_medians(self):
        from runner import ARMS
        plan = {'case':'record_reads','size':64,'profile':'small','iterations':10}
        samples=[]
        for arm in ARMS:
            for round_index,ns in enumerate((100,1000,10000)):
                samples.append({**plan,'arm':arm,'round':round_index,'kernel_ns':ns*(2 if arm!='go' else 1)})
        rows = summarize({'plans':[plan],'samples':samples})
        rust = next(row for row in rows if row['arm']=='rust')
        self.assertEqual(rust['median_ns_per_op'],200)
        self.assertEqual(rust['median_paired_ratio_to_go'],2)
        self.assertEqual(rust['paired_bootstrap_95_interval'],[2,2])

    def test_hand_computed_spec_edges(self):
        self.assertEqual(checksum('record_reads',2,1,1),30)
        self.assertEqual(checksum('tagged_stack',2,1,1),1010+10)
        self.assertEqual(checksum('mutate_unique',2,1,1),31)
        self.assertEqual(checksum('mutate_shared',2,1,1),45)
if __name__ == '__main__': unittest.main()
