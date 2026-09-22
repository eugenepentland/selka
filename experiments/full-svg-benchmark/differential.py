#!/usr/bin/env python3
"""Malformed-input differential between the mylang guest and the native ports.

Byte equality on the three frozen cases only exercises the success path. This
driver mutates each of the three documents, runs the mylang O3 guest and every
native arm on the same bytes, and requires the same outcome: the same first
issue code as both the process status and the printed result, or (for the
unmutated and semantically valid cases) the same complete SVG.

Writes `native-differential.json`. Run it after `ports/build_native.sh`.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT))
from measure import DOCUMENTS, NATIVE_ARMS, ROOT, WORK  # noqa: E402

DECLARED = ('io::circuit_input,io::pinout_input,io::interface_input,'
            'io::length,io::byte,io::put,io::issue')
MYLANG = WORK / 'mylang-o3'
SCRATCH = WORK / 'differential'


def replace(source, needle, replacement):
    """Apply one mutation, refusing a needle that does not occur verbatim."""
    assert needle in source, needle
    mutated = source.replace(needle, replacement, 1)
    assert mutated != source
    return mutated


def mutate_module(source):
    """(name, bytes) pairs for the module document.

    Together with the pinout and interface mutations these exercise the guest's
    located issues 1 (stray ')'), 3 (unclosed '('), 4 (unexpected end of input),
    6 (bad escape), 11 (unusable instance ref), 12 (duplicate ref), 13 (a pin
    with no net), 14 (invalid pin number), 15 (repeated pin number), 17
    (unexpected form), 18 (bad pinout), 19 (family not in the pinout), 20 (wrong
    passive pin count) and 21 (bad interface), plus the valid document.
    """
    half = len(source) // 2
    return [
        ('module-truncated', source[:half]),
        ('module-unclosed-list', source[:-40]),
        ('module-stray-close', b')' + source),
        ('module-extended-string',
         replace(source, b'(port "GND"', b'(port "GND')),
        ('module-bad-escape',
         replace(source, b'(port "GND"', b'(port "G\\qND"')),
        ('module-unexpected-form',
         replace(source, b'(design-block "LMX2595', b'(design-blocc "LMX2595')),
        ('module-block-name-not-string',
         replace(source, b'(design-block "LMX2595', b'(design-block LMX2595')),
        ('module-instance-ref-not-string',
         replace(source, b'(instance "U1" lmx2595rhar', b'(instance lmx2595rhar')),
        ('module-duplicate-ref',
         replace(source, b'(instance "C_VCCVCO"', b'(instance "C_VCCDIG"')),
        ('module-unknown-family',
         replace(source, b'(instance "U1" lmx2595rhar', b'(instance "U1" nope-9999')),
        ('module-pin-without-net',
         replace(source, b'(pin 1 "V_3V3.U1.7")', b'(pin 1)')),
        ('module-pin-number-three',
         replace(source, b'(pin 1 "V_3V3.U1.7")', b'(pin 3 "V_3V3.U1.7")')),
        ('module-repeated-pin-number',
         replace(source, b'(pin 2 "GND") (decouples "U1" 7)', b'(pin 1 "GND") (decouples "U1" 7)')),
        ('module-passive-missing-pin',
         replace(source, b'(pin 2 "GND") (decouples "U1" 7)', b'(decouples "U1" 7)')),
    ]


def mutate_pinout(source):
    half = len(source) // 2
    return [
        ('pinout-truncated', source[:half]),
        ('pinout-pin-zero', replace(source, b'(pin 1 ', b'(pin 0 ')),
    ]


def mutate_interface(source):
    return [
        ('interface-truncated', source[:len(source) // 2]),
        ('interface-missing-lane', replace(source, b'(signal CS   in)', b'(signal CSX  in)')),
    ]


def documents(case):
    project = WORK / 'projects' / case
    return [project / path for path in DOCUMENTS]


def write_mutants():
    SCRATCH.mkdir(parents=True, exist_ok=True)
    cases = {'fixture': documents('fixture')}
    module = cases['fixture'][0].read_bytes()
    pinout = cases['fixture'][1].read_bytes()
    interface = cases['fixture'][2].read_bytes()
    for name, data in mutate_module(module):
        path = SCRATCH / f'{name}.sexp'
        path.write_bytes(data)
        cases[name] = [path, cases['fixture'][1], cases['fixture'][2]]
    for name, data in mutate_pinout(pinout):
        path = SCRATCH / f'{name}.sexp'
        path.write_bytes(data)
        cases[name] = [cases['fixture'][0], path, cases['fixture'][2]]
    for name, data in mutate_interface(interface):
        path = SCRATCH / f'{name}.sexp'
        path.write_bytes(data)
        cases[name] = [cases['fixture'][0], cases['fixture'][1], path]
    return cases


def run_mylang(paths):
    svg = SCRATCH / 'mylang.svg'
    issue = SCRATCH / 'mylang.issue'
    svg.write_bytes(b'')
    issue.write_bytes(b'')
    environment = dict(os.environ)
    environment.update(
        MYLANG_SCHEMATIC_DECLARED=DECLARED, MYLANG_SCHEMATIC_OUTPUT=str(svg),
        MYLANG_SCHEMATIC_ISSUE=str(issue))
    for index, path in enumerate(paths):
        environment[f'MYLANG_SCHEMATIC_INPUT_{index}'] = str(path)
    result = subprocess.run([str(MYLANG), '--print-result'], env=environment,
                            capture_output=True, cwd=ROOT, timeout=60)
    return result, svg.read_bytes()


def run_native(arm, paths):
    svg = SCRATCH / f'{arm}.svg'
    if svg.exists():
        svg.unlink()
    result = subprocess.run([str(WORK / arm), *map(str, paths), str(svg)],
                            capture_output=True, cwd=ROOT, timeout=60)
    return result, svg.read_bytes() if svg.exists() else b''


def outcome(result, svg):
    stdout = result.stdout.decode().strip()
    return {
        'status': result.returncode,
        'stdout': stdout,
        'stderr': result.stderr.decode().strip(),
        'svg_sha256': hashlib.sha256(svg).hexdigest() if svg else None,
    }


def main():
    missing = [arm for arm in NATIVE_ARMS if not (WORK / arm).exists()]
    assert not missing, f'build the native arms first: {missing}'
    cases = write_mutants()
    records = []
    failures = []
    for name, paths in cases.items():
        expected, expected_svg = run_mylang(paths)
        reference = outcome(expected, expected_svg)
        for arm in NATIVE_ARMS:
            actual, actual_svg = run_native(arm, paths)
            observed = outcome(actual, actual_svg)
            if reference['status'] == 0:
                # A valid document must reproduce the complete SVG bytes.
                agree = (observed['status'] == 0 and observed['stderr'] == ''
                         and observed['svg_sha256'] == reference['svg_sha256'])
                detail = 'svg'
            else:
                # An issue must be reported the same way: the code is both the
                # status and the printed result, and no SVG is published.
                agree = (observed['status'] == reference['status']
                         and observed['stdout'] == reference['stdout']
                         and observed['stderr'] == ''
                         and observed['svg_sha256'] is None)
                detail = 'issue'
            records.append({'case': name, 'arm': arm, 'agrees': agree,
                            'kind': detail, 'mylang': reference, 'native': observed})
            if not agree:
                failures.append((name, arm, reference, observed))
    evidence = {
        'passed': not failures,
        'comparison': ('first-issue code and process status for malformed documents; '
                       'complete SVG bytes for valid documents'),
        'cases': sorted(cases),
        'arms': list(NATIVE_ARMS),
        'records': records,
    }
    (OUT / 'native-differential.json').write_text(json.dumps(evidence, indent=2) + '\n')
    for name, arm, reference, observed in failures:
        print(f'FAIL {name} {arm}: mylang={reference} native={observed}')
    print(f'{len(cases)} documents x {len(NATIVE_ARMS)} arms: '
          f'{"all agree" if not failures else str(len(failures)) + " disagreements"}')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
