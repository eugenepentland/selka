"""Exercise ordinary module applications against independent Python expectations."""
import argparse
import importlib.util
import json
import random
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(argv, status=0):
    result = subprocess.run([str(a) for a in argv], capture_output=True, text=True, timeout=90)
    assert result.returncode == status, (argv, result.returncode, result.stdout, result.stderr)
    return result


def invoice(counts):
    if any(n < 0 or n > 99 for n in counts):
        return None
    items = sum(counts)
    gross = sum(n * price for n, price in zip(counts, (2000, 500, 750)))
    discount = gross // 10 if items >= 10 else 0
    tax = ((gross - discount) * 750 + 5000) // 10000
    delivery = 0 if items == 0 else 100 if items <= 10 else 200
    packaging = 0 if items == 0 else 100 if items <= 10 else 200
    handling = 0 if items == 0 else 100 if items <= 10 else 250
    return dict(gross=gross, discount=discount, tax=tax, delivery=delivery,
                packaging=packaging, handling=handling,
                total=gross-discount+tax+delivery+packaging+handling, items=items)


def invoice_inputs(counts):
    names = ('books', 'cables', 'adapters')
    return 'module inputs;\n' + ''.join(f'export {n};\n' for n in names) + ''.join(
        f'fn {name}()->i64{{return {value};}}\n' for name, value in zip(names, counts))


def frame(kind, sequence, value=0):
    body = bytes([1, kind, 0 if kind == 1 else 4, sequence]) + value.to_bytes(4, 'big')
    return list(body + bytes([sum(body) % 256]))


def packet(data, size):
    if size != 9:
        return -1
    version, kind, length, sequence = data[:4]
    if version != 1:
        return -2
    if kind not in (1, 2):
        return -3
    if length != (0 if kind == 1 else 4):
        return -4
    if sum(data[:-1]) % 256 != data[-1]:
        return -5
    return sequence if kind == 1 else sequence * (2**32) + int.from_bytes(bytes(data[4:8]), 'big')


def packet_inputs(data, size):
    values = ','.join(str(n) + 'u8' for n in data)
    return ('module inputs;export bytes;export size;'
            f'fn bytes()->[9]u8{{return new [9]u8[{values}];}}'
            f'fn size()->u64{{return {size}u64;}}')


def cases(name):
    rng = random.Random(1700)
    if name == 'invoice':
        quantities = [(2, 3, 1), (0, 0, 0), (0, 1, 0), (0, 0, 1),
                      (9, 0, 0), (10, 0, 0), (11, 0, 0), (99, 99, 99),
                      (-1, 2, 3), (1, 100, 0), (0, 0, -9223372036854775808),
                      (9223372036854775807, 0, 0)]
        quantities += [tuple(rng.randrange(100) for _ in range(3)) for _ in range(12)]
        for values in quantities:
            receipt = invoice(values)
            yield invoice_inputs(values), -1 if receipt is None else receipt['total']
    else:
        packets = [(frame(1, 7), 9), (frame(2, 7, 300), 9),
                   (frame(2, 255, 2**32-1), 9), (frame(2, 0, 0), 9),
                   (frame(2, 7, 0x01020304), 9)]
        packets += [(frame(2, 1, 42), size) for size in (0, 1, 8)]
        for index, value in ((0, 2), (1, 3), (2, 3), (8, 0)):
            data = frame(2, 1, 42)
            data[index] = value
            packets.append((data, 9))
        packets += [(frame(2, rng.randrange(256), rng.randrange(2**32)), 9) for _ in range(12)]
        for data, size in packets:
            yield packet_inputs(data, size), packet(data, size)


def mutation(compiler, directory, filename, before, after, code=None, status=1, command='check-project'):
    path = directory / filename
    original = path.read_text()
    assert before in original, (filename, before)
    try:
        path.write_text(original.replace(before, after, 1))
        options = [f'--policy={directory / "import-policy.json"}'] if command == 'check-policy' else []
        result = run([compiler, command, directory / 'main.my', *options], status)
        if code:
            assert f'error[{code}]' in result.stderr, result.stderr
        if status == 3:
            assert 'language: valid' in result.stdout and 'denied=1' in result.stdout, result.stdout
    finally:
        path.write_text(original)


