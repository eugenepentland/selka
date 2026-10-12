#!/usr/bin/env python3
"""Qualify A05 public-library contracts without changing historical reports.

Use --admit for FIFO admission per guest compilation. Overlay mode is an explicitly labelled library
source experiment, not an integrated compiler qualification. Raw commands,
compiler/source identities, counters and statuses are retained for every case.
"""
# spec: STANDARD-MEMO-1 STANDARD-PERSISTENT-MEMO-1 STANDARD-DURABLE-1
# spec: NEW-CORE-ZERO-RC-RESOURCES-1 NEW-CORE-ZERO-RC-CONTAINERS-1
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import socket
import threading
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODES = {'release':['--release'], 'debug':['--unoptimized'], 'verified':['--release','--verify-facts'], 'optimized-debug':['--optimize-debug'], 'no-facts':['--release','--no-facts']}
NEGATIVE_CASES = {
    'provider_list_negative':('provider_list.my',('E_LIST_CAPABILITY',)),
    'provider_dictionary_negative':('provider_dictionary.my',('E_LIST_CAPABILITY',)),
    'provider_variant_negative':('provider_variant.my',('E_ZERO_RC_UNSUPPORTED',)),
    'provider_recursive_negative':('provider_recursive.my',('E_RECURSIVE_RECORD',)),
    'dictionary_get_view_negative':('dictionary_get_view.my',('E_ZERO_RC_VIEW_ESCAPE',)),
    'capability_array_negative':('capability_array.my',('E_ZERO_RC_UNSUPPORTED',)),
    'provider_root_move_negative':('provider_root_move.my',('E_SINGLE_OWNER_OVERLAP','E_ZERO_RC_RESOURCE_ESCAPE')),
    'provider_root_replace_negative':('provider_root_replace.my',('E_SINGLE_OWNER_OVERLAP','E_ZERO_RC_RESOURCE_ESCAPE')),
    'provider_copy_negative':('provider_copy.my',('E_ZERO_RC_UNSUPPORTED',)),
    'provider_parameter_result_negative':('provider_parameter_result.my',('E_ZERO_RC_RESOURCE_ORIGIN',)),
    'provider_field_move_negative':('provider_field_move.my',('E_SINGLE_OWNER_BORROW',)),
}

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def guest_main(source, text):
    """Preserve test bodies; give library-only fixtures an executable entrypoint."""
    if re.search(r'^func main\(', text, re.M):
        return text
    calls = re.findall(r'^public func (test_\w+)\(\) -> bool:', text, re.M)
    statements = ['    assert '+name+'()' for name in calls]
    if source.name == 'test_capabilities.my':
        statements += [
            '    const clock = time.simulated_clock(time.from_unix_nanoseconds(946684800000000000))',
            '    assert test_runner_clock_starts_at_the_documented_instant(clock)',
            '    const fs = filesystem.memory()',
            '    const env = environment.fixed({})',
            '    const net = network.denied()',
            '    const entropy = random.seeded_entropy(7)',
            '    assert test_runner_capabilities_are_empty_and_deterministic(fs, env, net, entropy)',
        ]
    return text+'\n\nfunc main() -> int:\n'+'\n'.join(statements)+'\n    return 0\n'

def run_command(argv, **options):
    try:
        return subprocess.run(argv, **options)
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode(errors='replace') if isinstance(value,bytes) else value or ''
        return subprocess.CompletedProcess(argv,124,text(error.stdout),text(error.stderr)+'\ncommand timed out\n')

