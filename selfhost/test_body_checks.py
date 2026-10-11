#!/usr/bin/env python3
"""Fail-closed pure and installed body_check component gate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from test_pilots import require_guest

ROOT=Path(__file__).resolve().parents[1]


def execute(command, env):
    result=subprocess.run([str(arg) for arg in command],cwd=ROOT,env=env,capture_output=True,text=True,timeout=600)
    print(result.stdout,end='',flush=True)
    print(result.stderr,end='',file=sys.stderr,flush=True)
    if result.returncode:raise RuntimeError(f'body_check gate command exited {result.returncode}')
    return result.stdout


def require_summary(output, edit=False):
    rows=re.findall(r'^body_check qualification: (\d+) workflows, (\d+) comparisons, (\d+) warm deployment checks, (\d+) live session checks; 0 failed, 0 skipped$',output,re.M)
    if len(rows)!=1:raise RuntimeError('missing/duplicate body_check qualification verdict')
    workflows,comparisons,warm,live=map(int,rows[0])
    fixtures = json.loads((ROOT / 'selfhost/tests/fixtures/body_check/manifest.json').read_text())
    expected = len(fixtures) + 2 * sum(bool(value.get('typed')) and not value.get('library') for value in fixtures.values()) + sum('result' in value for value in fixtures.values()) + 8 + 2 + 3 + 3
    if len(fixtures) < 20 or workflows != expected or comparisons!=(4 if edit else 2)*workflows or warm!=30 or live!=4:
        raise RuntimeError('incomplete body_check qualification selection')
    if re.findall(r'^body_check transport: (\d+) valid, (\d+) malformed; 0 failed, 0 skipped$', output, re.M) != [('1', '16')]:
        raise RuntimeError('missing/incomplete body_check transport selection')
    if re.findall(r'^body_check forged replies: (\d+) rejected; 0 failed, 0 skipped$', output, re.M) != ['16']:
        raise RuntimeError('missing/incomplete hostile body_check reply selection')
    if re.findall(r'^body_check publication: (\d+) host failures; 0 failed, 0 skipped$', output, re.M) != ['2']:
        raise RuntimeError('missing/incomplete cross-boundary publication selection')


def main():
    ap=argparse.ArgumentParser()
    for name in ('builder','compiler','component-dir','zig'):ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--report-dir',type=Path)
    args=ap.parse_args()
    env={k:v for k,v in os.environ.items() if not k.startswith(('MYLANG_','PILOT_')) or k=='MYLANG_COMPONENT_CACHE'}
    env.update(MYLANG_ZIG=str(args.zig),MYL_CORE_LEAKCHECK='1',MYLANG_LEXER_MODE='reference',MYLANG_PARSER_MODE='reference',MYLANG_DECLARATION_MODE='reference', MYLANG_BODY_CHECK_MODE='reference', MYLANG_TYPE_INTERFACE_MODE='reference',MYLANG_TEST_INDEX_MODE='reference',MYLANG_CACHE_PLAN_MODE='reference',MYLANG_COMPONENT_DIR=str(args.component_dir.resolve()))
    provision=execute([args.builder.resolve(),'--root',ROOT,'--zig',args.zig,'--seed-only'],env).strip().splitlines()
    if len(provision)!=1 or not Path(provision[0]).is_file():raise RuntimeError('missing qualified seed receipt')
    seed=Path(provision[0]);print('body_check seed SHA256 '+hashlib.sha256(seed.read_bytes()).hexdigest())
    roots=[(p,len(re.findall(r'^public func test_[A-Za-z0-9_]+\(',p.read_text(),re.M))) for p in sorted((ROOT/'selfhost/components/body_check').glob('*tests.my'))]
    roots=[(p,count) for p,count in roots if count]
    total=sum(count for _,count in roots)
    if not total:raise RuntimeError('empty body_check pure-test selection')
    for release in (False,True):
        flags=['--release','--verify-facts'] if release else []
        for source,count in roots:
            budget = ['--max-steps', '100000000'] if source.name in ('indexed_tests.my', 'profile_tests.my') else []
            require_guest(execute([seed,'test',source,'--force','--no-cache',*flags,*budget],env),count)
        command=[sys.executable,ROOT/'selfhost/tests/run_body_check_qualification.py','--compiler',args.compiler.resolve(),'--builder',args.builder.resolve(),'--component-dir',args.component_dir.resolve(),'--zig',args.zig]
        if args.report_dir:
            report = args.report_dir.resolve() / ('release.json' if release else 'normal.json')
            command.extend(['--report', report])
        if release:command.append('--release')
        else:command.append('--edit-check')
        require_summary(execute(command,env), edit=not release)
    print(f'body_check gate: {total} pure tests per mode; complete qualification passed')

if __name__=='__main__':main()
