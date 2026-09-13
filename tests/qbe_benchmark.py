#!/usr/bin/env python3
"""Frozen C/QBE run-ABI workloads; incomplete coverage never passes retirement."""
import argparse
import ctypes
import hashlib
import json
import platform
from pathlib import Path
import statistics
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

class Frame(ctypes.Structure):
    _fields_ = [('function', ctypes.c_char_p), ('path', ctypes.c_char_p),
                ('line', ctypes.c_size_t), ('column', ctypes.c_size_t)]
class Result(ctypes.Structure):
    _fields_ = [('status', ctypes.c_int), ('value', ctypes.c_int64), ('steps', ctypes.c_uint64),
                ('code', ctypes.c_char_p), ('path', ctypes.c_char_p),
                ('line', ctypes.c_size_t), ('column', ctypes.c_size_t),
                ('frame_count', ctypes.c_size_t), ('omitted_frames', ctypes.c_size_t),
                ('frames', Frame * 16)]
class Options(ctypes.Structure):
    _fields_ = [('max_steps', ctypes.c_uint64), ('max_frames', ctypes.c_uint64), ('providers', ctypes.c_void_p)]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def measure(library, expected):
    result, options = Result(), Options(1000000000, 1024, None)
    start = time.perf_counter_ns()
    status = library.mylang_native_run_v1(ctypes.byref(options), ctypes.byref(result))
    elapsed = (time.perf_counter_ns()-start)/1e9
    if status != 0 or result.status != 0 or result.value != expected:
        raise RuntimeError(f'bad benchmark result: status={status}, value={result.value}, expected={expected}, code={result.code}')
    return elapsed

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--c-compiler', type=Path)
    parser.add_argument('--zig', default='zig')
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline-only', action='store_true')
    args=parser.parse_args()
    suite_path=ROOT/'experiments/qbe-native/suite.json'
    suite=json.loads(suite_path.read_text())
    compilers={'c':(args.c_compiler or args.compiler).resolve(), 'qbe':args.compiler.resolve()}
    report={'version':'qbe-performance-v1','suite_sha256':sha(suite_path),
            'host':platform.platform(),'machine':platform.machine(),'python':sys.version,
            'compiler_sha256':{key:sha(value) for key,value in compilers.items()},
            'qbe_sha256':sha(Path(shutil.which(args.qbe)).resolve()) if shutil.which(args.qbe) else None,
            'zig_executable_sha256':sha(Path(shutil.which(args.zig)).resolve()),
            'zig_version':subprocess.check_output([args.zig,'version'],text=True).strip(),
            'scope':'steady-state synchronous native ABI calls; build/load/process startup excluded',
            'workloads':[], 'complete':False, 'passed':False}
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-bench-') as directory:
        directory=Path(directory)
        for workload in suite['workloads']:
            source=ROOT/'experiments/qbe-native/workloads'/workload['source']
            if sha(source)!=workload['sha256']:
                raise RuntimeError(f'benchmark source changed: {source}')
            row={'name':workload['name'],'source_sha256':sha(source),'samples':{},'unsupported':[]}
            report['workloads'].append(row)
            libraries={}
            for backend in (['c'] if args.baseline_only else ['c','qbe']):
                output=directory/(workload['name']+'-'+backend+'.so')
                script='native.py' if backend=='c' else 'qbe.py'
                command=[sys.executable, str(ROOT/'scripts'/script),str(source),'--compiler',str(compilers[backend]),
                         '--zig',args.zig,'--library','--mode','ReleaseFast','-o',str(output)]
                if backend=='qbe':command+=['--qbe',args.qbe,'--cache-dir',str(directory/'cache')]
                built=subprocess.run(command,capture_output=True,text=True,timeout=240)
                if built.returncode:
                    row['unsupported'].append({'backend':backend,'error':built.stderr})
                    continue
                library=ctypes.CDLL(str(output))
                library.mylang_native_run_v1.argtypes=[ctypes.POINTER(Options),ctypes.POINTER(Result)]
                library.mylang_native_run_v1.restype=ctypes.c_int
                libraries[backend]=library
                for _ in range(suite['warmups']):measure(library,workload['expected'])
                row['samples'][backend]=[]
            for sample in range(suite['samples']):
                for backend in (list(libraries) if sample%2==0 else list(reversed(libraries))):
                    row['samples'][backend].append(measure(libraries[backend],workload['expected']))
            row['median_seconds']={key:statistics.median(value) for key,value in row['samples'].items()}
            if len(libraries)==2:
                row['ratio']=row['median_seconds']['qbe']/row['median_seconds']['c']
                row['passed']=row['ratio']<=suite['maximum_ratio']
            else:row['passed']=False
            args.output.write_text(json.dumps(report,indent=2)+'\n')
            print(workload['name'],row['median_seconds'], 'coverage',list(libraries),flush=True)
    report['complete']=all(len(row['samples'])==2 for row in report['workloads'])
    report['passed']=report['complete'] and all(row['passed'] for row in report['workloads'])
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    return 0 if report['passed'] or args.baseline_only and all('c' in row['samples'] for row in report['workloads']) else 1

if __name__=='__main__':
    sys.exit(main())
