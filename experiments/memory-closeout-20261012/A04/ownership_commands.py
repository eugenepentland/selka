"""Explicit opt-in/default command selection with unconditional checked-ABI audits."""
import hashlib
from pathlib import Path
import subprocess


def digest():
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def add_option(parser):
    parser.add_argument('--default-ownership', action='store_true',
                        help='Qualify normal commands without an ownership selector; require the checked ABI.')


def flags(args):
    return [] if args.default_ownership else ['--experimental-zero-rc']


def lane(q, args, env, name, source, options, mode, expected, **kwargs):
    result = q.lane(args, env, name, source, options, mode, expected, **kwargs)
    if args.default_ownership:
        # The historical helper keys these assertions on its experimental flag.
        # Requiring them here prevents flag retirement from weakening the audit.
        assert '--experimental-zero-rc' not in options, 'default qualification used a retired selector'
        audit_default(q, args.output / name / mode, result)
    return result


def audit_default(q, directory, result):
    q.prior.clean_ir(directory / 'program.ll')
    symbols = subprocess.check_output(['nm', str(directory / 'program')], text=True)
    assert not any(symbol in symbols for symbol in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
    assert result['runs'], 'no default-command executions'
    for run in result['runs'].values():
        audit = run['audit']
        assert audit['observed_rc_free'] and audit['managed_leak_free'], audit
