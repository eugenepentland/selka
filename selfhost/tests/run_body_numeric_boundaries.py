#!/usr/bin/env python3
"""Supplemental native binary64 boundaries; does not replace strict B9 admission."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import run_body_check_qualification as D

SUCCESS = [
    '0.0',
    '-0.0',
    '5e-324',
    '-5e-324',
    '2.225073858507201e-308',
    '2.2250738585072014e-308',
    '2.225073858507202e-308',
    '0.9999999999999999',
    '1.0',
    '1.0000000000000002',
    '1.7976931348623157e308',
    '-1.7976931348623157e308',
    '9007199254740993.0',
    '1.00000000000000011102230246251565404236316680908203125',
    '1.000000000000000111022302462515654042363166809082031251',
    '2.4703282292062327e-324',
    '2.4703282292062328e-324',
    '1e-400',
    '-1e-400',
    '0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF',
    '0b1_0000',
]
ERRORS = [
    '1e400',
    '-1e400',
    '1__0.0',
    '1_.0',
    '1._0',
    '1e+',
    '1.0u8',
    '1.0j',
    '0x1u8',
    '0x__1',
    '0x_',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--component-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.component_dir = args.component_dir.resolve()
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    before = {'compiler_sha256': D.F.digest(args.compiler),
              'packages': D.packages(args.component_dir, body_schema=9)}
    cases = [(f'float_{i:02}.my',f'func value() -> float:\n    return {literal}\n\n\nfunc main() -> int:\n    _ = value()\n    return 0\n',0) for i,literal in enumerate(SUCCESS)]
    cases += [(f'error_{i:02}.my',f'func value() -> float:\n    return {literal}\n\n\nfunc main() -> int:\n    _ = value()\n    return 0\n',1) for i,literal in enumerate(ERRORS)]
    cases += [('parse_arity.my','func main() -> int:\n    _ = b"42".parse_int(1)\n    return 0\n',1),('float_parse_arity.my','func main() -> int:\n    _ = "42".parse_float(1)\n    return 0\n',1),('range_arity.my','func main() -> int:\n    _ = b"42".parse_int_range(1)\n    return 0\n',1)]

    report = dict(scope='supplemental B9 binary64 source boundaries and numeric method diagnostics',
                  complete=False, records=[], body_schema=9, **before)
    def save():
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    save()
    with tempfile.TemporaryDirectory(prefix='body-numeric-boundaries-') as temporary:
        work = Path(temporary)
        empty = work / 'empty-path'
        empty.mkdir()
        for name, source, status in cases:
            entry = work / name
            entry.write_text(source)
            for phase in (['check', 'typed'] if status == 0 else ['check']):
                outputs = []
                for mode in ('reference', 'shadow', 'component'):
                    env = D.environment(mode, args.component_dir, empty)
                    command = ([args.compiler, 'check-project', entry, '--no-cache', '--diagnostics=json']
                               if phase == 'check' else [args.compiler, 'dump-typed', entry])
                    actual = D.F.execute(command, env, work, 120)
                    outputs.append(actual)
                    report['records'].append(dict(name=name, source=source,
                        source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                        mode=mode, phase=phase, command=list(map(str, command)),
                        status=actual[0], stdout_hex=actual[1].hex(), stderr_hex=actual[2].hex()))
                    save()
                D.F.require(outputs[0][0] == status, 'native status changed: ' + name)
                if phase == 'typed':
                    D.F.require(bool(outputs[0][1]) and not outputs[0][2], 'missing native typed boundary: ' + name)
                D.F.require(outputs[0] == outputs[1] == outputs[2], 'numeric boundary differs: ' + name)
        D.F.require(before == {'compiler_sha256': D.F.digest(args.compiler),
                              'packages': D.packages(args.component_dir, body_schema=9)},
                    'boundary compiler/package deployment changed')
    report.update(complete=True, cases=len(cases), operations=len(report['records']), failed=0, skipped=0)
    save()
    print('B9 supplemental boundaries passed:', report['cases'], 'cases,', report['operations'], 'operations')


if __name__ == "__main__":
    main()
