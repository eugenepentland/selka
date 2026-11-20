#!/usr/bin/env python3
"""Preview the nightly user timer; --apply installs and enables it after R4 approval."""
import argparse
import os
from pathlib import Path
import subprocess

import service_worktree


def checked_path(value):
    """Reject bytes that cannot be represented in a single unit setting."""
    text = str(value)
    if any(character in text for character in ('\n', '\r', '\0')):
        raise ValueError('systemd paths may not contain newlines or NUL')
    return text


def quote(value):
    """Quote one ExecStart argument, preserving spaces and literal percent signs."""
    text = checked_path(value)
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%') + '"'


def working_directory(value):
    """WorkingDirectory takes a literal absolute path, not shell-style quotes."""
    text = checked_path(value)
    if not Path(text).is_absolute():
        raise ValueError('WorkingDirectory must be an absolute path')
    # Unit syntax strips trailing whitespace and joins a trailing backslash with
    # the following line. Refuse those paths rather than select another directory.
    if text != text.rstrip() or text.endswith('\\'):
        raise ValueError('WorkingDirectory may not end in whitespace or a backslash')
    return text.replace('%', '%%')


def render_units(root):
    """Render both units without writing configuration or contacting systemd."""
    command = root / 'scripts/service_worktree.py'
    units = {}
    for name in ('selka-nightly-integration.service', 'selka-nightly-integration.timer'):
        text = (root / 'scripts/systemd' / name).read_text()
        invocation = f'/usr/bin/python3 {quote(command)} --worktree {quote(root)} --service nightly'
        units[name] = text.replace('@WORKTREE@', working_directory(root)).replace('@COMMAND@', invocation)
    return units


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worktree', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--apply', action='store_true', help='install and enable; coordinator uses only in R4')
    args = parser.parse_args()
    root = args.worktree.resolve(strict=True)
    command = root / 'scripts/nightly-integration.sh'
    if not command.is_file() or not (root / 'scripts/verify_cache.py').is_file() or not (root / 'scripts/service_worktree.py').is_file():
        parser.error('--worktree must contain the committed nightly runner and coordinator')
    destination = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'systemd/user'
    units = render_units(root)
    for name, text in units.items():
        print(f'{destination / name}\n{text}')
    print('Logs: $XDG_STATE_HOME/selka/nightly-integration (default ~/.local/state/selka/nightly-integration)')
    print('Would run: systemctl --user daemon-reload; systemctl --user enable --now selka-nightly-integration.timer')
    if args.apply:
        service_worktree.register(root)
        destination.mkdir(parents=True, exist_ok=True)
        for name, text in units.items():
            target = destination / name
            temporary = target.with_suffix(target.suffix + '.new')
            temporary.write_text(text)
            temporary.replace(target)
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
        subprocess.run(['systemctl', '--user', 'enable', '--now', 'selka-nightly-integration.timer'], check=True)


if __name__ == '__main__':
    main()
