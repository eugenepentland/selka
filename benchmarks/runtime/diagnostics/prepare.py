#!/usr/bin/env python3
"""Generate versioned component probes from hash-checked frozen port copies."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
RUNTIME = HERE.parent
VARIANTS = {
    'dispatch_outside': {'group': 'compute', 'case': 'integer_math', 'control': 'original'},
    'arithmetic_only': {'group': 'compute', 'case': 'integer_math', 'control': 'dispatch_outside'},
    'collection_only': {'group': 'collections', 'case': 'list_scan', 'control': 'original'},
    'text_without_score': {'group': 'text', 'case': 'int_format', 'control': 'original'},
    'escaped_allocation': {'group': 'collections', 'case': 'alloc_short', 'control': 'original'},
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('port transform anchor is missing or ambiguous: ' + old[:90])
    return text.replace(old, new, 1)


def between(text, start, end, replacement):
    if text.count(start) != 1 or text.count(end) != 1:
        raise ValueError('port transform boundary is missing or ambiguous')
    first = text.index(start)
    last = text.index(end, first)
    return text[:first] + replacement + text[last:]


def dispatch(text, extension):
    # The operation is selected before timing. Setup and the arithmetic stay intact.
    if extension == 'my':
        text = once(text, 'if kind < 0:', 'if kind != 0:')
        return between(text, '            value = 0\n            if kind == 0:', '            pass_total += value',
                       '            value = ((x + phase) * 17 + 23) // 7 % 1009\n')
    if extension == 'rs':
        text = once(text, 'if kind < 0 {', 'if kind != 0 {') if 'if kind < 0 {' in text else text
        text = between(text, '            let value = match kind {', '            pass_total += value;',
                       '            let value = ((x + phase) * 17 + 23) / 7 % 1009;\n')
        return text
    if extension == 'go':
        text = once(text, 'if kind < 0 {', 'if kind != 0 {')
        text = once(text, 'for j, x := range values {', 'for _, x := range values {')
        text = once(text, '\tvar checksum int64', '\t_ = function\n\tvar checksum int64')
        return between(text, '\t\t\tvar value int64\n\t\t\tswitch kind {', '\t\t\tpassTotal += value',
                       '\t\t\tvalue := ((x+phase)*17 + 23) / 7 % 1009\n')
    text = once(text, 'for (values, 0..) |x, j| {', 'for (values) |x| {')
    text = once(text, '    var checksum: i64 = 0;', '    _ = function;\n    var checksum: i64 = 0;')
    return between(text, '            const value: i64 = switch (kind) {', '            pass_total += value;',
                   '            const value: i64 = @mod(@divTrunc((x + phase) * 17 + 23, 7), 1009);\n')


def arithmetic(text, extension):
    # j is the scalar input. Its distribution differs from the collection control.
    text = dispatch(text, extension)
    if extension == 'my':
        return once(text, '            x = values[j]', '            x = j')
    if extension == 'rs':
        return once(text, '            let x = values[j];', '            let x = j as i64;')
    if extension == 'go':
        return once(text, '\t\tfor _, x := range values {',
                    '\t\tfor j := 0; j < size; j++ {\n\t\t\tx := int64(j)')
    return once(text, '        for (values) |x| {',
                '        for (0..size) |j| {\n            const x: i64 = @intCast(j);')


def collection(text, extension):
    anchors = {
        'my': ('            total += (value + batch) % 1009', '            total += value'),
        'rs': ('0 => values.iter().map(|v| (v + batch) % 1009).sum(),', '0 => values.iter().sum(),'),
        'go': ('\t\t\t\tpart += (v + batch) % 1009', '\t\t\t\tpart += v'),
        'zig': ('for (input.values) |v| sum += @mod(v + batch, 1009);', 'for (input.values) |v| sum += v;'),
    }
    return once(text, *anchors[extension])


def text_only(text, extension):
    boundaries = {
        'my': ('def score(text: str) -> int:', '\n\ndef row_name(',
               'def score(text: str) -> int:\n    return len(text)\n'),
        'rs': ('fn score(text: &str) -> i64 {', '\nfn name(',
               'fn score(text: &str) -> i64 {\n    text.len() as i64\n}\n'),
        'go': ('func score(text string) int64 {', '\nfunc name(',
               'func score(text string) int64 {\n\treturn int64(len(text))\n}\n'),
        'zig': ('fn score(text: []const u8) i64 {', '\nfn rowName(',
                'fn score(text: []const u8) i64 {\n    return @intCast(text.len);\n}\n'),
    }
    return between(text, *boundaries[extension])


def escaped(text, extension):
    # Return nested owned lists across a function boundary, then consume them.
    # Optimizers may still eliminate allocations; assembly/counters decide that.
    if extension == 'my':
        helper = '\ndef escaped_allocations(size: int, seed: int, batch: int) -> list[list[int]]:\n    return [[seed + batch + j + k for k in range(4)] for j in range(size)]\n\n'
        text = once(text, '\ndef row_key(', helper + '\ndef row_key(')
        return between(text, '    elif kind == 8:', '    elif kind == 9:',
                       '    elif kind == 8:\n        escaped_lists = escaped_allocations(size, seed, batch)\n        for escaped_inner in escaped_lists:\n            for escaped_value in escaped_inner:\n                total += escaped_value\n        return total\n')
    if extension == 'rs':
        helper = '\nfn escaped_allocations(size: usize, seed: i64, batch: i64) -> Vec<Vec<i64>> {\n    (0..size).map(|j| (0..4).map(|k| seed + batch + j as i64 + k).collect()).collect()\n}\n'
        text = once(text, '\nfn main()', helper + '\nfn main()')
        return between(text, '            8 => {', '            9 => {',
                       '            8 => {\n                let lists = escaped_allocations(size, seed, batch);\n                lists.iter().map(|xs| xs.iter().sum::<i64>()).sum()\n            }\n')
    if extension == 'go':
        helper = '\nfunc escapedAllocations(size int, seed, batch int64) [][]int64 {\n\tlists := make([][]int64, size)\n\tfor j := range lists {\n\t\txs := make([]int64, 4)\n\t\tfor k := range xs { xs[k] = seed + batch + int64(j) + int64(k) }\n\t\tlists[j] = xs\n\t}\n\treturn lists\n}\n'
        text = once(text, '\nfunc main()', helper + '\nfunc main()')
        return between(text, '\t\tcase 8:\n\t\t\tfor j := 0; j < size; j++ {', '\t\tcase 9:\n\t\t\tlists :=',
                       '\t\tcase 8:\n\t\t\tlists := escapedAllocations(size, seed, batch)\n\t\t\tfor _, xs := range lists {\n\t\t\t\tfor _, v := range xs { part += v }\n\t\t\t}\n')
    helper = '\nfn escapedAllocations(allocator: std.mem.Allocator, size: usize, seed: i64, batch: i64) ![][]i64 {\n    const lists = try allocator.alloc([]i64, size);\n    for (lists, 0..) |*xs, j| {\n        xs.* = try allocator.alloc(i64, 4);\n        for (xs.*, 0..) |*v, k| v.* = seed + batch + @as(i64, @intCast(j)) + @as(i64, @intCast(k));\n    }\n    return lists;\n}\n'
    text = once(text, '\npub export fn main(', helper + '\npub export fn main(')
    return between(text, '    if (kind == 8) {', '    if (kind == 9) {',
                   '    if (kind == 8) {\n        const lists = try escapedAllocations(a, size, seed, batch);\n        defer a.free(lists);\n        defer for (lists) |xs| a.free(xs);\n        for (lists) |xs| {\n            for (xs) |v| sum += v;\n        }\n        return sum;\n    }\n')


TRANSFORMS = {'dispatch_outside': dispatch, 'arithmetic_only': arithmetic,
              'collection_only': collection, 'text_without_score': text_only, 'escaped_allocation': escaped}


def prepare(manifest, output):
    document = json.loads(manifest.read_text())
    identity = document['identity']
    receipt = {'schema': 'mylang-runtime-components-source-v1', 'status': 'complete',
               'input_manifest': str(manifest.resolve()), 'input_manifest_sha256': sha(manifest.read_bytes()),
               'candidate_id': identity['candidate_id'], 'source_revision': identity['source_revision'],
               'generator_sha256': sha(Path(__file__).read_bytes()), 'variants': {}}
    for variant, meta in VARIANTS.items():
        destination = output / variant
        destination.mkdir(parents=True, exist_ok=True)
        files = []
        group = RUNTIME / 'expanded' / meta['group']
        for extension in ('my', 'rs', 'go', 'zig'):
            source = group / ('main.' + extension)
            relative = str(source.relative_to(RUNTIME))
            before = source.read_bytes()
            if sha(before) != identity['sources'][relative]:
                raise ValueError('input port differs from candidate identity: ' + relative)
            after = TRANSFORMS[variant](before.decode(), extension).encode()
            target = destination / source.name
            target.write_bytes(after)
            diff = ''.join(difflib.unified_diff(before.decode().splitlines(True), after.decode().splitlines(True),
                                              fromfile=relative, tofile=variant + '/' + source.name))
            diff_path = target.with_suffix(target.suffix + '.diff')
            diff_path.write_text(diff)
            files.append({'source': relative, 'source_sha256': sha(before), 'generated': str(target.resolve()),
                          'generated_sha256': sha(after), 'diff': str(diff_path.resolve()), 'diff_sha256': sha(diff.encode())})
        dependencies = []
        for name in ('Cargo.toml', 'Cargo.lock'):
            source = group / name
            if source.is_file():
                if sha(source.read_bytes()) != identity['sources'][str(source.relative_to(RUNTIME))]:
                    raise ValueError('dependency source differs from candidate identity')
                shutil.copyfile(source, destination / name)
                dependencies.append({'source': str(source.relative_to(RUNTIME)), 'source_sha256': sha(source.read_bytes()),
                                     'generated': str((destination / name).resolve()),
                                     'generated_sha256': sha((destination / name).read_bytes())})
        receipt['variants'][variant] = {**meta, 'files': files, 'dependencies': dependencies}
    (output / 'sources.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    receipt = prepare(args.manifest, args.output.resolve())
    print('PASS diagnostic port copies: ' + ', '.join(receipt['variants']))


if __name__ == '__main__':
    main()
