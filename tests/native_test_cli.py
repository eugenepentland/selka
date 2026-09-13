#!/usr/bin/env python3
"""Native test CLI: typed assertions, provider snapshots, and affected-test reuse."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile


# spec: NATIVE-TEST-1 NATIVE-TEST-2 NATIVE-TEST-3
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    args.qbe = str(Path(shutil.which(args.qbe) or args.qbe).resolve())
    args.zig = str(Path(shutil.which(args.zig) or args.zig).resolve())
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-native-tests-') as directory:
        root = Path(directory)
        project = root / 'project'
        project.mkdir()
        entry = project / 'main.my'
        cache = root / 'cache'
        configuration = root / 'cases.json'
        configuration.write_text('{}')

        def invoke(pattern='*', code=0, extra=(), cache_path=cache, environment=None):
            process = subprocess.run([str(compiler), 'test', str(entry), '--json',
                '--qbe', str(args.qbe), '--zig', str(args.zig),
                *(['--cache-dir', str(cache_path)] if cache_path else []),
                '--cases', str(configuration), '--filter', pattern, *extra],
                cwd=project, env=environment, capture_output=True, text=True, timeout=180)
            assert process.returncode == code, (process.returncode, process.stdout, process.stderr)
            if code == 2:
                return process
            result = json.loads(process.stdout)
            assert result['version'] == 'native-tests-v1', result
            return result

        source = '''module main;
export test_first; export test_second;
fn main()->i64{return 0;}
fn helper()->i64{return 1;}
fn unrelated()->i64{return 9;}
fn test_first()->bool{return helper()>0;}
fn test_second()->bool{return true;}
'''
        entry.write_text(source)
        first = invoke()
        assert first['executed'] == 2 and first['failed'] == 0, first
        second = invoke()
        assert second['cached'] == 2 and second['executed'] == 0, second
        entry.write_text('\n\n' + source)
        whitespace = invoke()
        assert whitespace['cached'] == 2 and whitespace['executed'] == 0, whitespace
        receipt = cache / 'results' / (second['tests'][0]['key'] + '.json')
        receipt.write_text('corrupt')
        repaired = invoke()
        assert repaired['cached'] == 1 and repaired['executed'] == 1, repaired
        entry.write_text(source.replace('return 9;', 'return 10;'))
        unrelated = invoke()
        assert unrelated['cached'] == 2 and unrelated['executed'] == 0, unrelated
        entry.write_text(source.replace('return 1;', 'return 2;'))
        affected = invoke()
        assert affected['cached'] == 1 and affected['executed'] == 1, affected
        forced = invoke(extra=('--force',))
        assert forced['executed'] == 2 and forced['cached'] == 0, forced
        fixed_environment = dict(os.environ, MYLANG_NATIVE_TEST_INPUT='first')
        assert invoke(environment=fixed_environment)['executed'] == 2
        assert invoke(environment=fixed_environment)['cached'] == 2
        changed_environment = dict(fixed_environment, MYLANG_NATIVE_TEST_INPUT='second')
        assert invoke(environment=changed_environment)['executed'] == 2
        inside = project / 'custom-cache'
        assert invoke(cache_path=inside)['executed'] == 2
        assert invoke(cache_path=inside)['cached'] == 2
        assert invoke(cache_path=None)['executed'] == 2
        assert invoke(cache_path=None)['cached'] == 2
        assert invoke('*missing', code=3)['tests'] == []
        configuration.write_text(json.dumps({'main::test_first': {'skip': 'hardware fixture'}}))
        skipped = invoke('*first', code=3)
        assert skipped['skipped'] == 1 and skipped['tests'][0]['reason'] == 'hardware fixture', skipped
        configuration.write_text(json.dumps({'main::test_unknown': {}}))
        invoke(code=2)

        configuration.write_text('{}')
        callback_source = '''module main;
export test_callback;export test_stable;
fn main()->i64{return 0;}
fn target(n:i64)->i64 effects(){return n+1;}
fn apply(f:fn(i64)->i64 effects(),n:i64)->i64{return f(n);}
fn test_callback()->bool{return apply(target,1)>0;}
fn test_stable()->bool{return true;}
'''
        entry.write_text(callback_source)
        assert invoke()['executed'] == 2
        assert invoke()['cached'] == 2
        entry.write_text(callback_source.replace('n+1', 'n+2'))
        indirect = invoke()
        assert indirect['executed'] == 1 and indirect['cached'] == 1, indirect

        domain_source = '''module main;
export Positive;export Decoded;export test_domain;export test_domain_stable;
result Decoded{ok:Positive,err:i64}
domain Positive:i64{
 codec i64{decode:from_wire,encode:to_wire}
 private fn raw(n:i64)->Positive{return wrap<Positive>(n);}
 fn from_wire(n:i64)->Decoded{return new Decoded.ok(Positive.raw(n*2));}
 fn to_wire(p:Positive)->i64{return unwrap(p)+1;}
}
fn main()->i64{return 0;}
fn test_domain(n:Positive)->Positive{return n;}
fn test_domain_stable()->bool{return true;}
'''
        entry.write_text(domain_source)
        configuration.write_text(json.dumps({'main::test_domain': {'arguments': {'n': '3'}, 'expected': '7'}}))
        assert invoke()['executed'] == 2
        assert invoke()['cached'] == 2
        domain_source = domain_source.replace('n*2', 'n*2+0')
        entry.write_text(domain_source)
        decoder = invoke()
        assert decoder['executed'] == 1 and decoder['cached'] == 1, decoder
        entry.write_text(domain_source.replace('unwrap(p)+1', 'unwrap(p)+2-1'))
        encoder = invoke()
        assert encoder['executed'] == 1 and encoder['cached'] == 1, encoder

        entry.write_text('''module main;
export Pair;export test_pair;export test_bad;export test_trap;
struct Pair{number:i64,valid:bool}
fn main()->i64{return 0;}
fn test_pair(seed:i64)->Pair{return new Pair{number:seed,valid:true};}
fn test_bad()->bool{return false;}
fn test_trap()->i64{return 1/0;}
''')
        configuration.write_text(json.dumps({
            'main::test_pair': {'arguments': {'seed': '17'}, 'expected': {'valid': True, 'number': '17'}},
            'main::test_trap': {'expected': '0'}}))
        mixed = invoke(code=1)
        rows = {row['name']: row for row in mixed['tests']}
        assert rows['main::test_pair']['status'] == 'passed', mixed
        assert rows['main::test_bad']['status'] == 'failed', mixed
        assert rows['main::test_trap']['status'] == 'failed', mixed
        repeated = invoke(code=1)
        assert repeated['cached'] == 1 and repeated['executed'] == 2, repeated
        configuration.write_text(json.dumps({'main::test_pair': {'arguments': {'wrong': '17'}, 'expected': {}}}))
        invoke('*pair', code=2)
        configuration.write_text('{}')
        invoke('*pair', code=2)

        provider = project / 'provider.my'
        original = 'module provider;export sample;host fn sample(x:i64)->i64 effects(host);'
        provider.write_text(original)
        entry.write_text('module main;import provider;export test_sample;fn main()->i64{return 0;}'
                         'fn test_sample()->bool{return provider::sample(7)==42;}')
        configuration.write_text('{}')
        for _ in range(2):
            external = invoke(code=1)
            assert external['cached'] == 0 and external['executed'] == 1, external
        fixture = {'main::test_sample': {'providers': {'provider.my':
            'module provider;export sample;fn sample(x:i64)->i64{return x+35;}'}}}
        configuration.write_text(json.dumps(fixture))
        injected = invoke()
        assert injected['executed'] == 1 and injected['failed'] == 0, injected
        assert invoke()['cached'] == 1
        assert provider.read_text() == original
        fixture['main::test_sample']['providers']['provider.my'] = 'module provider;export sample;fn sample(x:i64)->i64{return x+34;}'
        configuration.write_text(json.dumps(fixture))
        assert invoke(code=1)['executed'] == 1
        assert provider.read_text() == original
        configuration.write_text(json.dumps({'main::test_sample': {'providers': {'main.my': 'module main;'}}}))
        invoke(code=2)
        entry.write_text('module main;fn main()->i64{return missing;}')
        configuration.write_text('{}')
        invoke(code=2)
    print('Native guest tests: assertions, traps, filtering, fixture isolation, and affected-test reuse pass')


if __name__ == '__main__':
    main()
