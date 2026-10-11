"""B7 fail-closed accounting; no installed schema-7 support is asserted here."""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import run_body_entry_qualification as Q


class BodyEntryTests(unittest.TestCase):
    def test_frozen_resource_inventory_preserves_all_native_contracts(self):
        value=Q.manifest()
        self.assertEqual(len(value['cases']),24)
        self.assertEqual([sum(s['class']==k for s in value['cases'].values()) for k in ('success','diagnostic','profile')],[14,8,2])
        limited=[s for s in value['cases'].values() if s.get('descriptor_limit')==32]
        self.assertEqual(len(limited),6)
        self.assertTrue(all(s['class']=='success' and s['runtime_status']==7 for s in limited))
        proposal=json.loads((Q.FIXTURES/'proposal.json').read_text())
        for native in proposal['cases']:
            spec=value['cases'][native['name']+'.my']
            self.assertEqual(spec['class'],native['class'])
            self.assertEqual(spec['source_sha256'],native['sha256'])
            self.assertEqual(spec.get('diagnostics'),native.get('diagnostics'))
            self.assertEqual(spec.get('runtime_stdout_hex'),native.get('runtime_stdout_hex'))

    def test_missing_changed_or_reclassified_source_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)/'fixtures';shutil.copytree(Q.FIXTURES,root)
            with patch.object(Q,'FIXTURES',root):
                original=(root/'manifest.json').read_text()
                value=json.loads(original);value['cases'].pop(next(iter(value['cases'])))
                (root/'manifest.json').write_text(json.dumps(value))
                with self.assertRaisesRegex(RuntimeError,'incomplete'):Q.manifest()
                (root/'manifest.json').write_text(original)
                (root/'entry_binary_try.input').write_bytes(b'changed')
                with self.assertRaisesRegex(RuntimeError,'source changed'):Q.manifest()

    def test_replays_require_all_seven_authentic_nonempty_pinned_requests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);request=root/'input.bin';request.write_bytes(b'authentic')
            spec={'file':'input.bin','sha256':Q.F.digest(request),'arguments':['--exchange'],'provenance':'authentic-native-request'}
            inventory={'schema':1,'complete':True,'packages':{name:dict(spec) for name in Q.ENTRIES}}
            (root/'requests.json').write_text(json.dumps(inventory))
            self.assertEqual(len(Q.request_inventory(root)['packages']),7)
            inventory['packages'].pop('body-check');(root/'requests.json').write_text(json.dumps(inventory))
            with self.assertRaisesRegex(RuntimeError,'seven authentic'):Q.request_inventory(root)
            inventory['packages']['body-check']=dict(spec,file='../input.bin');(root/'requests.json').write_text(json.dumps(inventory))
            with self.assertRaisesRegex(RuntimeError,'unsafe'):Q.request_inventory(root)
            inventory['packages']['body-check']=dict(spec,provenance='synthetic');(root/'requests.json').write_text(json.dumps(inventory))
            with self.assertRaisesRegex(RuntimeError,'synthetic'):Q.request_inventory(root)
            inventory['packages']['body-check']=dict(spec);(root/'requests.json').write_text(json.dumps(inventory));request.write_bytes(b'changed')
            with self.assertRaisesRegex(RuntimeError,'changed/empty'):Q.request_inventory(root)

    def test_capture_requires_real_correlated_schema7_body_exchange(self):
        payload=b'SLKBKI01'+struct.pack('<II',1,0)
        request=b'SLKBCK01'+struct.pack('<IIII',1,7,0,len(payload))+b'nonce123'+hashlib.sha256(payload).digest()+payload
        outcome=b'SLKBKR01'+struct.pack('<II',1,0)
        reply=request[:16]+struct.pack('<II',1,len(outcome))+request[24:64]+outcome
        self.assertEqual(Q.bound_capture(request,reply)['request_values'],1)
        import gzip
        with tempfile.TemporaryDirectory() as temporary:
            archives=Q.retained_capture(Path(temporary),0,request,reply)
            self.assertEqual(gzip.decompress(Path(archives['request_path']).read_bytes()),request)
            self.assertEqual(gzip.decompress(Path(archives['reply_path']).read_bytes()),reply)
            self.assertEqual(Q.F.digest(Path(archives['reply_path'])),archives['reply_archive_sha256'])
            with self.assertRaises(FileExistsError):Q.retained_capture(Path(temporary),0,request,reply)
        expected=[{'phase':name+phase,'mode':mode} for name in Q.ENTRIES
                  for phase,modes in (('-source-check',('shadow','component')),('-generation1',('shadow','component')),('-generation2',('component',))) for mode in modes]
        Q.require_capture_inventory(expected)
        for bad in (expected[:-1],expected[:-1]+[expected[0]],expected+[expected[0]]):
            with self.assertRaises(RuntimeError):Q.require_capture_inventory(bad)
        # CLI build graph paths are relative to the launch cwd, not private cwd.
        paths=('compiler','builder','component_dir','zig','source_root','requests_dir','work_dir','report')
        args=SimpleNamespace(**{name:Path('relative')/name for name in paths},release=False)
        with patch.object(Q.argparse.ArgumentParser,'parse_args',return_value=args),patch.object(Q,'Qualification') as qualification:
            Q.main()
            qualification.return_value.run.assert_called_once()
            self.assertTrue(all(getattr(qualification.call_args.args[0],name).is_absolute() for name in paths))

        for bad in (b'',reply[:12]+struct.pack('<I',6)+reply[16:],reply[:24]+b'wrong123'+reply[32:]):
            with self.assertRaises(RuntimeError):Q.bound_capture(request,bad)
        with self.assertRaises(RuntimeError):Q.bound_capture(request,reply+b'X')
        bad=request[:72]+struct.pack('<II',2097153,0)
        with self.assertRaises(RuntimeError):Q.bound_capture(bad,reply)
        with tempfile.TemporaryDirectory() as temporary:
            work=Path(temporary)
            q=object.__new__(Q.Qualification)
            q.args=SimpleNamespace(compiler=Path('/installed-host'),report=work/'report.json')
            q.work=work;q.empty=work;q.wrapper=work/'wrapper';q.wrapper.write_bytes(b'fixture')
            q.identity={};q.records=[];q.captures=[];q.generations=[]
            with patch.object(Q,'private_deployment'),patch.object(Q.D,'packages',return_value={'body-check':{'artifact':'real'}}),patch.object(Q.F,'execute',return_value=(0,b'',b'')):
                # Success without an exchange is not selected source admission.
                with self.assertRaisesRegex(RuntimeError,'did not execute'):
                    q.host('component',['build','entry.my','--no-cache'],work,work,'source-build',True)
                self.assertFalse(json.loads(q.args.report.read_text())['complete'])
                with self.assertRaisesRegex(RuntimeError,'may reuse'):
                    q.host('component',['build','entry.my'],work,work,'source-build')

    def test_descriptor_ceiling_is_guest_only_and_preserves_stricter_parent(self):
        with patch.object(Q.F,'process_limits') as common,patch.object(Q.resource,'getrlimit',return_value=(16,64)),patch.object(Q.resource,'setrlimit') as limits:
            Q.descriptor_limit()
            common.assert_called_once()
            limits.assert_called_once_with(Q.resource.RLIMIT_NOFILE,(16,64))
        with patch.object(Q.F,'process_limits'),patch.object(Q.resource,'getrlimit',return_value=(Q.resource.RLIM_INFINITY,64)),patch.object(Q.resource,'setrlimit') as limits:
            Q.descriptor_limit()
            limits.assert_called_once_with(Q.resource.RLIMIT_NOFILE,(32,64))

    def test_accounting_keeps_every_entry_generation_and_raw_failure(self):
        # Derive totals from required actions, not a subset that reports green.
        checks=24*3
        fixture_builds_and_runtime=(14*3+2)*2
        entry_checks=7*3
        entry_builds=7*3+7
        entry_probes=(7+entry_builds)*4
        self.assertEqual(checks+fixture_builds_and_runtime+entry_checks+entry_builds+entry_probes,Q.EXPECTED_OPERATIONS)
        self.assertEqual(Q.EXPECTED_OPERATIONS,349)
        self.assertEqual(7*2+7*2+7,35)
        with tempfile.TemporaryDirectory() as temporary:
            q=object.__new__(Q.Qualification)
            q.args=SimpleNamespace(report=Path(temporary)/'report.json')
            q.identity={};q.records=[];q.captures=[];q.generations=[]
            q.record('source-check','component',['host','check','entry','--no-cache'],(2,b'',b'ComponentProfile'))
            report=json.loads(q.args.report.read_text())
            self.assertFalse(report['complete'])
            self.assertEqual(report['selected_admission'],'pending')
            self.assertNotIn('failed',report)
            self.assertEqual(report['records'][0]['stderr_hex'],b'ComponentProfile'.hex())
            # Exercise the actual generation orchestration with bounded fakes:
            # every compilation must use the installed host, never seed.build.
            q.work=Path(temporary)
            q.args=SimpleNamespace(source_root=Path('/source'),component_dir=Path('/installed-components'),zig=Path('/zig'),release=True)
            self.assertEqual(q.build_flags(),['--release','--verify-facts'])
            q.args.release=False
            self.assertEqual(q.build_flags(),[])
            q.args.release=True
            q.identity={'host':'installed-host','sources':{},'packages':{name:{'artifact':name} for name in Q.ENTRIES}}
            commands=[]
            def host(mode,command,deployment,cwd,phase,capture=False):
                commands.append((mode,command,deployment,capture))
                self.assertIn('--no-cache',command)
                if command[0]=='build':Path(command[command.index('-o')+1]).write_bytes(b'generated')
                return (0,b'',b'')
            q.host=host
            with patch.object(q,'probes',return_value=[]) as probes,patch.object(Q,'private_deployment') as deploy,patch.object(Q.D,'packages',return_value=q.identity['packages']):
                q.entries()
            self.assertEqual(sum(c[1][0]=='check' for c in commands),21)
            self.assertEqual(sum(c[1][0]=='build' for c in commands),28)
            self.assertEqual(sum(c[3] for c in commands),35)
            self.assertEqual(probes.call_count,35)
            self.assertEqual(deploy.call_count,2)
            self.assertTrue(all(c[2]==Path(temporary)/'generation1' for c in commands[-7:]))


if __name__=='__main__':unittest.main()
