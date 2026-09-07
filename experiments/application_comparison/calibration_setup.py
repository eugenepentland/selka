"""Freeze an unscored calibration cohort; never sends a model request."""
from pathlib import Path
import secrets
import tempfile
from . import cohort, coordinator_receipt, practice_pack, task_pack, trial_configuration
from .responses_transport import ResponsesTransport
from .storage import digest, read_json, write_json

ROOT = Path(__file__).resolve().parent


def create(directory, *, blocks, seed, model, max_reported_tokens_per_phase, budgets,
           byte_io, compiler, navigate, zig, guardian):
    settings = {'model': model, 'max_reported_tokens_per_phase': max_reported_tokens_per_phase}
    cohort.validate_configuration('calibration', settings, budgets)
    catalog = read_json(ROOT / 'pilot_tasks/catalog.json')
    known = {item['id']: item for item in catalog['blocks']}
    if not isinstance(blocks, list) or not blocks or any(not isinstance(name, str) or name not in known for name in blocks):
        raise ValueError('select named pilot blocks for calibration')
    selected = [known[name] for name in blocks]
    if any(block['tier'] != 'small' for block in selected):
        raise ValueError('calibration setup supports the current small baseline tier only')
    cohort.schedule(selected, seed=seed)  # Reject duplicate blocks before writing anything.
    tools = {name: str(Path(path).resolve(strict=True)) for name, path in
             dict(byte_io=byte_io, compiler=compiler, navigate=navigate, zig=zig, guardian=guardian).items()}
    directory = Path(directory).resolve()
    directory.mkdir(exist_ok=False)
    setup = {'version': 'calibration-setup-v1', 'blocks': selected, 'seed': seed,
             'model_settings': settings, 'budgets': budgets, 'tools': tools,
             'catalog_sha256': digest(catalog), 'model_calls': 0, 'scored_launch_authorized': False}
    write_json(directory / 'setup.json', setup)
    try:
        # Construction needs the transport's public identity, never a credential or a call.
        transport = ResponsesTransport('identity-only').identity
        provenance = coordinator_receipt.capture(transport)
        with tempfile.TemporaryDirectory(prefix='construction-', dir=directory) as temporary:
            staging = Path(temporary)
            practices, tasks, configurations, baselines, cache = {}, {}, {}, {}, {}
            for language in cohort.LANGUAGES:
                practices[language] = staging / ('practice-' + language)
                practice_pack.create(practices[language], language=language)
            for block in selected:
                name, application = block['id'], block['application']
                tasks[name] = staging / name
                task_pack.create(tasks[name], task=name, hidden_seed=secrets.token_hex(32))
                for language in cohort.LANGUAGES:
                    baselines[f'{application}/small/{language}'] = ROOT / 'baselines' / application / language
                    for arm in ('main', 'language-focused'):
                        key = (application, language, arm)
                        if key not in cache:
                            cache[key] = trial_configuration.freeze(language, application, arm, **tools)
                        configurations[f'{arm}/{name}/{language}'] = cache[key]
            manifest = cohort.freeze(directory / 'cohort', blocks=selected, seed=seed,
                model_settings=settings, budgets=budgets, baseline_paths=baselines, task_paths=tasks,
                kind='calibration', practice_paths=practices, configurations=configurations, coordinator=provenance)
        coordinator_receipt.verify(provenance, transport_identity=transport)
        result = {'version': 'calibration-setup-result-v1', 'cohort': str(directory / 'cohort'),
                  'cohort_sha256': manifest['sha256'], 'setup_sha256': digest(setup),
                  'scheduled_attempts': len(manifest['schedule']), 'model_calls': 0,
                  'scored_launch_authorized': False, 'comparative_claim': False}
        write_json(directory / 'result.json', result)
        return result
    except Exception as error:
        write_json(directory / 'interrupted.json', {'type': type(error).__name__, 'message': str(error),
                   'recovery': 'retain this setup; do not overwrite or launch an incomplete setup'})
        raise


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--block', action='append', required=True)
    parser.add_argument('--seed', required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--reported-tokens-per-phase', type=int, required=True)
    parser.add_argument('--budgets', type=Path, required=True, help='JSON object with the five common budget fields')
    for name in ('byte-io', 'compiler', 'navigate', 'zig', 'guardian'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    result = create(args.directory, blocks=args.block, seed=args.seed, model=args.model,
        max_reported_tokens_per_phase=args.reported_tokens_per_phase, budgets=read_json(args.budgets),
        byte_io=args.byte_io, compiler=args.compiler, navigate=args.navigate, zig=args.zig, guardian=args.guardian)
    print(result['cohort'], result['cohort_sha256'])
    print('Frozen unscored setup only; zero model calls and no participant attempts launched.')


if __name__ == '__main__':
    main()
