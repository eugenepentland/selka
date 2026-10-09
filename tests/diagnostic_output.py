#!/usr/bin/env python3
"""Check the CLI diagnostic protocol independently of the Zig renderer."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def records(text):
    values = [json.loads(line) for line in text.splitlines()]
    assert all(value['version'] == 'diagnostic-v1' for value in values), values
    return values


def invoke(compiler, command, path, *options, status=0):
    result = subprocess.run([compiler, command, str(path), '--diagnostics=json', *options], capture_output=True, text=True, timeout=30)
    assert result.returncode == status, (command, result)
    return result.stdout, records(result.stderr)


def problem(messages, code):
    found = [item['diagnostic'] for item in messages if item['kind'] == 'diagnostic' and item['diagnostic']['code'] == code]
    assert len(found) == 1, (code, messages)
    return found[0]


def single_files(compiler, root):
    path = root / 'quoted"é.my'
    path.write_text('func main() -> i64:\n    mut unused = 1\n    return 7\n')
    stdout, messages = invoke(compiler, 'run', path, '--print-result')
    assert stdout == '7\n'
    warning = problem(messages, 'W_UNUSED_BINDING')
    assert warning['severity'] == 'warning' and warning['location']['path'] == str(path)
    text = subprocess.run([compiler, 'run', str(path), '--print-result'], capture_output=True, text=True, timeout=30)
    explicit = subprocess.run([compiler, 'run', str(path), '--print-result', '--diagnostics=text'], capture_output=True, text=True, timeout=30)
    assert (text.returncode, text.stdout, text.stderr) == (explicit.returncode, explicit.stdout, explicit.stderr)
    assert text.stdout == stdout and 'warning[W_UNUSED_BINDING]' in text.stderr
    path.write_text('func main() -> i64:\n    return absent\n')
    for command in ('check', 'run', 'dump-bytecode', 'report-quality', 'discover-duplicates'):
        stdout, messages = invoke(compiler, command, path, status=1)
        assert stdout == ''
        data = problem(messages, 'E_UNKNOWN_NAME')
        span = data['location']['bytes']
        assert path.read_bytes()[span['start']:span['end']] == b'absent'
    path.write_text('func main(')
    for command in ('check', 'fmt', 'fmt-module'):
        _, messages = invoke(compiler, command, path, status=1)
        assert messages[0]['diagnostic']['code'] == 'E_SYNTAX'
    path.write_text('func divide(n: i64) -> i64:\n    return divtrunc(7, n)\n\n\nfunc main() -> i64:\n    return divide(0)\n')
    _, messages = invoke(compiler, 'run', path, status=1)
    trap = problem(messages, 'R_DIVISION_BY_ZERO')
    assert [frame['function'] for frame in trap['stack']['frames']] == ['divide', 'main']
    path.write_text('func recur(n: i64) -> i64:\n    return recur(n + 1)\n\n\nfunc main() -> i64:\n    return recur(0)\n')
    _, messages = invoke(compiler, 'run', path, '--max-frames=20', status=1)
    stack = problem(messages, 'R_FRAME_LIMIT')['stack']
    # The native trap renders a bounded window of the guest's own call stack.
    assert len(stack['frames']) == 16 and 'omitted' in stack
    assert {frame['function'] for frame in stack['frames']} == {'recur'}
    # Indentation is syntax, so a program the parser accepts is already canonical:
    # `fmt --check` can no longer differ, and reports nothing on the JSON channel.
    path.write_text('func main() -> i64:\n    return 7\n')
    stdout, messages = invoke(compiler, 'fmt', path, '--check')
    assert stdout == '' and messages == []
    _, messages = invoke(compiler, 'check', root / 'missing.my', status=2)
    assert messages[0]['kind'] == 'message' and 'FileNotFound' in messages[0]['message']
    for options in (['--diagnostics=xml'], ['--diagnostics=json', '--diagnostics=text']):
        invalid = subprocess.run([compiler, 'check', str(path), *options], capture_output=True, text=True, timeout=30)
        assert invalid.returncode == 2 and invalid.stdout == '' and invalid.stderr.startswith('usage:')


def export_placement(compiler, root):
    entry = root / 'main.my'
    body = 'func main() -> int:\n    return 42\n'
    for declaration in ('func value() -> int:\n    return 42\n', 'record Value:\n    n: int\n'):
        entry.write_text('public ' + declaration + '\n' + body)
        assert invoke(compiler, 'check-project', entry) == ('', [])
        assert invoke(compiler, 'run-project', entry, '--print-result') == ('42\n', [])
        name = 'value' if declaration.startswith('func') else 'Value'
        legacy = declaration + '\nexport ' + name + '\n\n' + body
        entry.write_text(legacy)
        _, messages = invoke(compiler, 'check-project', entry, status=1)
        problem(messages, 'E_FRONTEND_EXPORT')
        fixed = subprocess.run([compiler, 'fix', str(entry)], capture_output=True, text=True, timeout=30)
        assert fixed.returncode == 0, fixed.stderr
        assert 'public ' + declaration in entry.read_text()
        assert invoke(compiler, 'check-project', entry) == ('', [])


def modules(compiler, root):
    entry, helper = root / 'main.my', root / 'helper.my'
    entry.write_text('import helper\n\n\nfunc main() -> i64:\n    return helper.work[bool](9)\n')
    bad = ('\n\n\nresult R:\n    ok: i64,\n    err: i64\n\n\nfunc work[T](input: i64) -> i64:\n    mut pending: R = Ok(input)\n    return input\n')
    helper.write_text(bad)
    _, messages = invoke(compiler, 'check-project', entry, status=1)
    data = problem(messages, 'E_RESULT_UNHANDLED')
    assert data['location']['path'] == 'helper.my'
    assert [note['role'] for note in data['notes']] == ['related']
    span = data['notes'][0]['location']['bytes']
    assert bad.encode()[span['start']:span['end']] == b'pending'
    helper.write_text(bad.replace('    pending: R = Ok(input)\n', ''))
    assert invoke(compiler, 'run-project', entry, '--print-result') == ('9\n', [])
    entry.write_text('import missing\n\n\nfunc main() -> i64:\n    return 0\n')
    _, messages = invoke(compiler, 'check-project', entry, status=1)
    assert messages[0]['kind'] == 'diagnostic' and messages[0]['diagnostic']['code'].startswith('E_')
    entry.write_text('import helper\n\n\nfunc main() -> i64:\n    return 0\n')
    helper.write_text('import main\n')
    _, messages = invoke(compiler, 'list-modules', entry, status=1)
    cycle = messages[0]['diagnostic']
    assert cycle['notes'] and cycle['location']['path'] != cycle['notes'][0]['location']['path']
    entry.write_text('\n\nfunc main() -> i64:\n    return divtrunc(1, 0)\n')
    _, messages = invoke(compiler, 'run-project', entry, status=1)
    assert problem(messages, 'R_DIVISION_BY_ZERO')['location']['path'] == 'main.my'
    entry.write_text('\n\nfunc main() -> i64:\n    mut unused = 1\n    return 7\n')
    result = subprocess.run([compiler, 'check-session', str(entry), '--diagnostics=json'], input='check\ncheck\nclear\ncheck\nquit\n', capture_output=True, text=True, timeout=30)
    assert result.returncode == 0
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(replies) == 5 and all(reply['status'] == 0 for reply in replies)
    assert replies[1]['semantic']['hits'] == 1 and replies[3]['semantic']['stored'] == 2
    warnings = records(result.stderr)
    assert len(warnings) == 3 and warnings[0] == warnings[1] == warnings[2]
    problem(warnings[:1], 'W_UNUSED_BINDING')
    manifest = root / 'bad.json'
    manifest.write_text('{}')
    _, messages = invoke(compiler, 'schema-project', entry, '--inputs=' + str(manifest), status=2)
    assert messages[0]['kind'] == 'message' and 'manifest' in messages[0]['message']
    _, messages = invoke(compiler, 'input-module', manifest, status=2)
    assert messages and all(item['kind'] == 'message' for item in messages if item.get('diagnostic', {}).get('severity') != 'warning')
    entry.write_text('\n\n\nfunc main() -> i64:\n    return 0\n')
    _, messages = invoke(compiler, 'list-interfaces', entry, status=1)
    assert messages[0]['kind'] == 'diagnostic' and messages[0]['diagnostic']['location']['path'] == 'main.my'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-diagnostic-output-') as directory:
        root = Path(directory)
        single_files(compiler, root)
        export_placement(compiler, root)
        modules(compiler, root)
    print('JSON diagnostics: source errors, warnings, module notes, native runtime traps, auxiliary failures, text compatibility and cached session replay passed')


if __name__ == '__main__':
    main()
