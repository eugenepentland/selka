"""Six-arm standalone QBE alias ablation; no compiler edits or guest runs."""
from collections import Counter
from pathlib import Path
import hashlib, importlib.util, json, os, re, subprocess, time

OWN = Path(__file__).resolve().parents[2]
WORK = OWN / '.tmp-lox-private-alias-ablation-20261003'
OLD = OWN / '.tmp-lox-qbe-dispatch-20261003'
INPUT = OWN.parent / 'codex-lox-parity-20261003/.tmp-lox-round3/cache-ast-qbe/frontend/fragments/7bd96f9c2181da4b1c69c215e024dd73ef2f54814a3f64bd5069a72e6d008eb0/il/6b891e9bcbb49a29442d53d6ea321fe463feb738e70071a4cdf4888c17722fc1'
QBE = OLD / 'compiler-v3/bin/qbe'
LOADUB = ['v624', 'v779', 'v2791', 'v3393']
LOADL = ['v6509', 'v6606']
ARMS = {'control': [], 'all-six': LOADUB + LOADL, 'loadub-four': LOADUB, 'loadl-two': LOADL, 's0-five': LOADUB + ['v6606'], 's1-one': ['v6509']}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()


def rewrite(source, names):
    lines = source.splitlines(keepends=True)
    replacements = []
    for name in names:
        definitions = [(i, re.fullmatch(r'\s*%' + name + r' =l copy %(s[01])\n', raw)) for i, raw in enumerate(lines)]
        definitions = [(i, m) for i, m in definitions if m]
        assert len(definitions) == 1
        at, definition = definitions[0]
        uses = [i for i, line in enumerate(lines) if re.search(r'%' + name + r'(?![A-Za-z0-9_])', line) and i != at]
        assert len(uses) == 1
        used = uses[0]
        match = re.fullmatch(r'(\s*%\S+ =[wl] (loadub|loadl) )%' + name + r'(\n)', lines[used])
        assert match and match[2] == ('loadub' if name in LOADUB else 'loadl')
        replaced = match[1] + '%' + definition[1] + match[3]
        replacements.append({'alias': name, 'root': definition[1], 'definition_line': at + 1, 'original_definition': lines[at], 'consumer_line': used + 1, 'original_consumer': lines[used], 'new_consumer': replaced})
        lines[at] = ''
        lines[used] = replaced
    result = ''.join(lines)
    # Every consumer retains its original opcode, width, destination and order;
    # only the address operand changes and the single-use copy disappears.
    return result, replacements


def instructions(path):
    out = []
    for line in path.read_text().splitlines():
        if re.match(r'^\t[a-z]', line):
            op, _, args = line.strip().partition(' ')
            out.append((op, [x.strip() for x in args.split(',')] if args else []))
    return out


def counts(path):
    ops = instructions(path)
    calls = Counter(args[0] for op, args in ops if op.startswith('call'))
    stack = lambda x: re.search(r'\(%(?:r[bs]p)\)', x) is not None
    prologue = next(args[0] for op, args in ops if op == 'subq' and args[-1] == '%rsp')
    return {'instructions': len(ops), 'calls': sum(calls.values()), 'call_sites_by_target': dict(sorted(calls.items())), 'conditional_branches': sum(op.startswith('j') and op != 'jmp' for op, _ in ops), 'unconditional_jumps': sum(op == 'jmp' for op, _ in ops), 'stack': {'initial_fixed_frame_bytes': int(prologue[1:]), 'pushes': sum(op.startswith('push') for op, _ in ops), 'pops': sum(op.startswith('pop') for op, _ in ops), 'stack_adjustments': sum(op in ['subq', 'addq'] and args[-1] == '%rsp' for op, args in ops), 'stack_address_instruction_sites': sum(any(stack(x) for x in args) for _, args in ops), 'stack_mov_load_sites': sum(op.startswith('mov') and len(args) == 2 and stack(args[0]) for op, args in ops), 'stack_mov_store_sites': sum(op.startswith('mov') and len(args) == 2 and stack(args[1]) for op, args in ops), 'stack_lea_sites': sum(op.startswith('lea') and any(stack(x) for x in args) for op, args in ops)}}