def tools_review(compiler, directory, name):
    entry = directory / 'main.my'
    original = {p.name: p.read_bytes() for p in directory.glob('*.my')}
    run([compiler, 'fmt-project', entry, '--check'])
    run([compiler, 'check-policy', entry, f'--policy={directory / "import-policy.json"}'])
    quality = run([compiler, 'report-project-quality', entry]).stdout
    assert 'Runtime coverage and assertions: not measured.' in quality
    assert 'reachable-from-main=false' not in quality
    assert 'module-exported=true reachable-from-exports=true' in quality
    discoveries = [run([compiler, 'discover-project-duplicates', entry, '--approximate']).stdout for _ in range(2)]
    assert discoveries[0] == discoveries[1] and 'truncated=false' in discoveries[0]
    assert original == {p.name: p.read_bytes() for p in directory.glob('*.my')}
    if name == 'invoice':
        text = discoveries[0]
        assert '1 candidate groups;' in text and '1 approximate pairs;' in text, text
        assert all(n in text for n in ('delivery::fee', 'packaging::fee', 'handling::fee', '- 100', '+ 150'))
        assert 'no code was merged' in text
        mutation(compiler, directory, 'catalog.my', '    adapter\n}', '    adapter, gift\n}', 'E_INCOMPLETE_TABLE')
        mutation(compiler, directory, 'pricing.my', 'struct Totals {', 'struct Totals {\n    audit: u8,', 'E_INCOMPLETE_CONVERSION')
        mutation(compiler, directory, 'catalog.my', 'import money;', 'import money;\nimport delivery;', status=3, command='check-policy')
        # An independent policy edit must not change the separate packaging source.
        path = directory / 'delivery.my'
        baseline = int(run([compiler, 'run-project', entry, '--print-result']).stdout)
        path.write_text(path.read_text().replace('cents = 100', 'cents = 101', 1))
        assert int(run([compiler, 'run-project', entry, '--print-result']).stdout) == baseline + 1
        assert (directory / 'packaging.my').read_bytes() == original['packaging.my']
        path.write_bytes(original['delivery.my'])
        manifest = directory / 'declared-inputs.json'
        values = (12, 0, 0)
        manifest.write_text(json.dumps({'version': 1, 'module': 'inputs', 'values': [
            {'name': k, 'type': 'i64', 'value': str(v)} for k, v in zip(('books', 'cables', 'adapters'), values)]}))
        assert int(run([compiler, 'eval-project', entry, f'--inputs={manifest}']).stdout) == invoice(values)['total']
        assert (directory / 'inputs.my').read_bytes() == original['inputs.my']
        document = {'version': 'typed-json-v1', 'type': 'pricing::Receipt', 'value': {k: str(v) for k, v in invoice((2, 3, 1)).items()}}
    else:
        assert '0 candidate groups;' in discoveries[0] and '0 approximate pairs;' in discoveries[0]
        assert 'line-bytes 113 exceeds configured 100' in quality, quality
        mutation(compiler, directory, 'model.my', '    reading: Reading\n}', '    reading: Reading, alarm: u8\n}', 'E_INCOMPLETE_MATCH')
        document = {'version': 'typed-json-v1', 'type': 'model::Message', 'value': {'case': 'reading', 'value': {'sequence': '7', 'value': '300'}}}
    value = directory / 'value.json'
    value.write_text(json.dumps(document))
    checked = run([compiler, 'check-value-project', entry, f'--value={value}'])
    assert json.loads(checked.stdout) == document
    output = directory / 'bindings.py'
    run([sys.executable, ROOT / 'scripts/bindings.py', entry, '--compiler', compiler, '--output', output])
    module_name = 'corpus_' + name
    spec = importlib.util.spec_from_file_location(module_name, output)
    binding = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = binding
    spec.loader.exec_module(binding)
    decoded = binding.loads(checked.stdout, expected_type=document['type'])
    assert json.loads(binding.dumps(decoded)) == document
    assert original == {p.name: p.read_bytes() for p in directory.glob('*.my')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    comparisons = 0
    with tempfile.TemporaryDirectory(prefix='mylang-corpus-') as temporary:
        root = Path(temporary)
        for name in ('invoice', 'packet'):
            directory = root / name
            shutil.copytree(ROOT / 'examples/corpus' / name, directory)
            tools_review(compiler, directory, name)
            entry = directory / 'main.my'
            for source, expected in cases(name):
                (directory / 'inputs.my').write_text(source)
                actual = run([compiler, 'run-project', entry, '--print-result'])
                assert int(actual.stdout) == expected, (name, source, expected, actual.stdout)
                comparisons += 1
        print(f'ordinary corpus (VM only): 2 applications, 13 modules, 48 input cases, {comparisons} independent-oracle execution checks; duplicates/quality, policy, schema/bindings, declared inputs, and change-impact rejection passed')

if __name__ == '__main__':
    main()
