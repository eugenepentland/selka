"""Fixture validation, never an agent maintenance result."""
import argparse
from pathlib import Path
import tempfile
from pack import prepare, seal, grade, checks, source_receipt


def replace(path, before, after):
    source = path.read_text()
    assert source.count(before) == 1, (path, before)
    path.write_text(source.replace(before, after))


def repair(work, stage):
    ledger, report, model = [work / name for name in ('ledger.my', 'report.my', 'model.my')]
    if stage == 1:
        replace(ledger, 'while i < 3u64', 'while i < 4u64')
    elif stage == 2:
        for path in (ledger, report):
            replace(path, 'floor: i64)', 'floor: i64, ceiling: i64)')
        replace(report, 'heap, input, floor)', 'heap, input, floor, ceiling)')
        replace(ledger, 'total += n;', 'if n > ceiling { total += ceiling; } else { total += n; }')
    else:
        replace(model, 'total: i64, count: u64', 'net: i64, accepted: u64, rejected: u64')
        replace(ledger, 'total: total, count: count', 'net: total, accepted: count, rejected: 4u64 - count')
        replace(report, 'reply.total * 100 + cast<i64>(reply.count)',
                'reply.net * 100 + cast<i64>(reply.accepted) * 10 + cast<i64>(reply.rejected)')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(dir=root / '.zig-cache', prefix='maintenance-fixture-') as temp:
        temporary = Path(temp)
        transcript = temporary / 'fixture.jsonl'
        transcript.write_text('{"kind":"fixture","event":"known reference restoration"}\n')
        failed = temporary / 'seeded-failure'
        prepare(failed, args.compiler.resolve(), 1, 'fixture-failure', 'not-an-agent', 'fixture')
        seal(failed, 'abandoned', transcript)
        assert not grade(failed, 'fixture-only-never-score-this-seed')['behavior_passed']
        previous = None
        for stage in (1, 2, 3):
            directory = temporary / str(stage)
            prepare(directory, args.compiler.resolve(), stage, 'fixture-one', 'not-an-agent', 'fixture', previous)
            work = directory / 'public/work'
            if stage == 1:
                actual = checks.observe(args.compiler.resolve(), work, stage >= 2,
                                        {'input': [1, 2, 3, 4], 'floor': 0, 'ceiling': 3})
                assert actual['stdout'] == '603\n' and actual['returncode'] == 0
            task = (directory / 'public/TASK.md').read_text()
            assert ('Stage ' + str(stage) + ' —') in task
            if stage < 3:
                assert ('Stage ' + str(stage + 1) + ' —') not in task
            if stage == 1:
                assert 'ceiling' not in (directory / 'public/check.py').read_text()
                assert 'ceiling' not in (directory / 'public/cases.json').read_text()
            if stage < 3:
                assert '"rejected"' not in (directory / 'public/cases.json').read_text()
            repair(work, stage)
            seal(directory, 'completed', transcript)
            frozen = source_receipt(directory / 'sealed')
            # Editing participant files after sealing cannot affect grading.
            (work / 'ledger.my').write_text('broken after sealing')
            result = grade(directory, 'fixture-only-never-score-this-seed')
            assert result['kind'] == 'fixture' and result['behavior_passed'], result
            assert len(result['outcomes']) == (192 if stage == 3 else 144)
            assert source_receipt(directory / 'sealed') == frozen
            try:
                grade(directory, 'another-seed')
            except ValueError:
                pass
            else:
                raise AssertionError('regrading must fail')
            if stage in (1, 3):
                adversarial = temporary / ('compensating-' + str(stage))
                if stage == 1:
                    prepare(adversarial, args.compiler.resolve(), stage, 'fixture-one', 'not-an-agent', 'fixture')
                    repair(adversarial / 'public/work', 1)
                    replace(adversarial / 'public/work/ledger.my', 'total: total, count: count',
                            'total: total - 1, count: count + 100u64')
                else:
                    prepare(adversarial, args.compiler.resolve(), stage, 'fixture-one', 'not-an-agent', 'fixture', temporary / '2')
                    repair(adversarial / 'public/work', 3)
                    replace(adversarial / 'public/work/ledger.my', 'net: total, accepted: count, rejected: 4u64 - count',
                            'net: total - 1, accepted: count, rejected: 104u64 - count')
                seal(adversarial, 'completed', transcript)
                rejected = grade(adversarial, 'fixture-only-never-score-this-seed')
                assert not rejected['behavior_passed']
                assert all(row['passed'] for row in rejected['outcomes'] if row['field'] == 'report')
                assert any(not row['passed'] for row in rejected['outcomes'] if row['field'] != 'report')
            previous = directory
        wrong = temporary / 'wrong-participant'
        try:
            prepare(wrong, args.compiler.resolve(), 3, 'different-person', 'not-an-agent', 'fixture', temporary / '2')
        except ValueError:
            pass
        else:
            raise AssertionError('cross-participant continuation must fail')
        print('Maintenance fixtures: seeded failure, three passing stages, 480 heldout checks and compensating-field rejection, sealed isolation, continuation identity and regrade rejection passed')


if __name__ == '__main__':
    main()