def main():
    WORK.mkdir(exist_ok=True)
    (WORK / 'tmp').mkdir(exist_ok=True)
    assert sha(INPUT) == '33055cc51ba3cd8b6a5c17130a0594c4421677eeffe49c021877c5d3f9eff113'
    assert sha(QBE) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
    helper = OWN / 'experiments/lox-qbe-dispatch-20261003/static-paths.py'
    spec = importlib.util.spec_from_file_location('paths', helper)
    paths = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paths)
    before = {str(p): sha(p) for p in [INPUT, QBE, helper, Path(__file__)]}
    env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['TMPDIR'] = str(WORK / 'tmp')
    receipt = {'scope': 'standalone static selected-IL emission only; no compiler changes/builds, guest tests, counters, timing or selection; independent of dispatch transformations74/e7c', 'before': before, 'arms': {}, 'verified_after': False}
    for name, aliases in ARMS.items():
        source, replacements = rewrite(INPUT.read_text(), aliases)
        il = WORK / (name + '.ssa')
        assembly = WORK / (name + '.s')
        assert not il.exists() and not assembly.exists()
        il.write_text(source)
        argv = [str(OWN / 'scripts/build-slot.sh'), 'build', str(QBE), '-o', str(assembly), str(il)]
        begin = time.time()
        run = subprocess.run(argv, cwd=OWN, env=env, capture_output=True)
        (WORK / (name + '.stdout')).write_bytes(run.stdout)
        (WORK / (name + '.stderr')).write_bytes(run.stderr)
        row = {'aliases': aliases, 'edits': replacements, 'argv': argv, 'cwd': str(OWN), 'environment': {'TMPDIR': env['TMPDIR']}, 'started': begin, 'finished': time.time(), 'status': run.returncode, 'IL_path': str(il), 'IL_sha256': sha(il), 'stdout_sha256': sha(WORK / (name + '.stdout')), 'stderr_sha256': sha(WORK / (name + '.stderr'))}
        receipt['arms'][name] = row
        (WORK / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        run.check_returncode()
        row.update(assembly_path=str(assembly), assembly_sha256=sha(assembly), whole=counts(assembly))
        parsed = paths.assembly(assembly)
        row['dispatch_paths'] = {str(op): paths.path(parsed, op) for op in range(37)}
    control = receipt['arms']['control']
    for name, row in receipt['arms'].items():
        row['instruction_delta'] = row['whole']['instructions'] - control['whole']['instructions']
        row['call_site_delta'] = row['whole']['calls'] - control['whole']['calls']
        row['call_site_target_deltas'] = {target: row['whole']['call_sites_by_target'].get(target, 0) - control['whole']['call_sites_by_target'].get(target, 0) for target in set(row['whole']['call_sites_by_target']) | set(control['whole']['call_sites_by_target']) if row['whole']['call_sites_by_target'].get(target, 0) != control['whole']['call_sites_by_target'].get(target, 0)}
        row['dispatch_deltas'] = {op: path['instructions'] - control['dispatch_paths'][op]['instructions'] for op, path in row['dispatch_paths'].items()}
    after = {p: sha(Path(p)) for p in before}
    assert before == after
    receipt.update(after=after, verified_after=True, path_scope='all37 successful dispatch paths from opcode0 comparison through original handler entry; OR paths/spills/jumps included, operand/IP prefix and handlers symmetrically excluded', count_scope='standalone assembly static sites; stack counts count instructions mentioning stack slots, not dynamic memory traffic; fewer cold fail-call sites do not establish dynamic saved calls')
    (WORK / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({name: {'instructions': row['whole']['instructions'], 'calls': row['whole']['calls'], 'stack': row['whole']['stack'], 'instruction_delta': row['instruction_delta'], 'call_site_delta': row['call_site_delta'], 'dispatch_deltas': row['dispatch_deltas'], 'call_site_target_deltas': row['call_site_target_deltas']} for name, row in receipt['arms'].items()}))


if __name__ == '__main__':
    main()
