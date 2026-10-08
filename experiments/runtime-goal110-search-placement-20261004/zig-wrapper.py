#!/usr/bin/env python3
"""Diagnostic-only transparent Zig capture, with optional exact assembly fill."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import uuid


def binding(path):
    return {'path': str(path.resolve()), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size}


def expand(arguments):
    expanded, responses = [], []
    for word in arguments:
        if word.startswith('@'):
            response = Path(word[1:]).resolve()
            nested, more = expand(shlex.split(response.read_text()))
            expanded.extend(nested)
            responses.append(response)
            responses.extend(more)
        else:
            expanded.append(word)
    return expanded, responses


def copy_bound(source, target):
    shutil.copyfile(source, target)
    return {'source': binding(source), 'saved': binding(target)}


config_path = Path(os.environ['MYL_PLACEMENT_CONFIG']).resolve()
config = json.loads(config_path.read_text())
real = Path(config['real_zig']).resolve()
assert binding(real)['sha256'] == config['real_zig_sha256']
mode = config['mode']
assert mode in ('capture', 'fill32')
capture = Path(config['capture_directory']).resolve()
capture.mkdir(parents=True, exist_ok=True)
call_id = str(uuid.uuid4())
here = capture / call_id
here.mkdir()
original = sys.argv[1:]
expanded, responses = expand(original)
record = {'kind': 'diagnostic-zig-call', 'id': call_id, 'mode': mode, 'pid': os.getpid(),
          'started_utc': datetime.now(timezone.utc).isoformat(), 'cwd': os.getcwd(),
          'argv': [str(real), *original], 'wrapper_argv': sys.argv,
          'expanded_for_inspection': expanded, 'config': binding(config_path),
          'wrapper': binding(Path(__file__)), 'real_zig': binding(real),
          'responses': [copy_bound(path, here / ('response-' + str(index) + '.rsp'))
                        for index, path in enumerate(responses)]}
lto = expanded and expanded[0] == 'ld.lld' and '--lto-emit-asm' in expanded
assembly = None
if lto:
    assert '--lto-O3' in expanded and '--lto-partitions=1' in expanded
    output = Path(expanded[expanded.index('-o') + 1])
    assembly = Path(str(output) + '.lto.s')
    inputs = [Path(word) for word in expanded[1:] if not word.startswith('-')
              and Path(word).is_file() and Path(word).suffix in ('.o', '.a')]
    record['lto_inputs'] = [copy_bound(path, here / ('input-' + str(index) + path.suffix))
                            for index, path in enumerate(inputs)]
if expanded and expanded[0] == 'cc' and '-c' in expanded:
    inputs = [Path(word) for word in expanded if word.endswith('/program.s')]
    if inputs:
        assert len(inputs) == 1
        record['annotated_assembly'] = copy_bound(inputs[0], here / 'program-annotated.s')
result = subprocess.run([str(real), *original], capture_output=True)
record['exit_status'] = result.returncode
(here / 'stdout').write_bytes(result.stdout)
(here / 'stderr').write_bytes(result.stderr)
record['stdout'] = binding(here / 'stdout')
record['stderr'] = binding(here / 'stderr')
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
if result.returncode == 0 and assembly is not None:
    record['raw_assembly'] = copy_bound(assembly, here / 'program-before.s')
    raw = assembly.read_bytes()
    if mode == 'fill32':
        assert hashlib.sha256(raw).hexdigest() == config['raw_assembly_sha256']
        label = config['loop_label'].encode() + b':'
        lines = raw.splitlines(keepends=True)
        indexes = [index for index, line in enumerate(lines) if line.split(b'#', 1)[0].strip() == label]
        assert len(indexes) == 1, indexes
        index = indexes[0]
        lines.insert(index, b'\t.fill 32, 1, 0x90 # diagnostic placement counterfactual only\n')
        changed = b''.join(lines)
        assert len(changed) > len(raw)
        assembly.write_bytes(changed)
        record['transform'] = {'kind': '32-nop-bytes-before-loop-label',
                               'label': config['loop_label'], 'source_line': index + 1,
                               'expected_body_normalized_sha256': config['loop_normalized_sha256'],
                               'backedge_skips_fill': 'Must be independently verified on final ELF before qualification/timing.'}
    record['used_assembly'] = copy_bound(assembly, here / 'program-after.s')
record['finished_utc'] = datetime.now(timezone.utc).isoformat()
(here / 'call.json').write_text(json.dumps(record, indent=2) + '\n')
sys.exit(result.returncode)