def network_provider(connections=3):
    server=socket.socket(); server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); server.bind(('127.0.0.1',43781)); server.listen(3); server.settimeout(15)
    state={'endpoint':'127.0.0.1:'+str(server.getsockname()[1]),'closed':0,'received':''}
    def serve():
        try:
            for index in range(connections):
                connection,_=server.accept(); connection.settimeout(15)
                with connection:
                    if index==0 and connections==3: connection.sendall(b'ab')
                    received=b''
                    while True:
                        part=connection.recv(16)
                        if not part: break
                        received += part
                    if index==1: state['received']=received.hex()
                    state['closed'] += 1
        except Exception as error: state['error']=repr(error)
        finally: server.close()
    thread=threading.Thread(target=serve,daemon=True); thread.start()
    return state,thread

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--compiler-revision', help='Exact source revision of the independently built compiler')
    p.add_argument('--zig', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--overlay', action='store_true')
    p.add_argument('--compiler-overlay', action='store_true',
                   help='Classify a private compiler source overlay as interim evidence')
    p.add_argument('--ordinary-command', action='store_true',
                   help='Use the ordinary command without the experimental ownership selector')
    p.add_argument('--admit', action='store_true')
    p.add_argument('--check-only', action='store_true')
    p.add_argument('--cases', nargs='*')
    p.add_argument('--modes', nargs='+', choices=MODES, default=['release'])
    a=p.parse_args()
    a.compiler=a.compiler.resolve(); a.zig=a.zig.resolve(); a.output=a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=True)
    spec=importlib.util.spec_from_file_location('audit',ROOT/'experiments/zero-rc-20261011/audit.py')
    audit=importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
    env=dict(os.environ,ZIG=str(a.zig),MYLANG_ZIG=str(a.zig),MYL_CORE_LEAKCHECK='1')
    for key in ('MYLANG_COUNTERS','MYLANG_OPTIONS','MYLANG_CORE_SANITIZE'): env.pop(key,None)
    sources={p.stem:(p,0) for p in sorted((HERE/'samples').glob('*.my'))}
    for name,(filename,_) in NEGATIVE_CASES.items():
        sources[name]=(HERE/'negative'/filename,0)
    for name in ('sort','math','integer_extrema'):
        sources[name]=(ROOT/f'src/stdlib/fixtures/{name}.my',42)
    for name in ('pool','time_random','time_random_provider'):
        sources[name]=(ROOT/f'src/stdlib/fixtures/{name}.my',42 if name=='pool' else 0)
    sources['memo_fixture']=(ROOT/'tests/lang/memo_cache.my',42)
    sources['dictionary_get_readonly']=(HERE/'boundaries/dictionary_get_readonly.my',0)
    for name in ('application_cache','capability_fields','rc_capability_values','rc_contract_results','test_capabilities'):
        sources['guest_'+name]=(ROOT/'tests/lang'/str(name+'.my'),0)
    sources['guest_stdlib']=(ROOT/'tests/value_semantics/stdlib.my',0)
    unknown=set(a.cases or ())-sources.keys()
    if unknown: p.error('unknown cases: '+', '.join(sorted(unknown)))
    modules={'memo','persistent_memo','durable','cache_record','hashes'}
    def overlay(text):
        return re.sub(r'^import (\w+)$',lambda m:'import a05_'+m[1]+' as '+m[1] if m[1] in modules else m[0],text,flags=re.M)
    report={'base':'fbfcaa7a923186a8e773c3760f81c10aa345a432','compiler':str(a.compiler),'compiler_sha256':digest(a.compiler),'overlay':a.overlay or a.compiler_overlay,'library_source_overlay':a.overlay,'compiler_source_overlay':a.compiler_overlay,'check_only':a.check_only,'harness_sha256':digest(__file__),'cases':{}}
    report['compiler_source_revision']=a.compiler_revision
    report['ownership_selection']='ordinary-command' if a.ordinary_command else 'experimental-zero-rc'
    failures=0
    for name,(source,expected) in sources.items():
        if a.cases and name not in a.cases: continue
        report['cases'][name]={}
        expected_refusal=name in NEGATIVE_CASES
        for mode in a.modes:
            if expected_refusal and mode!=a.modes[0]: continue
            directory=a.output/name/mode; directory.mkdir(parents=True,exist_ok=True)
            project=directory/'source'; project.mkdir(exist_ok=True)
            text=source.read_text()
            if name.startswith('guest_'):
                text=guest_main(source,text)
                if name=='guest_rc_capability_values':
                    (project/'test_capabilities.my').write_text((ROOT/'tests/lang/test_capabilities.my').read_text())
            if a.overlay:
                for library in sorted((ROOT/'src/stdlib').glob('*.my')):
                    if library.stem not in modules: continue
                    (project/('a05_'+library.name)).write_text(overlay(library.read_text()))
                text=overlay(text)
            main=project/'main.my'; main.write_text(text)
            binary=directory/'program'; llvm=directory/'program.ll'
            source_only=a.check_only or expected_refusal
            argv=[str(a.compiler),'check' if source_only else 'build',str(main)]
            if not a.ordinary_command: argv += ['--experimental-zero-rc']
            argv += ['--cache-dir',str(a.output/'cache')]
            if not source_only: argv += ['--zig',str(a.zig),*MODES[mode],'--counters','-o',str(binary),'--emit-llvm',str(llvm)]
            linked_provider=HERE/'samples/time_random_native_provider.c' if name=='time_random_provider' else None
            if linked_provider is not None and not source_only: argv += ['--link',str(linked_provider)]
            ran=run_command(([str(ROOT/'scripts/build-slot.sh'),'build'] if a.admit else [])+argv,cwd=ROOT,env=env,capture_output=True,text=True,timeout=1800)
            result={'original_source':str(source.relative_to(ROOT)),'original_sha256':digest(source),'source_sha256':digest(main),'argv':argv,'build_status':ran.returncode,'build_stdout':ran.stdout,'build_stderr':ran.stderr,'expected_status':expected,'passed':False}
            if linked_provider is not None: result['linked_provider']={'path':str(linked_provider.relative_to(ROOT)),'sha256':digest(linked_provider)}
            (directory/'build.stdout').write_text(ran.stdout); (directory/'build.stderr').write_text(ran.stderr)
            result['source_files']={str(p.relative_to(project)):digest(p) for p in sorted(project.glob('*.my'))}
            if expected_refusal:
                result['expected_refusal']=NEGATIVE_CASES[name][1]
                result['passed']=ran.returncode!=0 and any(code in ran.stderr for code in result['expected_refusal'])
            elif ran.returncode==0 and a.check_only: result['passed']=True
            elif ran.returncode==0:
                runtime=directory/'run'; runtime.mkdir(exist_ok=True)
                for sub in ('persistent','durable'): (runtime/sub).mkdir(exist_ok=True)
                counts=directory/'counts.json'
                run_env=dict(env,MYLANG_COUNTERS=str(counts))
                if linked_provider is not None: run_env['A05_PROVIDER_MODE']='success'
                provider=None
                if name in ('network','network_values'):
                    provider,thread=network_provider(3 if name=='network' else 1)
                    run_env.update(A05_ENDPOINT=provider['endpoint'],MYLANG_OPTIONS='--restrict --allow-endpoint='+provider['endpoint']+' --allow-env=A05_ENDPOINT')
                ran=run_command([str(binary)],cwd=runtime,env=run_env,capture_output=True,timeout=120)
                raw_stdout=ran.stdout if isinstance(ran.stdout,bytes) else ran.stdout.encode()
                raw_stderr=ran.stderr if isinstance(ran.stderr,bytes) else ran.stderr.encode()
                if provider is not None:
                    thread.join(timeout=20)
                    result['provider']=provider

                result.update(run_status=ran.returncode,stdout=raw_stdout.decode(errors='replace'),stdout_hex=raw_stdout.hex(),stderr=raw_stderr.decode(errors='replace'),binary_sha256=digest(binary),llvm_sha256=digest(llvm))
                if counts.exists(): result['audit']=audit.audit(counts)
                symbols=subprocess.run(['nm',str(binary)],capture_output=True,text=True,check=True).stdout
                result['legacy_symbols']=[s for s in ('myl_core_retain','myl_core_release','myl_core_share') if s in symbols]
                code=llvm.read_text()
                result['legacy_llvm']=[s for s in ('@myl_core_retain','@myl_core_release','@myl_core_share(','load atomic i32') if s in code]
                result['passed']=ran.returncode==expected and not ran.stderr and result.get('audit',{}).get('observed_rc_free',False) and result['audit']['managed_leak_free'] and not result['legacy_symbols'] and not result['legacy_llvm']
                if linked_provider is not None:
                    result['provider_error_runs']={}
                    for family in ('clock','random'):
                        for status,expected_error in (('unavailable',43),('denied',42),('failed',44)):
                            key=family+'_'+status
                            error_counts=directory/(key+'-counts.json')
                            error_run=run_command([str(binary)],cwd=runtime,env=dict(run_env,A05_PROVIDER_MODE=key,MYLANG_COUNTERS=str(error_counts)),capture_output=True,text=True,timeout=120)
                            error_audit=audit.audit(error_counts) if error_counts.exists() else {}
                            error_result={'expected_status':expected_error,'status':error_run.returncode,'stdout':error_run.stdout,'stderr':error_run.stderr,'audit':error_audit}
                            error_result['passed']=error_run.returncode==expected_error and not error_run.stderr and error_audit.get('observed_rc_free',False) and error_audit.get('managed_leak_free',False)
                            result['provider_error_runs'][key]=error_result
                            result['passed'] &=error_result['passed']
                if name=='stream_borrow':
                    result['expected_stdout_hex']='00ff4100ff4100ff4142'
                    result['passed'] &= raw_stdout.hex()==result['expected_stdout_hex']
            if result.get('provider'):
                expected_connections=3 if name=='network' else 1
                expected_received='6364' if name=='network' else ''
                result['passed'] &= result['provider'].get('closed')==expected_connections and result['provider'].get('received')==expected_received and 'error' not in result['provider']
            failures += not result['passed']
            report['cases'][name][mode]=result
            (directory/'result.json').write_text(json.dumps(result,indent=2)+'\n')
            (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
            print(name,mode,'PASS' if result['passed'] else 'FAIL',result.get('run_status',result['build_status']),result.get('build_stderr','')[:500],flush=True)
    report['failures']=failures
    (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    return bool(failures)

if __name__=='__main__': raise SystemExit(main())
