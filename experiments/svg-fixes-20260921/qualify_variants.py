#!/usr/bin/env python3
"""Check final combined binaries against legacy output on index-sensitive inputs."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

from run import ARMS, BASE, DOCS, NEW, OUT, ROOT, WORK, environment


def variants():
    source = (BASE / 'projects/fixture' / DOCS[0]).read_text()
    lines = source.splitlines(keepends=True)
    indexes = [next(i for i, line in enumerate(lines) if f'(instance "{name}"' in line)
               for name in ('C_LF1', 'C_LF2')]
    reordered = lines.copy()
    reordered[indexes[0]], reordered[indexes[1]] = reordered[indexes[1]], reordered[indexes[0]]
    nc_label = 'SYNC — phase-sync input unused; the board runs one free-standing synth, no SYSREF/JESD204B'
    return {
        'swapped_net_names': source.replace('LMX_CE', '__NET_SWAP__').replace('LMX_MUXOUT', 'LMX_CE').replace('__NET_SWAP__', 'LMX_MUXOUT'),
        'passive_declaration_order': ''.join(reordered),
        'passive_pin_order': re.sub(r'\(pin 1 "LMX_VTUNE"\)\s*\(pin 2 "LMX_CPOUT"\)', '(pin 2 "LMX_CPOUT") (pin 1 "LMX_VTUNE")', source),
        'display_raw_namespace': source.replace('V_3V3', 'V_ALT'),
        'nc_raw_collision': source.replace(nc_label, 'LMX_CE'),
        'nc_only_bridge_collision': (ROOT / 'experiments/svg-slowdown-20260921/production-row-index/nc-only-bridge-collision.sexp').read_text(),
        'empty_net_rejected': source.replace('(pin 1 "LMX_CE")', '(pin 1 "")', 1),
    }


def invoke(name, source, stress=False):
    svg, issue = WORK / 'variant.svg', WORK / 'variant.issue'
    svg.write_bytes(b'')
    issue.write_bytes(b'')
    env = environment()
    env.update(MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
               MYLANG_SCHEMATIC_INPUT_0=str(source),
               MYLANG_SCHEMATIC_INPUT_1=str(BASE / 'projects/fixture' / DOCS[1]),
               MYLANG_SCHEMATIC_INPUT_2=str(BASE / 'projects/fixture' / DOCS[2]),
               MYLANG_SCHEMATIC_OUTPUT=str(svg), MYLANG_SCHEMATIC_ISSUE=str(issue))
    command = [str(ARMS[name]), '--print-result']
    if name.endswith('bounded'):
        command += ['--max-steps=100000000']
    if stress:
        command += ['--gc-stress']
    result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, timeout=60)
    return result.returncode, result.stdout, result.stderr, svg.read_bytes(), issue.read_bytes()


def main():
    evidence = {}
    for case, text in variants().items():
        source = WORK / f'variant-{case}.sexp'
        source.write_text(text)
        expected = invoke('before-o3', source)
        assert expected[0] == (13 if case == 'empty_net_rejected' else 0), (case, expected)
        for name in NEW:
            assert invoke(name, source) == expected, (case, name)
            assert invoke(name, source, True) == expected, (case, name, 'stress')
        evidence[case] = {'status': expected[0], 'stdout': expected[1].decode(),
                          'stderr': expected[2].decode(), 'issue': expected[4].decode(),
                          'svg_sha256': hashlib.sha256(expected[3]).hexdigest(),
                          'input_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                          'matches_before_normal_and_gc_stress': list(NEW)}
    (OUT / 'variant-qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'{len(evidence)} index-sensitive variants match before in all four final builds, normally and under GC stress.')


if __name__ == '__main__':
    main()
