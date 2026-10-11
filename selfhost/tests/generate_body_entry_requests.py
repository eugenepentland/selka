#!/usr/bin/env python3
"""Capture seven genuine installed-host requests for the B7 source gate."""
import argparse
import json
from pathlib import Path
import shutil
import run_body_entry_qualification as E

F, D = E.F, E.D
MODES = dict(zip(E.ENTRIES, ('TEST_INDEX', 'CACHE_PLAN', 'LEXER', 'PARSER',
                            'DECLARATION', 'TYPE_INTERFACE', 'BODY_CHECK')))


def command(args, name, source):
    verb = {'test-index': 'tests-for', 'cache-plan': 'test'}.get(name, 'check-project')
    result = [args.compiler, verb, source, '--no-cache']
    if name == 'test-index':
        result.extend(['main::test_entry', '--diagnostics=json'])
    elif name == 'cache-plan':
        result.extend(['--force', '--json', '--zig=' + str(args.zig)])
    else:
        result.append('--diagnostics=json')
    return result


def replay_flag(name):
    E.require(name in E.ENTRIES, 'unknown runtime request package')
    return '--request' if name in ('test-index', 'cache-plan') else '--exchange'


def baseline_equal(name, native, selected):
    if name != 'cache-plan':
        return native == selected
    # Routing deliberately changes planner identities/work, not test outcomes.
    def outcomes(result):
        E.require(result[0] == 0 and not result[2], 'cache-plan control failed')
        value = json.loads(result[1])
        E.require(value.get('version') == 'native-tests-v1' and
                  [value.get(k) for k in ('passed', 'failed', 'skipped', 'cached', 'unsupported')] ==
                  [1, 0, 0, 0, 0] and len(value['tests']) == 1,
                  'cache-plan control did not execute its one test')
        value['tests'][0].pop('cache', None)
        return value
    return outcomes(native) == outcomes(selected)


def validate_exchange(name, request, reply, identity):
    E.require(0 < len(request) <= 67108864 and 0 < len(reply) <= 67108864,
              'empty/oversized runtime exchange')
    if replay_flag(name) == '--exchange':
        import hashlib
        import struct
        magic = {'lexer-pilot': b'SLKLEX01', 'parser-pilot': b'SLKPRS01',
                 'declaration-index': b'SLKDIX01', 'type-interface': b'SLKTIF01',
                 'body-check': b'SLKBCK01'}[name]
        for payload, direction in ((request, 0), (reply, 1)):
            E.require(len(payload) >= 64 and payload[:8] == magic, 'wrong runtime protocol')
            E.require(struct.unpack('<IIII', payload[8:24]) ==
                      (identity['protocol'], identity['schema'], direction, len(payload)-64),
                      'wrong runtime frame identity')
        E.require(request[32:64] == hashlib.sha256(request[64:]).digest() and
                  request[24:64] == reply[24:64], 'uncorrelated runtime reply')


def generate(args):
    work = args.output_dir
    work.mkdir(parents=True, exist_ok=False)
    identity = {'host_sha256': F.digest(args.compiler), 'zig_sha256': F.digest(args.zig),
                'packages': D.packages(args.component_dir, body_schema=E.SCHEMA),
                'sources': E.source_identity(args.source_root)}
    empty = work/'empty-path'; empty.mkdir()
    control = work/'control'; control.mkdir()
    source = control/'main.my'
    source.write_text('func main() -> int:\n    return 7\n\npublic func test_entry() -> bool:\n    return True\n')
    wrapper = work/'request-capture'
    build = F.execute([args.zig, 'cc', E.FIXTURES/'request_capture.c', '-O2', '-o', wrapper],
                      D.coordinator_environment(), work)
    E.require(build[0] == 0, 'capture fixture compilation failed: ' + repr(build))
    inventory = {'schema': 1, 'complete': False, 'identity': identity,
                 'control_sha256': F.digest(source), 'packages': {}, 'records': []}
    def checkpoint():
        (work/'requests.json').write_text(json.dumps(inventory, indent=2)+'\n')
    checkpoint()
    for name, mode in MODES.items():
        env = D.environment('reference', args.component_dir, empty)
        argv = command(args, name, source)
        native = F.execute(argv, env, work)
        E.require(native[0] == 0 and not native[2], 'native runtime control failed: ' + name)
        private = work/(name+'-deployment')
        E.private_deployment(args.component_dir, private, {name: wrapper},
                             {'capture_fixture_sha256': F.digest(wrapper), 'package': name})
        request, reply = work/(name+'.bin'), work/(name+'.reply')
        env = D.environment('reference', private, empty)
        env.update({'MYLANG_'+mode+'_MODE': 'component',
                    'BODY_REAL': str(args.component_dir/identity['packages'][name]['artifact']),
                    'BODY_REQUEST': str(request), 'BODY_CAPTURE': str(reply)})
        selected = F.execute(argv, env, work)
        record = {'package': name, 'command': list(map(str, argv)),
                  'native': [native[0], native[1].hex(), native[2].hex()],
                  'selected': [selected[0], selected[1].hex(), selected[2].hex()]}
        inventory['records'].append(record); checkpoint()
        E.require(baseline_equal(name, native, selected), 'capture changed native verdict: '+name)
        validate_exchange(name, request.read_bytes(), reply.read_bytes(), identity['packages'][name])
        replay = F.execute([args.component_dir/identity['packages'][name]['artifact'],
                            replay_flag(name), request], env, work)
        E.require(replay == (0, reply.read_bytes(), b''), 'real artifact replay failed: '+name)
        inventory['packages'][name] = {'file': request.name, 'arguments': [replay_flag(name)],
                                      'sha256': F.digest(request), 'reply_sha256': F.digest(reply),
                                      'provenance': 'authentic-native-request',
                                      'deployment': identity['packages'][name]}
        checkpoint()
        shutil.rmtree(private)
    E.require(identity == {'host_sha256': F.digest(args.compiler), 'zig_sha256': F.digest(args.zig),
                          'packages': D.packages(args.component_dir, body_schema=E.SCHEMA),
                          'sources': E.source_identity(args.source_root)}, 'capture deployment/source changed')
    E.require(set(inventory['packages']) == set(E.ENTRIES), 'incomplete generated runtime inventory')
    inventory['complete'] = True
    checkpoint()
    E.request_inventory(work)
    print('B7 runtime requests: 7 captured, 7 native comparisons, 7 real replays; 0 failed, 0 skipped')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'component-dir', 'zig', 'source-root', 'output-dir'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'component_dir', 'zig', 'source_root', 'output_dir'):
        setattr(args, name, getattr(args, name).resolve())
    generate(args)


if __name__ == '__main__':
    main()
