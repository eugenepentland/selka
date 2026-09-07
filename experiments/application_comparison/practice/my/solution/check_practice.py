"""Coordinator-only raw CLI checks; never copied into participant starter."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile


def run(host, project, data):
    return subprocess.run(
        [str(host), '--project', str(project)], input=data,
        capture_output=True, timeout=15, check=False,
    )


def verify(host):
    root = Path(__file__).resolve().parent.parent
    cases = [(b'm', 42), (b'd', 9)]
    cases += [(b'f' + bytes([48 + digit]), digit) for digit in range(10)]
    cases += [(value, -1) for value in (
        b'', b'fx', b'f', b'f12', b'f\xff', b'f\xc3\xa9', b'm\n',
        b'd\n', b'x', b'\x00', b'\xff', b'f0\n', b'm' * 256,
        b'm' * 257, b'f' + b'0' * 255, b'f' + b'0' * 256,
    )]
    for data, expected in cases:
        result = run(host, root / 'solution', data)
        assert (result.returncode, result.stdout) == (0, f'{expected}\n'.encode()), (
            data[:20], result.returncode, result.stdout, result.stderr,
        )
    result = run(host, root / 'starter', b'm')
    assert result.returncode != 0 and not result.stdout
    assert b'error[E_UNKNOWN_NAME]' in result.stderr, result.stderr
    with tempfile.TemporaryDirectory(prefix='my-practice-check-') as temporary:
        project = Path(temporary) / 'practice'
        shutil.copytree(root / 'starter', project)
        source = project / 'main.my'
        source.write_text(source.read_text().replace('return missing_nine;', 'return nine;'))
        for data, expected in [(b'm', 36), (b'fx', 0), (b'd', 9), (b'f7', 7)]:
            result = run(host, project, data)
            assert (result.returncode, result.stdout) == (0, f'{expected}\n'.encode()), result.stderr
        source.write_text(source.read_text().replace('helper::multiply(6)', 'helper::multiply(7)').replace(
            'ParsedDigit.err(discard) => { return 0; }',
            'ParsedDigit.err(discard) => { return -1; }',
        ))
        assert source.read_bytes() == (root / 'solution' / 'main.my').read_bytes()
    print(f'{len(cases)} solution cases passed; unresolved name and two remaining starter faults confirmed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', required=True, type=Path)
    arguments = parser.parse_args()
    verify(arguments.host.resolve())
